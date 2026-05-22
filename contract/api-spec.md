# API Specification

The backend exposes a REST API. All paths below are relative to the API base
URL (the AWS deployment; `http://localhost:8080` in development).

## Conventions

- **Auth.** Every endpoint requires `Authorization: Bearer <jwt>`, where the JWT
  is a Supabase Auth access token. The backend validates it and derives
  `userId` from the `sub` claim (a `uuid`). Missing/invalid → `401`.
- **JSON casing.** Response objects use `camelCase` for row columns
  (`weekStartDate`, `createdAt`, `mealPlanId`, …). Keys *inside* CFO JSONB blobs
  stay `snake_case` (`canonical_name`, `usage_context`, …). See `data-model.md`.
- **Errors.** `{ "error": "<message>" }` with a `4xx`/`5xx` status.
- **SSE.** Streaming endpoints respond `Content-Type: text/event-stream`; each
  event is a line `data: <json>\n\n`. Errors mid-stream are sent as
  `data: {"error":"..."}` then the stream ends.
- **Timestamps** are ISO-8601 strings. **Dates** (`weekStartDate`) are
  `YYYY-MM-DD`.

## Object shapes (response JSON)

```
Profile        { id, email, firstName, lastName, profileImageUrl,
                 createdAt, updatedAt }

Conversation   { id, userId, title, createdAt, updatedAt }
Message        { id, conversationId, role, content, metadata, createdAt }
ConversationWithMessages = Conversation & { messages: Message[] }

MealPlan       { id, userId, weekStartDate, createdAt, updatedAt }
MealPlanDay    { id, mealPlanId, dayOfWeek, recipeId, mealName, notes,
                 recipeContent, recipeImagePrompt }
MealPlanWithDays = MealPlan & { days: MealPlanDay[] }

ShoppingList   { id, userId, name, weekStartDate, mealPlanId, createdAt }
ShoppingItem   { id, shoppingListId, name, quantity, category, checked }
ShoppingListWithItems = ShoppingList & { items: ShoppingItem[] }

CookbookRecipe { id, userId, title, content, imagePrompt, createdAt }

Ingredient     { id, userId, name, quantity, confidence,
                 lastMentioned, createdAt }

FoodItem       { id, userId, canonicalName, displayName, quantity,
                 category, attributes, flexibility, usageContext,
                 inventoryState, sourcing, metadata, createdAt, updatedAt }
```

## Endpoint index

| Method | Path | Streaming | Summary |
|---|---|---|---|
| GET | `/api/auth/user` | | Current user's profile |
| GET | `/api/kitchen/conversation` | | Default conversation + messages |
| GET | `/api/kitchen/conversations` | | All conversations |
| POST | `/api/kitchen/conversation/new` | | Create a conversation |
| GET | `/api/kitchen/conversation/:id` | | One conversation + messages |
| POST | `/api/kitchen/message` | SSE | Send a chat message, stream reply |
| GET | `/api/kitchen/meal-plan` | | Most recent meal plan |
| GET | `/api/kitchen/calendar` | | All plans + lists (no children) |
| GET | `/api/kitchen/week/:weekStartDate` | | Plan + list for one week |
| POST | `/api/kitchen/generate-meal-plan` | | AI-generate a weekly plan |
| GET | `/api/kitchen/meal-plan-day/:id` | | One meal-plan day |
| POST | `/api/kitchen/generate-recipe/:dayId` | SSE | AI-generate a full recipe |
| POST | `/api/kitchen/recipe-message` | SSE | Per-recipe chat (swap a meal) |
| GET | `/api/kitchen/shopping-list` | | Most recent shopping list |
| GET | `/api/kitchen/shopping-lists` | | All shopping lists |
| GET | `/api/kitchen/shopping-list/:identifier` | | List by id or week |
| POST | `/api/kitchen/generate-shopping-list` | | AI-generate a shopping list |
| PATCH | `/api/kitchen/shopping-item/:id` | | Check/uncheck an item |
| DELETE | `/api/kitchen/shopping-items/checked` | | Clear checked items |
| GET | `/api/kitchen/ingredients` | | Ingredient memory |
| GET | `/api/kitchen/cookbook` | | All cookbook recipes |
| GET | `/api/kitchen/cookbook/:id` | | One cookbook recipe |
| POST | `/api/kitchen/cookbook` | | Save a recipe to the cookbook |
| DELETE | `/api/kitchen/cookbook/:id` | | Delete a cookbook recipe |
| POST | `/api/kitchen/regenerate-image` | | Generate a food photo |

Ownership: any endpoint taking an `:id`/`:dayId` returns `403` if the row
belongs to another user, `404` if it does not exist, `400` if the id is not a
valid integer.

---

## Auth

### `GET /api/auth/user`
Returns the caller's `Profile`. The profile row is created automatically on
sign-up by a database trigger (see `supabase/migrations`), so this is a plain
read. `401` if unauthenticated.

---

## Conversations & chat

### `GET /api/kitchen/conversation`
Returns the user's most recently created conversation as
`ConversationWithMessages`. If the user has none, one is created (title
`"Kitchen Chat"`) and returned with an empty `messages` array.

### `GET /api/kitchen/conversations`
Returns `Conversation[]`, ordered by `updatedAt` descending. No messages.

### `POST /api/kitchen/conversation/new`
Creates a new conversation (title `"Kitchen Chat"`). Returns the `Conversation`.

### `GET /api/kitchen/conversation/:id`
Returns `ConversationWithMessages` for `:id` if owned by the caller. `404` if
not found or not owned.

