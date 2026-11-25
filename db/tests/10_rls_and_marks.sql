\set ON_ERROR_STOP on
\set parent  '''11111111-1111-1111-1111-111111111111'''
\set parent2 '''22222222-2222-2222-2222-222222222222'''
\set kid     '''33333333-3333-3333-3333-333333333333'''

-- =====================================================================
-- S. Seed sanity (as superuser): the CAPS list is complete and well formed
-- =====================================================================
do $$
declare missing text;
begin
  -- every official language at all three levels
  select string_agg(l || '_' || lv, ', ') into missing
  from unnest(array['afrikaans','english','isindebele','isixhosa','isizulu','sepedi','sesotho','setswana','siswati','tshivenda','xitsonga']) l,
       unnest(array['hl','fal','sal']) lv
  where not exists (select 1 from subjects where key = l || '_' || lv);
  assert missing is null, 'S1 missing official language rows: ' || missing;

  -- every Grade 10-12 subject on the DBE ATP list
  select string_agg(k, ', ') into missing
  from unnest(array[
    'accounting','agricultural_management_practices','agricultural_sciences','agricultural_technology',
    'business_studies','computer_applications_technology','civil_technology_civil_services',
    'civil_technology_construction','civil_technology_woodworking','consumer_studies','dance_studies','design',
    'dramatic_arts','economics','electrical_technology_digital_electronics','electrical_technology_electronics',
    'electrical_technology_power_systems','engineering_graphics_and_design','geography','history',
    'hospitality_studies','information_technology','life_orientation','life_sciences','mathematical_literacy',
    'mathematics','mechanical_technology_automotive','mechanical_technology_fitting_and_machining',
    'mechanical_technology_welding_and_metalwork','music_iam','music_jazz','music_wam','physical_sciences',
    'religion_studies','technical_mathematics','technical_sciences','tourism','visual_arts',
    'equine_studies','marine_sciences','maritime_economics','nautical_science','sport_and_exercise_science']) k
  where not exists (select 1 from subjects where key = k);
  assert missing is null, 'S2 missing FET subjects: ' || missing;

  -- phase subjects from the NCS policy
  select string_agg(k, ', ') into missing
  from unnest(array['life_skills','life_skills_beginning_knowledge','life_skills_creative_arts',
    'life_skills_physical_education','life_skills_personal_social_wellbeing','natural_sciences_technology',
    'social_sciences','natural_sciences','technology','ems','creative_arts','creative_arts_dance',
    'creative_arts_drama','creative_arts_music','creative_arts_visual_arts','sasl_hl',
    'german_sal','mandarin_sal','serbian_hl','serbian_sal']) k
  where not exists (select 1 from subjects where key = k);
  assert missing is null, 'S3 missing phase subjects: ' || missing;

  -- v0.1 keys still exist
  assert (select count(*) from subjects where key in ('english_hl','afrikaans_fal','isizulu_hl','mathematics')) = 4, 'S4 old keys lost';

  assert (select count(*) from subjects where is_life_orientation) = 1, 'S5 exactly one Life Orientation expected';
  assert not exists (select 1 from subjects where created_for_learner is not null), 'S6 seed must hold standard subjects only';

  -- every component has an umbrella whose grade range overlaps it
  assert not exists (
    select 1 from subjects c join subjects p on p.id = c.parent_subject_id
    where c.min_grade > p.max_grade or c.max_grade < p.min_grade), 'S7 component outside its umbrella grades';
  assert (select count(*) from subjects where parent_subject_id is not null) = 10, 'S8 expected 10 components';

  -- aliases all point somewhere and are lower case (enforced), career links resolved
  assert (select count(*) from subject_aliases) > 50, 'S9 aliases missing';
  assert (select count(*) from career_field_subjects) = 20, 'S10 career links';
  raise notice 'S ok: seed covers all official languages, every Grade 10-12 subject, all phase subjects and components';
end $$;

-- =====================================================================
-- Fixtures that need superuser: users, profiles, a second family
-- =====================================================================
insert into auth.users(id,email,raw_user_meta_data) values
  (:parent,'p@x','{"display_name":"Parent One","role":"parent"}'),
  (:parent2,'p2@x','{"display_name":"Parent Two"}'),
  (:kid,'k@x','{"display_name":"Lerato","role":"learner"}'),
  ('44444444-4444-4444-4444-444444444444','sneaky@x','{"role":"admin"}');
