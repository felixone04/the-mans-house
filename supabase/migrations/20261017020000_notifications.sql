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
