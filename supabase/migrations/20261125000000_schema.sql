-- =====================================================================
-- My School Journey: data model v0.2 (draft)
-- Target: Postgres 15+ on Supabase (uses auth.users, auth.uid(), storage.*)
-- Run order: schema.sql, then seed.sql
--
-- v0.2 changes: marks can never be hidden from guardians (and every change is logged),
-- two averages (with and without Life Orientation), learner-specific extra subjects,
-- the full CAPS subject list (see seed.sql), and report cards are stored as attachments
-- for record keeping instead of being read by a scanner.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------
create or replace function set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ---------------------------------------------------------------------
-- People and access
-- ---------------------------------------------------------------------

-- One row per sign-in (parent or learner). Create it from an auth.users trigger.
create table profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role         text not null check (role in ('parent', 'learner')),
  created_at   timestamptz not null default now()
);

-- A learner is a person's school record. The learner may or may not have a login.
-- Data minimisation: first name only. No surname, ID number or date of birth.
create table learners (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid unique references profiles(id) on delete set null,
  first_name        text not null,
  created_by        uuid not null references profiles(id),
  share_extramurals boolean not null default true,  -- guardians see extramurals unless the learner turns it off
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- Which parents or guardians can see (and optionally edit) a learner.
create table learner_guardians (
  learner_id   uuid not null references learners(id) on delete cascade,
  guardian_id  uuid not null references profiles(id) on delete cascade,
  relationship text not null default 'parent' check (relationship in ('parent', 'guardian', 'other')),
  can_edit     boolean not null default true,
  created_at   timestamptz not null default now(),
  primary key (learner_id, guardian_id)
);

-- POPIA: a guardian's recorded consent for each purpose, with the policy version shown.
create table consents (
  id             uuid primary key default gen_random_uuid(),
  learner_id     uuid not null references learners(id) on delete cascade,
  guardian_id    uuid not null references profiles(id),
  purpose        text not null check (purpose in ('store_results', 'store_report_copies', 'career_insights', 'learner_account')),
  policy_version text not null,
  granted_at     timestamptz not null default now(),
  withdrawn_at   timestamptz
);

-- Access helpers used by every policy below.
create or replace function is_learner_self(p_learner uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from learners l where l.id = p_learner and l.user_id = auth.uid());
$$;

create or replace function is_guardian(p_learner uuid, p_need_edit boolean default false) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from learner_guardians g
    where g.learner_id = p_learner
      and g.guardian_id = auth.uid()
      and (not p_need_edit or g.can_edit)
  );
$$;

