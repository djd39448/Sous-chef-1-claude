-- Sous Chef AI — initial schema
-- Ported from sous-chef-ai shared/schema.ts (Drizzle/Postgres).
-- See contract/data-model.md for the normative description and Decisions D1-D4.

-- ============================================================
-- Helpers
-- ============================================================

-- Keeps updated_at current on any UPDATE.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ============================================================
-- profiles  (Decision D1 — replaces the original users table)
-- ============================================================
create table public.profiles (
  id                 uuid primary key references auth.users (id) on delete cascade,
  email              text unique,
  first_name         text,
  last_name          text,
  profile_image_url  text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Create a profile row automatically when a user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, profile_image_url)
  values (new.id, new.email, new.raw_user_meta_data ->> 'avatar_url')
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- food_items  — the Canonical Food Object
-- ============================================================
create table public.food_items (
  id              serial primary key,
  user_id         uuid not null references auth.users (id) on delete cascade,
  canonical_name  text not null,
  display_name    text not null,
  quantity        jsonb,
  category        jsonb not null,
  attributes      jsonb not null default '{}'::jsonb,
  flexibility     jsonb not null default
                    '{"substitution_allowed":true,"acceptable_variants":[],"strict":false}'::jsonb,
  usage_context   jsonb not null,
  inventory_state jsonb not null default
                    '{"status":"unknown","on_hand_amount":null,"last_confirmed":null}'::jsonb,
  sourcing        jsonb not null default
                    '{"store_affinity":null,"bulk_allowed":true,"generic_ok":true}'::jsonb,
  metadata        jsonb not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index food_items_user_idx on public.food_items (user_id);

-- CFO identity invariant: one item per (user, canonical_name, role).
-- Lets the backend upsert with ON CONFLICT race-safely.
create unique index food_items_identity_uniq
  on public.food_items (user_id, canonical_name, (usage_context ->> 'role'));

create trigger food_items_set_updated_at
  before update on public.food_items
  for each row execute function public.set_updated_at();

-- ============================================================
-- ingredient_memory  (Decision D3 — legacy soft inventory)
-- ============================================================
create table public.ingredient_memory (
  id              serial primary key,
  user_id         uuid not null references auth.users (id) on delete cascade,
  name            text not null,
  quantity        text,
  confidence      real not null default 1.0,
  last_mentioned  timestamptz not null default now(),
  created_at      timestamptz not null default now()
);

create unique index ingredient_memory_user_name_uniq
  on public.ingredient_memory (user_id, name);

-- ============================================================
-- recipes  — dormant; kept for schema fidelity
-- ============================================================
create table public.recipes (
  id            serial primary key,
  user_id       uuid not null references auth.users (id) on delete cascade,
  name          text not null,
  description   text,
  ingredients   jsonb not null,
  instructions  jsonb not null,
  cook_time     integer,
  servings      integer default 4,
  created_at    timestamptz not null default now()
);

-- ============================================================
-- meal_plans / meal_plan_days
-- ============================================================
create table public.meal_plans (
  id              serial primary key,
  user_id         uuid not null references auth.users (id) on delete cascade,
  week_start_date date not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- One plan per week.
create unique index meal_plans_user_week_uniq
  on public.meal_plans (user_id, week_start_date);

create trigger meal_plans_set_updated_at
  before update on public.meal_plans
  for each row execute function public.set_updated_at();

create table public.meal_plan_days (
  id                  serial primary key,
  meal_plan_id        integer not null references public.meal_plans (id) on delete cascade,
  day_of_week         integer not null,
  recipe_id           integer references public.recipes (id),
  meal_name           text not null,
  notes               text,
  recipe_content      text,
  recipe_image_prompt text
);

create index meal_plan_days_plan_idx on public.meal_plan_days (meal_plan_id);

-- ============================================================
-- cookbook_recipes
-- ============================================================
create table public.cookbook_recipes (
  id            serial primary key,
  user_id       uuid not null references auth.users (id) on delete cascade,
  title         text not null,
  content       text not null,
  image_prompt  text,
  created_at    timestamptz not null default now()
);

create index cookbook_recipes_user_idx on public.cookbook_recipes (user_id);

-- ============================================================
-- shopping_lists / shopping_list_items
-- ============================================================
create table public.shopping_lists (
  id              serial primary key,
  user_id         uuid not null references auth.users (id) on delete cascade,
  name            text not null,
  week_start_date date,
  meal_plan_id    integer references public.meal_plans (id) on delete set null,
  created_at      timestamptz not null default now()
);

-- One list per week (only when a week is assigned).
create unique index shopping_lists_user_week_uniq
  on public.shopping_lists (user_id, week_start_date)
  where week_start_date is not null;

create table public.shopping_list_items (
  id                serial primary key,
  shopping_list_id  integer not null references public.shopping_lists (id) on delete cascade,
  name              text not null,
  quantity          text,
  category          text not null,
  checked           integer not null default 0
);

create index shopping_list_items_list_idx
  on public.shopping_list_items (shopping_list_id);

-- ============================================================
-- kitchen_conversations / kitchen_messages
-- ============================================================
create table public.kitchen_conversations (
  id          serial primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  title       text not null default 'New Chat',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index kitchen_conversations_user_idx
  on public.kitchen_conversations (user_id);

create trigger kitchen_conversations_set_updated_at
  before update on public.kitchen_conversations
  for each row execute function public.set_updated_at();

create table public.kitchen_messages (
  id               serial primary key,
  conversation_id  integer not null
                     references public.kitchen_conversations (id) on delete cascade,
  role             text not null,
  content          text not null,
  metadata         jsonb,
  created_at       timestamptz not null default now()
);

create index kitchen_messages_conversation_idx
  on public.kitchen_messages (conversation_id, created_at);
