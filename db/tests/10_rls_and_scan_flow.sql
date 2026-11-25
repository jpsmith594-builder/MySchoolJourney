\set ON_ERROR_STOP on
\set parent  '''11111111-1111-1111-1111-111111111111'''
\set parent2 '''22222222-2222-2222-2222-222222222222'''
\set kid     '''33333333-3333-3333-3333-333333333333'''

-- fixtures that need superuser: auth users and profiles
insert into auth.users(id,email) values (:parent,'p@x'),(:parent2,'p2@x'),(:kid,'k@x');
insert into profiles(id,display_name,role) values
  (:parent,'Parent One','parent'),(:parent2,'Parent Two','parent'),(:kid,'Lerato','learner');

-- ===== as parent one =====
set role authenticated;
select set_config('request.jwt.claim.sub', :parent, false);

insert into learners(id,first_name,created_by) values ('aaaaaaaa-0000-0000-0000-000000000001','Lerato',:parent);
do $$ begin
  assert (select count(*) from learner_guardians where learner_id='aaaaaaaa-0000-0000-0000-000000000001' and guardian_id='11111111-1111-1111-1111-111111111111')=1, 'T1 creator not auto guardian';
  raise notice 'T1 ok: creator becomes guardian';
end $$;
update learners set user_id=:kid where id='aaaaaaaa-0000-0000-0000-000000000001';

insert into enrolments(id,learner_id,calendar_year,grade) values
 ('e0000000-0000-0000-0000-000000000008','aaaaaaaa-0000-0000-0000-000000000001',2024,8),
 ('e0000000-0000-0000-0000-000000000009','aaaaaaaa-0000-0000-0000-000000000001',2025,9),
 ('e0000000-0000-0000-0000-000000000010','aaaaaaaa-0000-0000-0000-000000000001',2026,10);
insert into term_results(id,learner_id,enrolment_id,term) values
 ('b0000000-0000-0000-0000-000000000081','aaaaaaaa-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000008',1),
 ('b0000000-0000-0000-0000-000000000082','aaaaaaaa-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000008',2),
 ('b0000000-0000-0000-0000-000000000083','aaaaaaaa-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000008',3),
 ('b0000000-0000-0000-0000-000000000101','aaaaaaaa-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000010',1);
-- maths marks 52,56(+),55(-) in grade 8; life sciences in term 1 of 2026
insert into subject_marks(learner_id,term_result_id,subject_id,mark_percent)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.tr::uuid, (select id from subjects where key=v.k), v.m
from (values
 ('b0000000-0000-0000-0000-000000000081','mathematics',52),
 ('b0000000-0000-0000-0000-000000000082','mathematics',56),
 ('b0000000-0000-0000-0000-000000000083','mathematics',55),
 ('b0000000-0000-0000-0000-000000000081','life_orientation',80),
 ('b0000000-0000-0000-0000-000000000101','life_sciences',82)) v(tr,k,m);

do $$ declare r record; begin
  -- view: averages. LO counts by default so term1 grade8 = (52+80)/2 = 66
  select average_percent into r from term_averages where grade=8 and term=1;
  assert r.average_percent=66.0, 'T2 average wrong: '||coalesce(r.average_percent::text,'null');
  -- view: change since previous term for maths
  assert (select change_since_previous_term from subject_term_marks where subject_name='Mathematics' and term=2)=4, 'T2b lag up';
  assert (select change_since_previous_term from subject_term_marks where subject_name='Mathematics' and term=3)=-1, 'T2c lag down';
  assert (select change_since_previous_term from subject_term_marks where subject_name='Mathematics' and term=1) is null, 'T2d first term null';
  raise notice 'T2 ok: term_averages and subject_term_marks give correct values';
end $$;

-- integrity: a mark cannot attach another learner's term result
reset role;
insert into learners(id,first_name,created_by) values ('aaaaaaaa-0000-0000-0000-000000000002','Other',:parent2);
set role authenticated; select set_config('request.jwt.claim.sub', :parent2, false);
do $$ begin
  begin
    insert into subject_marks(learner_id,term_result_id,subject_id,mark_percent)
    values ('aaaaaaaa-0000-0000-0000-000000000002','b0000000-0000-0000-0000-000000000081',1,50);
    raise exception 'T3 FAILED: cross-learner mark accepted';
  exception when foreign_key_violation or insufficient_privilege or check_violation then
    raise notice 'T3 ok: cross-learner mark rejected (%)', sqlstate;
  end;
