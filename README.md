# My School Journey

An app that helps a learner tell the story of their school years: term results (typed in or scanned from a
report card) become charts, strengths, focus areas, patterns and career ideas, with extramurals alongside.
Parents are the usual buyers, learners are the daily users.

Status: design stage. Data model drafted and tested; screens exist as mock-ups; no app code yet.

## Repo layout

| Path | What it is |
|---|---|
| `db/schema.sql` | Postgres schema for Supabase: tables, views, row level security, scan-confirm function |
| `db/seed.sql` | Reference data: subjects, subject aliases (for scanning), career fields |
| `db/tests/` | Tests that run the schema on a plain Postgres with Supabase stand-ins |
| `docs/data-model.md` | The data model explained: entities, decisions, scan flow, screen queries, open questions |

## Running the database tests

Needs Postgres 15+ and `psql`:

```bash
PGHOST=localhost PGUSER=postgres db/tests/run.sh
```

This creates a throwaway database called `journal_test`. Each line should end in `ok`.
