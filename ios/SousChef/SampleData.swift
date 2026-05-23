import Foundation

// Stock food photography (Unsplash), matching FOOD in shared.jsx. Used by
// `ImageLookup.url(for:)` as the keyword-match fallback when an AI-generated
// photo from `/api/kitchen/regenerate-image` is not yet available.
//
// Depends on:     nothing.
// Depended on by: Helpers/ImageLookup, SignInScreen (hero), CookbookScreen
//                 + PlanScreen + HomeScreen (food images).
// Why it exists:  one place that owns the URL constants, so swapping in
//                 the real AI photos later is a single-call-site change.
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
