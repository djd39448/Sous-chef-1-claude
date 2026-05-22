# Data Model

The database is PostgreSQL on Supabase. This document is the normative
description; `supabase/migrations/` is the executable form of it.

Column names are `snake_case`. JSON returned by the API uses `camelCase` for row
columns (the original Drizzle ORM mapped e.g. `week_start_date` → `weekStartDate`)
and `snake_case` *inside* CFO JSONB blobs. Both are preserved exactly — see
`api-spec.md` for the response shapes.

## Identity & auth (Decision D1)

Supabase Auth owns users. It maintains the `auth.users` table and issues JWTs.
There is **no** `sessions` table and **no** application `users` table.

### `profiles`
One row per user, created on first sign-in. Mirrors the original `users` table.

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | = `auth.users.id`, `references auth.users(id) on delete cascade` |
| `email` | `text` | unique, nullable |
| `first_name` | `text` | nullable |
| `last_name` | `text` | nullable |
| `profile_image_url` | `text` | nullable |
| `created_at` | `timestamptz` | default `now()` |
| `updated_at` | `timestamptz` | default `now()` |

Every other table's `user_id` is a `uuid` referencing `auth.users(id) on delete
cascade`. (The original used Replit's opaque string user IDs; Supabase user IDs
are UUIDs.)

## Canonical Food Object

### `food_items`
The CFO — the single object schema for all food data (inventory, shopping,
recipe ingredients, planned items). Lists and plans are *views* over this table,
distinguished by `usage_context.role`.

| Column | Type | Notes |
|---|---|---|
| `id` | `serial` PK | |
| `user_id` | `uuid` | not null, FK `auth.users` |
| `canonical_name` | `text` | not null. lowercase, singular, generic ("milk"). Always stored lowercased. |
| `display_name` | `text` | not null. human-readable ("Whole Milk"). UI only, never used for matching. |
| `quantity` | `jsonb` | nullable. `FoodQuantity`. |
| `category` | `jsonb` | not null. `FoodCategory`. |
| `attributes` | `jsonb` | default `{}`. `FoodAttributes`. |
| `flexibility` | `jsonb` | default `{substitution_allowed:true,acceptable_variants:[],strict:false}`. `FoodFlexibility`. |
| `usage_context` | `jsonb` | not null. `FoodUsageContext`. |
| `inventory_state` | `jsonb` | default `{status:"unknown",on_hand_amount:null,last_confirmed:null}`. `FoodInventoryState`. |
| `sourcing` | `jsonb` | default `{store_affinity:null,bulk_allowed:true,generic_ok:true}`. `FoodSourcing`. |
| `metadata` | `jsonb` | not null. `FoodMetadata`. |
| `created_at` | `timestamptz` | default `now()` |
| `updated_at` | `timestamptz` | default `now()` |

**Identity invariant.** A food item is uniquely identified by
`(user_id, canonical_name, usage_context.role)`. The same `canonical_name` may
exist once per role — e.g. "milk" as both `inventory` and `shopping`. Upserts
match on this triple. Enforced by a unique expression index (see Constraints);
the original enforced it only in application code.

### CFO JSONB shapes

`snake_case` keys, exactly as the original stores them.

```
FoodQuantity      { amount: number, unit: string }

FoodCategory      { primary: IngredientCategory, secondary?: string }

FoodAttributes    { [key: string]: string | boolean | number | null }

FoodFlexibility   { substitution_allowed: boolean,
                    acceptable_variants: string[],
                    strict: boolean }

FoodUsageContext  { role: FoodItemRole,
                    required: boolean,
                    recipe_ids: number[],
                    meal_plan_id?: number,
                    shopping_list_id?: number }

FoodInventoryState { status: InventoryStatus,
                     on_hand_amount: number | null,
                     last_confirmed: string | null }   // ISO-8601

FoodSourcing      { store_affinity: string | null,
                    bulk_allowed: boolean,
                    generic_ok: boolean }

FoodMetadata      { created_by: "ai" | "user", confidence: number }  // 0..1
```

### Enums (string values, not Postgres enum types)

```
IngredientCategory : produce | dairy | meat | seafood | pantry
                     | frozen | bakery | beverages | other