### `POST /api/kitchen/message` — SSE
Send a chat message; the assistant's reply streams back.

Request body:
```
{ "content": string,            // required
  "conversationId": number }    // optional; default = most recent conversation
```

Behavior:
1. Resolve the conversation (`conversationId`, else most-recent, else create).
   `404` if `conversationId` is given but not owned.
2. Persist the user message.
3. Build the OpenAI request (see `ai-behavior.md` → *Main chat*): system prompt
   + ingredient context (from `ingredient_memory`) + cookbook context (from
   `cookbook_recipes`) + last 10 messages of history.
4. Stream the completion. Assistant text is forwarded chunk by chunk. Tool
   calls (`update_ingredients`, `create_meal_plan`, `create_shopping_list`) are
   executed server-side and **not** surfaced in the stream — the client
   refetches affected resources after the stream ends.
5. Persist the full assistant message.

SSE events:
```
data: {"content":"<delta>"}     // repeated, partial assistant text
data: {"done":true}             // final
data: {"error":"<message>"}     // on failure (instead of done)
```

---

## Meal plans

### `GET /api/kitchen/meal-plan`
Most recent `MealPlanWithDays` for the user, or `null`.

### `GET /api/kitchen/calendar`
`{ "mealPlans": MealPlan[], "shoppingLists": ShoppingList[] }` — all of the
user's plans and lists, no `days`/`items`. `mealPlans` ordered by
`weekStartDate` desc; `shoppingLists` by `createdAt` desc.

### `GET /api/kitchen/week/:weekStartDate`
`weekStartDate` is `YYYY-MM-DD`. Returns
`{ "mealPlan": MealPlanWithDays | null, "shoppingList": ShoppingListWithItems | null }`.

### `POST /api/kitchen/generate-meal-plan`
Request body: `{ "weekStartDate": string }` (optional; defaults to the current
week's Monday). AI-generates a 7-day plan (see `ai-behavior.md` → *Meal-plan
generation*), **replacing** any existing plan for that week, and creates one
`meal_plan_days` row per returned meal. Returns the new `MealPlanWithDays`.

### `GET /api/kitchen/meal-plan-day/:id`
Returns the `MealPlanDay` for `:id` (with a `userId` field), ownership-checked.

### `POST /api/kitchen/generate-recipe/:dayId` — SSE
Generates the full recipe for a meal-plan day and streams it as Markdown.
Ownership-checked. On completion the backend saves `recipeContent` and a derived
`recipeImagePrompt` onto the day row.

SSE events:
```
data: {"content":"<delta>"}                       // repeated, recipe Markdown
data: {"imagePrompt":"<prompt>","done":true}      // final
data: {"error":"<message>"}                        // on failure
```
The image is **not** generated here — the client calls `regenerate-image` with
the returned `imagePrompt` when it wants the photo.

### `POST /api/kitchen/recipe-message` — SSE
Per-recipe chat: ask questions about a meal, or swap it for another.

Request body:
```
{ "content": string,    // required — the user's message
  "dayId": number,      // required — the meal_plan_days row
  "mealName": string,   // current meal name (prompt context)
  "dayName": string }   // e.g. "Tuesday" (prompt context)
```
Ownership-checked on `dayId`. Streams the reply; if the model calls the
`update_meal` tool the day's `mealName`/`notes` are updated and
`recipeContent`/`recipeImagePrompt` are cleared.

SSE events:
```
data: {"content":"<delta>"}                              // repeated
data: {"done":true,"updatedMeal":{"mealName":...,"notes":...}}   // or "updatedMeal":null
data: {"error":"<message>"}                               // on failure
```

---

## Shopping lists

### `GET /api/kitchen/shopping-list`
Most recent `ShoppingListWithItems`, or `null`.

### `GET /api/kitchen/shopping-lists`
`ShoppingList[]`, ordered by `createdAt` desc. No items.

### `GET /api/kitchen/shopping-list/:identifier`
If `:identifier` is all digits → look up by list id (user-scoped). Otherwise
treat it as a `weekStartDate` and look up by week. Returns
`ShoppingListWithItems | null`.

### `POST /api/kitchen/generate-shopping-list`
No body. Generates a shopping list for the user's most recent meal plan (see
`ai-behavior.md` → *Shopping-list generation*), creates the list and its items,
and returns the most recent `ShoppingListWithItems`.

### `PATCH /api/kitchen/shopping-item/:id`
Body `{ "checked": boolean }`. Sets the item's `checked` to `1`/`0`. Returns the
updated `ShoppingItem`.

### `DELETE /api/kitchen/shopping-items/checked`
Deletes all checked items from the user's most recent shopping list. `204`.

---

## Ingredients

### `GET /api/kitchen/ingredients`
`Ingredient[]` from `ingredient_memory` for the user.

---

## Cookbook

### `GET /api/kitchen/cookbook`
`CookbookRecipe[]`, ordered by `createdAt` desc.

### `GET /api/kitchen/cookbook/:id`
One `CookbookRecipe`, ownership-checked.

### `POST /api/kitchen/cookbook`
Body `{ "title": string, "content": string, "imagePrompt": string? }`. Saves and
returns the `CookbookRecipe`. `400` if `title` or `content` is missing.

### `DELETE /api/kitchen/cookbook/:id`
Deletes the recipe, ownership-checked. `204`.

---

## Images

### `POST /api/kitchen/regenerate-image`
Body `{ "prompt": string }`. Generates one image with `gpt-image-1` and returns
`{ "imageUrl": "data:image/png;base64,<...>" }`. `400` if `prompt` is missing.