create or replace function can_access_learner(p_learner uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select is_learner_self(p_learner) or is_guardian(p_learner, false);
$$;

create or replace function can_edit_learner(p_learner uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select is_learner_self(p_learner) or is_guardian(p_learner, true);
$$;

-- The parent who creates a learner becomes their first guardian.
create or replace function learners_add_creator_as_guardian() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into learner_guardians (learner_id, guardian_id, relationship, can_edit)
  values (new.id, new.created_by, 'parent', true)
  on conflict do nothing;
  return new;
end $$;

create trigger learners_creator_guardian
  after insert on learners
  for each row execute function learners_add_creator_as_guardian();

-- ---------------------------------------------------------------------
-- Subjects
-- ---------------------------------------------------------------------

-- The CAPS subjects (seed.sql) plus any extra subjects a family adds for one learner.
--   created_for_learner is null     -> a standard subject, maintained by us
--   created_for_learner is not null -> an extra subject, visible only to that learner's people
-- min_grade and max_grade are the typical range, used to suggest subjects. They are NOT enforced,
-- because schools differ; any subject can be recorded against any grade.
-- parent_subject_id links a component to its umbrella (History and Geography sit under Social Sciences,
-- the four art forms under Creative Arts, and so on). If a term has a mark for the umbrella, its
-- components are left out of the averages so nothing is counted twice.
create table subjects (
  id                    smallint generated always as identity primary key,
  key                   text unique,
  name                  text not null,
  short_name            text not null,
  category              text not null check (category in
                          ('language', 'mathematics', 'science', 'humanities', 'commerce', 'technology',
                           'agriculture', 'services', 'arts', 'life_skills', 'other')),
  min_grade             smallint not null default 0  check (min_grade between 0 and 12),
  max_grade             smallint not null default 12 check (max_grade between 0 and 12),
  parent_subject_id     smallint references subjects(id),
  is_life_orientation   boolean  not null default false,  -- drives the "average excluding Life Orientation"
  counts_toward_average boolean  not null default true,   -- every standard subject counts; extra subjects can opt out
  created_for_learner   uuid references learners(id) on delete cascade,
  created_at            timestamptz not null default now(),
  check (min_grade <= max_grade),
  check ((created_for_learner is null and key is not null)
      or (created_for_learner is not null and key is null)),
  check (created_for_learner is null or (parent_subject_id is null and not is_life_orientation))
);

create unique index subjects_extra_name on subjects (created_for_learner, lower(name))
  where created_for_learner is not null;

-- Names seen on reports or typed by people ("Maths", "Wiskunde", "LO"), mapped to one subject. Lower case.
create table subject_aliases (
  alias      text primary key check (alias = lower(btrim(alias))),
  subject_id smallint not null references subjects(id) on delete cascade
);

create table career_fields (
  id                 smallint generated always as identity primary key,
  key                text not null unique,
  name               text not null,
  summary            text not null,
  requirements_note  text not null   -- hedged, plain-language note about what this field usually asks for
);

create table career_field_subjects (
  career_field_id smallint not null references career_fields(id) on delete cascade,
  subject_id      smallint not null references subjects(id) on delete cascade,
  weight          text not null check (weight in ('core', 'helpful')),
  primary key (career_field_id, subject_id)
);

-- ---------------------------------------------------------------------
-- School years, terms and marks
-- ---------------------------------------------------------------------

-- One row per learner per school year. Grade 0 = Grade R. Repeating a grade is a new year, same grade.
create table enrolments (
  id            uuid primary key default gen_random_uuid(),
  learner_id    uuid not null references learners(id) on delete cascade,
  calendar_year smallint not null check (calendar_year between 2000 and 2100),
  grade         smallint not null check (grade between 0 and 12),
  -- CAPS phase: Foundation R-3, Intermediate 4-6, Senior 7-9, FET 10-12
  phase         text generated always as (
                  case when grade <= 3 then 'foundation'
                       when grade <= 6 then 'intermediate'
                       when grade <= 9 then 'senior'
                       else 'fet' end) stored,
  school_level  text generated always as (case when grade <= 7 then 'primary' else 'high' end) stored,
  school_name   text,
  created_at    timestamptz not null default now(),
  unique (learner_id, calendar_year),
  unique (id, learner_id)   -- lets child tables prove they belong to the same learner
);

-- One row per enrolment per term.
create table term_results (
  id               uuid primary key default gen_random_uuid(),
  learner_id       uuid not null,
  enrolment_id     uuid not null,
  term             smallint not null check (term between 1 and 4),
  reported_average numeric(5,2) check (reported_average between 0 and 100),  -- average printed on the report, to cross-check ours
  report_date      date,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  foreign key (enrolment_id, learner_id) references enrolments(id, learner_id) on delete cascade,
  unique (enrolment_id, term),
  unique (id, learner_id)
);

-- Marks are typed in by the learner or a guardian. This is the source of every chart.
-- A learner can add and correct marks but cannot delete them, and every change is logged (mark_audit).
create table subject_marks (
  id                uuid primary key default gen_random_uuid(),
  learner_id        uuid not null,
  term_result_id    uuid not null,
  -- Deferred so erasing a learner can remove their extra subjects and marks in one go. It also means
  -- an extra subject that still has marks cannot be deleted (the commit fails), so that cannot hide marks.
  subject_id        smallint not null references subjects(id) deferrable initially deferred,
  reported_name     text,                      -- what the report called it, if different
  mark_percent      numeric(5,2) check (mark_percent between 0 and 100),
  achievement_level smallint check (achievement_level between 1 and 7),  -- primary reports often show levels
  entered_by        uuid default auth.uid() references profiles(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  foreign key (term_result_id, learner_id) references term_results(id, learner_id) on delete cascade,
  unique (term_result_id, subject_id),
  check (mark_percent is not null or achievement_level is not null)
);

-- Who changed which mark, when, from what to what. Guardians and the learner can read it; nobody can edit it.
create table mark_audit (
  id                    bigint generated always as identity primary key,
  learner_id            uuid not null references learners(id) on delete cascade,
  term_result_id        uuid,       -- no foreign key on purpose: history outlives the mark
  subject_id            smallint,
  action                text not null check (action in ('insert', 'update', 'delete')),
  old_mark_percent      numeric(5,2),
  new_mark_percent      numeric(5,2),
  old_achievement_level smallint,
  new_achievement_level smallint,
  changed_by            uuid,
  changed_at            timestamptz not null default now()
);

create or replace function log_mark_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into mark_audit (learner_id, term_result_id, subject_id, action,
                            new_mark_percent, new_achievement_level, changed_by)
    values (new.learner_id, new.term_result_id, new.subject_id, 'insert',
            new.mark_percent, new.achievement_level, auth.uid());
    return new;
  elsif tg_op = 'UPDATE' then
    if (old.mark_percent, old.achievement_level, old.subject_id)
       is distinct from (new.mark_percent, new.achievement_level, new.subject_id) then
      insert into mark_audit (learner_id, term_result_id, subject_id, action,
                              old_mark_percent, new_mark_percent,
                              old_achievement_level, new_achievement_level, changed_by)
      values (new.learner_id, new.term_result_id, new.subject_id, 'update',
              old.mark_percent, new.mark_percent,
              old.achievement_level, new.achievement_level, auth.uid());
    end if;
    return new;
  else
    -- When a whole learner is erased the learner row is already gone: log nothing, the data is being removed.
    if exists (select 1 from learners where id = old.learner_id) then
      insert into mark_audit (learner_id, term_result_id, subject_id, action,
                              old_mark_percent, old_achievement_level, changed_by)
      values (old.learner_id, old.term_result_id, old.subject_id, 'delete',
              old.mark_percent, old.achievement_level, auth.uid());
    end if;
    return old;
  end if;
end $$;

create trigger subject_marks_audit
  after insert or update or delete on subject_marks
  for each row execute function log_mark_change();

-- An extra subject belongs to one learner and cannot be used for anyone else.
create or replace function check_subject_for_learner() returns trigger
language plpgsql security definer set search_path = public as $$
declare owner uuid;
begin
  if new.subject_id is null then
    return new;
  end if;
  select created_for_learner into owner from subjects where id = new.subject_id;
  if owner is not null and owner <> new.learner_id then
    raise exception 'subject belongs to a different learner' using errcode = '23503';
  end if;
  return new;
end $$;

create trigger subject_marks_subject_check
  before insert or update of subject_id, learner_id on subject_marks
  for each row execute function check_subject_for_learner();

-- ---------------------------------------------------------------------
-- Report card copies: stored for record keeping, never read by the app.
-- File path: <learner_id>/<attachment_id>.<ext> in the private 'report-attachments' bucket.
-- ---------------------------------------------------------------------
create table report_attachments (
  id           uuid primary key default gen_random_uuid(),
  learner_id   uuid not null,
  enrolment_id uuid not null,
  term         smallint check (term between 1 and 4),   -- null = a year-end or whole-year report
  file_name    text not null,
  storage_path text not null unique,
  mime_type    text not null check (mime_type in
                 ('application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/heic')),
  size_bytes   integer not null check (size_bytes > 0 and size_bytes <= 10485760),  -- 10 MB
  note         text,
  uploaded_by  uuid default auth.uid() references profiles(id) on delete set null,
  uploaded_at  timestamptz not null default now(),
  foreign key (enrolment_id, learner_id) references enrolments(id, learner_id) on delete cascade,
  check (storage_path like learner_id::text || '/%')
);

-- ---------------------------------------------------------------------
-- Extramurals, goals and private notes
-- ---------------------------------------------------------------------

create table activities (
  id         uuid primary key default gen_random_uuid(),
  learner_id uuid not null references learners(id) on delete cascade,
  name       text not null,
  category   text not null check (category in ('sport', 'culture', 'service', 'academic', 'leadership', 'other')),
  created_at timestamptz not null default now(),
  unique (id, learner_id)
);

-- The bars under the charts: which terms of which year the learner did the activity.
create table activity_seasons (
  id                  uuid primary key default gen_random_uuid(),
  learner_id          uuid not null,
  activity_id         uuid not null,
  enrolment_id        uuid not null,
  first_term          smallint not null check (first_term between 1 and 4),
  last_term           smallint not null check (last_term between 1 and 4),
  role_or_achievement text,   -- "1st team", "Captain", "Provincial trials"
  foreign key (activity_id, learner_id) references activities(id, learner_id) on delete cascade,
  foreign key (enrolment_id, learner_id) references enrolments(id, learner_id) on delete cascade,
  check (last_term >= first_term),
  unique (activity_id, enrolment_id, first_term)
);

-- The dashed goal line. subject_id null means the overall average.
create table goals (
  id             uuid primary key default gen_random_uuid(),
  learner_id     uuid not null references learners(id) on delete cascade,
  subject_id     smallint references subjects(id) deferrable initially deferred,
  target_percent numeric(5,2) not null check (target_percent between 0 and 100),
  set_on         date not null default current_date,
  achieved_on    date,
  created_at     timestamptz not null default now()
);

create trigger goals_subject_check
  before insert or update of subject_id, learner_id on goals
  for each row execute function check_subject_for_learner();

-- Private by default. The learner decides, entry by entry, whether guardians can read it.
create table journal_entries (
  id                    uuid primary key default gen_random_uuid(),
  learner_id            uuid not null references learners(id) on delete cascade,
  enrolment_id          uuid,
  term                  smallint check (term between 1 and 4),
  body                  text not null check (length(body) <= 5000),
  shared_with_guardians boolean not null default false,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  foreign key (enrolment_id, learner_id) references enrolments(id, learner_id) on delete cascade
);

-- ---------------------------------------------------------------------
-- Insights are views, not stored copies, so they never go stale.
-- ---------------------------------------------------------------------

-- Every mark that counts toward an average: a percentage exists, the subject counts,
-- and it is not a component whose umbrella subject already has a mark in the same term.
create view counted_marks with (security_invoker = true) as
select sm.learner_id,
       sm.term_result_id,
       sm.subject_id,
       sm.mark_percent,
       s.is_life_orientation
from subject_marks sm
join subjects s on s.id = sm.subject_id
where sm.mark_percent is not null
  and s.counts_toward_average
  and not exists (
    select 1 from subject_marks p
    where p.term_result_id = sm.term_result_id
      and p.subject_id = s.parent_subject_id
      and p.mark_percent is not null
  );

-- Average per term, with and without Life Orientation. Powers the journey map and the term bars.
create view term_averages with (security_invoker = true) as
select tr.learner_id,
       e.id            as enrolment_id,
       e.calendar_year,
       e.grade,
       tr.term,
       round(avg(cm.mark_percent), 1)                                          as average_percent,
       round(avg(cm.mark_percent) filter (where not cm.is_life_orientation), 1) as average_excluding_lo,
       count(*)                                                                as subjects_counted
from counted_marks cm
join term_results tr on tr.id = cm.term_result_id
join enrolments e    on e.id = tr.enrolment_id
group by tr.learner_id, e.id, e.calendar_year, e.grade, tr.term;

-- Year average: the mean of the term averages recorded so far (not of every mark).
create view year_averages with (security_invoker = true) as
select learner_id,
       enrolment_id,
       calendar_year,
       grade,
       round(avg(average_percent), 1)       as average_percent,
       round(avg(average_excluding_lo), 1)  as average_excluding_lo,
       count(*)                             as terms_recorded
from term_averages
group by learner_id, enrolment_id, calendar_year, grade;

-- Every subject mark with its change since the previous term. Powers the subject story
-- and pattern spotting (for example, "Term 3 dipped in Grade 8 and Grade 9").
create view subject_term_marks with (security_invoker = true) as
select sm.learner_id,
       e.calendar_year,
       e.grade,
       tr.term,
       sm.subject_id,
       s.name as subject_name,
       sm.mark_percent,
       sm.mark_percent - lag(sm.mark_percent) over (
         partition by sm.learner_id, sm.subject_id
         order by e.calendar_year, tr.term
       ) as change_since_previous_term
from subject_marks sm
join term_results tr on tr.id = sm.term_result_id
join enrolments e    on e.id = tr.enrolment_id
join subjects s      on s.id = sm.subject_id
where sm.mark_percent is not null;

-- ---------------------------------------------------------------------
-- Indexes (foreign keys and the common lookups)
-- ---------------------------------------------------------------------
create index on learner_guardians (guardian_id);
create index on subjects (parent_subject_id);
create index on subjects (created_for_learner);
create index on enrolments (learner_id);
create index on term_results (learner_id);
create index on subject_marks (learner_id, subject_id);
create index on subject_marks (term_result_id);
create index on mark_audit (learner_id, changed_at desc);
create index on report_attachments (learner_id);
create index on activity_seasons (learner_id);
create index on goals (learner_id);
create index on journal_entries (learner_id);
create index on consents (learner_id);

-- ---------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['learners', 'term_results', 'subject_marks', 'journal_entries'] loop
    execute format('create trigger %I before update on %I for each row execute function set_updated_at()',
                   t || '_updated_at', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Row level security
-- Rules:
--  * A learner sees their own data. A guardian sees marks and trends ALWAYS: there is no setting
--    that hides marks, and a learner cannot delete marks, terms, years or report copies (only
--    guardians can), nor remove a guardian. Corrections are allowed but logged in mark_audit.
--  * Extramurals are visible to guardians unless the learner switched sharing off.
--  * Journal entries are visible to guardians only when marked as shared.
-- ---------------------------------------------------------------------

alter table profiles          enable row level security;
alter table learners          enable row level security;
alter table learner_guardians enable row level security;
alter table consents          enable row level security;

create policy profiles_own on profiles for all
  using (id = auth.uid()) with check (id = auth.uid());

create policy learners_select on learners for select
  using (created_by = auth.uid() or can_access_learner(id));
create policy learners_insert on learners for insert
  with check (created_by = auth.uid()
              and exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'parent'));
create policy learners_update on learners for update
  using (can_edit_learner(id)) with check (can_edit_learner(id));
create policy learners_delete on learners for delete
  using (is_guardian(id, true));   -- erasure request

create policy guardians_select on learner_guardians for select
  using (guardian_id = auth.uid() or can_access_learner(learner_id));
create policy guardians_write on learner_guardians for all
  using (is_guardian(learner_id, true)) with check (is_guardian(learner_id, true));

create policy consents_select on consents for select using (is_guardian(learner_id));
create policy consents_insert on consents for insert
  with check (guardian_id = auth.uid() and is_guardian(learner_id));
create policy consents_update on consents for update
  using (guardian_id = auth.uid() and is_guardian(learner_id));

-- The record: learner and guardians can read and add or correct; only guardians can delete.
do $$
declare t text;
begin
  foreach t in array array['enrolments', 'term_results', 'subject_marks', 'report_attachments'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy %I on %I for select using (can_access_learner(learner_id))', t || '_select', t);
    execute format('create policy %I on %I for insert with check (can_edit_learner(learner_id))', t || '_insert', t);
    execute format('create policy %I on %I for update using (can_edit_learner(learner_id)) with check (can_edit_learner(learner_id))',
                   t || '_update', t);
    execute format('create policy %I on %I for delete using (is_guardian(learner_id, true))', t || '_delete', t);
  end loop;
end $$;

-- Goals: the learner and guardians share the same access.
alter table goals enable row level security;
create policy goals_select on goals for select using (can_access_learner(learner_id));
create policy goals_write on goals for all
  using (can_edit_learner(learner_id)) with check (can_edit_learner(learner_id));

-- The change log is read-only for everyone (the trigger writes it).
alter table mark_audit enable row level security;
create policy mark_audit_select on mark_audit for select using (can_access_learner(learner_id));

-- Extramurals: guardians see them only while the learner shares them.
-- Write policies are split by command on purpose: a "for all" policy also grants SELECT,
-- and permissive policies are OR-ed, which would let a guardian read hidden extramurals.
alter table activities        enable row level security;
alter table activity_seasons  enable row level security;

create policy activities_select on activities for select
  using (is_learner_self(learner_id)
         or (is_guardian(learner_id) and (select l.share_extramurals from learners l where l.id = learner_id)));
create policy activities_insert on activities for insert
  with check (can_edit_learner(learner_id));
create policy activities_update on activities for update
  using (can_edit_learner(learner_id)) with check (can_edit_learner(learner_id));
create policy activities_delete on activities for delete
  using (can_edit_learner(learner_id));

create policy seasons_select on activity_seasons for select
  using (is_learner_self(learner_id)
         or (is_guardian(learner_id) and (select l.share_extramurals from learners l where l.id = learner_id)));
create policy seasons_insert on activity_seasons for insert
  with check (can_edit_learner(learner_id));
create policy seasons_update on activity_seasons for update
  using (can_edit_learner(learner_id)) with check (can_edit_learner(learner_id));
create policy seasons_delete on activity_seasons for delete
  using (can_edit_learner(learner_id));

-- Journal: only the learner writes. Guardians read only entries marked as shared.
alter table journal_entries enable row level security;

create policy journal_select on journal_entries for select
  using (is_learner_self(learner_id) or (is_guardian(learner_id) and shared_with_guardians));
create policy journal_write on journal_entries for all
  using (is_learner_self(learner_id)) with check (is_learner_self(learner_id));

-- Subjects: everyone signed in reads the standard ones; a learner's extra subjects are visible
-- to that learner's people only, and only they can create or change them.
alter table subjects enable row level security;

create policy subjects_select on subjects for select to authenticated
  using (created_for_learner is null or can_access_learner(created_for_learner));
create policy subjects_insert on subjects for insert to authenticated
  with check (created_for_learner is not null and can_edit_learner(created_for_learner));
create policy subjects_update on subjects for update to authenticated
  using (created_for_learner is not null and can_edit_learner(created_for_learner))
  with check (created_for_learner is not null and can_edit_learner(created_for_learner));
create policy subjects_delete on subjects for delete to authenticated
  using (created_for_learner is not null and can_edit_learner(created_for_learner));

-- Other reference data: everyone signed in can read, only the service role can write.
do $$
declare t text;
begin
  foreach t in array array['subject_aliases', 'career_fields', 'career_field_subjects'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy %I on %I for select to authenticated using (true)', t || '_read', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Storage: private bucket for report card copies, 10 MB limit, PDF and images only.
-- Object path is <learner_id>/<attachment_id>.<ext>, so the first folder is the learner.
-- Deleting a file: delete the row in report_attachments, then remove the object through the
-- Storage API (not by SQL), because the file itself lives outside Postgres.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('report-attachments', 'report-attachments', false, 10485760,
        array['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/heic'])
on conflict (id) do nothing;

create policy attachments_select on storage.objects for select to authenticated
  using (bucket_id = 'report-attachments'
         and can_access_learner(((storage.foldername(name))[1])::uuid));
create policy attachments_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'report-attachments'
              and can_edit_learner(((storage.foldername(name))[1])::uuid));
create policy attachments_delete on storage.objects for delete to authenticated
  using (bucket_id = 'report-attachments'
         and is_guardian(((storage.foldername(name))[1])::uuid, true));