FoodItemRole       : ingredient | planned | inventory | shopping
InventoryStatus    : confirmed | likely | unknown | out
```

## Meal planning

### `meal_plans`
| Column | Type | Notes |
|---|---|---|
| `id` | `serial` PK | |
| `user_id` | `uuid` | not null, FK `auth.users` |
| `week_start_date` | `date` | not null. Monday of the week (ISO `YYYY-MM-DD`). |
| `created_at` | `timestamptz` | default `now()` |
| `updated_at` | `timestamptz` | default `now()` |

One plan per `(user_id, week_start_date)` — unique constraint. Creating a plan
for a week that already has one **replaces** it (delete-then-insert).

### `meal_plan_days`
| Column | Type | Notes |
|---|---|---|
| `id` | `serial` PK | |
| `meal_plan_id` | `integer` | not null, FK `meal_plans(id) on delete cascade` |
| `day_of_week` | `integer` | `0`=Sunday … `6`=Saturday |
| `recipe_id` | `integer` | nullable, FK `recipes(id)`. Currently always null — see note. |
| `meal_name` | `text` | not null |
| `notes` | `text` | nullable. Free text, usually a cook time ("30 min"). |
| `recipe_content` | `text` | nullable. Full recipe Markdown, filled on demand. |
| `recipe_image_prompt` | `text` | nullable. Prompt for `gpt-image-1`, filled with `recipe_content`. |

> The recipe **content** lives in `recipe_content` on the day row. The `recipes`
> table and `recipe_id` FK exist in the schema but no code path populates them;
> kept for fidelity, effectively dormant.

### `recipes`
Dormant table — preserved from the original schema, not written by any flow.
| Column | Type | Notes |
|---|---|---|
| `id` | `serial` PK | |
| `user_id` | `uuid` | not null |
| `name` | `text` | not null |
| `description` | `text` | nullable |
| `ingredients` | `jsonb` | not null. `string[]`. |
| `instructions` | `jsonb` | not null. `string[]`. |
| `cook_time` | `integer` | nullable |
| `servings` | `integer` | default `4` |
| `created_at` | `timestamptz` | default `now()` |

### `cookbook_recipes`
Saved recipes, reused as RAG context in chat and meal-plan generation.
| Column | Type | Notes |
|---|---|---|
| `id` | `serial` PK | |
| `user_id` | `uuid` | not null |
| `title` | `text` | not null |
| `content` | `text` | not null. Recipe Markdown. |
| `image_prompt` | `text` | nullable |
| `created_at` | `timestamptz` | default `now()` |

## Shopping

### `shopping_lists`
| Column | Type | Notes |
|---|---|---|
| `id` | `serial` PK | |
| `user_id` | `uuid` | not null |
| `name` | `text` | not null |
| `week_start_date` | `date` | nullable |
| `meal_plan_id` | `integer` | nullable, FK `meal_plans(id) on delete set null` |
| `created_at` | `timestamptz` | default `now()` |

When `week_start_date` is set, creating a list for that week **replaces** the
existing one — partial unique index on `(user_id, week_start_date)` where the
date is not null.

### `shopping_list_items`
| Column | Type | Notes |
|---|---|---|
| `id` | `serial` PK | |
| `shopping_list_id` | `integer` | not null, FK `shopping_lists(id) on delete cascade` |
| `name` | `text` | not null |
| `quantity` | `text` | nullable. Free text ("2 lbs"). |
| `category` | `text` | not null |
| `checked` | `integer` | default `0`. `0` = unchecked, `1` = checked. (Int, not bool — preserved from original.) |

## Chat

### `kitchen_conversations`
| Column | Type | Notes |
|---|---|---|
| `id` | `serial` PK | |
| `user_id` | `uuid` | not null |
| `title` | `text` | not null, default `'New Chat'` |
| `created_at` | `timestamptz` | default `now()` |
| `updated_at` | `timestamptz` | default `now()`. Bumped on every new message. |

### `kitchen_messages`
| Column | Type | Notes |
|---|---|---|
| `id` | `serial` PK | |
| `conversation_id` | `integer` | not null, FK `kitchen_conversations(id) on delete cascade` |
| `role` | `text` | `'user'` or `'assistant'` |
| `content` | `text` | not null |
| `metadata` | `jsonb` | nullable |
| `created_at` | `timestamptz` | default `now()` |

## Ingredient memory (legacy, Decision D3)

### `ingredient_memory`
"Soft inventory" — a simpler key/value store the AI dual-writes alongside CFO
inventory items. `GET /api/kitchen/ingredients` reads from here.

| Column | Type | Notes |
|---|---|---|
| `id` | `serial` PK | |
| `user_id` | `uuid` | not null |
| `name` | `text` | not null. Stored lowercased. |
| `quantity` | `text` | nullable. Free text. |
| `confidence` | `real` | not null, default `1.0` |
| `last_mentioned` | `timestamptz` | not null, default `now()` |
| `created_at` | `timestamptz` | default `now()` |

Upsert key: `(user_id, lower(name))`.

> Decision D3: this table and `shopping_list_items` are *legacy* — the CFO spec
> intends them to be views over `food_items`. The port keeps the original
> dual-write behavior faithfully; consolidation is a future cleanup.

## Constraints & indexes

Beyond primary keys and the foreign keys above:

| Object | Definition | Why |
|---|---|---|
| `food_items` unique | `(user_id, canonical_name, (usage_context->>'role'))` | The CFO identity invariant. Makes upserts race-safe via `ON CONFLICT`. |
| `food_items` index | `(user_id)` | Per-user list queries. |
| `meal_plans` unique | `(user_id, week_start_date)` | One plan per week. |
| `meal_plan_days` index | `(meal_plan_id)` | Day lookup by plan. |
| `shopping_lists` partial unique | `(user_id, week_start_date) where week_start_date is not null` | One list per week. |
| `shopping_list_items` index | `(shopping_list_id)` | Item lookup by list. |
| `kitchen_messages` index | `(conversation_id, created_at)` | Ordered history reads. |
| `ingredient_memory` unique | `(user_id, name)` | Upsert key. |

## Removed from the original (Decision D2)

`shared/models/chat.ts` defined `conversations` and `messages` tables that no
route or storage method references — dead code. They are not in this schema.
