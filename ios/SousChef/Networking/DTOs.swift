import Foundation

// DTOs — the wire shapes the Go backend serves under /api/. These mirror
// the response types in `contract/api-spec.md` ("Object shapes"). JSON
// keys are camelCase, matching what the backend emits; Swift property
// names line up so no `CodingKeys` is needed.
//
// Depends on:     Foundation.
// Depended on by: APIClient (decoding), every screen that fetches data.
// Why it exists:  the contract is the source of truth; these types are
//                 the Swift restatement of it. Keep them additive — when
//                 the contract grows, add types here.

/// A kitchen chat conversation.
struct Conversation: Codable, Identifiable {
    let id: Int
    let userId: String
    let title: String
    let createdAt: Date
    let updatedAt: Date
}

/// One chat message inside a conversation. `metadata` is ignored on the
/// client today (the contract leaves it as freeform JSONB).
struct Message: Codable, Identifiable {
    let id: Int
    let conversationId: Int
    let role: String         // "user" | "assistant"
    let content: String
    let createdAt: Date
}

/// `GET /api/kitchen/conversation[/:id]` — a conversation with its messages.
struct ConversationWithMessages: Codable, Identifiable {
    let id: Int
    let userId: String
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let messages: [Message]
}

/// `GET /api/auth/user`
struct Profile: Codable, Identifiable {
    let id: String
    let email: String?
    let firstName: String?
    let lastName: String?
    let profileImageUrl: String?
    let createdAt: Date
    let updatedAt: Date
}

/// Meal-plan summary (no days). Returned by `/api/kitchen/calendar`.
struct MealPlan: Codable, Identifiable {
    let id: Int
    let userId: String
    let weekStartDate: String   // YYYY-MM-DD
    let createdAt: Date
    let updatedAt: Date
}

/// Shopping-list summary (no items). Returned by `/api/kitchen/calendar`.
struct ShoppingList: Codable, Identifiable {
    let id: Int
    let userId: String
    let name: String
    let weekStartDate: String?
    let mealPlanId: Int?
    let createdAt: Date
}

/// `GET /api/kitchen/calendar` — every plan and list, no children.
struct CalendarResponse: Codable {
    let mealPlans: [MealPlan]
    let shoppingLists: [ShoppingList]
}

/// `GET /api/kitchen/ingredients` — soft-inventory ingredient memory row.
struct Ingredient: Codable, Identifiable {
    let id: Int
    let userId: String
    let name: String
    let quantity: String?
    let confidence: Double
    let lastMentioned: Date
    let createdAt: Date
}

/// One day inside a meal plan. `dayOfWeek` is 0=Sunday … 6=Saturday.
/// `imageUrl` is a persisted `data:image/png;base64,…` URL set by
/// `/regenerate-image`; nil means "no image generated yet — show the
/// Tap-to-generate placeholder."
struct MealPlanDay: Codable, Identifiable {
    let id: Int
    let mealPlanId: Int
    let dayOfWeek: Int
    let recipeId: Int?
    let mealName: String
    let notes: String?
    let recipeContent: String?
    let recipeImagePrompt: String?
    let imageUrl: String?
}

/// `GET /api/kitchen/meal-plan` — the user's most recent plan, with days.
struct MealPlanWithDays: Codable, Identifiable {
    let id: Int
    let userId: String
    let weekStartDate: String   // YYYY-MM-DD
    let createdAt: Date
    let updatedAt: Date
    let days: [MealPlanDay]
}

/// `GET /api/kitchen/cookbook[/{id}]` — a saved recipe. `imageUrl` is
/// a persisted `data:image/png;base64,…` URL — same semantics as
/// `MealPlanDay.imageUrl`.
struct CookbookRecipe: Codable, Identifiable {
    let id: Int
    let userId: String
    let title: String
    let content: String
    let imagePrompt: String?
    let imageUrl: String?
    let createdAt: Date
}

/// One item on a shopping list. `checked` is `0`/`1` (preserved from the
/// original schema; see contract data-model.md, Decision D3).
struct ShoppingItem: Codable, Identifiable {
    let id: Int
    let shoppingListId: Int
    let name: String
    let quantity: String?
    let category: String
    var checked: Int
}

/// `GET /api/kitchen/shopping-list` — the user's most recent list, with items.
struct ShoppingListWithItems: Codable, Identifiable {
    let id: Int
    let userId: String
    let name: String
    let weekStartDate: String?
    let mealPlanId: Int?
    let createdAt: Date
    var items: [ShoppingItem]
}

/// `GET /api/kitchen/week/{weekStartDate}` — both the meal plan AND the
/// shopping list for a specific Monday-anchored week. Either field is
/// nullable when the user hasn't generated that resource yet.
struct WeekResponse: Codable {
    let mealPlan: MealPlanWithDays?
    let shoppingList: ShoppingListWithItems?
}
