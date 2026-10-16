-- =====================================================================
--  Lista d'attesa
--  - Il cliente si mette in lista per un orario gia' occupato (con un
--    barbiere preciso o "primo disponibile").
--  - Se l'orario si libera (annullamento o spostamento) il posto va in
--    automatico al primo in lista: l'appuntamento compare nella sua app.
--  - Il cliente vede solo QUANTI sono in lista, mai chi: i nomi li vede
--    soltanto l'admin.
--  - L'admin puo' accettare comunque una persona in lista anche se si e'
--    pieni: l'appuntamento viene inserito come "extra" (overbooked) e non
--    blocca gli altri orari.
-- =====================================================================

-- Appuntamenti extra: fuori dal vincolo "niente sovrapposizioni"
alter table public.appointments
  add column if not exists overbooked boolean not null default false;

alter table public.appointments drop constraint if exists appointments_no_overlap;
alter table public.appointments
  add constraint appointments_no_overlap exclude using gist (
    barber_id with =,
    tstzrange(start_at, end_at, '[)') with &&
  ) where (status = 'confirmed' and not overbooked);

create table if not exists public.waitlist (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles (id) on delete cascade,
  customer_name  text not null default '',
  customer_phone text not null default '',
  service_id     uuid references public.services (id) on delete set null,
  service_name   text not null,
  duration_min   int not null check (duration_min > 0),
  price          numeric(8,2) not null default 0,
  barber_id      uuid references public.barbers (id) on delete set null, -- null = primo disponibile
  start_at       timestamptz not null,
  status         text not null default 'waiting'
                 check (status in ('waiting', 'assigned', 'accepted', 'cancelled')),
  appointment_id uuid references public.appointments (id) on delete set null,
  created_at     timestamptz not null default now()
);
create index if not exists waitlist_start on public.waitlist (start_at) where status = 'waiting';
create index if not exists waitlist_user on public.waitlist (user_id, start_at);

alter table public.waitlist enable row level security;
drop policy if exists "waitlist own read" on public.waitlist;
drop policy if exists "waitlist admin" on public.waitlist;
-- il cliente legge solo le sue richieste; scrive solo tramite le funzioni
create policy "waitlist own read" on public.waitlist for select using (user_id = auth.uid());
create policy "waitlist admin" on public.waitlist for all using (public.is_admin()) with check (public.is_admin());

-- Mettersi in lista per un orario occupato
create or replace function public.join_waitlist(p_service uuid, p_barber uuid, p_start timestamptz)
returns public.waitlist
language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_service public.services;
  v_profile public.profiles;
  v_settings public.shop_settings;
  v_end timestamptz;
  v_row public.waitlist;
begin
  if v_uid is null then raise exception 'Devi accedere per metterti in lista'; end if;
  select * into v_service from public.services where id = p_service and active;
  if not found then raise exception 'Servizio non disponibile'; end if;
  if p_barber is not null and not exists (select 1 from public.barbers where id = p_barber and active) then
    raise exception 'Barbiere non disponibile';
  end if;
  if p_start <= now() then raise exception 'Orario gia'' passato'; end if;
  select * into v_settings from public.shop_settings where id = 1;
  if p_start > now() + make_interval(days => v_settings.booking_days_ahead + 1) then
    raise exception 'Data troppo lontana';
  end if;

  v_end := p_start + make_interval(mins => v_service.duration_min);
  -- se l'orario e' libero si prenota direttamente
  if exists (
    select 1 from public.barbers b
     where b.active and (p_barber is null or b.id = p_barber)
       and public.is_slot_available(b.id, p_start, v_end)
  ) then
    raise exception 'L''orario e'' libero: puoi prenotarlo subito';
  end if;

  if exists (
    select 1 from public.waitlist w
     where w.user_id = v_uid and w.start_at = p_start and w.status = 'waiting'
  ) then
    raise exception 'Sei gia'' in lista d''attesa per questo orario';
  end if;

  select * into v_profile from public.profiles where id = v_uid;
  insert into public.waitlist (user_id, customer_name, customer_phone, service_id, service_name,
                               duration_min, price, barber_id, start_at)
  values (v_uid, coalesce(v_profile.full_name, ''), coalesce(v_profile.phone, ''), v_service.id,
          v_service.name, v_service.duration_min, v_service.price, p_barber, p_start)
  returning * into v_row;
  return v_row;
end;
$$;

