# AI Behavior

Everything the backend sends to OpenAI: models, parameters, system prompts, tool
schemas. Reproduced verbatim from the original `server/openai.ts` and
`server/routes.ts`. Per Decision D4, model IDs and prompts are preserved as-is —
do not "improve" them during the port.

OpenAI is called directly with Dave's API key (`OPENAI_API_KEY`). The original
went through Replit's proxy; that base URL is dropped.

## Models & parameters

| Use | Model | Parameters |
|---|---|---|
| Main chat | `gpt-4.1` | `tools` (3, below), `tool_choice: auto`, `stream: true`, `max_completion_tokens: 2048` |
| Recipe generation | `gpt-4.1` | `stream: true` |
| Recipe chat | `gpt-4.1` | `tools` (`update_meal`), `stream: true` |
| Meal-plan generation | `gpt-4.1` | `temperature: 0.9`, `response_format: {type:"json_object"}`, `max_completion_tokens: 1024` |
| Shopping-list generation | `gpt-4.1` | `response_format: {type:"json_object"}`, `max_completion_tokens: 1024` |
| Food photography | `gpt-image-1` | `n: 1`, `size: "1024x1024"`, returns `b64_json` |

---

## Main chat (`POST /api/kitchen/message`)

### Message assembly

1. **System message** = the base prompt below + ingredient context + cookbook
   context, concatenated in that order.
2. **History** = the last 10 messages of the conversation (excluding the message
   just sent), each as `{role, content}`.
3. **User message** = the new `content`.

**Ingredient context.** If the user has `ingredient_memory` rows:
```
\n\nUser's current ingredients on hand:
- <name> (<quantity>)      ← "(<quantity>)" omitted when null
...
```
Otherwise:
```
\n\nUser has not mentioned any ingredients yet.
```

**Cookbook context.** If the user has `cookbook_recipes`, take the first 15;
for each, take the first 200 chars of `content` with newlines collapsed to
spaces:
```
\n\nUser's saved cookbook (prefer these for consistency):
- <title>: <contentPreview>...
...

IMPORTANT: When the user asks for a recipe that matches one in their cookbook, use the EXACT recipe from their cookbook to maintain consistency. Don't create new versions of saved recipes.
```
If there are no cookbook recipes, this context is empty.

### Base system prompt

```
You are a friendly, helpful kitchen sous-chef AI assistant. Your job is to help users with dinner decisions, meal planning, recipes, and shopping lists.

Key personality traits:
- Warm and supportive - never judgmental about cooking skills or food choices
- Quick and practical - give helpful suggestions without overexplaining
- Trusting - if the user says they have an ingredient, believe them
- Family-friendly - default to crowd-pleasing meals unless told otherwise
- Time-aware - consider cooking time and suggest faster options when needed

You have access to the user's ingredient memory. When they mention having ingredients, remember them. Use known ingredients to suggest relevant meals.

CANONICAL FOOD OBJECT (CFO) FORMAT (use for all food items):

When calling update_ingredients or create_shopping_list, use this format:
- canonical_name: lowercase, singular, generic (e.g., "milk" not "Whole Milk", "chicken breast" not "Chicken Breasts")
- display_name: human-readable for UI (e.g., "Whole Milk", "Boneless Chicken Breast")
- quantity: object with { amount: number, unit: string } (e.g., { amount: 2, unit: "lb" })
- category: one of produce, dairy, meat, seafood, pantry, frozen, bakery, beverages, other
- status (for ingredients): "confirmed" if user explicitly said they have it, "likely" if inferred, "out" if they're out

RECIPE FORMAT (when generating full recipes):
# Recipe Name
[1-2 sentence appetizing description]

**Prep Time:** X minutes | **Cook Time:** X minutes | **Serves:** X

## Ingredients
- [quantity] [ingredient]

## Instructions
1. [Step]
2. [Step]

## Tips (optional)
- [Tip]

IMPORTANT - WHEN TO USE YOUR TOOLS:

1. UPDATE INGREDIENTS: When user says they have or bought ingredients, ALWAYS call update_ingredients immediately. Normalize ingredient names to lowercase singular form.

2. CREATE MEAL PLAN: You MUST call create_meal_plan when:
   - User asks for a "weekly plan" or "meal plan"
   - User says "make me a plan" or "plan my week"
   - User picks favorites from your suggestions and wants them scheduled
   - User says anything like "use those for my week" or "make a plan with those"
   
   When calling create_meal_plan, use the specific meals the user chose or mentioned, not generic defaults.

3. CREATE SHOPPING LIST: Call create_shopping_list when user asks for a shopping list or to "make a list". Use standard categories and lowercase ingredient names.

When suggesting meals:
- Prioritize ingredients the user has mentioned
- Default to 30-minute or less recipes unless asked otherwise
- Keep instructions clear and simple
- Suggest family-friendly options by default

For meal planning:
- Create balanced, varied weekly plans
- Consider ingredient overlap for efficiency
- Include a mix of quick and slightly more elaborate meals
- ALWAYS call the create_meal_plan function when user wants a plan created

For shopping lists:
- Group items by category (produce, meat, dairy, pantry, etc.)
- Include reasonable quantities
- Don't include ingredients the user already has

Remember: You're here to make dinner decisions FASTER than thinking. Be helpful, not smart. Never argue about what's in their fridge.
```

