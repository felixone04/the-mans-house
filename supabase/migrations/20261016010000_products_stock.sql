-- =====================================================================
--  Prodotti in vendita, magazzino (giacenza + sottoscorta) e vendite.
--  La giacenza e' in una tabella separata, leggibile SOLO dall'admin.
-- =====================================================================

create table if not exists public.products (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  brand       text not null default '',
  category    text not null default '',
  format      text not null default '',
  price       numeric(8,2) not null default 0,
  description text not null default '',
  how_to_use  text not null default '',
  hair_type   text not null default '',
  hold        smallint not null default 0 check (hold between 0 and 5),
  shine       smallint not null default 0 check (shine between 0 and 5),
  photos      text[] not null default '{}',
  active      boolean not null default true,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now()
);

create table if not exists public.product_stock (
  product_id uuid primary key references public.products (id) on delete cascade,
  stock      int not null default 0,
  threshold  int not null default 0 check (threshold >= 0)
);

-- Movimenti: vendita (qty negativa), carico/rettifica (qty positiva o negativa)
create table if not exists public.stock_movements (
  id             uuid primary key default gen_random_uuid(),
  product_id     uuid not null references public.products (id) on delete cascade,
  qty            int not null,
  kind           text not null check (kind in ('sale', 'adjust')),
  unit_price     numeric(8,2) not null default 0,
  appointment_id uuid references public.appointments (id) on delete set null,
  note           text not null default '',
  created_at     timestamptz not null default now()
);
create index if not exists stock_movements_appointment on public.stock_movements (appointment_id);

alter table public.appointments
  add column if not exists products_total numeric(8,2) not null default 0;

alter table public.products        enable row level security;
alter table public.product_stock   enable row level security;
alter table public.stock_movements enable row level security;

drop policy if exists "products read"  on public.products;
drop policy if exists "products admin" on public.products;
drop policy if exists "stock admin"    on public.product_stock;
drop policy if exists "movements admin" on public.stock_movements;
create policy "products read"   on public.products for select using (active or public.is_admin());
create policy "products admin"  on public.products for all using (public.is_admin()) with check (public.is_admin());
create policy "stock admin"     on public.product_stock for all using (public.is_admin()) with check (public.is_admin());
create policy "movements admin" on public.stock_movements for all using (public.is_admin()) with check (public.is_admin());

-- Ogni nuovo prodotto ha la sua riga di giacenza
create or replace function public.product_stock_row()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.product_stock (product_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;
drop trigger if exists product_stock_row on public.products;
create trigger product_stock_row after insert on public.products
  for each row execute function public.product_stock_row();

-- Carico o rettifica della giacenza
create or replace function public.adjust_stock(p_product uuid, p_delta int, p_note text default '')
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_stock int;
begin
  if not public.is_admin() then raise exception 'Operazione non consentita'; end if;
  insert into public.product_stock (product_id) values (p_product) on conflict do nothing;
  select stock into v_stock from public.product_stock where product_id = p_product for update;
  if v_stock + p_delta < 0 then raise exception 'La giacenza non può andare sotto zero'; end if;
  update public.product_stock set stock = stock + p_delta where product_id = p_product;
  insert into public.stock_movements (product_id, qty, kind, note) values (p_product, p_delta, 'adjust', coalesce(p_note, ''));
end;
$$;

-- Vendita (anche insieme a un appuntamento: si somma al suo totale)
create or replace function public.sell_product(p_product uuid, p_qty int, p_appointment uuid default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_price numeric(8,2);
  v_stock int;
begin
  if not public.is_admin() then raise exception 'Operazione non consentita'; end if;
  if p_qty is null or p_qty <= 0 then raise exception 'Quantità non valida'; end if;
  select price into v_price from public.products where id = p_product;
  if not found then raise exception 'Prodotto non trovato'; end if;
  insert into public.product_stock (product_id) values (p_product) on conflict do nothing;
  select stock into v_stock from public.product_stock where product_id = p_product for update;
  if v_stock < p_qty then raise exception 'Giacenza insufficiente: ne restano %', v_stock; end if;

  update public.product_stock set stock = stock - p_qty where product_id = p_product;
  insert into public.stock_movements (product_id, qty, kind, unit_price, appointment_id)
    values (p_product, -p_qty, 'sale', v_price, p_appointment);
  if p_appointment is not null then
    update public.appointments set products_total = products_total + v_price * p_qty where id = p_appointment;
  end if;
end;
$$;

-- Annulla una vendita: la giacenza e il totale dell'appuntamento tornano come prima
create or replace function public.cancel_sale(p_movement uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_mov public.stock_movements;
begin
  if not public.is_admin() then raise exception 'Operazione non consentita'; end if;
  select * into v_mov from public.stock_movements where id = p_movement and kind = 'sale' for update;
  if not found then raise exception 'Vendita non trovata'; end if;
  update public.product_stock set stock = stock - v_mov.qty where product_id = v_mov.product_id;
  if v_mov.appointment_id is not null then
    update public.appointments
       set products_total = greatest(0, products_total + v_mov.unit_price * v_mov.qty)
     where id = v_mov.appointment_id;
  end if;
  delete from public.stock_movements where id = p_movement;
end;
$$;

revoke all on function public.adjust_stock(uuid, int, text) from public, anon;
revoke all on function public.sell_product(uuid, int, uuid) from public, anon;
revoke all on function public.cancel_sale(uuid) from public, anon;
grant execute on function public.adjust_stock(uuid, int, text) to authenticated;
grant execute on function public.sell_product(uuid, int, uuid) to authenticated;
grant execute on function public.cancel_sale(uuid) to authenticated;

-- Foto dei prodotti: cartella pubblica in lettura, caricamento solo admin
insert into storage.buckets (id, name, public) values ('products', 'products', true)
  on conflict (id) do nothing;
drop policy if exists "product photos read"  on storage.objects;
drop policy if exists "product photos admin" on storage.objects;
create policy "product photos read" on storage.objects for select using (bucket_id = 'products');
create policy "product photos admin" on storage.objects for all
  using (bucket_id = 'products' and public.is_admin())
  with check (bucket_id = 'products' and public.is_admin());