end $$;

-- ===== other parent cannot see learner one =====
do $$ begin
  assert (select count(*) from learners where id='aaaaaaaa-0000-0000-0000-000000000001')=0, 'T4 learners leak';
  assert (select count(*) from subject_marks)=0, 'T4 marks leak';
  assert (select count(*) from term_averages)=0, 'T4 view leak';
  raise notice 'T4 ok: unrelated parent sees nothing (tables and views)';
end $$;
do $$ begin
  begin
    insert into enrolments(learner_id,calendar_year,grade) values ('aaaaaaaa-0000-0000-0000-000000000001',2027,11);
    raise exception 'T4b FAILED: wrote to another learner';
  exception when insufficient_privilege then raise notice 'T4b ok: write to another learner blocked';
  end;
end $$;

-- ===== learner login: role learner cannot create learners =====
select set_config('request.jwt.claim.sub', :kid, false);
do $$ begin
  begin
    insert into learners(first_name,created_by) values ('Sneaky','33333333-3333-3333-3333-333333333333');
    raise exception 'T5 FAILED: learner created a learner';
  exception when insufficient_privilege then raise notice 'T5 ok: learner role cannot create learners';
  end;
  assert (select count(*) from subject_marks)=5, 'T5b learner should see own marks';
  raise notice 'T5b ok: learner sees own marks';
end $$;

-- journal: private by default, shared entry visible to parent
insert into journal_entries(learner_id,body) values ('aaaaaaaa-0000-0000-0000-000000000001','private thoughts');
insert into journal_entries(learner_id,body,shared_with_guardians) values ('aaaaaaaa-0000-0000-0000-000000000001','proud of Term 3',true);
-- extramurals
insert into activities(id,learner_id,name,category) values ('ac000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Hockey','sport');
insert into activity_seasons(learner_id,activity_id,enrolment_id,first_term,last_term,role_or_achievement)
 values ('aaaaaaaa-0000-0000-0000-000000000001','ac000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000010',1,4,'1st team');

select set_config('request.jwt.claim.sub', :parent, false);
do $$ begin
  assert (select count(*) from journal_entries)=1, 'T6 parent should see only the shared entry, saw '||(select count(*) from journal_entries);
  assert (select body from journal_entries)='proud of Term 3', 'T6 wrong entry';
  begin
    insert into journal_entries(learner_id,body) values ('aaaaaaaa-0000-0000-0000-000000000001','parent writing');
    raise exception 'T6b FAILED: parent wrote journal';
  exception when insufficient_privilege then raise notice 'T6b ok: parent cannot write the learner journal';
  end;
  raise notice 'T6 ok: parent sees only shared journal entries';
  assert (select count(*) from activities)=1, 'T7 parent should see activities by default';
  raise notice 'T7 ok: parent sees extramurals by default';
end $$;

-- learner switches extramural sharing off
select set_config('request.jwt.claim.sub', :kid, false);
update learners set share_extramurals=false where id='aaaaaaaa-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub', :parent, false);
do $$ begin
  assert (select count(*) from activities)=0, 'T7b activities still visible';
  assert (select count(*) from activity_seasons)=0, 'T7c seasons still visible';
  assert (select count(*) from subject_marks)=5, 'T7d marks must stay visible to parent';
  raise notice 'T7b ok: sharing off hides extramurals, marks stay visible';
end $$;

-- ===== scan flow =====
insert into report_uploads(id,learner_id,enrolment_id,term,storage_path,mime_type,status,uploaded_by)
 values ('c0000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000010',3,'aaaaaaaa-0000-0000-0000-000000000001/c0000000-0000-0000-0000-000000000001.jpg','image/jpeg','needs_review',:parent);
insert into upload_rows(learner_id,upload_id,row_index,reported_name,subject_id,mark_percent,confidence,needs_check)
select 'aaaaaaaa-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001', v.i, v.n,
       (select subject_id from subject_aliases where alias=lower(btrim(v.n))), v.m, v.c, v.chk