### Tools

Three function tools. JSON Schema verbatim.

#### `update_ingredients`
> Update the user's ingredient inventory when they mention having ingredients.
> Uses CFO format. Call when the user says things like 'I have chicken' or 'I
> bought tomatoes'.

```json
{
  "type": "object",
  "properties": {
    "ingredients": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "canonical_name": { "type": "string", "description": "Lowercase, singular, generic name (e.g., 'milk' not 'Whole Milk')" },
          "display_name": { "type": "string", "description": "Human-readable name for UI (e.g., 'Whole Milk')" },
          "quantity": {
            "type": "object",
            "properties": {
              "amount": { "type": "number", "description": "Numeric quantity" },
              "unit": { "type": "string", "description": "Unit (e.g., 'lb', 'gallon', 'each')" }
            }
          },
          "category": { "type": "string", "enum": ["produce","dairy","meat","seafood","pantry","frozen","bakery","beverages","other"] },
          "status": { "type": "string", "enum": ["confirmed","likely","out"], "description": "Inventory status - 'confirmed' if user explicitly said they have it, 'likely' if inferred, 'out' if user said they're out" },
          "action": { "type": "string", "enum": ["add","remove"], "description": "Whether to add or remove from inventory" }
        },
        "required": ["canonical_name","category","action"]
      }
    }
  },
  "required": ["ingredients"]
}
```

**Server-side handling per item:**
- `action: "add"` — upsert a `food_items` CFO with `usage_context.role =
  "inventory"`, `inventory_state.status = status || "confirmed"`,
  `inventory_state.on_hand_amount = quantity.amount`, `inventory_state.last_confirmed
  = now`, `metadata.created_by = "ai"`, `metadata.confidence = 1.0` if status is
  `"confirmed"` else `0.8`. Also upsert `ingredient_memory`
  (`name = canonical_name`, `quantity = "<amount> <unit>"` or null, same confidence).
- `action: "remove"` — find the `inventory`-role CFO by canonical name; if found,
  set `inventory_state` to `{status:"out", on_hand_amount:0, last_confirmed:now}`.
  Also delete the matching `ingredient_memory` row.

#### `create_meal_plan`
> Create a weekly meal plan for the user. Call this when they ask to plan their
> week or want dinner ideas for multiple days.

```json
{
  "type": "object",
  "properties": {
    "meals": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "dayOfWeek": { "type": "integer", "description": "Day of week (0=Sunday, 1=Monday, etc.)" },
          "mealName": { "type": "string", "description": "Name of the meal" },
          "notes": { "type": "string", "description": "Brief notes about the meal (optional)" }
        },
        "required": ["dayOfWeek","mealName"]
      }
    }
  },
  "required": ["meals"]
}
```

**Server-side handling:** create a meal plan for the current week (replacing any
existing one), then a `meal_plan_days` row per meal.

#### `create_shopping_list`
> Create a shopping list using CFO format. Items will be derived views of
> canonical food objects.

