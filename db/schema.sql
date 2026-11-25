-- =====================================================================
-- My High School Journal: data model v0.1 (draft)
-- Target: Postgres 15+ on Supabase (uses auth.users, auth.uid(), storage.*)
-- Run order: schema.sql, then seed.sql
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
  purpose        text not null check (purpose in ('store_results', 'scan_reports', 'career_insights', 'learner_account')),
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
-- Reference data (maintained by us, read-only for users)
-- ---------------------------------------------------------------------

create table subjects (
  id                    smallint generated always as identity primary key,
  key                   text not null unique,
  name                  text not null,
  short_name            text not null,
  category              text not null check (category in
                          ('language', 'mathematics', 'science', 'humanities', 'commerce', 'technology', 'arts', 'life_skills')),
  min_grade             smallint not null default 1  check (min_grade between 0 and 12),
  max_grade             smallint not null default 12 check (max_grade between 0 and 12),
  counts_toward_average boolean  not null default true,  -- flip off for subjects a school or university excludes
  check (min_grade <= max_grade)
);

-- Names seen on real reports ("Maths", "Wiskunde") mapped to one subject. Stored lower case.
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
  phase         text generated always as (case when grade <= 7 then 'primary' else 'high' end) stored,
  school_name   text,
  created_at    timestamptz not null default now(),
  unique (learner_id, calendar_year),
  unique (id, learner_id)   -- lets child tables prove they belong to the same learner
);

-- One row per enrolment per term.
create table term_results (
  id              uuid primary key default gen_random_uuid(),
  learner_id      uuid not null,
  enrolment_id    uuid not null,
  term            smallint not null check (term between 1 and 4),
  reported_average numeric(5,2) check (reported_average between 0 and 100),  -- average printed on the report, to cross-check ours
  report_date     date,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  foreign key (enrolment_id, learner_id) references enrolments(id, learner_id) on delete cascade,
  unique (enrolment_id, term),
  unique (id, learner_id)
);

-- ---------------------------------------------------------------------
-- Scanning: upload, extract, learner confirms, then marks are saved
-- ---------------------------------------------------------------------

create table report_uploads (
  id             uuid primary key default gen_random_uuid(),
  learner_id     uuid not null references learners(id) on delete cascade,
  enrolment_id   uuid,
  term           smallint check (term between 1 and 4),
  storage_path   text not null,   -- object in the private 'report-scans' bucket: <learner_id>/<upload_id>.<ext>
  mime_type      text not null,
  status         text not null default 'uploaded' check (status in
                   ('uploaded', 'processing', 'needs_review', 'confirmed', 'failed', 'discarded')),
  extractor      text,            -- which pipeline and version read it
  raw_extraction jsonb,           -- untouched extractor output, for debugging and re-runs
  error_message  text,
  uploaded_by    uuid not null references profiles(id),
  uploaded_at    timestamptz not null default now(),
  processed_at   timestamptz,
  confirmed_at   timestamptz,
  delete_after   timestamptz,     -- retention: remove the original image after confirmation
  foreign key (enrolment_id, learner_id) references enrolments(id, learner_id) on delete cascade,
  unique (id, learner_id)
);

-- What the extractor read, held here until the learner confirms. Not used in any chart.
create table upload_rows (
  id            uuid primary key default gen_random_uuid(),
  learner_id    uuid not null,
  upload_id     uuid not null,
  row_index     smallint not null,
  reported_name text not null,
  subject_id    smallint references subjects(id),   -- suggested by alias match, editable
  mark_percent  numeric(5,2) check (mark_percent between 0 and 100),
  achievement_level smallint check (achievement_level between 1 and 7),
  confidence    numeric(3,2) check (confidence between 0 and 1),
  needs_check   boolean not null default false,     -- shown in coral on the confirm screen
  foreign key (upload_id, learner_id) references report_uploads(id, learner_id) on delete cascade,
  unique (upload_id, row_index)
);

-- Confirmed marks. Everything the charts show comes from here.
create table subject_marks (
  id                uuid primary key default gen_random_uuid(),
  learner_id        uuid not null,
  term_result_id    uuid not null,
  subject_id        smallint not null references subjects(id),
  reported_name     text,                      -- what the report called it
  mark_percent      numeric(5,2) check (mark_percent between 0 and 100),
  achievement_level smallint check (achievement_level between 1 and 7),  -- primary school reports often show levels
  source            text not null default 'manual' check (source in ('manual', 'scan')),
  upload_id         uuid references report_uploads(id) on delete set null,
  confirmed_by      uuid references profiles(id),
  confirmed_at      timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  foreign key (term_result_id, learner_id) references term_results(id, learner_id) on delete cascade,
  unique (term_result_id, subject_id),
  check (mark_percent is not null or achievement_level is not null)
);

-- Turn a reviewed upload into term results and marks, in one transaction.
create or replace function confirm_upload(p_upload_id uuid) returns void
language plpgsql security invoker as $$
declare
  u  report_uploads;
  tr uuid;
