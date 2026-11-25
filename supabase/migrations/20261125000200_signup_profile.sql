-- Create a profile automatically when someone signs up.
-- The sign-up form passes display_name and role in the user metadata. Anything other than
-- 'learner' becomes 'parent'. A learner account on its own can do nothing until a parent links it
-- to a learner record (invite flow to be designed), so the role cannot be abused to gain access.
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name, role)
  values (
    new.id,
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(coalesce(new.email, 'user'), '@', 1)),
    case when new.raw_user_meta_data ->> 'role' = 'learner' then 'learner' else 'parent' end
  );
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();
