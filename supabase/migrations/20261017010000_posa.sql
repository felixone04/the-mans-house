-- =====================================================================
--  Servizi con tempo di posa (es. colore).
--  Il servizio ha un tempo TOTALE (duration_min, quello che vede il cliente)
--  e un tempo INIZIALE (busy_min) in cui il barbiere e' occupato. Dopo il
--  tempo iniziale il barbiere e' libero per altri clienti, mentre il cliente
--  resta in posa. busy_min null = occupato per tutto il servizio (come prima).
--  Gli appuntamenti tengono busy_end_at: fine del lavoro del barbiere.
-- =====================================================================

alter table public.services
  add column if not exists busy_min int check (busy_min is null or busy_min > 0);

alter table public.appointments add column if not exists busy_min int;
alter table public.appointments add column if not exists busy_end_at timestamptz;

alter table public.waitlist add column if not exists busy_min int;

-- busy_end_at sempre allineato a inizio, fine e tempo iniziale
create or replace function public.appointments_busy_end()
returns trigger
language plpgsql
as $$
begin
  new.busy_end_at := case
    when new.busy_min is null then new.end_at
    else least(new.end_at, new.start_at + make_interval(mins => new.busy_min))
  end;
  return new;
end;
$$;
drop trigger if exists appointments_busy_end on public.appointments;
create trigger appointments_busy_end before insert or update of start_at, end_at, busy_min
  on public.appointments for each row execute function public.appointments_busy_end();

update public.appointments set busy_end_at = end_at where busy_end_at is null;
alter table public.appointments alter column busy_end_at set not null;

-- Niente sovrapposizioni solo sul tempo di lavoro del barbiere
alter table public.appointments drop constraint if exists appointments_no_overlap;
alter table public.appointments
  add constraint appointments_no_overlap exclude using gist (
    barber_id with =,
    tstzrange(start_at, busy_end_at, '[)') with &&
  ) where (status = 'confirmed' and not overbooked);

-- Intervalli occupati: per gli appuntamenti conta solo il tempo di lavoro
create or replace function public.get_busy_intervals(p_from timestamptz, p_to timestamptz)
returns table (barber_id uuid, start_at timestamptz, end_at timestamptz, is_time_off boolean)
language sql stable security definer set search_path = public
as $$
  select a.barber_id, a.start_at, a.busy_end_at, false
    from public.appointments a
   where a.status = 'confirmed' and a.start_at < p_to and a.busy_end_at > p_from
  union all
  select t.barber_id, t.start_at, t.end_at, true
    from public.barber_time_off t
   where t.start_at < p_to and t.end_at > p_from;
$$;

-- Slot prenotabile: il servizio intero dentro l'orario del barbiere,
-- il barbiere libero solo fino a p_busy_end (null = fino alla fine)
drop function if exists public.is_slot_available(uuid, timestamptz, timestamptz);
create or replace function public.is_slot_available(
  p_barber uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_busy_end timestamptz default null
)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  v_tz text;
begin
  select timezone into v_tz from public.shop_settings where id = 1;
  v_tz := coalesce(v_tz, 'Europe/Rome');

  if not public.barber_works(p_barber, p_start at time zone v_tz, p_end at time zone v_tz) then
    return false;
  end if;

  if exists (
    select 1 from public.get_busy_intervals(p_start, coalesce(p_busy_end, p_end)) b
     where b.barber_id = p_barber
  ) then return false; end if;

  return true;
end;
$$;
revoke all on function public.is_slot_available(uuid, timestamptz, timestamptz, timestamptz) from public, anon;

-- Fine del lavoro del barbiere per un servizio che inizia a p_start
create or replace function public.service_busy_end(p_service public.services, p_start timestamptz)
returns timestamptz
language sql stable
as $$
  select p_start + make_interval(mins => case
    when p_service.busy_min is not null and p_service.busy_min < p_service.duration_min then p_service.busy_min
    else p_service.duration_min end);
$$;

