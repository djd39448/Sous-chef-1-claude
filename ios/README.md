# iOS — SwiftUI app

Phase 4. UI is built.

A SwiftUI port of the *Sous Chef iOS* design (handoff bundle from
[claude.ai/design](https://claude.ai/design)). Runs on mock content matching
the prototype; wiring to the Go backend is the next step.

## Structure

```
SousChef.xcodeproj      Hand-written Xcode project (file-system-synced target)
SousChef/
  SousChefApp.swift     @main app entry
  Theme.swift           Design tokens — OKLCH→sRGB Color initializer + palette
  Components.swift      Reusable views — SCIcon, IconButton, Chip, PrimaryButton,
                        NavBar, FoodImage, CatDot, Hairline + .cardSurface()
  SampleData.swift      Mock content matching the prototype
  RootView.swift        Sign-in gate, MainView, custom 5-tab CustomTabBar
  Screens/
    SignInScreen.swift     Hero photo, Sign in with Apple / Google / Email
    HomeScreen.swift       Tonight, This Week, Ask Sous Chef, Pantry
    PlanScreen.swift       Weekly meal plan rows
    CalendarScreen.swift   Month grid + day detail (pushed from Plan)
    CookbookScreen.swift   Filters, featured, recipe grid
    RecipeScreen.swift     Hero, ingredients, instructions, floating ask pill
    ShoppingScreen.swift   Checkable grouped shopping list
    ChatScreen.swift       Conversation + composer
  Assets.xcassets/      AppIcon placeholder + AccentColor (terracotta)
```

## Build & run

```sh
# Build for the simulator
xcodebuild -project SousChef.xcodeproj -scheme SousChef \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build

# Or open in Xcode and run on a simulator (the scheme is shared)
open SousChef.xcodeproj
```

Deployment target: **iOS 17.0**. Swift 5. No third-party dependencies.

## Design system notes

- **Colors** are authored as `oklch(…)` exactly as in the prototype's
  `shared.jsx`. The conversion to sRGB happens once, in `Color.init(oklch:_:_)`
  in `Theme.swift` — change a token there and every screen follows.
- **Type.** The prototype calls for Fraunces; this port uses the *system serif*
  (New York) — native, Dynamic-Type aware, nothing to bundle. To switch in
  Fraunces later, change `Theme.display(…)` and drop in the font files.
- **Icons** map onto SF Symbols via `SCIcon.symbol(_:)`.
- **Navigation.** Five tabs in a `MainView` with a custom `CustomTabBar`
  (frosted cream + terracotta active). Each tab is its own `NavigationStack` —
  Calendar pushes onto Plan's stack; the Recipe detail is a `fullScreenCover`
  that covers the tab bar.

## What's next

- An `APIClient` (`URLSession`) targeting the Go backend (`../backend/`,
  contract `../contract/api-spec.md`) — replace mock data with real fetches.
- Real Sign in with Apple + Supabase Auth instead of the mock sign-in tap.
- Replace the Unsplash placeholders with the AI-generated photos from the
  `regenerate-image` endpoint.
