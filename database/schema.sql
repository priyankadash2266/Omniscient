-- Omniscient Vercel foundation. Apply once to a new Supabase project.
create schema if not exists omniscient_private;
revoke all on schema omniscient_private from public, anon, authenticated;
create table public.omniscient_records (
 id uuid primary key, owner uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in ('report','task','team')), data jsonb not null check(jsonb_typeof(data)='object'),
 revision integer not null default 1, updated_at timestamptz not null default now()
);
create index omniscient_records_owner_kind on public.omniscient_records(owner,kind);
alter table public.omniscient_records enable row level security;
create policy own_records_select on public.omniscient_records for select to authenticated using(owner=(select auth.uid()));
create policy own_records_insert on public.omniscient_records for insert to authenticated with check(owner=(select auth.uid()));
create policy own_records_update on public.omniscient_records for update to authenticated using(owner=(select auth.uid())) with check(owner=(select auth.uid()));
revoke all on public.omniscient_records from anon, authenticated;
grant select,insert,update on public.omniscient_records to authenticated;
create table public.omniscient_audits (
 id uuid primary key default gen_random_uuid(), owner uuid not null references auth.users(id) on delete cascade,
 actor text not null, action text not null, resource text not null, created_at timestamptz not null default now()
);
create index omniscient_audits_owner_time on public.omniscient_audits(owner,created_at desc);
alter table public.omniscient_audits enable row level security;
create policy own_audits_select on public.omniscient_audits for select to authenticated using(owner=(select auth.uid()));
revoke all on public.omniscient_audits from anon, authenticated;
grant select on public.omniscient_audits to authenticated;

create function omniscient_private.validate_record() returns trigger language plpgsql security invoker set search_path='' as $$
declare section_name text; complete_count integer:=0;
begin
 if auth.uid() is null or new.owner<>auth.uid() then raise exception 'Sign in required'; end if;
 if octet_length(new.data::text)>250000 then raise exception 'Document too large';end if;
 if tg_op='UPDATE' then
  if new.kind<>old.kind or new.owner<>old.owner or new.id<>old.id then raise exception 'Identity cannot change';end if;
  new.revision:=old.revision+1;
 else new.revision:=1; end if;
 new.updated_at:=now();
 if new.kind in ('report','task') and (coalesce(length(trim(new.data->>'title')),0)=0 or length(new.data->>'title')>300) then raise exception 'Title required';end if;
 if new.kind='report' then
  if not coalesce(new.data->>'label' in ('Public','Internal','Confidential','Restricted'),false) or not coalesce(new.data->>'severity' in ('SEV 1','SEV 2','SEV 3','SEV 4'),false) then raise exception 'Invalid report metadata';end if;
  if not coalesce(new.data->>'status' in ('Draft','In review','Changes requested'),false) then raise exception 'Independent approval not enabled';end if;
  foreach section_name in array array['Summary','Impact','Background','Trigger','Detection','Root cause','Lessons learned','5 whys','Mitigations','Timeline'] loop
   if length(coalesce(new.data->'sections'->>section_name,''))>18000 then raise exception 'Section too large';end if;
   if length(trim(coalesce(new.data->'sections'->>section_name,'')))>0 then complete_count:=complete_count+1;end if;
  end loop;
  if new.data->>'status'='In review' and complete_count<10 then raise exception 'Complete all ten sections before review';end if;
  if new.data::text ~ '(-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|sk-(proj-)?[A-Za-z0-9_-]{20,}|(ghp|github_pat)_[A-Za-z0-9_]{20,})' then raise exception 'Possible credential detected';end if;
 elsif new.kind='task' then
  if not coalesce(new.data->>'status' in ('Open','In progress','Done'),false) or not coalesce(new.data->>'priority' in ('High','Medium','Low'),false) then raise exception 'Invalid action item';end if;
  if not exists(select 1 from public.omniscient_records where id::text=new.data->>'reportId' and owner=auth.uid() and kind='report') then raise exception 'Choose an owned RCA';end if;
  if not coalesce(new.data->>'due' ~ '^\d{4}-\d{2}-\d{2}$',false) then raise exception 'Due date required';end if;
  perform (new.data->>'due')::date;
 elsif new.kind='team' then
  if coalesce(length(trim(new.data->>'name')),0)=0 then raise exception 'Team name required';end if;
  if (select count(*) from unnest(string_to_array(coalesce(new.data->>'members',''),',')) x where length(trim(x))>0)>30 then raise exception 'Maximum 30 members';end if;
 end if;
 return new;
