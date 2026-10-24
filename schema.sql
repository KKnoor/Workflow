-- WorkFlow Hub initial schema. Run in Supabase SQL Editor.
create extension if not exists pgcrypto;

create type public.workspace_role as enum ('owner','admin','member','viewer');
create type public.task_status as enum ('todo','in_progress','completed','on_hold','blocked');
create type public.task_priority as enum ('low','medium','high');
create type public.library_kind as enum ('document','template');

create table public.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.workspace_members (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  email text not null,
  display_name text not null default 'Team member',
  role public.workspace_role not null default 'member',
  created_at timestamptz not null default now(),
  unique(workspace_id,user_id)
);
create index workspace_members_user_idx on public.workspace_members(user_id);
create index workspace_members_workspace_idx on public.workspace_members(workspace_id);

create or replace function public.is_workspace_member(target_workspace uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.workspace_members wm where wm.workspace_id=target_workspace and wm.user_id=auth.uid()); $$;

create or replace function public.has_workspace_role(target_workspace uuid, allowed public.workspace_role[])
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.workspace_members wm where wm.workspace_id=target_workspace and wm.user_id=auth.uid() and wm.role=any(allowed)); $$;

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  task_no bigint generated always as identity unique,
  parent_task_id uuid references public.tasks(id) on delete cascade,
  title text not null,
  description text,
  status public.task_status not null default 'todo',
  priority public.task_priority not null default 'medium',
  assignee_id uuid references public.workspace_members(id) on delete set null,
  created_by uuid not null default auth.uid() references auth.users(id),
  due_date date,
  start_date date,
  completed_at timestamptz,
  position integer not null default 0,
  labels text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint task_not_own_parent check (parent_task_id is null or parent_task_id <> id)
);
create index tasks_workspace_status_idx on public.tasks(workspace_id,status);
create index tasks_assignee_idx on public.tasks(assignee_id);
create index tasks_parent_idx on public.tasks(parent_task_id);
create index tasks_due_idx on public.tasks(due_date);

create table public.task_comments (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);
create table public.task_attachments (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  uploaded_by uuid not null default auth.uid() references auth.users(id),
  storage_path text not null,
  file_name text not null,
  mime_type text,
  size_bytes bigint,
  created_at timestamptz not null default now()
);
create table public.task_watchers (
  task_id uuid not null references public.tasks(id) on delete cascade,
  member_id uuid not null references public.workspace_members(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(task_id,member_id)
);
create table public.task_activity (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  details jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create table public.documents (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  title text not null,
  description text,
  kind public.library_kind not null default 'document',
  storage_path text,
  external_url text,
  created_by uuid not null default auth.uid() references auth.users(id),
  updated_at timestamptz not null default now()
);
create index documents_workspace_kind_idx on public.documents(workspace_id,kind);

create table public.chat_channels (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  name text not null,
  description text,
  can_members_post boolean not null default true,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique(workspace_id,name)
);
create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  channel text not null default 'general',
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  body text not null check (length(body) <= 10000),
  created_at timestamptz not null default now()
);
create index chat_messages_workspace_channel_idx on public.chat_messages(workspace_id,channel,created_at desc);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text not null,
  event_type text not null,
  entity_type text,
  entity_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_recipient_idx on public.notifications(recipient_user_id,created_at desc);

create table public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  in_app_enabled boolean not null default true,
  email_enabled boolean not null default true,
  teams_enabled boolean not null default false,
  teams_destination text,
  updated_at timestamptz not null default now()
);

-- Bootstrap a private workspace and owner membership for a signed-in user.
create or replace function public.create_workspace(workspace_name text)
returns uuid language plpgsql security definer set search_path=public
as $$
declare wid uuid; uname text; mail text; clean_slug text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if length(trim(workspace_name)) < 2 then raise exception 'Workspace name is too short'; end if;
  select coalesce(raw_user_meta_data->>'full_name', split_part(email,'@',1)), email
    into uname, mail from auth.users where id=auth.uid();
  clean_slug := regexp_replace(lower(trim(workspace_name)), '[^a-z0-9]+', '-', 'g') || '-' || substr(gen_random_uuid()::text,1,6);
  insert into public.workspaces(name,slug,created_by) values(trim(workspace_name),clean_slug,auth.uid()) returning id into wid;
  insert into public.workspace_members(workspace_id,user_id,email,display_name,role) values(wid,auth.uid(),coalesce(mail,''),coalesce(uname,'Owner'),'owner');
  insert into public.chat_channels(workspace_id,name,description,created_by) values(wid,'general','General team conversation',auth.uid());
  return wid;
end $$;
revoke all on function public.create_workspace(text) from public;
grant execute on function public.create_workspace(text) to authenticated;

-- RLS on all tenant-owned data.
alter table public.workspaces enable row level security;
alter table public.workspace_members enable row level security;
alter table public.tasks enable row level security;
alter table public.task_comments enable row level security;
alter table public.task_attachments enable row level security;
alter table public.task_watchers enable row level security;
alter table public.task_activity enable row level security;
alter table public.documents enable row level security;
alter table public.chat_channels enable row level security;
alter table public.chat_messages enable row level security;
alter table public.notifications enable row level security;
alter table public.notification_preferences enable row level security;

