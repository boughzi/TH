-- =====================================================================
-- LiveTV · Esquema completo para Supabase
-- Pegar en SQL Editor y ejecutar. Es idempotente (se puede relanzar).
-- =====================================================================
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- TABLAS
-- ---------------------------------------------------------------------
-- Correos con permiso de administración (solo accesible vía is_admin()).
create table if not exists public.admins (
  email text primary key
);

create table if not exists public.categories (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  sort_order int  not null default 0,
  is_hidden  boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.channels (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  country_code    text not null default 'un' check (country_code ~ '^[a-z]{2}$'),
  country_name    text not null default 'Internacional',
  category_id     uuid references public.categories(id) on delete set null,
  logo_url        text,
  stream_url_enc  text not null,              -- base64(nonce12 || AES-256-GCM(url) || tag16)
  sort_order      int  not null default 0,
  is_hidden       boolean not null default false,  -- lo controla el admin
  is_active       boolean not null default true,   -- lo controla el chequeo nocturno
  fail_count      int  not null default 0,
  last_checked_at timestamptz,
  created_at      timestamptz not null default now()
);
create index if not exists channels_country_idx  on public.channels (country_code);
create index if not exists channels_category_idx on public.channels (category_id);

-- Una fila por usuario registrado (se crea sola al hacer login con Google).
create table if not exists public.user_codes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null unique references auth.users(id) on delete cascade,
  email       text not null,
  code        text,                              -- código de activación generado por el admin
  is_active   boolean not null default false,
  redeemed_at timestamptz,                       -- cuándo el usuario canjeó el código
  expires_at  timestamptz,                       -- caducidad (null = sin caducidad)
  attempts    int not null default 0,            -- intentos fallidos (bloqueo a los 10)
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.app_config (
  key             text primary key,
  value           text not null,
  requires_access boolean not null default false, -- true = solo usuarios activados/admin
  updated_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- FUNCIONES
-- ---------------------------------------------------------------------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.admins
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

create or replace function public.has_access() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.user_codes u
    where u.user_id = auth.uid()
      and u.is_active
      and u.redeemed_at is not null
      and (u.expires_at is null or u.expires_at > now())
  );
$$;

-- Estado para la app: locked | disabled | expired | ok
create or replace function public.access_status() returns text
language plpgsql stable security definer set search_path = public as $$
declare u public.user_codes;
begin
  select * into u from public.user_codes where user_id = auth.uid();
  if not found or u.redeemed_at is null then return 'locked'; end if;
  if not u.is_active then return 'disabled'; end if;
  if u.expires_at is not null and u.expires_at <= now() then return 'expired'; end if;
  return 'ok';
end $$;

-- Canje del código manual (el usuario nunca puede leer su propio código).
create or replace function public.redeem_code(p_code text) returns boolean
language plpgsql security definer set search_path = public as $$
declare u public.user_codes;
begin
  select * into u from public.user_codes where user_id = auth.uid() for update;
  if not found or u.code is null or u.attempts >= 10 then return false; end if;
  if upper(trim(p_code)) <> upper(u.code) then
    update public.user_codes set attempts = attempts + 1 where user_id = auth.uid();
    return false;
  end if;
  update public.user_codes
     set redeemed_at = coalesce(redeemed_at, now()), attempts = 0, updated_at = now()
   where user_id = auth.uid();
  return true;
end $$;

-- Alta automática en user_codes al registrarse un usuario nuevo.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.user_codes (user_id, email)
  values (new.id, lower(coalesce(new.email, '')))
  on conflict do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Usuarios que ya existían antes de ejecutar este script.
insert into public.user_codes (user_id, email)
select id, lower(coalesce(email, '')) from auth.users
on conflict do nothing;

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
alter table public.admins     enable row level security;  -- sin políticas: nadie la lee por API
alter table public.categories enable row level security;
alter table public.channels   enable row level security;
alter table public.user_codes enable row level security;
alter table public.app_config enable row level security;

-- categories
drop policy if exists categories_read  on public.categories;
drop policy if exists categories_admin on public.categories;
create policy categories_read on public.categories for select to authenticated
  using ((select public.is_admin()) or ((select public.has_access()) and not is_hidden));
create policy categories_admin on public.categories for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- channels: la app solo ve canales activos, no ocultos y de categorías no ocultas
drop policy if exists channels_read  on public.channels;
drop policy if exists channels_admin on public.channels;
create policy channels_read on public.channels for select to authenticated
  using (
    (select public.is_admin())
    or (
      (select public.has_access()) and is_active and not is_hidden
      and (category_id is null or exists (
            select 1 from public.categories c where c.id = category_id and not c.is_hidden))
    )
  );
create policy channels_admin on public.channels for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- user_codes: SOLO admin (la app usa access_status() y redeem_code())
drop policy if exists user_codes_admin on public.user_codes;
create policy user_codes_admin on public.user_codes for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- app_config
drop policy if exists app_config_read  on public.app_config;
drop policy if exists app_config_admin on public.app_config;
create policy app_config_read on public.app_config for select to authenticated
  using ((select public.is_admin()) or not requires_access or (select public.has_access()));
create policy app_config_admin on public.app_config for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- ---------------------------------------------------------------------
-- DATOS INICIALES
-- ---------------------------------------------------------------------
insert into public.app_config (key, value, requires_access) values
  ('aes_key', encode(extensions.gen_random_bytes(32), 'hex'), true),   -- clave AES-256 (64 hex)
  ('contact_text', 'Contacta con el administrador para obtener tu código de activación.', false)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- TU CUENTA DE ADMIN (cámbiala por el correo del usuario que crees en
-- Authentication → Users → Add user, con contraseña):
-- ---------------------------------------------------------------------
-- insert into public.admins (email) values ('tu-correo@gmail.com') on conflict do nothing;