do $$ begin
  assert (select role from profiles where id='11111111-1111-1111-1111-111111111111')='parent', 'A1 parent role';
  assert (select role from profiles where id='22222222-2222-2222-2222-222222222222')='parent', 'A1b default role is parent';
  assert (select role from profiles where id='33333333-3333-3333-3333-333333333333')='learner', 'A1c learner role';
  assert (select display_name from profiles where id='33333333-3333-3333-3333-333333333333')='Lerato', 'A1d display name';
  assert (select role from profiles where id='44444444-4444-4444-4444-444444444444')='parent', 'A1e unknown role must fall back to parent';
  assert (select display_name from profiles where id='44444444-4444-4444-4444-444444444444')='sneaky', 'A1f name falls back to the email name';
  raise notice 'A ok: signing up creates a profile; display name and role come from the sign-up form, unknown roles become parent';
end $$;
insert into learners(id,first_name,created_by) values ('aaaaaaaa-0000-0000-0000-000000000002','Other',:parent2);
insert into enrolments(id,learner_id,calendar_year,grade) values ('e0000000-0000-0000-0000-000000000020','aaaaaaaa-0000-0000-0000-000000000002',2026,10);
insert into term_results(id,learner_id,enrolment_id,term) values ('b0000000-0000-0000-0000-000000000020','aaaaaaaa-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000020',1);

-- =====================================================================
-- Parent one builds a learner record
-- =====================================================================
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
 ('b0000000-0000-0000-0000-000000000091','aaaaaaaa-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000009',1),
 ('b0000000-0000-0000-0000-000000000101','aaaaaaaa-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000010',1);

insert into subject_marks(learner_id,term_result_id,subject_id,mark_percent)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.tr::uuid, (select id from subjects where key=v.k), v.m
from (values
 ('b0000000-0000-0000-0000-000000000081','mathematics',52),
 ('b0000000-0000-0000-0000-000000000082','mathematics',56),
 ('b0000000-0000-0000-0000-000000000083','mathematics',55),
 ('b0000000-0000-0000-0000-000000000081','life_orientation',80),
 ('b0000000-0000-0000-0000-000000000101','life_sciences',82)) v(tr,k,m);

-- ---------------------------------------------------------------------
-- Two averages: Life Orientation counts, and an average excluding it
-- ---------------------------------------------------------------------
do $$ declare r record; begin
  select * into r from term_averages where grade=8 and term=1;
  assert r.average_percent=66.0, 'T2 average with LO wrong: '||coalesce(r.average_percent::text,'null');
  assert r.average_excluding_lo=52.0, 'T2 average excluding LO wrong: '||coalesce(r.average_excluding_lo::text,'null');
  assert r.subjects_counted=2, 'T2 subjects counted';
  -- a term with no LO mark: both averages agree
  select * into r from term_averages where grade=8 and term=2;
  assert r.average_percent=56.0 and r.average_excluding_lo=56.0, 'T2b averages should match without LO';
  -- year averages are the mean of the term averages recorded so far
  select * into r from year_averages where grade=8;
  assert r.average_percent=59.0, 'T2c year average with LO: '||r.average_percent;
  assert r.average_excluding_lo=54.3, 'T2c year average excluding LO: '||r.average_excluding_lo;
  assert r.terms_recorded=3, 'T2c terms recorded';
  -- change since previous term
  assert (select change_since_previous_term from subject_term_marks where subject_name='Mathematics' and term=2 and grade=8)=4, 'T2d lag up';
  assert (select change_since_previous_term from subject_term_marks where subject_name='Mathematics' and term=3 and grade=8)=-1, 'T2e lag down';
  assert (select change_since_previous_term from subject_term_marks where subject_name='Mathematics' and term=1 and grade=8) is null, 'T2f first term null';
  raise notice 'T2 ok: average with Life Orientation, average excluding it, year averages and term-on-term change';
end $$;

