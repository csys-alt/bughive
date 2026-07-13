# Supabase Setup

Paste this into Supabase SQL Editor and run it once.

If repository delete says `GRANT DELETE ON public.repositories`, run this hotfix:

```sql
grant delete on public.repositories to authenticated;

drop policy if exists "repositories_delete_own" on public.repositories;
create policy "repositories_delete_own" on public.repositories
for delete using (user_id = auth.uid());
```

If closing an issue says `engineering_logs_sync_status_check`, run this hotfix:

```sql
alter table public.engineering_logs
  drop constraint if exists engineering_logs_sync_status_check;

alter table public.engineering_logs
  add constraint engineering_logs_sync_status_check
  check (sync_status in ('LOCAL', 'SYNCED', 'CLOSED'));
```

```sql
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  github_id text,
  username text,
  avatar_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.repositories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  github_repo_id bigint not null,
  owner text not null,
  name text not null,
  url text not null,
  last_sync timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, github_repo_id)
);

create table if not exists public.engineering_logs (
  id uuid primary key default gen_random_uuid(),
  repo_id uuid not null references public.repositories(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  description text not null,
  type text not null default 'BUG' check (type in ('BUG', 'FEATURE', 'RESEARCH', 'NOTE')),
  severity text not null default 'MEDIUM' check (severity in ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
  environment text not null default '',
  labels jsonb not null default '[]'::jsonb,
  sync_status text not null default 'LOCAL' check (sync_status in ('LOCAL', 'SYNCED', 'CLOSED')),
  github_issue_number int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.attachments (
  id uuid primary key default gen_random_uuid(),
  log_id uuid not null references public.engineering_logs(id) on delete cascade,
  file_url text not null,
  created_at timestamptz not null default now()
);

create index if not exists repositories_user_id_idx on public.repositories(user_id);
create index if not exists engineering_logs_repo_id_idx on public.engineering_logs(repo_id);
create index if not exists engineering_logs_user_id_idx on public.engineering_logs(user_id);
create index if not exists attachments_log_id_idx on public.attachments(log_id);

grant usage on schema public to authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select, insert, update, delete on public.repositories to authenticated;
grant select, insert, update, delete on public.engineering_logs to authenticated;
grant select, insert, update, delete on public.attachments to authenticated;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists engineering_logs_set_updated_at on public.engineering_logs;
create trigger engineering_logs_set_updated_at
before update on public.engineering_logs
for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.repositories enable row level security;
alter table public.engineering_logs enable row level security;
alter table public.attachments enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
for select using (id = auth.uid());

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
for insert with check (id = auth.uid());

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
for update using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "repositories_select_own" on public.repositories;
create policy "repositories_select_own" on public.repositories
for select using (user_id = auth.uid());

drop policy if exists "repositories_insert_own" on public.repositories;
create policy "repositories_insert_own" on public.repositories
for insert with check (user_id = auth.uid());

drop policy if exists "repositories_update_own" on public.repositories;
create policy "repositories_update_own" on public.repositories
for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "repositories_delete_own" on public.repositories;
create policy "repositories_delete_own" on public.repositories
for delete using (user_id = auth.uid());

drop policy if exists "engineering_logs_select_own" on public.engineering_logs;
create policy "engineering_logs_select_own" on public.engineering_logs
for select using (user_id = auth.uid());

drop policy if exists "engineering_logs_insert_own" on public.engineering_logs;
create policy "engineering_logs_insert_own" on public.engineering_logs
for insert with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.repositories
    where repositories.id = repo_id
      and repositories.user_id = auth.uid()
  )
);

drop policy if exists "engineering_logs_update_own" on public.engineering_logs;
create policy "engineering_logs_update_own" on public.engineering_logs
for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "engineering_logs_delete_own" on public.engineering_logs;
create policy "engineering_logs_delete_own" on public.engineering_logs
for delete using (user_id = auth.uid());

drop policy if exists "attachments_select_own" on public.attachments;
create policy "attachments_select_own" on public.attachments
for select using (
  exists (
    select 1 from public.engineering_logs
    where engineering_logs.id = log_id
      and engineering_logs.user_id = auth.uid()
  )
);

drop policy if exists "attachments_insert_own" on public.attachments;
create policy "attachments_insert_own" on public.attachments
for insert with check (
  exists (
    select 1 from public.engineering_logs
    where engineering_logs.id = log_id
      and engineering_logs.user_id = auth.uid()
  )
);

drop policy if exists "attachments_delete_own" on public.attachments;
create policy "attachments_delete_own" on public.attachments
for delete using (
  exists (
    select 1 from public.engineering_logs
    where engineering_logs.id = log_id
      and engineering_logs.user_id = auth.uid()
  )
);

insert into storage.buckets (id, name, public)
values ('bughive', 'bughive', true)
on conflict (id) do update set public = true;

drop policy if exists "bughive_storage_public_read" on storage.objects;
create policy "bughive_storage_public_read" on storage.objects
for select using (bucket_id = 'bughive');

drop policy if exists "bughive_storage_insert_own_log" on storage.objects;
create policy "bughive_storage_insert_own_log" on storage.objects
for insert with check (
  bucket_id = 'bughive'
  and (storage.foldername(name))[1] = 'logs'
  and auth.uid() is not null
);

drop policy if exists "bughive_storage_update_own_log" on storage.objects;
create policy "bughive_storage_update_own_log" on storage.objects
for update using (
  bucket_id = 'bughive'
  and (storage.foldername(name))[1] = 'logs'
  and auth.uid() is not null
) with check (
  bucket_id = 'bughive'
  and (storage.foldername(name))[1] = 'logs'
  and auth.uid() is not null
);
```

