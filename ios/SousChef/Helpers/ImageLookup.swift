import Foundation

// ImageLookup — picks a stock food photo URL from a meal name.
//
// Depends on:     Food (in SampleData.swift).
// Depended on by: HomeScreen, PlanScreen, CookbookScreen — anywhere a
//                 meal name needs to be illustrated before the AI photo
//                 (`/api/kitchen/regenerate-image`) has been generated.
// Why it exists:  the backend doesn't return an image URL on a meal-plan
//                 day until the AI photo flow runs; this is the lightweight
//                 keyword-match stand-in. Replace with real photos once
//                 `regenerate-image` is wired into the screens.
enum ImageLookup {
    static func url(for mealName: String) -> String {
        let lower = mealName.lowercased()
        if lower.contains("carbonara") || lower.contains("pasta") { return Food.carbonara }
        if lower.contains("salmon")  { return Food.salmon }
        if lower.contains("taco")    { return Food.tacos }
        if lower.contains("stir")    { return Food.stirfry }
        if lower.contains("pizza")   { return Food.pizza }
        if lower.contains("soup")    { return Food.soup }
        if lower.contains("rib")     { return Food.ribs }
        if lower.contains("curry")   { return Food.curry }
        if lower.contains("roast")   { return Food.roast }
        if lower.contains("salad")   { return Food.salad }
        if lower.contains("chicken") { return Food.chicken }
        return Food.carbonara
    }
}