-- Prenotazione: come prima, con il tempo di posa
create or replace function public.book_appointment(
  p_barber uuid,
  p_service uuid,
  p_start timestamptz,
  p_notes text default '',
  p_customer_name text default null,
  p_customer_phone text default null,
  p_customer_email text default null,
  p_user uuid default null
)
returns public.appointments
language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_admin boolean := public.is_admin();
  v_service public.services;
  v_profile public.profiles;
  v_target public.profiles;
  v_settings public.shop_settings;
  v_end timestamptz;
  v_row public.appointments;
  v_walkin boolean;
begin
  if v_uid is null then
    raise exception 'Devi accedere per prenotare';
  end if;

  select * into v_settings from public.shop_settings where id = 1;
  select * into v_service from public.services where id = p_service and active;
  if not found then raise exception 'Servizio non disponibile'; end if;

  if not exists (select 1 from public.barbers where id = p_barber and active) then
    raise exception 'Barbiere non disponibile';
  end if;

  if p_start <= now() then raise exception 'Orario non piu'' disponibile'; end if;
  if not v_admin and p_start > now() + make_interval(days => v_settings.booking_days_ahead + 1) then
    raise exception 'Data troppo lontana';
  end if;

  v_end := p_start + make_interval(mins => v_service.duration_min);

  if not public.is_slot_available(p_barber, p_start, v_end, public.service_busy_end(v_service, p_start)) then
    raise exception 'Orario non piu'' disponibile';
  end if;

  if v_admin and p_user is not null then
    select * into v_target from public.profiles where id = p_user;
    if not found then raise exception 'Cliente non trovato'; end if;
  end if;
  v_walkin := v_admin and p_user is null and p_customer_name is not null;

  select * into v_profile from public.profiles where id = v_uid;

  insert into public.appointments (
    user_id, barber_id, service_id, service_name, price, start_at, end_at, busy_min,
    customer_name, customer_phone, customer_email, notes, created_by_admin
  ) values (
    case when v_target.id is not null then v_target.id when v_walkin then null else v_uid end,
    p_barber, v_service.id, v_service.name, v_service.price, p_start, v_end,
    case when v_service.busy_min < v_service.duration_min then v_service.busy_min end,
    case when v_target.id is not null then v_target.full_name
         when v_walkin then p_customer_name
         else coalesce(v_profile.full_name, '') end,
    case when v_target.id is not null then v_target.phone
         when v_walkin then coalesce(p_customer_phone, '')
         else coalesce(v_profile.phone, '') end,
    case when v_target.id is not null then coalesce(v_target.email, '')
         when v_walkin then coalesce(p_customer_email, '')
         else coalesce(v_profile.email, '') end,
    coalesce(p_notes, ''),
    v_target.id is not null or v_walkin
  )
  returning * into v_row;

  return v_row;
exception
  when exclusion_violation then
    raise exception 'Orario non piu'' disponibile';
end;
$$;

-- Spostamento: stesse regole, con il tempo di posa
create or replace function public.reschedule_appointment(
  p_id uuid,
  p_barber uuid,
  p_start timestamptz
)
returns public.appointments
language plpgsql security definer set search_path = public
as $$
declare
  v_admin boolean := public.is_admin();
  v_row public.appointments;
  v_settings public.shop_settings;
  v_tz text;
  v_end timestamptz;
  v_busy_end timestamptz;