-- ---------------------------------------------------------------------
-- Components: History and Geography count on their own, unless the umbrella has a mark
-- ---------------------------------------------------------------------
insert into subject_marks(learner_id,term_result_id,subject_id,mark_percent)
select 'aaaaaaaa-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000091',(select id from subjects where key=k),m
from (values ('history',70),('geography',80)) v(k,m);
do $$ begin
  assert (select average_percent from term_averages where grade=9 and term=1)=75.0, 'T3 components should count on their own';
  assert (select subjects_counted from term_averages where grade=9 and term=1)=2, 'T3 two components counted';
end $$;
insert into subject_marks(learner_id,term_result_id,subject_id,mark_percent)
values ('aaaaaaaa-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000091',(select id from subjects where key='social_sciences'),60);
do $$ begin
  assert (select average_percent from term_averages where grade=9 and term=1)=60.0, 'T3b umbrella mark should replace its components';
  assert (select subjects_counted from term_averages where grade=9 and term=1)=1, 'T3b one mark counted';
  raise notice 'T3 ok: components count alone, and are not double counted once the umbrella has a mark';
end $$;

-- ---------------------------------------------------------------------
-- Extra subjects
-- ---------------------------------------------------------------------
insert into subjects(name, short_name, category, created_for_learner)
values ('Chess','Chess','other','aaaaaaaa-0000-0000-0000-000000000001');
insert into subject_marks(learner_id,term_result_id,subject_id,mark_percent)
select 'aaaaaaaa-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000101',id,90
from subjects where name='Chess' and created_for_learner='aaaaaaaa-0000-0000-0000-000000000001';
do $$ begin
  assert (select average_percent from term_averages where grade=10 and term=1)=86.0, 'T4 extra subject should count';
  update subjects set counts_toward_average=false where name='Chess';
  assert (select average_percent from term_averages where grade=10 and term=1)=82.0, 'T4b opted-out extra subject should not count';
  raise notice 'T4 ok: an extra subject counts in the average, and can opt out';
end $$;
do $$ begin
  begin
    insert into subjects(key,name,short_name,category) values ('sneaky','Sneaky','Sneaky','other');
    raise exception 'T4c FAILED: a user created a standard subject';
  exception when insufficient_privilege then raise notice 'T4c ok: users cannot create standard subjects';
  end;
  begin
    insert into subjects(key,name,short_name,category,created_for_learner)
    values ('k','Both','Both','other','aaaaaaaa-0000-0000-0000-000000000001');
    raise exception 'T4d FAILED: extra subject accepted a key';
  exception when check_violation or insufficient_privilege then raise notice 'T4d ok: extra subjects cannot carry a standard key';
  end;
  begin
    insert into subjects(name,short_name,category,created_for_learner)
    values ('chess','Chess','other','aaaaaaaa-0000-0000-0000-000000000001');
    raise exception 'T4e FAILED: duplicate extra subject name accepted';
  exception when unique_violation then raise notice 'T4e ok: duplicate extra subject names rejected (case-insensitive)';
  end;
end $$;

-- the trigger refuses another learner's extra subject (tested as superuser so RLS is not the thing doing the work)
reset role;
do $$ begin
  begin
    insert into subject_marks(learner_id,term_result_id,subject_id,mark_percent)
    values ('aaaaaaaa-0000-0000-0000-000000000002','b0000000-0000-0000-0000-000000000020',
            (select id from subjects where name='Chess'),50);
    raise exception 'T4f FAILED: another learner used this extra subject';
  exception when foreign_key_violation then raise notice 'T4f ok: an extra subject cannot be used for another learner';
  end;
end $$;
set role authenticated;