If login still does not open GitHub, this SQL is not the blocker. Check Supabase Auth -> Providers -> GitHub and Supabase Auth -> URL Configuration -> Redirect URLs has `bughive://auth-callback`.

## Delete account data + RLS hardening

Run this once. It does four things:

1. **Enables account deletion** — grants `delete` on `profiles` and adds a
   `profiles_delete_own` policy, so a signed-in user can delete their own
   `profiles` row. The `on delete cascade` FKs then remove every
   `repositories`/`engineering_logs`/`attachments` row that hangs off it.
   (Without this grant, the delete button fails with a `permission denied
   for table profiles` error.)
2. **Scopes every policy `to authenticated`** — defense in depth so no policy
   is ever evaluated for anonymous users.
3. **Fixes a storage write hole** — the old storage insert/update policies
   only checked that a path started with `logs/`, so any signed-in user
   could write into *any* log's folder. These now verify the caller owns the
   referenced log, and a matching delete policy is added.
4. **Removes the broad public listing policy and pins the trigger
   function's search_path** — public object URLs still resolve for a public
   bucket without a `select` policy; dropping it stops clients from
   enumerating everyone's screenshots.

```sql
-- 1. Account deletion
grant delete on public.profiles to authenticated;

-- 2. profiles policies (scoped to authenticated) + delete
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select to authenticated using (id = auth.uid());
drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check (id = auth.uid());
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
drop policy if exists "profiles_delete_own" on public.profiles;
create policy "profiles_delete_own" on public.profiles
  for delete to authenticated using (id = auth.uid());

-- repositories
drop policy if exists "repositories_select_own" on public.repositories;
create policy "repositories_select_own" on public.repositories
  for select to authenticated using (user_id = auth.uid());
drop policy if exists "repositories_insert_own" on public.repositories;
create policy "repositories_insert_own" on public.repositories
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "repositories_update_own" on public.repositories;
create policy "repositories_update_own" on public.repositories
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "repositories_delete_own" on public.repositories;
create policy "repositories_delete_own" on public.repositories
  for delete to authenticated using (user_id = auth.uid());

-- engineering_logs
drop policy if exists "engineering_logs_select_own" on public.engineering_logs;
create policy "engineering_logs_select_own" on public.engineering_logs
  for select to authenticated using (user_id = auth.uid());
drop policy if exists "engineering_logs_insert_own" on public.engineering_logs;
create policy "engineering_logs_insert_own" on public.engineering_logs
  for insert to authenticated with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.repositories
      where repositories.id = repo_id and repositories.user_id = auth.uid()
    )
  );
drop policy if exists "engineering_logs_update_own" on public.engineering_logs;
create policy "engineering_logs_update_own" on public.engineering_logs
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "engineering_logs_delete_own" on public.engineering_logs;
create policy "engineering_logs_delete_own" on public.engineering_logs
  for delete to authenticated using (user_id = auth.uid());

-- attachments
drop policy if exists "attachments_select_own" on public.attachments;
create policy "attachments_select_own" on public.attachments
  for select to authenticated using (
    exists (
      select 1 from public.engineering_logs
      where engineering_logs.id = log_id and engineering_logs.user_id = auth.uid()
    )
  );
drop policy if exists "attachments_insert_own" on public.attachments;
create policy "attachments_insert_own" on public.attachments
  for insert to authenticated with check (
    exists (
      select 1 from public.engineering_logs
      where engineering_logs.id = log_id and engineering_logs.user_id = auth.uid()
    )
  );
drop policy if exists "attachments_delete_own" on public.attachments;
create policy "attachments_delete_own" on public.attachments
  for delete to authenticated using (
    exists (
      select 1 from public.engineering_logs
      where engineering_logs.id = log_id and engineering_logs.user_id = auth.uid()
    )
  );

-- 3 + 4. Storage: ownership-scoped writes, add delete, drop public listing
drop policy if exists "bughive_storage_public_read" on storage.objects;

drop policy if exists "bughive_storage_insert_own_log" on storage.objects;
create policy "bughive_storage_insert_own_log" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'bughive'
    and (storage.foldername(name))[1] = 'logs'
    and exists (
      select 1 from public.engineering_logs
      where engineering_logs.id::text = (storage.foldername(name))[2]
        and engineering_logs.user_id = auth.uid()
    )
  );

drop policy if exists "bughive_storage_update_own_log" on storage.objects;
create policy "bughive_storage_update_own_log" on storage.objects
  for update to authenticated using (
    bucket_id = 'bughive'
    and (storage.foldername(name))[1] = 'logs'
    and exists (
      select 1 from public.engineering_logs
      where engineering_logs.id::text = (storage.foldername(name))[2]
        and engineering_logs.user_id = auth.uid()
    )
  ) with check (
    bucket_id = 'bughive'
    and (storage.foldername(name))[1] = 'logs'
    and exists (
      select 1 from public.engineering_logs
      where engineering_logs.id::text = (storage.foldername(name))[2]
        and engineering_logs.user_id = auth.uid()
    )
  );

drop policy if exists "bughive_storage_delete_own_log" on storage.objects;
create policy "bughive_storage_delete_own_log" on storage.objects
  for delete to authenticated using (
    bucket_id = 'bughive'
    and (storage.foldername(name))[1] = 'logs'
    and exists (
      select 1 from public.engineering_logs
      where engineering_logs.id::text = (storage.foldername(name))[2]
        and engineering_logs.user_id = auth.uid()
    )
  );

alter function public.set_updated_at() set search_path = '';
```

Note: deleting the `profiles` row does not delete the underlying
`auth.users` row or revoke BugHive's GitHub OAuth grant (that needs the
service-role key, which must never live in the client app). After deleting
their data in-app, users should also revoke access from
https://github.com/settings/applications if they want to fully unlink
GitHub.