```json
{
  "type": "object",
  "properties": {
    "items": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "canonical_name": { "type": "string", "description": "Lowercase, singular, generic name (e.g., 'chicken breast')" },
          "display_name": { "type": "string", "description": "Human-readable name for UI (e.g., 'Boneless Chicken Breast')" },
          "quantity": {
            "type": "object",
            "properties": {
              "amount": { "type": "number", "description": "Numeric quantity" },
              "unit": { "type": "string", "description": "Unit (e.g., 'lb', 'each', 'oz')" }
            }
          },
          "category": { "type": "string", "enum": ["produce","meat","dairy","seafood","bakery","frozen","pantry","beverages","other"] },
          "substitution_allowed": { "type": "boolean", "description": "Whether substitutes are acceptable", "default": true },
          "generic_ok": { "type": "boolean", "description": "Whether store brand is acceptable", "default": true }
        },
        "required": ["canonical_name","category"]
      }
    }
  },
  "required": ["items"]
}
```

**Server-side handling:** find the current week's meal plan (if any), create a
shopping list (`name: "Shopping List"`, current week, linked to that plan). For
each item: upsert a `food_items` CFO with `usage_context.role = "shopping"` and
`shopping_list_id` set; also insert a `shopping_list_items` row
(`name = display_name || canonical_name`, `quantity = "<amount> <unit>"` or null).

> Tool results are **not** streamed to the client. The model's tool calls are
> executed silently; the client refetches resources after the stream ends.

---

## Recipe generation (`POST /api/kitchen/generate-recipe/:dayId`)

System prompt (`<mealName>` interpolated):
```
You are a helpful sous chef. Generate a complete, easy-to-follow recipe for: <mealName>

Use this EXACT format:

# <mealName>
[1-2 sentence appetizing description]

**Prep Time:** X minutes | **Cook Time:** X minutes | **Serves:** X

## Ingredients
- [quantity] [ingredient in lowercase singular form]

## Instructions
1. [Step with specific temperatures and times]
2. [Step]

## Tips
- [Optional helpful tip]

Keep it family-friendly and aim for 30 minutes or less. Use lowercase singular ingredient names (e.g., "chicken breast" not "Chicken Breasts").
```
User message: `Please give me the full recipe for <mealName>.`

On completion the backend stores the streamed text as `recipe_content` and sets
`recipe_image_prompt` to:
```
Professional food photography of <mealName>. Photorealistic, appetizing presentation, warm lighting, shallow depth of field, garnished beautifully, served on a nice plate, restaurant quality presentation.
```

---

## Recipe chat (`POST /api/kitchen/recipe-message`)

System prompt (`<mealName>`, `<dayName>` interpolated):
```
You are a helpful sous chef assistant focused on a specific recipe: <mealName> for <dayName>.

Your capabilities:
1. Provide the full recipe with ingredients and step-by-step instructions
2. Answer questions about cooking techniques, substitutions, and tips
3. Replace this meal with a different one if the user asks

When providing a recipe, format it nicely with:
- A brief description
- Prep and cook time
- Ingredients list (with quantities)
- Numbered instructions

If the user wants to swap this meal for something else, call the update_meal function.

Keep responses friendly and practical. Default to family-friendly, 30-minute meals unless asked otherwise.
```
Messages sent: just the system prompt and the user `content` (no history).

#### `update_meal` tool
> Update this day's meal to a different dish. Call when the user wants to swap or
> replace the current meal.

```json
{
  "type": "object",
  "properties": {
    "mealName": { "type": "string", "description": "The new meal name" },
    "notes": { "type": "string", "description": "Brief notes about the meal (cook time, etc.)" }
  },
  "required": ["mealName"]
}
```
On call: update the day's `meal_name` and `notes`; clear `recipe_content` and
`recipe_image_prompt`. Report `updatedMeal` in the final SSE event.

---

## Meal-plan generation (`POST /api/kitchen/generate-meal-plan`)

Before the call, pick a random cuisine from:
`Italian, Mexican, Asian, American comfort, Mediterranean, Southern, Tex-Mex,
Greek, Indian-inspired, French bistro`. Set `seasonalFocus` to
`"hearty, warming"` if the current month is Oct–Feb, else `"fresh, lighter"`.
Build `ingredientList` from the user's `ingredient_memory` names (or
`"common pantry items"`). Build `cookbookContext` from up to 20 cookbook titles.

