-- SalaSync: backend inicial para Supabase
-- Execute este arquivo inteiro no SQL Editor do seu projeto Supabase.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.salasync_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Convidado' check (char_length(display_name) between 1 and 30),
  avatar_data text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.salasync_rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 40),
  owner_id uuid not null references auth.users(id) on delete cascade,
  is_public boolean not null default false,
  media_type text not null default 'none' check (media_type in ('none','youtube','video','music')),
  media_url text,
  media_path text,
  media_title text,
  playback_state jsonb not null default '{"playing":false,"current_time":0,"updated_at":null}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.salasync_room_members (
  room_id uuid not null references public.salasync_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

-- Os hashes de senhas ficam em uma tabela sem acesso direto pelo navegador.
create table if not exists public.salasync_room_secrets (
  room_id uuid primary key references public.salasync_rooms(id) on delete cascade,
  password_hash text not null
);

create table if not exists public.salasync_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.salasync_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  avatar_data text,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index if not exists salasync_rooms_created_at_idx on public.salasync_rooms(created_at desc);
create index if not exists salasync_members_user_idx on public.salasync_room_members(user_id, room_id);
create index if not exists salasync_messages_room_time_idx on public.salasync_messages(room_id, created_at);

create or replace function public.is_salasync_member(p_room_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.salasync_room_members m
    where m.room_id = p_room_id and m.user_id = p_user_id
  );
$$;

revoke all on function public.is_salasync_member(uuid, uuid) from public, anon;
grant execute on function public.is_salasync_member(uuid, uuid) to authenticated;

create or replace function public.create_salasync_room(
  p_name text,
  p_password text default '',
  p_is_public boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_room public.salasync_rooms%rowtype;
  v_name text := btrim(coalesce(p_name, ''));
  v_password text := coalesce(p_password, '');
begin
  if auth.uid() is null then raise exception 'Você precisa estar conectado.'; end if;
  if char_length(v_name) < 1 or char_length(v_name) > 40 then raise exception 'O nome deve ter de 1 a 40 caracteres.'; end if;
  if not coalesce(p_is_public, false) and char_length(v_password) < 3 then raise exception 'A senha deve ter pelo menos 3 caracteres.'; end if;

  insert into public.salasync_rooms(name, owner_id, is_public)
  values (v_name, auth.uid(), coalesce(p_is_public, false))
  returning * into v_room;

  if not v_room.is_public then
    insert into public.salasync_room_secrets(room_id, password_hash)
    values (v_room.id, crypt(v_password, gen_salt('bf')));
  end if;

  insert into public.salasync_room_members(room_id, user_id)
  values (v_room.id, auth.uid())
  on conflict do nothing;

  return jsonb_build_object('id', v_room.id, 'name', v_room.name, 'is_public', v_room.is_public);
end;
$$;

create or replace function public.join_salasync_room(p_room_id uuid, p_password text default '')
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_room public.salasync_rooms%rowtype;
  v_hash text;
  v_is_member boolean;
begin
  if auth.uid() is null then raise exception 'Você precisa estar conectado.'; end if;
  select * into v_room from public.salasync_rooms where id = p_room_id;
  if not found then raise exception 'Sala não encontrada.'; end if;

  select exists (
    select 1 from public.salasync_room_members
    where room_id = p_room_id and user_id = auth.uid()
  ) into v_is_member;

  if not v_room.is_public and v_room.owner_id <> auth.uid() and not v_is_member then
    select password_hash into v_hash from public.salasync_room_secrets where room_id = p_room_id;
    if v_hash is null or crypt(coalesce(p_password, ''), v_hash) <> v_hash then
      raise exception 'Senha incorreta ou convite inválido.';
    end if;
  end if;

  insert into public.salasync_room_members(room_id, user_id)
  values (p_room_id, auth.uid())
  on conflict do nothing;

  return jsonb_build_object('id', v_room.id, 'name', v_room.name, 'is_public', v_room.is_public);
end;
$$;

revoke all on function public.create_salasync_room(text, text, boolean) from public, anon;
revoke all on function public.join_salasync_room(uuid, text) from public, anon;
grant execute on function public.create_salasync_room(text, text, boolean) to authenticated;
grant execute on function public.join_salasync_room(uuid, text) to authenticated;

alter table public.salasync_profiles enable row level security;
alter table public.salasync_rooms enable row level security;
alter table public.salasync_room_members enable row level security;
alter table public.salasync_room_secrets enable row level security;
alter table public.salasync_messages enable row level security;

drop policy if exists "Profile owner can create" on public.salasync_profiles;
create policy "Profile owner can create" on public.salasync_profiles
  for insert to authenticated with check (id = auth.uid());
drop policy if exists "Profile owner and room peers can view" on public.salasync_profiles;
create policy "Profile owner and room peers can view" on public.salasync_profiles
  for select to authenticated using (
    id = auth.uid()
    or exists (
      select 1 from public.salasync_room_members mine
      where mine.user_id = auth.uid()
        and public.is_salasync_member(mine.room_id, public.salasync_profiles.id)
    )
  );
drop policy if exists "Profile owner can update" on public.salasync_profiles;
create policy "Profile owner can update" on public.salasync_profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "Public rooms and room participants can view" on public.salasync_rooms;
create policy "Public rooms and room participants can view" on public.salasync_rooms
  for select to authenticated using (
    is_public or owner_id = auth.uid() or public.is_salasync_member(id, auth.uid())
  );
drop policy if exists "Room owner can update" on public.salasync_rooms;
create policy "Room owner can update" on public.salasync_rooms
  for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists "Room owner can delete" on public.salasync_rooms;
create policy "Room owner can delete" on public.salasync_rooms
  for delete to authenticated using (owner_id = auth.uid());

drop policy if exists "Members can see room membership" on public.salasync_room_members;
create policy "Members can see room membership" on public.salasync_room_members
  for select to authenticated using (user_id = auth.uid() or public.is_salasync_member(room_id, auth.uid()));

drop policy if exists "Room members can read chat" on public.salasync_messages;
create policy "Room members can read chat" on public.salasync_messages
  for select to authenticated using (public.is_salasync_member(room_id, auth.uid()));
drop policy if exists "Room members can send as themselves" on public.salasync_messages;
create policy "Room members can send as themselves" on public.salasync_messages
  for insert to authenticated with check (
    user_id = auth.uid()
    and public.is_salasync_member(room_id, auth.uid())
    and char_length(body) between 1 and 1000
  );

revoke all on public.salasync_room_secrets from anon, authenticated;
grant select, insert, update on public.salasync_profiles to authenticated;
grant select, update, delete on public.salasync_rooms to authenticated;
grant select on public.salasync_room_members to authenticated;
grant select, insert on public.salasync_messages to authenticated;

insert into storage.buckets (id, name, public, file_size_limit)
values ('salasync-media', 'salasync-media', false, 524288000)
on conflict (id) do update
set public = false, file_size_limit = excluded.file_size_limit;

drop policy if exists "Room members can read shared media" on storage.objects;
create policy "Room members can read shared media" on storage.objects
  for select to authenticated using (
    bucket_id = 'salasync-media'
    and public.is_salasync_member((storage.foldername(name))[1]::uuid, auth.uid())
  );
drop policy if exists "Room members can upload shared media" on storage.objects;
create policy "Room members can upload shared media" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'salasync-media'
    and public.is_salasync_member((storage.foldername(name))[1]::uuid, auth.uid())
  );
