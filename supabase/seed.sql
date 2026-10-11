-- Dati iniziali di esempio: modificabili dall'area riservata dell'app.

update public.shop_settings set
  name = 'The Man''s House',
  tagline = 'Barber Shop · Andria',
  about = 'Tagli classici e moderni, rasatura tradizionale con panno caldo e cura della barba. Prenota il tuo barbiere di fiducia in pochi secondi.',
  address = 'Via Garibaldi 91, Andria',
  maps_url = 'https://maps.google.com/?q=Via+Garibaldi+91+Andria',
  phone = '',
  whatsapp = '',
  instagram = ''
where id = 1;

insert into public.services (name, description, duration_min, price, sort_order) values
  ('Taglio',              'Taglio su misura con rifinitura',        30, 15, 1),
  ('Taglio + Shampoo',    'Taglio con lavaggio e styling',          40, 18, 2),
  ('Barba',               'Regolazione e modellatura della barba',  20, 10, 3),
  ('Taglio + Barba',      'Il pacchetto completo',                  50, 23, 4),
  ('Rasatura tradizionale','Rasoio a mano libera e panno caldo',    30, 15, 5),
  ('Taglio bambino',      'Fino a 12 anni',                         20, 10, 6);

insert into public.barbers (name, title, sort_order) values
  ('Barbiere 1', 'Master Barber', 1),
  ('Barbiere 2', 'Barber',        2),
  ('Barbiere 3', 'Barber',        3);

-- Orari di esempio: mar-sab, 9:00-13:00 e 15:30-20:00
-- (il barbiere 3 lavora anche il lunedi' pomeriggio e fa orario continuato il sabato)
-- ::time esplicito: con UNION i letterali diventano text e l'insert fallirebbe
insert into public.barber_hours (barber_id, weekday, start_time, end_time)
select b.id, d, '09:00'::time, '13:00'::time from public.barbers b, generate_series(2, 6) d
where not (b.sort_order = 3 and d = 6)
union all
select b.id, d, '15:30'::time, '20:00'::time from public.barbers b, generate_series(2, 6) d
where not (b.sort_order = 3 and d = 6);

insert into public.barber_hours (barber_id, weekday, start_time, end_time)
select id, 6, '09:00'::time, '18:00'::time from public.barbers where sort_order = 3
union all
select id, 1, '15:30'::time, '20:00'::time from public.barbers where sort_order = 3;

-- Email dell'amministratore: chi si registra con questa email diventa admin.
-- Sostituisci con l'email reale del titolare.
-- insert into public.admin_emails (email) values ('titolare@esempio.it');
