-- Isolation tests for the unit separation. Non-destructive: every block ends in ROLLBACK.
-- Run in the Supabase SQL Editor AFTER 01_schema.sql + 02_seed.sql. Every check raises on failure; look for PASS notices.
create schema if not exists t; grant usage on schema t to anon, authenticated;
create or replace function t.ok(c boolean, m text) returns void language plpgsql as $$
begin if c then raise notice 'PASS  %', m; else raise exception 'FAIL  %', m; end if; end $$;
grant execute on function t.ok(boolean,text) to anon, authenticated;

-- ── IT user ──────────────────────────────────────────────
begin; set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","app_metadata":{"unit":"it"}}',true);
select t.ok((select count(*) from unit_records)=88, 'IT user sees only its 88 records through the table directly');
select t.ok((select count(distinct unit) from unit_records)=1 and (select max(unit) from unit_records)='it','…all of them unit=it');
select t.ok((select count(*) from unit_records where unit='admin')=0,'IT user querying unit=admin gets 0 rows');
select t.ok((select count(*) from unit_meta)=1,'IT user sees only its own meta row');
select t.ok((public.load_unit_data()->>'unit')='it' and jsonb_array_length(public.load_unit_data()->'assets')=76,'load_unit_data(): IT gets 76 assets');
select t.ok(jsonb_array_length(public.load_unit_data()->'stockItems')=0,'…and no Admin stock');
-- attempts to write into / modify / delete the other unit
do $$ begin
  begin insert into unit_records values ('admin','assets',999,'{"tag":"HACK"}'); perform t.ok(false,'insert into admin should be blocked');
  exception when insufficient_privilege or check_violation then perform t.ok(true,'direct INSERT into unit=admin is rejected by RLS'); end;
end $$;
with d as (delete from unit_records where unit='admin' returning 1) select t.ok((select count(*) from d)=0,'DELETE of admin rows affects 0 rows');
with u as (update unit_records set data='{}' where unit='admin' returning 1) select t.ok((select count(*) from u)=0,'UPDATE of admin rows affects 0 rows');
with u as (update unit_meta set rev=999 where unit='admin' returning 1) select t.ok((select count(*) from u)=0,'cannot bump admin revision');
do $$ begin
  begin update unit_records set unit='admin' where unit='it' and collection='assets' and pos=0; perform t.ok(false,'moving a row to admin should be blocked');
  exception when insufficient_privilege or check_violation then perform t.ok(true,'cannot move an IT row into the admin unit (WITH CHECK)'); end;
end $$;
-- save works and stays inside IT
select t.ok((public.save_unit_data(1, (public.load_unit_data() - 'unit' - 'rev') || '{"assets":[{"id":"X","tag":"IT-ONLY"}]}'::jsonb)->>'rev')='2','IT save OK, rev 1 → 2');
select t.ok((select count(*) from unit_records where unit='it' and collection='assets')=1,'IT assets replaced');
select t.ok((public.save_unit_data(1, '{"assets":[],"history":[],"reassignments":[],"stockItems":[],"stockLog":[]}'::jsonb)->>'conflict')='true','stale rev → conflict, nothing written');
do $$ begin begin perform public.save_unit_data(2,'{"assets":"x"}'); perform t.ok(false,'bad payload');
  exception when others then perform t.ok(true,'malformed payload rejected'); end; end $$;
do $$ begin begin perform public.save_unit_data(2,'{"assets":[1],"history":[],"reassignments":[],"stockItems":[],"stockLog":[]}'); perform t.ok(false,'bad record');
  exception when others then perform t.ok(true,'non-object record rejected'); end; end $$;
rollback;

-- ── Admin user ─────────────────────────────────────────────
begin; set local role authenticated;
select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","app_metadata":{"unit":"admin"}}',true);
select t.ok((select count(*) from unit_records)=153,'Admin user sees exactly its 153 records');
select t.ok((select count(*) from unit_records where unit='it')=0,'Admin user cannot see any IT rows (and IT edits above did not touch admin)');
select t.ok(jsonb_array_length(public.load_unit_data()->'stockItems')=15 and jsonb_array_length(public.load_unit_data()->'stockLog')=129,'Admin gets 15 stock items + 129 releases');
select t.ok((public.load_unit_data()->>'rev')='1','Admin revision untouched by IT save');
rollback;

-- ── Users that must get nothing ───────────────────────────
begin; set local role authenticated;
select set_config('request.jwt.claims','{"sub":"33333333-3333-3333-3333-333333333333","app_metadata":{}}',true);
select t.ok((select count(*) from unit_records)=0,'authenticated user with NO unit sees 0 rows');
do $$ begin begin perform public.load_unit_data(); perform t.ok(false,'no unit');
  exception when insufficient_privilege then perform t.ok(true,'…and load_unit_data() raises 42501'); end; end $$;
rollback;
begin; set local role authenticated;
select set_config('request.jwt.claims','{"sub":"44444444-4444-4444-4444-444444444444","user_metadata":{"unit":"admin"},"app_metadata":{}}',true);
select t.ok((select count(*) from unit_records)=0,'user_metadata.unit (user-editable) is ignored — only app_metadata counts');
rollback;
begin; set local role authenticated;
select set_config('request.jwt.claims','{"app_metadata":{"unit":"finance"}}',true);
select t.ok((select count(*) from unit_records)=0,'unknown unit value sees 0 rows');
rollback;
begin; set local role anon;
do $$ begin begin perform count(*) from unit_records; perform t.ok(false,'anon should be denied');
  exception when insufficient_privilege then perform t.ok(true,'anonymous (not signed-in) role is denied the tables'); end; end $$;
do $$ begin begin perform public.load_unit_data(); perform t.ok(false,'anon rpc');
  exception when insufficient_privilege then perform t.ok(true,'anonymous role cannot call load_unit_data()'); end; end $$;
rollback;
drop schema t cascade;