-- ---------------------------------------------------------------------
-- Cross-learner integrity and unrelated family
-- ---------------------------------------------------------------------
select set_config('request.jwt.claim.sub', :parent2, false);
do $$ begin
  begin
    insert into subject_marks(learner_id,term_result_id,subject_id,mark_percent)
    values ('aaaaaaaa-0000-0000-0000-000000000002','b0000000-0000-0000-0000-000000000081',(select id from subjects where key='geography'),50);
    raise exception 'T5 FAILED: cross-learner mark accepted';
  exception when foreign_key_violation or insufficient_privilege or check_violation then
    raise notice 'T5 ok: a mark cannot attach to another learner''s term (%)', sqlstate;
  end;
  assert (select count(*) from learners where id='aaaaaaaa-0000-0000-0000-000000000001')=0, 'T6 learners leak';
  assert (select count(*) from subject_marks)=0, 'T6 marks leak';
  assert (select count(*) from term_averages)=0, 'T6 averages view leak';
  assert (select count(*) from year_averages)=0, 'T6 year view leak';
  assert (select count(*) from mark_audit)=0, 'T6 audit leak';
  assert (select count(*) from subjects where created_for_learner is not null)=0, 'T6 extra subject leak';
  raise notice 'T6 ok: an unrelated parent sees nothing (tables, views, audit log, extra subjects)';
  begin
    insert into enrolments(learner_id,calendar_year,grade) values ('aaaaaaaa-0000-0000-0000-000000000001',2027,11);
    raise exception 'T6b FAILED: wrote to another learner';
  exception when insufficient_privilege then raise notice 'T6b ok: write to another learner blocked';
  end;
end $$;

-- ---------------------------------------------------------------------
-- The learner: can add and correct marks, can never hide them
-- ---------------------------------------------------------------------
select set_config('request.jwt.claim.sub', :kid, false);
do $$ declare n int; begin
  begin
    insert into learners(first_name,created_by) values ('Sneaky','33333333-3333-3333-3333-333333333333');
    raise exception 'T7 FAILED: learner created a learner';
  exception when insufficient_privilege then raise notice 'T7 ok: learner role cannot create learners';
  end;
  assert (select count(*) from subject_marks)=9, 'T7b learner should see own marks, saw '||(select count(*) from subject_marks);

  -- there is no flag anywhere that could hide a mark
  assert not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name in ('subject_marks','term_results','enrolments','mark_audit')
      and (column_name ilike '%hidden%' or column_name ilike '%private%' or column_name ilike '%share%' or column_name ilike '%visible%')),
    'T8 a visibility column exists on the marks tables';

  -- deleting is silently a no-op for a learner (no delete policy applies)
  delete from subject_marks;      get diagnostics n = row_count; assert n=0, 'T8b learner deleted marks';
  delete from term_results;       get diagnostics n = row_count; assert n=0, 'T8c learner deleted terms';
  delete from enrolments;         get diagnostics n = row_count; assert n=0, 'T8d learner deleted years';
  delete from learner_guardians;  get diagnostics n = row_count; assert n=0, 'T8e learner removed a guardian';
  assert (select count(*) from subject_marks)=9, 'T8f marks changed';
  -- deleting an extra subject that still has marks must fail, so it cannot be used to hide them
  set constraints all immediate;
  begin
    delete from subjects where name='Chess';
    raise exception 'T8g FAILED: an extra subject with marks was deleted';
  exception when foreign_key_violation then null;
  end;
  set constraints all deferred;
  assert (select count(*) from subject_marks)=9, 'T8h marks changed after the delete attempt';
  raise notice 'T8 ok: no way to hide marks; a learner cannot delete marks, terms, years or guardians';
end $$;

-- a learner may correct a mark, and the correction is logged
update subject_marks set mark_percent=57
 where term_result_id='b0000000-0000-0000-0000-000000000083'
   and subject_id=(select id from subjects where key='mathematics');
do $$ declare r record; begin
  select * into r from mark_audit where action='update' order by id desc limit 1;
  assert r.old_mark_percent=55 and r.new_mark_percent=57, 'T9 audit values';
  assert r.changed_by='33333333-3333-3333-3333-333333333333', 'T9 audit actor';
  begin
    insert into mark_audit(learner_id,action) values ('aaaaaaaa-0000-0000-0000-000000000001','insert');
    raise exception 'T9b FAILED: learner wrote to the audit log';
  exception when insufficient_privilege then null;
  end;
  raise notice 'T9 ok: a learner correction is allowed and logged with who and what changed';
end $$;

