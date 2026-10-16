-- =====================================================================
--  Notifiche, conferma presenza e recensioni.
--  - shop_settings.notifications: per ogni tipo di notifica attiva/disattiva,
--    titolo, testo e tempo (modificabili dall'area riservata -> Notifiche).
--  - shop_settings.google_review_url: link per lasciare la recensione su Google.
-- =====================================================================

alter table public.shop_settings
  add column if not exists notifications jsonb not null default '{}'::jsonb;
alter table public.shop_settings
  add column if not exists google_review_url text not null default '';

-- Conferma presenza e voto dopo il taglio
alter table public.appointments add column if not exists attendance_confirmed_at timestamptz;
alter table public.appointments add column if not exists review_stars smallint check (review_stars between 1 and 5);
alter table public.appointments add column if not exists review_comment text not null default '';
alter table public.appointments add column if not exists reviewed_at timestamptz;

-- Il cliente conferma che ci sara' (o l'admin per lui)
create or replace function public.confirm_attendance(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update public.appointments set attendance_confirmed_at = now()
   where id = p_id and status = 'confirmed'
     and (user_id = auth.uid() or public.is_admin());
  if not found then raise exception 'Operazione non consentita'; end if;
end;
$$;

-- Voto dopo l'appuntamento: una volta sola, solo per i propri appuntamenti.
-- Il commento resta privato: lo legge solo il negozio.
create or replace function public.submit_review(p_id uuid, p_stars int, p_comment text default '')
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_row public.appointments;
begin
  if p_stars is null or p_stars < 1 or p_stars > 5 then raise exception 'Voto non valido'; end if;
  select * into v_row from public.appointments where id = p_id for update;
  if not found or v_row.user_id is distinct from auth.uid() then
    raise exception 'Operazione non consentita';
  end if;
  if v_row.status = 'cancelled' or v_row.start_at > now() then
    raise exception 'Potrai lasciare un voto dopo l''appuntamento';
  end if;
  if v_row.review_stars is not null then raise exception 'Hai gia'' lasciato un voto'; end if;
  update public.appointments
     set review_stars = p_stars, review_comment = coalesce(p_comment, ''), reviewed_at = now()
   where id = p_id;
end;
$$;

revoke all on function public.confirm_attendance(uuid) from public, anon;
revoke all on function public.submit_review(uuid, int, text) from public, anon;
grant execute on function public.confirm_attendance(uuid) to authenticated;
grant execute on function public.submit_review(uuid, int, text) to authenticated;
