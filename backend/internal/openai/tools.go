package openai

import "encoding/json"

// ChatTools returns the four function tools offered during the main kitchen
// chat. The parameter schemas are verbatim from contract/ai-behavior.md.
func ChatTools() []Tool {
	return []Tool{
		{Type: "function", Function: ToolFunction{
			Name:        "update_ingredients",
			Description: "Update the user's ingredient inventory when they mention having ingredients. Uses CFO format. Call when the user says things like 'I have chicken' or 'I bought tomatoes'.",
			Parameters:  json.RawMessage(updateIngredientsSchema),
		}},
		{Type: "function", Function: ToolFunction{
			Name:        "create_meal_plan",
			Description: "Create a weekly meal plan for the user. Call this when they ask to plan their week or want dinner ideas for multiple days.",
			Parameters:  json.RawMessage(createMealPlanSchema),
		}},
		{Type: "function", Function: ToolFunction{
			Name:        "create_shopping_list",
			Description: "Create a shopping list using CFO format. Items will be derived views of canonical food objects.",
			Parameters:  json.RawMessage(createShoppingListSchema),
		}},
		{Type: "function", Function: ToolFunction{
			Name:        "save_recipe",
			Description: "Save a recipe to the user's cookbook so it lands on the Cookbook tab. Call when the user asks to save the recipe you just generated (e.g., 'save this', 'save it to my cookbook'). Pass the exact title and the full markdown body.",
			Parameters:  json.RawMessage(saveRecipeSchema),
		}},
	}
}

// RecipeTools returns the function tool offered during per-recipe chat.
func RecipeTools() []Tool {
	return []Tool{
		{Type: "function", Function: ToolFunction{
			Name:        "update_meal",
			Description: "Update this day's meal to a different dish. Call when the user wants to swap or replace the current meal.",
			Parameters:  json.RawMessage(updateMealSchema),
		}},
	}
}

const updateIngredientsSchema = `{
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
}`

const createMealPlanSchema = `{
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
}`

const createShoppingListSchema = `{
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
}`

const updateMealSchema = `{
  "type": "object",
  "properties": {
    "mealName": { "type": "string", "description": "The new meal name" },
    "notes": { "type": "string", "description": "Brief notes about the meal (cook time, etc.)" }
  },
  "required": ["mealName"]
}`

const saveRecipeSchema = `{
  "type": "object",
  "properties": {
    "title":       { "type": "string", "description": "Recipe title — exactly as it appears in the recipe heading, without the leading '# '." },
    "content":     { "type": "string", "description": "Full recipe in markdown: description, Prep/Cook/Serves line, Ingredients, Instructions, optional Tips. Do not wrap in code fences." },
    "imagePrompt": { "type": "string", "description": "Optional one-sentence image-generation prompt for the dish photo." }
  },
  "required": ["title","content"]
}`