-- ---------------------------------------------------------------------
-- The guardian sees the log, can delete (also logged), and the log cannot be edited
-- ---------------------------------------------------------------------
select set_config('request.jwt.claim.sub', :parent, false);
do $$ declare n int; r record; begin
  select * into r from mark_audit where action='update' and changed_by='33333333-3333-3333-3333-333333333333';
  assert found, 'T10 guardian cannot see the learner correction';
  -- guardian reverts it
  update subject_marks set mark_percent=55
   where term_result_id='b0000000-0000-0000-0000-000000000083'
     and subject_id=(select id from subjects where key='mathematics');
  -- guardian deletes a mark
  insert into subject_marks(learner_id,term_result_id,subject_id,mark_percent)
  values ('aaaaaaaa-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000101',(select id from subjects where key='religion_studies'),40);
  delete from subject_marks where subject_id=(select id from subjects where key='religion_studies');
  get diagnostics n = row_count; assert n=1, 'T10b guardian could not delete a mark';
  assert exists (select 1 from mark_audit where action='delete' and old_mark_percent=40), 'T10c delete not logged';
  update mark_audit set new_mark_percent=0;   get diagnostics n = row_count; assert n=0, 'T10d audit edited';
  delete from mark_audit;                      get diagnostics n = row_count; assert n=0, 'T10e audit deleted';
  raise notice 'T10 ok: guardian sees every change, can delete (logged), and nobody can edit the log';
end $$;

-- ---------------------------------------------------------------------
-- Journal and extramurals
-- ---------------------------------------------------------------------
select set_config('request.jwt.claim.sub', :kid, false);
insert into journal_entries(learner_id,body) values ('aaaaaaaa-0000-0000-0000-000000000001','private thoughts');
insert into journal_entries(learner_id,body,shared_with_guardians) values ('aaaaaaaa-0000-0000-0000-000000000001','proud of Term 3',true);
insert into activities(id,learner_id,name,category) values ('ac000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Hockey','sport');
insert into activity_seasons(learner_id,activity_id,enrolment_id,first_term,last_term,role_or_achievement)
 values ('aaaaaaaa-0000-0000-0000-000000000001','ac000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000010',1,4,'1st team');

select set_config('request.jwt.claim.sub', :parent, false);
do $$ begin
  assert (select count(*) from journal_entries)=1, 'T11 parent should see only the shared entry';
  begin
    insert into journal_entries(learner_id,body) values ('aaaaaaaa-0000-0000-0000-000000000001','parent writing');
    raise exception 'T11b FAILED: parent wrote journal';
  exception when insufficient_privilege then null;
  end;
  assert (select count(*) from activities)=1, 'T12 parent should see activities by default';
  raise notice 'T11/T12 ok: parent sees only shared journal entries and, by default, extramurals';
end $$;
select set_config('request.jwt.claim.sub', :kid, false);
update learners set share_extramurals=false where id='aaaaaaaa-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub', :parent, false);
do $$ begin
  assert (select count(*) from activities)=0 and (select count(*) from activity_seasons)=0, 'T12b extramurals still visible';
  assert (select count(*) from subject_marks)>=8, 'T12c marks must stay visible to the parent';
  raise notice 'T12b ok: sharing off hides extramurals, marks stay visible';
end $$;

-- ---------------------------------------------------------------------
-- Report card copies for record keeping
-- ---------------------------------------------------------------------
insert into report_attachments(id,learner_id,enrolment_id,term,file_name,storage_path,mime_type,size_bytes)
values ('a1000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000010',1,
        'Term 1 report.pdf','aaaaaaaa-0000-0000-0000-000000000001/a1000000-0000-0000-0000-000000000001.pdf','application/pdf',250000);
do $$ begin
  begin
    insert into report_attachments(learner_id,enrolment_id,file_name,storage_path,mime_type,size_bytes)
    values ('aaaaaaaa-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000010','x.pdf','aaaaaaaa-0000-0000-0000-000000000002/x.pdf','application/pdf',1000);
    raise exception 'T13 FAILED: path outside the learner folder accepted';
  exception when check_violation then null; end;
  begin
    insert into report_attachments(learner_id,enrolment_id,file_name,storage_path,mime_type,size_bytes)
    values ('aaaaaaaa-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000010','x.txt','aaaaaaaa-0000-0000-0000-000000000001/x.txt','text/plain',1000);
    raise exception 'T13b FAILED: text file accepted';
  exception when check_violation then null; end;
  begin
    insert into report_attachments(learner_id,enrolment_id,file_name,storage_path,mime_type,size_bytes)
    values ('aaaaaaaa-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000010','big.pdf','aaaaaaaa-0000-0000-0000-000000000001/big.pdf','application/pdf',20000000);
    raise exception 'T13c FAILED: 20 MB file accepted';
  exception when check_violation then null; end;
  raise notice 'T13 ok: attachments must be in the learner folder, PDF or image, and at most 10 MB';
