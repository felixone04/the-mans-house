-- =====================================================================
--  The Man's House - schema iniziale
--  Prenotazioni barbiere: servizi, barbieri, orari, appuntamenti,
--  impostazioni del locale e promemoria WhatsApp.
-- =====================================================================

create extension if not exists btree_gist;

-- ---------------------------------------------------------------------
--  Tabelle
-- ---------------------------------------------------------------------

create table public.shop_settings (
  id                 int primary key default 1 check (id = 1),
  name               text not null default 'The Man''s House',
  tagline            text not null default 'Barber Shop',
  about              text not null default '',
  address            text not null default 'Via Garibaldi 91, Andria',
  maps_url           text not null default 'https://maps.google.com/?q=Via+Garibaldi+91+Andria',
  phone              text not null default '',
  whatsapp           text not null default '',
  instagram          text not null default '',
  timezone           text not null default 'Europe/Rome',
  slot_step_min      int  not null default 15  check (slot_step_min between 5 and 120),
  booking_days_ahead int  not null default 30  check (booking_days_ahead between 1 and 365),
  min_cancel_hours   int  not null default 2   check (min_cancel_hours between 0 and 72),
  reminders_enabled  boolean not null default true,
  updated_at         timestamptz not null default now()
);

create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text,
  full_name   text not null default '',
  phone       text not null default '',
  is_admin    boolean not null default false,
  whatsapp_opt_in boolean not null default true,
  created_at  timestamptz not null default now()
);

-- Email che diventano automaticamente amministratori alla registrazione.
create table public.admin_emails (
  email text primary key
);

create table public.services (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  description  text not null default '',
  duration_min int  not null check (duration_min between 5 and 480),
  price        numeric(8,2) not null default 0,
  active       boolean not null default true,
  sort_order   int not null default 0,
  created_at   timestamptz not null default now()
);

create table public.barbers (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  title       text not null default 'Barbiere',
  photo_url   text,
  active      boolean not null default true,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now()
);

-- Orari settimanali: piu' fasce per giorno (es. 9-13 e 15-20).
-- weekday: 1 = lunedi' ... 7 = domenica (ISO). Orari locali del negozio.
create table public.barber_hours (
  id          uuid primary key default gen_random_uuid(),
  barber_id   uuid not null references public.barbers (id) on delete cascade,
  weekday     smallint not null check (weekday between 1 and 7),
  start_time  time not null,
  end_time    time not null,
  check (end_time > start_time)
);
create index on public.barber_hours (barber_id, weekday);

-- Ferie / permessi / chiusure
create table public.barber_time_off (
  id          uuid primary key default gen_random_uuid(),
  barber_id   uuid not null references public.barbers (id) on delete cascade,
  start_at    timestamptz not null,
  end_at      timestamptz not null,
  reason      text not null default '',
  check (end_at > start_at)
);
create index on public.barber_time_off (barber_id, start_at);

create table public.appointments (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid references public.profiles (id) on delete set null,
  barber_id        uuid not null references public.barbers (id) on delete restrict,
  service_id       uuid references public.services (id) on delete set null,
  service_name     text not null,
  price            numeric(8,2) not null default 0,
  start_at         timestamptz not null,
  end_at           timestamptz not null,
  status           text not null default 'confirmed'
                   check (status in ('confirmed','cancelled','completed','no_show')),
  customer_name    text not null default '',
  customer_phone   text not null default '',
  notes            text not null default '',
  created_by_admin boolean not null default false,
  reminder_24h_sent_at timestamptz,
  reminder_1h_sent_at  timestamptz,
  cancelled_at     timestamptz,
  created_at       timestamptz not null default now(),
  check (end_at > start_at),
  -- impedisce le doppie prenotazioni sullo stesso barbiere
  constraint appointments_no_overlap exclude using gist (
    barber_id with =,
    tstzrange(start_at, end_at, '[)') with &&
  ) where (status = 'confirmed')
);
create index on public.appointments (user_id, start_at);
create index on public.appointments (barber_id, start_at);
create index on public.appointments (status, start_at);

-- ---------------------------------------------------------------------
--  Helper
-- ---------------------------------------------------------------------

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

-- Crea il profilo alla registrazione (email, Google, Apple)
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, phone, is_admin)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', ''),
    coalesce(new.raw_user_meta_data->>'phone', ''),
    exists (select 1 from public.admin_emails a where lower(a.email) = lower(new.email))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Un cliente non puo' promuoversi ad admin da solo