begin
  if auth.uid() is null then raise exception 'Devi accedere'; end if;

  select * into v_row from public.appointments where id = p_id for update;
  if not found then raise exception 'Appuntamento non trovato'; end if;

  select * into v_settings from public.shop_settings where id = 1;

  if not v_admin then
    if v_row.user_id is distinct from auth.uid() then
      raise exception 'Operazione non consentita';
    end if;
    if v_row.start_at < now() + make_interval(hours => coalesce(v_settings.min_cancel_hours, 0)) then
      raise exception 'Non e'' piu'' possibile spostarlo: contatta il negozio';
    end if;
    if p_start > now() + make_interval(days => v_settings.booking_days_ahead + 1) then
      raise exception 'Data troppo lontana';
    end if;
  end if;

  if v_row.status <> 'confirmed' then
    raise exception 'Appuntamento gia'' chiuso o annullato';
  end if;

  if not exists (select 1 from public.barbers where id = p_barber and active) then
    raise exception 'Barbiere non disponibile';
  end if;

  if p_start <= now() then raise exception 'Orario non piu'' disponibile'; end if;

  v_end := p_start + (v_row.end_at - v_row.start_at);
  v_busy_end := p_start + (v_row.busy_end_at - v_row.start_at);
  v_tz := coalesce(v_settings.timezone, 'Europe/Rome');

  if not public.barber_works(p_barber, p_start at time zone v_tz, v_end at time zone v_tz) then
    raise exception 'Orario non piu'' disponibile';
  end if;

  -- niente sovrapposizioni sul tempo di lavoro (escluso l'appuntamento stesso)
  if exists (
    select 1 from public.appointments a
     where a.barber_id = p_barber and a.status = 'confirmed' and a.id <> p_id
       and a.start_at < v_busy_end and a.busy_end_at > p_start
  ) or exists (
    select 1 from public.barber_time_off t
     where t.barber_id = p_barber and t.start_at < v_busy_end and t.end_at > p_start
  ) then
    raise exception 'Orario non piu'' disponibile';
  end if;

  update public.appointments
     set barber_id = p_barber,
         start_at = p_start,
         end_at = v_end,
         reminder_24h_sent_at = null,
         reminder_1h_sent_at = null
   where id = p_id
  returning * into v_row;
  return v_row;
exception
  when exclusion_violation then
    raise exception 'Orario non piu'' disponibile';
end;
$$;

-- Lista d'attesa con il tempo di posa
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
  if exists (
    select 1 from public.barbers b
     where b.active and (p_barber is null or b.id = p_barber)
       and public.is_slot_available(b.id, p_start, v_end, public.service_busy_end(v_service, p_start))
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
                               duration_min, busy_min, price, barber_id, start_at)
  values (v_uid, coalesce(v_profile.full_name, ''), coalesce(v_profile.phone, ''), v_service.id,
          v_service.name, v_service.duration_min,
          case when v_service.busy_min < v_service.duration_min then v_service.busy_min end,
          v_service.price, p_barber, p_start)
  returning * into v_row;
  return v_row;
end;
$$;

create or replace function public.promote_waitlist(p_day_start timestamptz, p_day_end timestamptz)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  w public.waitlist;
  v_barber uuid;
  v_end timestamptz;
  v_busy_end timestamptz;
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
    v_busy_end := w.start_at + make_interval(mins => coalesce(w.busy_min, w.duration_min));
    v_barber := null;
    select b.id into v_barber from public.barbers b
     where b.active and (w.barber_id is null or b.id = w.barber_id)
       and public.is_slot_available(b.id, w.start_at, v_end, v_busy_end)
     order by b.sort_order
     limit 1;
    if v_barber is null then continue; end if;

    insert into public.appointments (user_id, barber_id, service_id, service_name, price, start_at, end_at,
                                     busy_min, customer_name, customer_phone, notes)
    values (w.user_id, v_barber, w.service_id, w.service_name, w.price, w.start_at, v_end,
            w.busy_min, w.customer_name, w.customer_phone, 'Dalla lista d''attesa')
    returning * into v_appt;
    update public.waitlist set status = 'assigned', appointment_id = v_appt.id where id = w.id;
  end loop;
end;
$$;

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
                                   busy_min, customer_name, customer_phone, notes, created_by_admin, overbooked)
  values (w.user_id, v_barber, w.service_id, w.service_name, w.price, w.start_at, v_end,
          w.busy_min, w.customer_name, w.customer_phone, 'Accettato dalla lista d''attesa', true, true)
  returning * into v_appt;
  update public.waitlist set status = 'accepted', appointment_id = v_appt.id where id = w.id;
  return v_appt;
end;
$$;

-- my_waitlist restituisce anche il tempo iniziale
drop function if exists public.my_waitlist();
create or replace function public.my_waitlist()
returns table (
  id uuid, service_name text, duration_min int, busy_min int, price numeric, barber_id uuid, barber_name text,
  start_at timestamptz, status text, appointment_id uuid, created_at timestamptz, "position" int
)
language sql stable security definer set search_path = public
as $$
  select w.id, w.service_name, w.duration_min, w.busy_min, w.price, w.barber_id, coalesce(b.name, ''),
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
revoke all on function public.my_waitlist() from public, anon;
grant execute on function public.my_waitlist() to authenticated;
