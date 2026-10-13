-- =====================================================================
--  Chiusure e orari speciali del negozio + consensi privacy/marketing
-- =====================================================================

-- ---------------------------------------------------------------------
--  Giorni speciali: chiusura (orari nulli) o orario diverso dal solito.
--  barber_ids: barbieri al lavoro nell'orario speciale (null = tutti).
-- ---------------------------------------------------------------------
create table if not exists public.shop_days (
  day         date primary key,
  open_time   time,
  close_time  time,
  note        text not null default '',
  barber_ids  uuid[],
  check ((open_time is null) = (close_time is null)),
  check (close_time is null or close_time > open_time)
);

alter table public.shop_days enable row level security;
drop policy if exists "shop_days read" on public.shop_days;
drop policy if exists "shop_days admin" on public.shop_days;
create policy "shop_days read"  on public.shop_days for select using (true);
create policy "shop_days admin" on public.shop_days for all using (public.is_admin()) with check (public.is_admin());

-- Il barbiere lavora in quell'intervallo (orari locali del negozio)?
-- Un giorno speciale sostituisce gli orari settimanali.
create or replace function public.barber_works(p_barber uuid, p_local_start timestamp, p_local_end timestamp)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  v_day public.shop_days;
begin
  if p_local_start::date <> p_local_end::date then return false; end if;

  select * into v_day from public.shop_days where day = p_local_start::date;
  if found then
    if v_day.open_time is null then return false; end if;
    if v_day.barber_ids is not null and cardinality(v_day.barber_ids) > 0
       and not (p_barber = any(v_day.barber_ids)) then
      return false;
    end if;
    return v_day.open_time <= p_local_start::time and v_day.close_time >= p_local_end::time;
  end if;

  return exists (
    select 1 from public.barber_hours h
     where h.barber_id = p_barber
       and h.weekday = extract(isodow from p_local_start)
       and h.start_time <= p_local_start::time
       and h.end_time   >= p_local_end::time
  );
end;
$$;

-- Verifica server-side che uno slot sia prenotabile (ora considera i giorni speciali).
create or replace function public.is_slot_available(p_barber uuid, p_start timestamptz, p_end timestamptz)
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

  -- niente sovrapposizioni
  if exists (
    select 1 from public.get_busy_intervals(p_start, p_end) b
     where b.barber_id = p_barber
  ) then return false; end if;

  return true;
end;
$$;

-- Spostamento: stesse regole, con i giorni speciali.
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
  v_tz := coalesce(v_settings.timezone, 'Europe/Rome');

  if not public.barber_works(p_barber, p_start at time zone v_tz, v_end at time zone v_tz) then
    raise exception 'Orario non piu'' disponibile';
  end if;

  -- niente sovrapposizioni (escluso l'appuntamento stesso)
  if exists (
    select 1 from public.appointments a
     where a.barber_id = p_barber and a.status = 'confirmed' and a.id <> p_id
       and a.start_at < v_end and a.end_at > p_start
  ) or exists (
    select 1 from public.barber_time_off t
     where t.barber_id = p_barber and t.start_at < v_end and t.end_at > p_start
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

revoke all on function public.barber_works(uuid, timestamp, timestamp) from public, anon;

-- ---------------------------------------------------------------------
--  Consensi
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists privacy_accepted_at timestamptz,
  add column if not exists marketing_opt_in    boolean not null default false;

-- Il profilo nasce con i consensi dati in registrazione (metadati dell'utente)
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, phone, is_admin, privacy_accepted_at, marketing_opt_in)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', ''),
    coalesce(new.raw_user_meta_data->>'phone', ''),
    exists (select 1 from public.admin_emails a where lower(a.email) = lower(new.email)),
    case when (new.raw_user_meta_data->>'privacy_accepted')::boolean then now() end,
    coalesce((new.raw_user_meta_data->>'marketing_opt_in')::boolean, false)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Clienti dal banco (senza account): consensi dati a voce in negozio
create table if not exists public.walkin_consents (
  name                text primary key,
  marketing_opt_in    boolean not null default false,
  privacy_accepted_at timestamptz,
  updated_at          timestamptz not null default now()
);
alter table public.walkin_consents enable row level security;
drop policy if exists "walkin_consents admin" on public.walkin_consents;
create policy "walkin_consents admin" on public.walkin_consents
  for all using (public.is_admin()) with check (public.is_admin());

-- Elenco clienti con i consensi (cambia il tipo restituito: va ricreata)
drop function if exists public.admin_customers();
create function public.admin_customers()
returns table (
  id text, email text, full_name text, phone text, created_at timestamptz,
  bookings bigint, last_visit timestamptz, marketing_opt_in boolean, privacy_accepted_at timestamptz
)
language sql stable security definer set search_path = public
as $$
  select c.id, c.email, c.full_name, c.phone, c.created_at, c.bookings, c.last_visit,
         c.marketing_opt_in, c.privacy_accepted_at
    from (
      select p.id::text as id, p.email, p.full_name, p.phone, p.created_at,
             count(a.id) filter (where a.status in ('confirmed','completed')) as bookings,
             max(a.start_at) filter (where a.status in ('confirmed','completed') and a.start_at < now()) as last_visit,
             p.marketing_opt_in, p.privacy_accepted_at
        from public.profiles p
        left join public.appointments a on a.user_id = p.id
       group by p.id
      union all
      select 'banco:' || a.customer_name, '', a.customer_name, max(a.customer_phone), min(a.created_at),
             count(*) filter (where a.status in ('confirmed','completed')),
             max(a.start_at) filter (where a.status in ('confirmed','completed') and a.start_at < now()),
             coalesce(bool_or(w.marketing_opt_in), false), max(w.privacy_accepted_at)
        from public.appointments a
        left join public.walkin_consents w on w.name = a.customer_name
       where a.user_id is null and a.customer_name <> ''
       group by a.customer_name
    ) c
   where public.is_admin()
   order by c.full_name;
$$;

revoke all on function public.admin_customers() from public, anon;
grant execute on function public.admin_customers() to authenticated;
