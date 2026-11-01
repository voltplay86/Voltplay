
-- ==========================================
-- VOLTPLAY MEMBERSHIP SYSTEM
-- Database schema - Supabase
-- ==========================================

create extension if not exists pgcrypto;

-- 1. USER PROFILES
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz default now()
);

-- 2. NEWSLETTER SUBSCRIBERS
create table if not exists public.newsletter_subscribers (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  consented_at timestamptz not null default now(),
  confirmed_at timestamptz,
  unsubscribed_at timestamptz
);

-- 3. PREMIUM SUBSCRIPTIONS
create table if not exists public.subscriptions (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references auth.users(id) on delete cascade,

  provider text not null default 'stripe',

  stripe_customer_id text unique,
  stripe_subscription_id text unique,

  plan text not null check (
    plan in ('premium_monthly', 'premium_yearly')
  ),

  status text not null default 'pending' check (
    status in (
      'pending',
      'active',
      'trialing',
      'past_due',
      'canceled',
      'incomplete',
      'unpaid'
    )
  ),

  current_period_start timestamptz,
  current_period_end timestamptz,

  cancel_at_period_end boolean default false,

  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 4. SECURITY
alter table public.profiles enable row level security;
alter table public.newsletter_subscribers enable row level security;
alter table public.subscriptions enable row level security;

-- Users can only access their own profile
create policy "Read own profile"
on public.profiles
for select to authenticated
using (auth.uid() = id);

create policy "Insert own profile"
on public.profiles
for insert to authenticated
with check (auth.uid() = id);

create policy "Update own profile"
on public.profiles
for update to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

-- Users can only read their own subscriptions
create policy "Read own subscriptions"
on public.subscriptions
for select to authenticated
using (auth.uid() = user_id);

-- No public access to newsletter or subscription writes.
-- These operations will use secure server-side functions.

-- 5. AUTOMATIC PROFILE CREATION
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', '')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- 6. UPDATE TIMESTAMP
create or replace function public.update_timestamp()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists subscription_timestamp
on public.subscriptions;

create trigger subscription_timestamp
before update on public.subscriptions
for each row execute procedure public.update_timestamp();
