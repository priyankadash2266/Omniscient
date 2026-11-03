-- Non-destructive production schema smoke test. All fixture rows roll back.
begin;
insert into auth.users(id,email) values('00000000-0000-4000-8000-000000000001','alice@omniscient.test'),('00000000-0000-4000-8000-000000000002','bob@omniscient.test');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","email":"alice@omniscient.test","role":"authenticated"}',true);
select public.omniscient_save('10000000-0000-4000-8000-000000000001','report','{"id":"10000000-0000-4000-8000-000000000001","title":"Database isolation test","label":"Internal","severity":"SEV 2","status":"Draft","sections":{"Summary":"Connection timeout"}}',null);
do $$begin
 if (select count(*) from public.omniscient_records)<>1 then raise exception 'Owner cannot read own report';end if;
 if (select count(*) from public.omniscient_audits)<>1 then raise exception 'Write was not audited';end if;
 begin
  perform public.omniscient_save('10000000-0000-4000-8000-000000000001','report','{"title":"Incomplete review","label":"Internal","severity":"SEV 2","status":"In review","sections":{}}',1);
  raise exception 'TEST: incomplete review accepted';
 exception when others then if sqlerrm like 'TEST:%' then raise;end if;end;
 begin
  perform public.omniscient_save('10000000-0000-4000-8000-000000000001','report','{"title":"Stale change","label":"Internal","severity":"SEV 2","status":"Draft","sections":{}}',99);
  raise exception 'TEST: stale write accepted';
 exception when serialization_failure then null;end;
 begin
  update public.omniscient_audits set action='Tampered';
  raise exception 'TEST: audit tampering allowed';
 exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","email":"bob@omniscient.test","role":"authenticated"}',true);
do $$begin
 if (select count(*) from public.omniscient_records)<>0 then raise exception 'Cross-user report leak';end if;
 if (select count(*) from public.omniscient_audits)<>0 then raise exception 'Cross-user audit leak';end if;
 begin
  perform public.omniscient_save('10000000-0000-4000-8000-000000000002','task','{"title":"Unauthorized task","reportId":"10000000-0000-4000-8000-000000000001","status":"Open","priority":"High","due":"2026-11-10"}',null);
  raise exception 'TEST: task references another user report';
 exception when others then if sqlerrm like 'TEST:%' then raise;end if;end;
 begin
  perform public.omniscient_log_search('timeout',array['10000000-0000-4000-8000-000000000001'::uuid]);
  raise exception 'TEST: search log accepted inaccessible source';
 exception when others then if sqlerrm like 'TEST:%' then raise;end if;end;
end $$;
set local role anon;
do $$begin
 begin
  perform 1 from public.omniscient_records;
  raise exception 'TEST: anonymous read allowed';
 exception when insufficient_privilege then null;end;
end $$;
rollback;
select 'PASS: owner access, cross-user isolation, immutable audit access, stale edits, review completeness, action ownership, search source authorization, anonymous denial' as result;
