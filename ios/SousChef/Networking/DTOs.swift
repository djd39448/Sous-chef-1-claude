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

/// One day inside a meal plan. `dayOfWeek` is 0=Sunday … 6=Saturday.
struct MealPlanDay: Codable, Identifiable {
    let id: Int
    let mealPlanId: Int
    let dayOfWeek: Int
    let recipeId: Int?
    let mealName: String
    let notes: String?
    let recipeContent: String?
    let recipeImagePrompt: String?
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
