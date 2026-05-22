-- Sous Chef AI — row-level security
--
-- Every user sees and modifies only their own data. Owned tables key off
-- user_id = auth.uid(); child tables check ownership through their parent.
--
-- Note: the Go backend connects with a service-role credential that bypasses
-- RLS and enforces ownership in code (faithful to the original Express server).
-- These policies protect the Supabase PostgREST surface as defense-in-depth.

-- ============================================================
-- profiles
-- ============================================================
alter table public.profiles enable row level security;

create policy profiles_select_own on public.profiles
  for select using (id = auth.uid());

create policy profiles_update_own on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

-- ============================================================
-- Owned tables — user_id = auth.uid()
-- ============================================================
alter table public.food_items enable row level security;
create policy food_items_owner on public.food_items
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.ingredient_memory enable row level security;
create policy ingredient_memory_owner on public.ingredient_memory
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.recipes enable row level security;
create policy recipes_owner on public.recipes
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.cookbook_recipes enable row level security;
create policy cookbook_recipes_owner on public.cookbook_recipes
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.meal_plans enable row level security;
create policy meal_plans_owner on public.meal_plans
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.shopping_lists enable row level security;
create policy shopping_lists_owner on public.shopping_lists
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.kitchen_conversations enable row level security;
create policy kitchen_conversations_owner on public.kitchen_conversations
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ============================================================
-- Child tables — ownership via parent
-- ============================================================
alter table public.meal_plan_days enable row level security;
create policy meal_plan_days_owner on public.meal_plan_days
  for all
  using (exists (
    select 1 from public.meal_plans p
    where p.id = meal_plan_days.meal_plan_id and p.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.meal_plans p
    where p.id = meal_plan_days.meal_plan_id and p.user_id = auth.uid()
  ));

alter table public.shopping_list_items enable row level security;
create policy shopping_list_items_owner on public.shopping_list_items
  for all
  using (exists (
    select 1 from public.shopping_lists l
    where l.id = shopping_list_items.shopping_list_id and l.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.shopping_lists l
    where l.id = shopping_list_items.shopping_list_id and l.user_id = auth.uid()
  ));

alter table public.kitchen_messages enable row level security;
create policy kitchen_messages_owner on public.kitchen_messages
  for all
  using (exists (
    select 1 from public.kitchen_conversations c
    where c.id = kitchen_messages.conversation_id and c.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.kitchen_conversations c
    where c.id = kitchen_messages.conversation_id and c.user_id = auth.uid()
  ));