from (values (1,'Maths',61,0.97,false),(2,'Phys Sci',64,0.55,true),(3,'Wiskunde',99,0.9,false)) v(i,n,m,c,chk);
do $$ begin
  assert (select subject_id from upload_rows where reported_name='Wiskunde') = (select id from subjects where key='mathematics'), 'T8 alias match failed';
  raise notice 'T8 ok: alias "Wiskunde" matched to Mathematics';
  begin
    perform confirm_upload('c0000000-0000-0000-0000-000000000001');
    raise exception 'T8b FAILED: confirmed with a flagged row';
  exception when others then
    if sqlerrm like 'every row needs%' then raise notice 'T8b ok: flagged row blocks confirmation';
    else raise; end if;
  end;
end $$;

-- unflag Phys Sci; the duplicate-subject rows (Maths + Wiskunde) must now give a clear error
update upload_rows set needs_check=false where reported_name='Phys Sci';
do $$ begin
  begin
    perform confirm_upload('c0000000-0000-0000-0000-000000000001');
    raise exception 'T8c FAILED: duplicate subject rows confirmed';
  exception when others then
    if sqlerrm = 'two rows are assigned to the same subject' then raise notice 'T8c ok: duplicate subject rows give a clear error';
    else raise exception 'T8c FAILED with unexpected error: %', sqlerrm; end if;
  end;
end $$;
-- learner removes the bad duplicate row, then confirmation succeeds
delete from upload_rows where reported_name='Wiskunde';
select confirm_upload('c0000000-0000-0000-0000-000000000001');
do $$ declare m record; begin
  assert (select status from report_uploads where id='c0000000-0000-0000-0000-000000000001')='confirmed', 'T9 status';
  assert (select delete_after from report_uploads where id='c0000000-0000-0000-0000-000000000001') > now()+interval '29 days', 'T9 delete_after';
  select * into m from subject_marks where source='scan' and subject_id=(select id from subjects where key='mathematics');
  assert m.mark_percent=61 and m.upload_id is not null and m.confirmed_by='11111111-1111-1111-1111-111111111111', 'T9 mark not saved correctly';
  assert (select count(*) from term_results where enrolment_id='e0000000-0000-0000-0000-000000000010' and term=3)=1, 'T9 term result not created';
  raise notice 'T9 ok: confirm_upload saved marks, term result, provenance and retention date';
end $$;
-- confirming again must not duplicate (idempotent upsert)
select confirm_upload('c0000000-0000-0000-0000-000000000001');
do $$ begin
  assert (select count(*) from subject_marks where source='scan')=2, 'T9b duplicated marks on re-confirm';
  raise notice 'T9b ok: re-confirming does not duplicate marks';
end $$;

-- ===== storage policies =====
insert into storage.objects(bucket_id,name) values ('report-scans','aaaaaaaa-0000-0000-0000-000000000001/c0000000-0000-0000-0000-000000000001.jpg');
do $$ begin
  assert (select count(*) from storage.objects)=1, 'T10 guardian cannot read own learner scan';
  raise notice 'T10 ok: guardian can store and read a scan for their learner';
end $$;
select set_config('request.jwt.claim.sub', :parent2, false);
do $$ begin
  assert (select count(*) from storage.objects)=0, 'T10b other parent can read scan';
  begin
    insert into storage.objects(bucket_id,name) values ('report-scans','aaaaaaaa-0000-0000-0000-000000000001/evil.jpg');
    raise exception 'T10c FAILED: other parent uploaded into learner folder';
  exception when insufficient_privilege then raise notice 'T10b/c ok: other parent cannot read or write that learner''s scans';
  end;
end $$;

-- ===== erasure =====
select set_config('request.jwt.claim.sub', :parent, false);
delete from learners where id='aaaaaaaa-0000-0000-0000-000000000001';
reset role;
do $$ declare t text; n bigint; bad text := ''; begin
  foreach t in array array['enrolments','term_results','subject_marks','report_uploads','upload_rows','activities','activity_seasons','goals','journal_entries','learner_guardians'] loop
    execute format('select count(*) from %I where learner_id = %L', t, 'aaaaaaaa-0000-0000-0000-000000000001') into n;
    if n<>0 then bad := bad||t||'='||n||' '; end if;
  end loop;
  assert bad='', 'T11 rows left after erasure: '||bad;
  assert (select count(*) from learners where id='aaaaaaaa-0000-0000-0000-000000000002')=1, 'T11b other learner was deleted';
  assert (select count(*) from learner_guardians where learner_id='aaaaaaaa-0000-0000-0000-000000000002')=1, 'T11c other learner guardian row lost';
  raise notice 'T11 ok: deleting a learner cascades through every table and leaves other learners untouched';
end $$;