drop policy if exists "Room members can update shared media" on storage.objects;
create policy "Room members can update shared media" on storage.objects
  for update to authenticated using (
    bucket_id = 'salasync-media'
    and public.is_salasync_member((storage.foldername(name))[1]::uuid, auth.uid())
  ) with check (
    bucket_id = 'salasync-media'
    and public.is_salasync_member((storage.foldername(name))[1]::uuid, auth.uid())
  );
drop policy if exists "Room members can delete shared media" on storage.objects;
create policy "Room members can delete shared media" on storage.objects
  for delete to authenticated using (
    bucket_id = 'salasync-media'
    and public.is_salasync_member((storage.foldername(name))[1]::uuid, auth.uid())
  );

alter table public.salasync_rooms replica identity full;
alter table public.salasync_messages replica identity full;

do $$
begin
  alter publication supabase_realtime add table public.salasync_rooms;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.salasync_messages;
exception when duplicate_object then null;
end $$;

-- Pronto. Configure Authentication > Sign In / Providers > Anonymous Sign-ins.


-- Diretório público de salas. Mostra apenas metadados, nunca senha, URLs ou caminhos dos arquivos.
create table if not exists public.salasync_room_directory (
  id uuid primary key references public.salasync_rooms(id) on delete cascade,
  name text not null,
  is_public boolean not null default false,
  media_type text not null default 'none',
  media_title text,
  created_at timestamptz not null
);

alter table public.salasync_room_directory enable row level security;
drop policy if exists "Authenticated users can see room directory" on public.salasync_room_directory;
create policy "Authenticated users can see room directory" on public.salasync_room_directory
  for select to authenticated using (auth.uid() is not null);
revoke insert, update, delete on public.salasync_room_directory from anon, authenticated;
grant select on public.salasync_room_directory to authenticated;

create or replace function public.sync_salasync_room_directory()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    delete from public.salasync_room_directory where id = old.id;
    return old;
  end if;

  -- Playback updates happen frequently; do not emit directory updates for them.
  if tg_op = 'UPDATE'
     and new.name is not distinct from old.name
     and new.is_public is not distinct from old.is_public
     and new.media_type is not distinct from old.media_type
     and new.media_title is not distinct from old.media_title
     and new.created_at is not distinct from old.created_at then
    return new;
  end if;

  insert into public.salasync_room_directory(id, name, is_public, media_type, media_title, created_at)
  values (new.id, new.name, new.is_public, new.media_type, new.media_title, new.created_at)
  on conflict (id) do update set
    name = excluded.name,
    is_public = excluded.is_public,
    media_type = excluded.media_type,
    media_title = excluded.media_title,
    created_at = excluded.created_at;
  return new;
end;
$$;

drop trigger if exists salasync_rooms_directory_sync on public.salasync_rooms;
create trigger salasync_rooms_directory_sync
  after insert or update or delete on public.salasync_rooms
  for each row execute function public.sync_salasync_room_directory();

insert into public.salasync_room_directory(id, name, is_public, media_type, media_title, created_at)
select id, name, is_public, media_type, media_title, created_at
from public.salasync_rooms
on conflict (id) do update set
  name = excluded.name,
  is_public = excluded.is_public,
  media_type = excluded.media_type,
  media_title = excluded.media_title,
  created_at = excluded.created_at;

create or replace function public.list_salasync_rooms()
returns table(
  id uuid,
  name text,
  is_public boolean,
  media_type text,
  media_title text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select d.id, d.name, d.is_public, d.media_type, d.media_title, d.created_at
  from public.salasync_room_directory d
  order by d.created_at desc;
$$;

revoke all on function public.list_salasync_rooms() from public, anon;
grant execute on function public.list_salasync_rooms() to authenticated;

alter table public.salasync_room_directory replica identity full;
do $$
begin
  alter publication supabase_realtime add table public.salasync_room_directory;
exception when duplicate_object then null;
end $$;
