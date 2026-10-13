-- =====================================================================
--  Spostamento appuntamenti (cliente e area riservata)
-- =====================================================================

-- Sposta un appuntamento confermato su un altro orario e/o barbiere,
-- mantenendo durata, servizio e prezzo. Il cliente puo' spostare solo i
-- propri appuntamenti ed entro lo stesso limite dell'annullamento.
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
  v_local_start timestamp;
  v_local_end timestamp;
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
  v_local_start := p_start at time zone v_tz;
  v_local_end   := v_end   at time zone v_tz;

  -- stesso giorno e dentro una fascia oraria del barbiere
  if v_local_start::date <> v_local_end::date or not exists (
    select 1 from public.barber_hours h
     where h.barber_id = p_barber
       and h.weekday = extract(isodow from v_local_start)
       and h.start_time <= v_local_start::time
       and h.end_time   >= v_local_end::time
  ) then
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
         -- nuovo orario: i promemoria WhatsApp ripartono
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

revoke all on function public.reschedule_appointment(uuid, uuid, timestamptz) from public, anon;
grant execute on function public.reschedule_appointment(uuid, uuid, timestamptz) to authenticated;
