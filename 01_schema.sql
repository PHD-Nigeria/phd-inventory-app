-- ════════════════════════════════════════════════════════════════════
-- PHD Inventory Manager — database schema with unit-level isolation
-- Run in: Supabase Dashboard → SQL Editor (as the default `postgres` role).
--
-- Model
--   • Every user's JWT carries  app_metadata.unit = 'it' | 'admin'.
--     app_metadata can only be written with the service_role key (never by the
--     user or the browser), so a user cannot change their own unit.
--   • Row Level Security restricts EVERY table to rows whose `unit` equals the
--     unit in the caller's JWT. This is enforced inside Postgres, so it holds
--     no matter what the front-end code does or what is sent to the API.
-- ════════════════════════════════════════════════════════════════════

create table if not exists public.unit_records (
  unit       text    not null check (unit in ('it','admin')),
  collection text    not null check (collection in ('assets','history','reassignments','stockItems','stockLog')),
  pos        integer not null,
  data       jsonb   not null,
  primary key (unit, collection, pos)
);

create table if not exists public.unit_meta (
  unit       text primary key check (unit in ('it','admin')),
  rev        integer not null default 0,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

-- The caller's unit, taken ONLY from the verified JWT.
create or replace function public.current_unit() returns text
language sql stable security invoker set search_path = public as $$
  select case when (auth.jwt() -> 'app_metadata' ->> 'unit') in ('it','admin')
              then auth.jwt() -> 'app_metadata' ->> 'unit' end
$$;

alter table public.unit_records enable row level security;
alter table public.unit_meta    enable row level security;
alter table public.unit_records force row level security;
alter table public.unit_meta    force row level security;

drop policy if exists unit_records_all on public.unit_records;
create policy unit_records_all on public.unit_records
  for all to authenticated
  using      (unit = public.current_unit())
  with check (unit = public.current_unit());

drop policy if exists unit_meta_select on public.unit_meta;
create policy unit_meta_select on public.unit_meta
  for select to authenticated using (unit = public.current_unit());

drop policy if exists unit_meta_update on public.unit_meta;
create policy unit_meta_update on public.unit_meta
  for update to authenticated
  using (unit = public.current_unit()) with check (unit = public.current_unit());

-- No access at all for the anonymous (not-signed-in) role.
revoke all on public.unit_records, public.unit_meta from anon, public;
revoke all on public.unit_records, public.unit_meta from authenticated;
grant select, insert, update, delete on public.unit_records to authenticated;
grant select, update                 on public.unit_meta    to authenticated;

-- ── Load everything the caller's unit owns ──────────────────────────
create or replace function public.load_unit_data() returns jsonb
language plpgsql stable security invoker set search_path = public as $$
declare u text := public.current_unit(); out jsonb; c text;
begin
  if u is null then raise exception 'Not authorised' using errcode = '42501'; end if;
  out := jsonb_build_object('unit', u, 'rev', coalesce((select rev from unit_meta where unit = u), 0));
  foreach c in array array['assets','history','reassignments','stockItems','stockLog'] loop
    out := out || jsonb_build_object(c, coalesce(
      (select jsonb_agg(data order by pos) from unit_records where unit = u and collection = c), '[]'::jsonb));
  end loop;
  return out;
end $$;

-- ── Save the caller's unit (atomic; optimistic-concurrency on rev) ──
create or replace function public.save_unit_data(p_rev integer, p_data jsonb) returns jsonb
language plpgsql security invoker set search_path = public as $$
declare u text := public.current_unit(); cur integer; c text; total integer := 0; n integer;
begin
  if u is null then raise exception 'Not authorised' using errcode = '42501'; end if;
  if p_data is null or jsonb_typeof(p_data) <> 'object' then raise exception 'Invalid data payload'; end if;
  if octet_length(p_data::text) > 8000000 then raise exception 'Payload too large'; end if;
  foreach c in array array['assets','history','reassignments','stockItems','stockLog'] loop
    if jsonb_typeof(p_data -> c) is distinct from 'array' then raise exception 'Collection "%" must be an array', c; end if;
    if exists (select 1 from jsonb_array_elements(p_data -> c) e where jsonb_typeof(e) <> 'object') then
      raise exception 'Collection "%" contains an invalid record', c; end if;
    n := jsonb_array_length(p_data -> c); total := total + n;
  end loop;
  if total > 50000 then raise exception 'Too many records'; end if;

  select rev into cur from unit_meta where unit = u for update;     -- serialises concurrent saves
  if cur is null then raise exception 'Unit not initialised'; end if;
  if cur <> p_rev then return jsonb_build_object('conflict', true, 'rev', cur); end if;

  delete from unit_records where unit = u;
  foreach c in array array['assets','history','reassignments','stockItems','stockLog'] loop
    insert into unit_records(unit, collection, pos, data)
      select u, c, (ord - 1)::int, elem from jsonb_array_elements(p_data -> c) with ordinality as t(elem, ord);
  end loop;
  update unit_meta set rev = cur + 1, updated_at = now(), updated_by = auth.uid() where unit = u;
  return jsonb_build_object('ok', true, 'rev', cur + 1);
end $$;

revoke all on function public.current_unit(), public.load_unit_data(), public.save_unit_data(integer, jsonb) from public, anon;
grant execute on function public.current_unit(), public.load_unit_data(), public.save_unit_data(integer, jsonb) to authenticated;
