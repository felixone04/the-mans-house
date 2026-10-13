-- =====================================================================
--  Arrivo del cliente e pagamento (segnati dal negozio in agenda)
-- =====================================================================

alter table public.appointments
  add column if not exists arrived_at     timestamptz,
  add column if not exists payment_status text not null default 'unpaid'
    check (payment_status in ('unpaid', 'paid', 'later', 'deposit')),
  add column if not exists amount_paid    numeric(8,2) not null default 0
    check (amount_paid >= 0);

-- Le modifiche passano dalla policy "appointments admin" (solo amministratori).