end $$;

insert into storage.objects(bucket_id,name) values ('report-attachments','aaaaaaaa-0000-0000-0000-000000000001/a1000000-0000-0000-0000-000000000001.pdf');
do $$ begin
  assert (select count(*) from storage.objects)=1, 'T14 guardian cannot read own learner file';
  raise notice 'T14 ok: guardian can store and read a report copy for their learner';
end $$;
select set_config('request.jwt.claim.sub', :kid, false);
do $$ declare n int; begin
  assert (select count(*) from storage.objects)=1, 'T14b learner cannot read own file';
  assert (select count(*) from report_attachments)=1, 'T14c learner cannot see the attachment row';
  delete from report_attachments; get diagnostics n = row_count; assert n=0, 'T14d learner deleted an attachment row';
  delete from storage.objects;    get diagnostics n = row_count; assert n=0, 'T14e learner deleted a stored file';
  raise notice 'T14b ok: learner can read report copies but not delete them';
end $$;
select set_config('request.jwt.claim.sub', :parent2, false);
do $$ begin
  assert (select count(*) from storage.objects)=0, 'T15 other parent can read file';
  assert (select count(*) from report_attachments)=0, 'T15b other parent sees attachment row';
  begin
    insert into storage.objects(bucket_id,name) values ('report-attachments','aaaaaaaa-0000-0000-0000-000000000001/evil.pdf');
    raise exception 'T15c FAILED: other parent uploaded into the learner folder';
  exception when insufficient_privilege then raise notice 'T15 ok: another family cannot read or write these report copies';
  end;
end $$;
reset role;
do $$ begin
  assert (select file_size_limit from storage.buckets where id='report-attachments')=10485760, 'T16 bucket size limit';
  assert (select 'application/pdf' = any (allowed_mime_types) and not ('text/plain' = any (allowed_mime_types)) from storage.buckets where id='report-attachments'), 'T16 bucket mime types';
  raise notice 'T16 ok: the bucket is private with a 10 MB limit and PDF and image types only';
end $$;
select count(*) as audit_rows_before_erasure from mark_audit \gset
set role authenticated;

-- ---------------------------------------------------------------------
-- Erasure: one learner goes, everything of theirs goes, other families are untouched
-- ---------------------------------------------------------------------
select set_config('request.jwt.claim.sub', :parent, false);
delete from learners where id='aaaaaaaa-0000-0000-0000-000000000001';
reset role;
do $$ declare t text; n bigint; bad text := ''; begin
  foreach t in array array['enrolments','term_results','subject_marks','report_attachments','activities','activity_seasons',
                           'goals','journal_entries','learner_guardians','mark_audit'] loop
    execute format('select count(*) from %I where learner_id = %L', t, 'aaaaaaaa-0000-0000-0000-000000000001') into n;
    if n<>0 then bad := bad||t||'='||n||' '; end if;
  end loop;
  assert bad='', 'T17 rows left after erasure: '||bad;
  assert not exists (select 1 from subjects where created_for_learner='aaaaaaaa-0000-0000-0000-000000000001'), 'T17b extra subjects left';
  assert (select count(*) from learners where id='aaaaaaaa-0000-0000-0000-000000000002')=1, 'T17c other learner was deleted';
  assert (select count(*) from term_results where learner_id='aaaaaaaa-0000-0000-0000-000000000002')=1, 'T17d other learner data lost';
  assert (select count(*) from subjects where created_for_learner is null)>100, 'T17e standard subjects touched';
  raise notice 'T17 ok: erasing a learner removes all their data, including extra subjects and the audit log, and leaves others untouched';
end $$;