begin
  select * into u from report_uploads where id = p_upload_id for update;
  if not found then
    raise exception 'upload not found';
  end if;
  if u.enrolment_id is null or u.term is null then
    raise exception 'choose the grade and term first';
  end if;
  if exists (select 1 from upload_rows where upload_id = p_upload_id and (subject_id is null or needs_check)) then
    raise exception 'every row needs a subject and a confirmed mark';
  end if;

  if exists (select 1 from upload_rows where upload_id = p_upload_id
             group by subject_id having count(*) > 1) then
    raise exception 'two rows are assigned to the same subject';
  end if;

  insert into term_results (learner_id, enrolment_id, term)
  values (u.learner_id, u.enrolment_id, u.term)
  on conflict (enrolment_id, term) do update set updated_at = now()
  returning id into tr;

  insert into subject_marks (learner_id, term_result_id, subject_id, reported_name,
                             mark_percent, achievement_level, source, upload_id, confirmed_by, confirmed_at)
  select r.learner_id, tr, r.subject_id, r.reported_name,
         r.mark_percent, r.achievement_level, 'scan', u.id, auth.uid(), now()
  from upload_rows r
  where r.upload_id = p_upload_id
  on conflict (term_result_id, subject_id) do update
    set reported_name = excluded.reported_name,
        mark_percent = excluded.mark_percent,
        achievement_level = excluded.achievement_level,
        source = 'scan',
        upload_id = excluded.upload_id,
        confirmed_by = excluded.confirmed_by,
        confirmed_at = excluded.confirmed_at,
        updated_at = now();

  update report_uploads
     set status = 'confirmed', confirmed_at = now(), delete_after = now() + interval '30 days'
   where id = p_upload_id;
end $$;

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
  subject_id     smallint references subjects(id),
  target_percent numeric(5,2) not null check (target_percent between 0 and 100),
  set_on         date not null default current_date,
  achieved_on    date,
  created_at     timestamptz not null default now()
);

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

-- Average per term. Powers the journey map and the term bars on My story.
create view term_averages with (security_invoker = true) as
select tr.learner_id,
       e.id            as enrolment_id,
       e.calendar_year,
       e.grade,
       tr.term,
       round(avg(sm.mark_percent) filter (where s.counts_toward_average), 1) as average_percent,
       count(*) filter (where s.counts_toward_average)                       as subjects_counted
from term_results tr
join enrolments e     on e.id = tr.enrolment_id
join subject_marks sm on sm.term_result_id = tr.id
join subjects s       on s.id = sm.subject_id
where sm.mark_percent is not null
group by tr.learner_id, e.id, e.calendar_year, e.grade, tr.term;

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
create index on enrolments (learner_id);
create index on term_results (learner_id);
create index on subject_marks (learner_id, subject_id);
create index on subject_marks (term_result_id);
create index on report_uploads (learner_id, status);
create index on upload_rows (upload_id);
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
-- Rules: a learner sees their own data. A guardian sees marks and trends always,
-- extramurals unless the learner switched sharing off, and journal entries only when shared.
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

-- Tables where the learner and their guardians share the same access.
do $$
declare t text;
begin
  foreach t in array array['enrolments', 'term_results', 'subject_marks', 'report_uploads', 'upload_rows', 'goals'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy %I on %I for select using (can_access_learner(learner_id))', t || '_select', t);
    execute format('create policy %I on %I for all using (can_edit_learner(learner_id)) with check (can_edit_learner(learner_id))',
                   t || '_write', t);
  end loop;
end $$;

-- Extramurals: guardians see them only while the learner shares them.
alter table activities        enable row level security;
alter table activity_seasons  enable row level security;

create policy activities_select on activities for select
  using (is_learner_self(learner_id)
         or (is_guardian(learner_id) and (select l.share_extramurals from learners l where l.id = learner_id)));
-- Write policies are split by command on purpose: a "for all" policy also grants SELECT,
-- and permissive policies are OR-ed, which would let a guardian read hidden extramurals.
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

-- Reference data: everyone signed in can read, only the service role can write.
do $$
declare t text;
begin
  foreach t in array array['subjects', 'subject_aliases', 'career_fields', 'career_field_subjects'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy %I on %I for select to authenticated using (true)', t || '_read', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Storage: private bucket for scanned report cards.
-- Object path is <learner_id>/<upload_id>.<ext>, so the first folder is the learner.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('report-scans', 'report-scans', false)
on conflict (id) do nothing;

create policy scans_select on storage.objects for select to authenticated
  using (bucket_id = 'report-scans'
         and can_access_learner(((storage.foldername(name))[1])::uuid));
create policy scans_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'report-scans'
              and can_edit_learner(((storage.foldername(name))[1])::uuid));
create policy scans_delete on storage.objects for delete to authenticated
  using (bucket_id = 'report-scans'
         and can_edit_learner(((storage.foldername(name))[1])::uuid));
