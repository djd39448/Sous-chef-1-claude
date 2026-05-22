import Foundation

// Sample content for the design build. These are the placeholder values from
// the prototype; the real data arrives once the screens are wired to the Go
// backend (the API contract in ../../contract/).

/// Stock food photography (Unsplash), matching FOOD in shared.jsx.
enum Food {
    static let pasta     = "https://images.unsplash.com/photo-1621996346565-e3dbc646d9a9?w=900&q=80&auto=format&fit=crop"
    static let carbonara = "https://images.unsplash.com/photo-1612874742237-6526221588e3?w=900&q=80&auto=format&fit=crop"
    static let salmon    = "https://images.unsplash.com/photo-1467003909585-2f8a72700288?w=900&q=80&auto=format&fit=crop"
    static let tacos     = "https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=900&q=80&auto=format&fit=crop"
    static let chicken   = "https://images.unsplash.com/photo-1532550907401-a500c9a57435?w=900&q=80&auto=format&fit=crop"
    static let stirfry   = "https://images.unsplash.com/photo-1512058564366-18510be2db19?w=900&q=80&auto=format&fit=crop"
    static let pizza     = "https://images.unsplash.com/photo-1574071318508-1cdbab80d002?w=900&q=80&auto=format&fit=crop"
    static let soup      = "https://images.unsplash.com/photo-1547592180-85f173990554?w=900&q=80&auto=format&fit=crop"
    static let ribs      = "https://images.unsplash.com/photo-1544025162-d76694265947?w=900&q=80&auto=format&fit=crop"
    static let curry     = "https://images.unsplash.com/photo-1565557623262-b51c2513a641?w=900&q=80&auto=format&fit=crop"
    static let roast     = "https://images.unsplash.com/photo-1606755962773-d324e0a13086?w=900&q=80&auto=format&fit=crop"
    static let salad     = "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=900&q=80&auto=format&fit=crop"
}

// MARK: - Models

enum MealState {
    case cooked, today, planned
}

struct WeekDay: Identifiable {
    let id = UUID()
    let abbrev: String
    let meal: String
    var done = false
    var today = false
}

struct PlanMeal: Identifiable {
    let id = UUID()
    let day: String
    let date: String
    let meal: String
    let notes: String
    let image: String
    let state: MealState
}

struct PantryItem: Identifiable {
    let id = UUID()
    let name: String
    let category: String
}

struct ShoppingLine: Identifiable {
    let id: String
    let name: String
    let qty: String
    var checked: Bool
}

struct ShoppingSection: Identifiable {
    var id: String { category }
    let category: String
    let label: String
    var items: [ShoppingLine]
}

struct Recipe: Identifiable {
    let id = UUID()
    let title: String
    let time: String
    let tag: String
    let image: String
}

enum ChatRole {
    case user, assistant, tool
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let text: String
    var streaming = false
}

// MARK: - Sample collections

enum Samples {
    static let weekStrip: [WeekDay] = [
        WeekDay(abbrev: "Mon", meal: "Lemon-Herb Salmon", done: true),
        WeekDay(abbrev: "Tue", meal: "Pasta Carbonara", today: true),
        WeekDay(abbrev: "Wed", meal: "Chicken Stir-Fry"),
        WeekDay(abbrev: "Thu", meal: "Veggie Tacos"),
        WeekDay(abbrev: "Fri", meal: "Margherita Pizza"),
        WeekDay(abbrev: "Sat", meal: "Slow-Cooker Ribs"),
        WeekDay(abbrev: "Sun", meal: "Sunday Roast Chicken"),
    ]

    static let pantry: [PantryItem] = [
        PantryItem(name: "Whole milk", category: "dairy"),
        PantryItem(name: "Eggs", category: "dairy"),
        PantryItem(name: "Chicken breast", category: "meat"),
        PantryItem(name: "Spaghetti", category: "pantry"),
        PantryItem(name: "Tomatoes", category: "produce"),
        PantryItem(name: "Garlic", category: "produce"),
        PantryItem(name: "Parmesan", category: "dairy"),
        PantryItem(name: "Olive oil", category: "pantry"),
    ]