create or replace function public.protect_profile_admin_flag()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  -- auth.uid() nullo = SQL editor / service role: consentito
  if new.is_admin is distinct from old.is_admin
     and auth.uid() is not null and not public.is_admin() then
    raise exception 'Operazione non consentita';
  end if;
  -- l'email del profilo e' usata per assegnare il ruolo admin (admin_emails):
  -- il cliente non puo' cambiarla per spacciarsi per un'altra email
  if new.email is distinct from old.email
     and auth.uid() is not null and not public.is_admin() then
    raise exception 'Operazione non consentita';
  end if;
  return new;
end;
$$;

create trigger protect_profile_admin_flag
  before update on public.profiles
  for each row execute function public.protect_profile_admin_flag();

-- ---------------------------------------------------------------------
--  RLS
-- ---------------------------------------------------------------------

alter table public.shop_settings   enable row level security;
alter table public.profiles        enable row level security;
alter table public.admin_emails    enable row level security;
alter table public.services        enable row level security;
alter table public.barbers         enable row level security;
alter table public.barber_hours    enable row level security;
alter table public.barber_time_off enable row level security;
alter table public.appointments    enable row level security;

-- Dati pubblici (visibili anche senza login)
create policy "settings read"  on public.shop_settings for select using (true);
create policy "settings admin" on public.shop_settings for all using (public.is_admin()) with check (public.is_admin());

create policy "services read"  on public.services for select using (active or public.is_admin());
create policy "services admin" on public.services for all using (public.is_admin()) with check (public.is_admin());

create policy "barbers read"   on public.barbers for select using (active or public.is_admin());
create policy "barbers admin"  on public.barbers for all using (public.is_admin()) with check (public.is_admin());

create policy "hours read"     on public.barber_hours for select using (true);
create policy "hours admin"    on public.barber_hours for all using (public.is_admin()) with check (public.is_admin());

create policy "timeoff admin"  on public.barber_time_off for all using (public.is_admin()) with check (public.is_admin());

create policy "admin_emails admin" on public.admin_emails for all using (public.is_admin()) with check (public.is_admin());

-- Profili
create policy "profiles self read"   on public.profiles for select using (id = auth.uid() or public.is_admin());
create policy "profiles self update" on public.profiles for update using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

-- Appuntamenti: il cliente vede i suoi, l'admin tutto.
-- Inserimenti e annullamenti passano dalle funzioni book_/cancel_appointment.
create policy "appointments read"  on public.appointments for select using (user_id = auth.uid() or public.is_admin());
create policy "appointments admin" on public.appointments for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------
--  Disponibilita'
-- ---------------------------------------------------------------------

-- Intervalli occupati (appuntamenti confermati + ferie), senza dati personali.
create or replace function public.get_busy_intervals(p_from timestamptz, p_to timestamptz)
returns table (barber_id uuid, start_at timestamptz, end_at timestamptz)
language sql stable security definer set search_path = public
as $$
  select a.barber_id, a.start_at, a.end_at
    from public.appointments a
   where a.status = 'confirmed' and a.start_at < p_to and a.end_at > p_from
  union all
  select t.barber_id, t.start_at, t.end_at
    from public.barber_time_off t
   where t.start_at < p_to and t.end_at > p_from;
$$;

-- Verifica server-side che uno slot sia prenotabile.
create or replace function public.is_slot_available(p_barber uuid, p_start timestamptz, p_end timestamptz)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  v_tz text;
  v_local_start timestamp;
  v_local_end   timestamp;
begin
  select timezone into v_tz from public.shop_settings where id = 1;
  v_tz := coalesce(v_tz, 'Europe/Rome');
  v_local_start := p_start at time zone v_tz;
  v_local_end   := p_end   at time zone v_tz;

  if v_local_start::date <> v_local_end::date then return false; end if;

  -- dentro una fascia oraria del barbiere
  if not exists (
    select 1 from public.barber_hours h
     where h.barber_id = p_barber
       and h.weekday = extract(isodow from v_local_start)
       and h.start_time <= v_local_start::time
       and h.end_time   >= v_local_end::time
  ) then return false; end if;

  -- niente sovrapposizioni
  if exists (
    select 1 from public.get_busy_intervals(p_start, p_end) b
     where b.barber_id = p_barber
  ) then return false; end if;

  return true;
end;
$$;

-- ---------------------------------------------------------------------
--  Prenotazione / annullamento
-- ---------------------------------------------------------------------