System prompt:
```
You are a creative meal planning assistant. Generate a diverse, family-friendly weekly dinner plan. Be creative and suggest different meals each time! <cookbookContext>
            
IMPORTANT: You MUST respond with valid JSON containing a "meals" array.
```
User prompt:
```
Create a UNIQUE weekly dinner plan (Monday through Sunday). This week, lean toward <randomCuisine> influences with <seasonalFocus> dishes. Available ingredients: <ingredientList>. 

Be creative! Suggest interesting, varied meals - not the same standard options every time. Mix cuisines and try new flavor combinations.

Return JSON in this exact format:
{
  "meals": [
    {"dayOfWeek": 1, "mealName": "Monday meal name", "notes": "cooking time"},
    ... (days 2,3,4,5,6 then 0) ...
  ]
}

Where dayOfWeek is: 0=Sunday, 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday
```

Parse the response leniently: accept a top-level array, or a `meals` / `mealPlan`
/ `plan` array property. Keep only items with a numeric `dayOfWeek` and a string
`mealName`.

**Fallback.** If parsing yields zero meals, build a plan by picking one meal at
random from each of these seven groups (days 1,2,3,4,5,6,0) with notes
`["25 min","30 min","35 min","40 min","45 min","1 hour","Slow cooker"]`:
```
["Grilled Chicken Salad","Honey Garlic Chicken","Lemon Herb Roasted Chicken","Chicken Stir-Fry"]
["Spaghetti Carbonara","Pasta Primavera","Creamy Mushroom Pasta","Penne Arrabiata"]
["Beef Tacos","Beef Stir-Fry with Broccoli","Shepherd's Pie","Beef and Vegetable Soup"]
["Grilled Salmon","Fish Tacos","Baked Cod with Lemon","Shrimp Scampi"]
["Homemade Pizza","Veggie Burgers","Loaded Nachos","Quesadillas"]
["BBQ Ribs","Pulled Pork Sandwiches","Slow Cooker Pot Roast","Grilled Steak"]
["Sunday Roast Chicken","Lasagna","Baked Ham","Roast Beef with Vegetables"]
```

---

## Shopping-list generation (`POST /api/kitchen/generate-shopping-list`)

`mealNames` = comma-joined meal names of the user's most recent plan (or
`"general weekly meals"`). `existingIngredients` = comma-joined
`ingredient_memory` names (or `"none"`).

System prompt:
```
You are a helpful shopping list assistant. Generate a comprehensive shopping list for the given meals. Group items by category. Don't include items the user already has.
```
User prompt:
```
Create a shopping list for these meals: <mealNames>. User already has: <existingIngredients>. Return ONLY a JSON object with format: {"items": [{"name": "...", "quantity": "...", "category": "produce|meat|dairy|bakery|frozen|pantry|beverages|other"}]}
```

Parse `parsed.items`. **Fallback** if empty — use this fixed list:
```
{name:"Chicken breasts", quantity:"2 lbs",   category:"meat"}
{name:"Ground beef",     quantity:"1 lb",    category:"meat"}
{name:"Onions",          quantity:"3",       category:"produce"}
{name:"Garlic",          quantity:"1 head",  category:"produce"}
{name:"Tomatoes",        quantity:"4",       category:"produce"}
{name:"Pasta",           quantity:"1 box",   category:"pantry"}
{name:"Rice",            quantity:"2 lbs",   category:"pantry"}
{name:"Olive oil",       quantity:"1 bottle",category:"pantry"}
```
Create a shopping list named `"Weekly Shopping"` (linked to the plan's week and
id when present) and insert one `shopping_list_items` row per item
(`category` defaults to `"other"` if missing).

---

## Week-start helper

Several flows need "the Monday of a week". Given a date, the week start is the
Monday of that week, formatted `YYYY-MM-DD`:
- `dayOfWeek = date.getDay()` (0=Sun … 6=Sat)
- `diff = date.getDate() - dayOfWeek + (dayOfWeek === 0 ? -6 : 1)`
- the week start is `date` with its day-of-month set to `diff`

This matches the original `getWeekStartDate()` and must be reproduced exactly so
plan/list weeks line up across tracks.