    static let planMeals: [PlanMeal] = [
        PlanMeal(day: "Monday", date: "May 25", meal: "Lemon-Herb Salmon",
                 notes: "30 min", image: Food.salmon, state: .cooked),
        PlanMeal(day: "Tuesday", date: "May 26", meal: "Pasta Carbonara",
                 notes: "30 min", image: Food.carbonara, state: .today),
        PlanMeal(day: "Wednesday", date: "May 27", meal: "Chicken Stir-Fry",
                 notes: "25 min", image: Food.stirfry, state: .planned),
        PlanMeal(day: "Thursday", date: "May 28", meal: "Veggie Tacos",
                 notes: "20 min", image: Food.tacos, state: .planned),
        PlanMeal(day: "Friday", date: "May 29", meal: "Margherita Pizza",
                 notes: "40 min", image: Food.pizza, state: .planned),
        PlanMeal(day: "Saturday", date: "May 30", meal: "Slow-Cooker Ribs",
                 notes: "Slow cooker", image: Food.ribs, state: .planned),
        PlanMeal(day: "Sunday", date: "May 31", meal: "Sunday Roast Chicken",
                 notes: "1 hour", image: Food.roast, state: .planned),
    ]

    static let cookbook: [Recipe] = [
        Recipe(title: "Pasta Carbonara", time: "30 min", tag: "Italian", image: Food.carbonara),
        Recipe(title: "Lemon-Herb Salmon", time: "25 min", tag: "Mediterranean", image: Food.salmon),
        Recipe(title: "Chicken Stir-Fry", time: "25 min", tag: "Asian", image: Food.stirfry),
        Recipe(title: "Veggie Tacos", time: "20 min", tag: "Mexican", image: Food.tacos),
        Recipe(title: "Margherita Pizza", time: "40 min", tag: "Italian", image: Food.pizza),
        Recipe(title: "Slow-Cooker Ribs", time: "Slow", tag: "American", image: Food.ribs),
        Recipe(title: "Sunday Roast Chicken", time: "1 hour", tag: "American", image: Food.roast),
        Recipe(title: "Coconut Curry", time: "35 min", tag: "Indian", image: Food.curry),
    ]

    static let shoppingSections: [ShoppingSection] = [
        ShoppingSection(category: "produce", label: "Produce", items: [
            ShoppingLine(id: "p1", name: "Tomatoes", qty: "4 large", checked: true),
            ShoppingLine(id: "p2", name: "Garlic", qty: "1 head", checked: true),
            ShoppingLine(id: "p3", name: "Lemons", qty: "3", checked: false),
            ShoppingLine(id: "p4", name: "Basil", qty: "1 bunch", checked: false),
            ShoppingLine(id: "p5", name: "Bell peppers", qty: "2", checked: false),
        ]),
        ShoppingSection(category: "meat", label: "Meat", items: [
            ShoppingLine(id: "m1", name: "Chicken breast", qty: "2 lbs", checked: true),
            ShoppingLine(id: "m2", name: "Guanciale", qty: "6 oz", checked: false),
            ShoppingLine(id: "m3", name: "Pork ribs", qty: "3 lbs", checked: false),
        ]),
        ShoppingSection(category: "dairy", label: "Dairy & Eggs", items: [
            ShoppingLine(id: "d1", name: "Pecorino romano", qty: "8 oz", checked: false),
            ShoppingLine(id: "d2", name: "Parmesan", qty: "4 oz", checked: true),
            ShoppingLine(id: "d3", name: "Eggs", qty: "1 dozen", checked: false),
            ShoppingLine(id: "d4", name: "Whole milk", qty: "½ gal", checked: false),
        ]),
        ShoppingSection(category: "pantry", label: "Pantry", items: [
            ShoppingLine(id: "pa1", name: "Spaghetti", qty: "1 lb", checked: false),
            ShoppingLine(id: "pa2", name: "Olive oil", qty: "1 bottle", checked: true),
            ShoppingLine(id: "pa3", name: "Black peppercorns", qty: "small jar", checked: false),
        ]),
    ]

    static let chat: [ChatMessage] = [
        ChatMessage(role: .user,
                    text: "I have chicken breast, garlic, and lemons. What can I make tonight?"),
        ChatMessage(role: .assistant,
                    text: "Easy — a quick lemon-garlic chicken pan-sear. About 20 minutes, family-friendly. Want me to walk you through it?"),
        ChatMessage(role: .tool,
                    text: "Updated ingredients · chicken breast, garlic, lemons"),
        ChatMessage(role: .user,
                    text: "Sounds great. Also can you plan the rest of my week?"),
        ChatMessage(role: .assistant,
                    text: "On it. I'll lean toward 30-minute meals, mix in a couple of family favorites from your cookbook, and avoid heavy",
                    streaming: true),
    ]
}
