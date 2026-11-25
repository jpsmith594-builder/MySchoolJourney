# My School Journey

An app that helps a learner tell the story of their school years. Term results are typed in, and become charts, strengths, focus areas, patterns and career ideas, with extramurals alongside. A copy of each report card can be kept for the record. Parents are the usual buyers, learners are the daily users.

Status: design stage. The database is designed and tested, the screens exist as mock-ups, and there is no app code yet.

## Repo layout

| Path | What it is |
|---|---|
| `supabase/migrations/` | The database: schema and security rules, the CAPS subject list, and the sign-up trigger |
| `db/tests/` | Tests that run the migrations on a plain Postgres with Supabase stand-ins |
| `docs/data-model.md` | The data model explained: decisions, CAPS coverage, queries for each screen, open questions |
| `docs/supabase-setup.md` | How to create and migrate the Supabase project |

## Running the database tests

Needs Postgres 15+ and `psql`:

```bash
PGHOST=localhost PGUSER=postgres db/tests/run.sh
```

This creates a throwaway database called `journal_test`. Every line should end in `ok`.