end $$;
create trigger validate_omniscient_record before insert or update on public.omniscient_records for each row execute function omniscient_private.validate_record();

-- Narrow trigger privilege: clients cannot insert, change or delete audit entries.
create function omniscient_private.audit_record() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or new.owner<>auth.uid() then raise exception 'Sign in required';end if;
 insert into public.omniscient_audits(owner,actor,action,resource) values(auth.uid(),coalesce(auth.jwt()->>'email',auth.uid()::text),case when tg_op='INSERT' then 'Created ' else 'Updated ' end||new.kind,coalesce(new.data->>'title',new.data->>'name','Record'));
 return new;
end $$;
revoke all on function omniscient_private.audit_record() from public,anon,authenticated;
revoke all on function omniscient_private.validate_record() from public,anon,authenticated;
create trigger audit_omniscient_record after insert or update on public.omniscient_records for each row execute function omniscient_private.audit_record();

create function public.omniscient_save(p_id uuid,p_kind text,p_data jsonb,p_revision integer default null) returns jsonb language plpgsql security invoker set search_path='' as $$
declare changed integer; current_revision integer;
begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 if p_revision is null then
  insert into public.omniscient_records(id,owner,kind,data) values(p_id,auth.uid(),p_kind,p_data);
  current_revision:=1;
 else
  update public.omniscient_records set data=p_data where id=p_id and owner=auth.uid() and kind=p_kind and revision=p_revision returning revision into current_revision;
  get diagnostics changed=row_count;
  if changed=0 then raise exception 'Record changed. Reload before saving.' using errcode='40001';end if;
 end if;
 return jsonb_build_object('ok',true,'id',p_id,'revision',current_revision);
end $$;
revoke all on function public.omniscient_save(uuid,text,jsonb,integer) from public,anon;
grant execute on function public.omniscient_save(uuid,text,jsonb,integer) to authenticated;

create function public.omniscient_seed(p_reports jsonb,p_tasks jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare item jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 if exists(select 1 from public.omniscient_records where owner=auth.uid()) then raise exception 'Examples require an empty workspace';end if;
 if jsonb_array_length(p_reports)>5 or jsonb_array_length(p_tasks)>10 then raise exception 'Too many examples';end if;
 for item in select value from jsonb_array_elements(p_reports) loop
  perform public.omniscient_save((item->>'id')::uuid,'report',item,null);
 end loop;
 for item in select value from jsonb_array_elements(p_tasks) loop
  perform public.omniscient_save((item->>'id')::uuid,'task',item,null);
 end loop;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.omniscient_seed(jsonb,jsonb) from public,anon;
grant execute on function public.omniscient_seed(jsonb,jsonb) to authenticated;

create function omniscient_private.log_search(p_query text,p_documents uuid[]) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 if length(p_query)>2000 or cardinality(p_documents)>4 then raise exception 'Invalid search';end if;
 if exists(select 1 from unnest(p_documents) d where not exists(select 1 from public.omniscient_records r where r.id=d and r.owner=auth.uid() and r.kind='report')) then raise exception 'Source access denied';end if;
 insert into public.omniscient_audits(owner,actor,action,resource) values(auth.uid(),coalesce(auth.jwt()->>'email',auth.uid()::text),'Searched evidence',jsonb_build_object('query',p_query,'documents',p_documents)::text);
end $$;
revoke all on function omniscient_private.log_search(text,uuid[]) from public,anon;
grant usage on schema omniscient_private to authenticated;
grant execute on function omniscient_private.log_search(text,uuid[]) to authenticated;
create function public.omniscient_log_search(p_query text,p_documents uuid[]) returns void language sql security invoker set search_path='' as $$select omniscient_private.log_search(p_query,p_documents)$$;
revoke all on function public.omniscient_log_search(text,uuid[]) from public,anon;
grant execute on function public.omniscient_log_search(text,uuid[]) to authenticated;