create or replace function public.book_appointment(
  p_barber uuid,
  p_service uuid,
  p_start timestamptz,
  p_notes text default '',
  p_customer_name text default null,
  p_customer_phone text default null
)
returns public.appointments
language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_admin boolean := public.is_admin();
  v_service public.services;
  v_profile public.profiles;
  v_settings public.shop_settings;
  v_end timestamptz;
  v_row public.appointments;
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

  if not public.is_slot_available(p_barber, p_start, v_end) then
    raise exception 'Orario non piu'' disponibile';
  end if;

  select * into v_profile from public.profiles where id = v_uid;

  insert into public.appointments (
    user_id, barber_id, service_id, service_name, price, start_at, end_at,
    customer_name, customer_phone, notes, created_by_admin
  ) values (
    case when v_admin and p_customer_name is not null then null else v_uid end,
    p_barber, v_service.id, v_service.name, v_service.price, p_start, v_end,
    coalesce(case when v_admin then p_customer_name end, v_profile.full_name, ''),
    coalesce(case when v_admin then p_customer_phone end, v_profile.phone, ''),
    coalesce(p_notes, ''),
    v_admin and p_customer_name is not null
  )
  returning * into v_row;

  return v_row;
exception
  when exclusion_violation then
    raise exception 'Orario non piu'' disponibile';
end;
$$;

create or replace function public.cancel_appointment(p_id uuid)
returns public.appointments
language plpgsql security definer set search_path = public
as $$
declare
  v_row public.appointments;
  v_hours int;
begin
  select * into v_row from public.appointments where id = p_id for update;
  if not found then raise exception 'Appuntamento non trovato'; end if;

  if not public.is_admin() then
    if v_row.user_id is distinct from auth.uid() then
      raise exception 'Operazione non consentita';
    end if;
    select min_cancel_hours into v_hours from public.shop_settings where id = 1;
    if v_row.start_at < now() + make_interval(hours => coalesce(v_hours, 0)) then
      raise exception 'Non e'' piu'' possibile annullare: contatta il negozio';
    end if;
  end if;

  if v_row.status <> 'confirmed' then
    raise exception 'Appuntamento gia'' chiuso o annullato';
  end if;

  update public.appointments
     set status = 'cancelled', cancelled_at = now()
   where id = p_id
  returning * into v_row;
  return v_row;
end;
$$;

-- Eliminazione account (richiesta da App Store / GDPR)
create or replace function public.delete_my_account()
returns void
language plpgsql security definer set search_path = public, auth
as $$
begin
  if auth.uid() is null then raise exception 'Non autenticato'; end if;
  update public.appointments
     set status = 'cancelled', cancelled_at = now()
   where user_id = auth.uid() and status = 'confirmed' and start_at > now();
  delete from auth.users where id = auth.uid();
end;
$$;

-- Elenco clienti per l'area riservata: account registrati + clienti inseriti
-- dal banco (prenotazioni telefoniche senza account), come nella modalita' demo.
create or replace function public.admin_customers()
returns table (
  id text, email text, full_name text, phone text, created_at timestamptz,
  bookings bigint, last_visit timestamptz
)
language sql stable security definer set search_path = public
as $$
  select c.id, c.email, c.full_name, c.phone, c.created_at, c.bookings, c.last_visit
    from (
      select p.id::text as id, p.email, p.full_name, p.phone, p.created_at,
             count(a.id) filter (where a.status in ('confirmed','completed')) as bookings,
             max(a.start_at) filter (where a.status in ('confirmed','completed') and a.start_at < now()) as last_visit
        from public.profiles p
        left join public.appointments a on a.user_id = p.id
       group by p.id
      union all
      select 'banco:' || a.customer_name, '', a.customer_name, max(a.customer_phone), min(a.created_at),
             count(*) filter (where a.status in ('confirmed','completed')),
             max(a.start_at) filter (where a.status in ('confirmed','completed') and a.start_at < now())
        from public.appointments a
       where a.user_id is null and a.customer_name <> ''
       group by a.customer_name
    ) c
   where public.is_admin()
   order by c.full_name;
$$;

-- Permessi funzioni
revoke all on function public.book_appointment(uuid, uuid, timestamptz, text, text, text) from public, anon;
revoke all on function public.cancel_appointment(uuid) from public, anon;
revoke all on function public.delete_my_account() from public, anon;
revoke all on function public.admin_customers() from public, anon;
revoke all on function public.is_slot_available(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.book_appointment(uuid, uuid, timestamptz, text, text, text) to authenticated;
grant execute on function public.cancel_appointment(uuid) to authenticated;
grant execute on function public.delete_my_account() to authenticated;
grant execute on function public.admin_customers() to authenticated;
grant execute on function public.get_busy_intervals(timestamptz, timestamptz) to anon, authenticated;

-- Riga unica impostazioni
insert into public.shop_settings (id) values (1) on conflict do nothing;