create policy "members can read their workspaces" on public.workspaces for select to authenticated using (public.is_workspace_member(id));
create policy "users can create workspace as creator" on public.workspaces for insert to authenticated with check (created_by=auth.uid());
create policy "owners can update workspace" on public.workspaces for update to authenticated using (public.has_workspace_role(id,array['owner','admin']::public.workspace_role[])) with check (public.has_workspace_role(id,array['owner','admin']::public.workspace_role[]));

create policy "members read members" on public.workspace_members for select to authenticated using (public.is_workspace_member(workspace_id));
create policy "admins manage members" on public.workspace_members for all to authenticated using (public.has_workspace_role(workspace_id,array['owner','admin']::public.workspace_role[])) with check (public.has_workspace_role(workspace_id,array['owner','admin']::public.workspace_role[]));

create policy "workspace members read tasks" on public.tasks for select to authenticated using (public.is_workspace_member(workspace_id));
create policy "members create tasks" on public.tasks for insert to authenticated with check (public.is_workspace_member(workspace_id) and created_by=auth.uid() and (assignee_id is null or exists(select 1 from public.workspace_members wm where wm.id=assignee_id and wm.workspace_id=tasks.workspace_id)));
create policy "members update tasks" on public.tasks for update to authenticated using (public.is_workspace_member(workspace_id) and not public.has_workspace_role(workspace_id,array['viewer']::public.workspace_role[])) with check (public.is_workspace_member(workspace_id));
create policy "admins delete tasks" on public.tasks for delete to authenticated using (public.has_workspace_role(workspace_id,array['owner','admin']::public.workspace_role[]));

create policy "members read task comments" on public.task_comments for select to authenticated using (public.is_workspace_member(workspace_id));
create policy "members add task comments" on public.task_comments for insert to authenticated with check (public.is_workspace_member(workspace_id) and user_id=auth.uid());
create policy "authors or admins delete comments" on public.task_comments for delete to authenticated using (user_id=auth.uid() or public.has_workspace_role(workspace_id,array['owner','admin']::public.workspace_role[]));

create policy "members read attachments" on public.task_attachments for select to authenticated using (public.is_workspace_member(workspace_id));
create policy "members upload attachments" on public.task_attachments for insert to authenticated with check (public.is_workspace_member(workspace_id) and uploaded_by=auth.uid());
create policy "admins delete attachments" on public.task_attachments for delete to authenticated using (public.has_workspace_role(workspace_id,array['owner','admin']::public.workspace_role[]));

create policy "members read watchers" on public.task_watchers for select to authenticated using (exists(select 1 from public.tasks t where t.id=task_id and public.is_workspace_member(t.workspace_id)));
create policy "members manage own watcher" on public.task_watchers for all to authenticated using (exists(select 1 from public.tasks t join public.workspace_members wm on wm.workspace_id=t.workspace_id where t.id=task_id and wm.id=member_id and wm.user_id=auth.uid())) with check (exists(select 1 from public.tasks t join public.workspace_members wm on wm.workspace_id=t.workspace_id where t.id=task_id and wm.id=member_id and wm.user_id=auth.uid()));

create policy "members read activity" on public.task_activity for select to authenticated using (public.is_workspace_member(workspace_id));
create policy "members write activity" on public.task_activity for insert to authenticated with check (public.is_workspace_member(workspace_id) and (actor_id is null or actor_id=auth.uid()));

create policy "members read documents" on public.documents for select to authenticated using (public.is_workspace_member(workspace_id));
create policy "members manage documents" on public.documents for all to authenticated using (public.has_workspace_role(workspace_id,array['owner','admin','member']::public.workspace_role[])) with check (public.has_workspace_role(workspace_id,array['owner','admin','member']::public.workspace_role[]));

create policy "members read channels" on public.chat_channels for select to authenticated using (public.is_workspace_member(workspace_id));
create policy "admins manage channels" on public.chat_channels for all to authenticated using (public.has_workspace_role(workspace_id,array['owner','admin']::public.workspace_role[])) with check (public.has_workspace_role(workspace_id,array['owner','admin']::public.workspace_role[]));

create policy "members read messages" on public.chat_messages for select to authenticated using (public.is_workspace_member(workspace_id));
create policy "members send messages if permitted" on public.chat_messages for insert to authenticated with check (
  user_id=auth.uid() and public.is_workspace_member(workspace_id) and
  exists(select 1 from public.chat_channels c where c.workspace_id=chat_messages.workspace_id and c.name=chat_messages.channel and
    (c.can_members_post or public.has_workspace_role(workspace_id,array['owner','admin']::public.workspace_role[])))
);

create policy "users read own notifications" on public.notifications for select to authenticated using (recipient_user_id=auth.uid() and public.is_workspace_member(workspace_id));
create policy "users mark own notifications read" on public.notifications for update to authenticated using (recipient_user_id=auth.uid()) with check (recipient_user_id=auth.uid());
create policy "users manage own notification preferences" on public.notification_preferences for all to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());

-- Note: create private Storage buckets and storage.objects policies separately before enabling file uploads.
