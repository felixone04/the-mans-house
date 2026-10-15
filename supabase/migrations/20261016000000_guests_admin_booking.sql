-- =====================================================================
--  Prenotazione senza account (ospiti) e prenotazione dell'admin per un
--  cliente esistente, nuovo o senza dati.
--
--  PRIMA di usare la prenotazione senza account abilitare in Supabase:
--  Authentication -> Sign In / Providers -> "Allow anonymous sign-ins".
-- =====================================================================

alter table public.appointments
  add column if not exists customer_email text not null default '';

-- Profilo alla registrazione. Gli ospiti (accesso anonimo) non hanno email
-- di accesso: si usa quella facoltativa indicata nel modulo (contact_email).
-- Il ruolo admin dipende SOLO dall'email verificata dell'account.
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, phone, is_admin, privacy_accepted_at, marketing_opt_in)
  values (
    new.id,
    coalesce(new.email, nullif(new.raw_user_meta_data->>'contact_email', '')),
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', ''),
    coalesce(new.raw_user_meta_data->>'phone', ''),
    new.email is not null
      and exists (select 1 from public.admin_emails a where lower(a.email) = lower(new.email)),
    case when (new.raw_user_meta_data->>'privacy_accepted')::boolean then now() end,
    coalesce((new.raw_user_meta_data->>'marketing_opt_in')::boolean, false)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Prenotazione: nuova firma con email del cliente e cliente con account (p_user).
drop function if exists public.book_appointment(uuid, uuid, timestamptz, text, text, text);

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

  if not public.is_slot_available(p_barber, p_start, v_end) then
    raise exception 'Orario non piu'' disponibile';
  end if;

  -- solo l'admin puo' prenotare per un altro cliente
  if v_admin and p_user is not null then
    select * into v_target from public.profiles where id = p_user;
    if not found then raise exception 'Cliente non trovato'; end if;
  end if;
  v_walkin := v_admin and p_user is null and p_customer_name is not null;

  select * into v_profile from public.profiles where id = v_uid;

  insert into public.appointments (
    user_id, barber_id, service_id, service_name, price, start_at, end_at,
    customer_name, customer_phone, customer_email, notes, created_by_admin
  ) values (
    case when v_target.id is not null then v_target.id when v_walkin then null else v_uid end,
    p_barber, v_service.id, v_service.name, v_service.price, p_start, v_end,
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

revoke all on function public.book_appointment(uuid, uuid, timestamptz, text, text, text, text, uuid) from public, anon;
grant execute on function public.book_appointment(uuid, uuid, timestamptz, text, text, text, text, uuid) to authenticated;
