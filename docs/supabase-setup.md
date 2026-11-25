# Setting up the Supabase project

Everything the app needs on the database side is in `supabase/migrations/`. Applying those three files creates the tables, security rules, the CAPS subject list, the sign-up trigger and the private storage bucket. There is nothing to click together by hand.

## What you do (about 10 minutes)

1. **Create the project** at supabase.com. Choose the region closest to your users (South Africa (Cape Town) if it is offered, which also helps with POPIA). Save the database password somewhere safe.
2. **Install and sign in to the CLI** on your computer:
   ```bash
   npx supabase@latest login
   ```
3. **Link this repo to the project.** The project reference is the code in your project's URL (`https://supabase.com/dashboard/project/<reference>`):
   ```bash
   npx supabase@latest init            # creates supabase/config.toml, keeps the migrations
   npx supabase@latest link --project-ref <reference>
   ```
4. **Apply the migrations:**
   ```bash
   npx supabase@latest db push
   ```
   You can also paste the three files from `supabase/migrations/` into the SQL editor, in file order.

## Check it worked

In the SQL editor:

```sql
select count(*) from subjects;                       -- 121
select count(*) from subject_aliases;                -- 71
select id, public, file_size_limit from storage.buckets where id = 'report-attachments';
```

Then, under Authentication, add a test user (with `{"display_name":"Test","role":"parent"}` as user metadata) and confirm a row appears in `profiles`.

## Settings to change in the dashboard

- **Authentication, URL configuration:** set the Site URL to where the app will run, and add local development addresses to the redirect list.
- **Authentication, providers:** email is on by default. Keep email confirmation on.
- **Project settings, API:** the app needs the Project URL and the public (anon or publishable) key. These are safe to put in the app. **Never put the `service_role` key in the app or in git.**
- **Backups:** daily backups are included on paid plans. Point in time recovery is a paid add-on and worth considering once real families use it.

## Keeping the database and the repo in sync

- Change the database only by adding a new migration file (`npx supabase@latest migration new <name>`), never by editing an applied one.
- Run `db/tests/run.sh` against a local Postgres before pushing a migration.

## If you connect the Supabase connector in Claude

I can create the project, apply the migrations and run the checks above for you. You would then only copy the project URL and public key into the app.