-- Uscire dalla lista (il cliente le sue, l'admin tutte)
create or replace function public.leave_waitlist(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update public.waitlist set status = 'cancelled'
   where id = p_id and status = 'waiting'
     and (user_id = auth.uid() or public.is_admin());
  if not found then raise exception 'Richiesta non trovata'; end if;
end;
$$;

-- Quanti sono in lista per ogni orario: SOLO numeri, nessun nome
create or replace function public.waitlist_counts(p_from timestamptz, p_to timestamptz)
returns table (start_at timestamptz, barber_id uuid, waiting int)
language sql stable security definer set search_path = public
as $$
  select w.start_at, w.barber_id, count(*)::int
    from public.waitlist w
   where w.status = 'waiting' and w.start_at >= greatest(p_from, now()) and w.start_at < p_to
   group by w.start_at, w.barber_id;
$$;

-- Le richieste del cliente con la sua posizione in lista
create or replace function public.my_waitlist()
returns table (
  id uuid, service_name text, duration_min int, price numeric, barber_id uuid, barber_name text,
  start_at timestamptz, status text, appointment_id uuid, created_at timestamptz, "position" int
)
language sql stable security definer set search_path = public
as $$
  select w.id, w.service_name, w.duration_min, w.price, w.barber_id, coalesce(b.name, ''),
         w.start_at, w.status, w.appointment_id, w.created_at,
         case when w.status = 'waiting' then (
           select count(*)::int + 1 from public.waitlist o
            where o.status = 'waiting' and o.start_at = w.start_at and o.created_at < w.created_at
              and (o.barber_id is null or w.barber_id is null or o.barber_id = w.barber_id)
         ) end
    from public.waitlist w
    left join public.barbers b on b.id = w.barber_id
   where w.user_id = auth.uid() and w.start_at > now() - interval '1 day'
     and w.status <> 'cancelled'
   order by w.start_at;
$$;

-- Assegna i posti liberi ai primi in lista di quel giorno
create or replace function public.promote_waitlist(p_day_start timestamptz, p_day_end timestamptz)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  w public.waitlist;
  v_barber uuid;
  v_end timestamptz;
  v_appt public.appointments;
begin
  for w in
    select * from public.waitlist
     where status = 'waiting' and start_at > now()
       and start_at >= p_day_start and start_at < p_day_end
     order by created_at
     for update skip locked
  loop
    v_end := w.start_at + make_interval(mins => w.duration_min);
    select b.id into v_barber from public.barbers b
     where b.active and (w.barber_id is null or b.id = w.barber_id)
       and public.is_slot_available(b.id, w.start_at, v_end)
     order by b.sort_order
     limit 1;
    if v_barber is null then continue; end if;

    insert into public.appointments (user_id, barber_id, service_id, service_name, price, start_at, end_at,
                                     customer_name, customer_phone, notes)
    values (w.user_id, v_barber, w.service_id, w.service_name, w.price, w.start_at, v_end,
            w.customer_name, w.customer_phone, 'Dalla lista d''attesa')
    returning * into v_appt;
    update public.waitlist set status = 'assigned', appointment_id = v_appt.id where id = w.id;
  end loop;
end;
$$;

-- Quando un appuntamento libera il posto (annullato o spostato) si guarda la lista
create or replace function public.waitlist_on_free()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_tz text;
  v_day date;
begin
  if old.status = 'confirmed' and (
       new.status <> 'confirmed' or new.start_at <> old.start_at or new.barber_id <> old.barber_id
     ) then
    select coalesce(timezone, 'Europe/Rome') into v_tz from public.shop_settings where id = 1;
    v_day := (old.start_at at time zone v_tz)::date;
    perform public.promote_waitlist(v_day::timestamp at time zone v_tz,
                                    (v_day + 1)::timestamp at time zone v_tz);
  end if;
  return new;
end;
$$;
drop trigger if exists waitlist_on_free on public.appointments;
create trigger waitlist_on_free after update on public.appointments
  for each row execute function public.waitlist_on_free();

-- L'admin accetta comunque una persona in lista anche se si e' pieni:
-- stesso orario, barbiere scelto dal cliente o uno a caso tra chi lavora.
create or replace function public.accept_waitlist(p_id uuid)
returns public.appointments
language plpgsql security definer set search_path = public
as $$
declare
  w public.waitlist;
  v_barber uuid;
  v_end timestamptz;
  v_tz text;
  v_appt public.appointments;
begin
  if not public.is_admin() then raise exception 'Operazione non consentita'; end if;
  select * into w from public.waitlist where id = p_id and status = 'waiting' for update;
  if not found then raise exception 'Richiesta non trovata'; end if;

  v_end := w.start_at + make_interval(mins => w.duration_min);
  select coalesce(timezone, 'Europe/Rome') into v_tz from public.shop_settings where id = 1;
  v_barber := w.barber_id;
  if v_barber is null then
    select b.id into v_barber from public.barbers b
     where b.active and public.barber_works(b.id, w.start_at at time zone v_tz, v_end at time zone v_tz)
     order by random() limit 1;
  end if;
  if v_barber is null then
    select b.id into v_barber from public.barbers b where b.active order by random() limit 1;
  end if;
  if v_barber is null then raise exception 'Nessun barbiere disponibile'; end if;

  insert into public.appointments (user_id, barber_id, service_id, service_name, price, start_at, end_at,
                                   customer_name, customer_phone, notes, created_by_admin, overbooked)
  values (w.user_id, v_barber, w.service_id, w.service_name, w.price, w.start_at, v_end,
          w.customer_name, w.customer_phone, 'Accettato dalla lista d''attesa', true, true)
  returning * into v_appt;
  update public.waitlist set status = 'accepted', appointment_id = v_appt.id where id = w.id;
  return v_appt;
end;
$$;

revoke all on function public.join_waitlist(uuid, uuid, timestamptz) from public, anon;
revoke all on function public.leave_waitlist(uuid) from public, anon;
revoke all on function public.my_waitlist() from public, anon;
revoke all on function public.promote_waitlist(timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.accept_waitlist(uuid) from public, anon;
grant execute on function public.join_waitlist(uuid, uuid, timestamptz) to authenticated;
grant execute on function public.leave_waitlist(uuid) to authenticated;
grant execute on function public.my_waitlist() to authenticated;
grant execute on function public.accept_waitlist(uuid) to authenticated;
grant execute on function public.waitlist_counts(timestamptz, timestamptz) to anon, authenticated;
