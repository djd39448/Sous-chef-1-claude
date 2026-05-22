# iOS — SwiftUI app

Phase 4. Not started.

Rewrites the original React client (`client/` in sous-chef-ai) as a native
SwiftUI app. Builds against [`../contract/`](../contract/) — the API spec.

Screens (ported from the React pages):
- **Landing** — sign in.
- **Chat** — conversational assistant, streaming responses, conversation history.
- **Plan** — weekly meal plan, week navigation.
- **Calendar** — month view of which weeks have plans / lists.
- **Recipe** — auto-generated recipe + AI food photo + per-recipe chat.
- **Cookbook** — saved recipes.
- **Shopping** — checkable shopping list.

Navigation: a `TabView` replacing the web app's bottom nav.
Auth: Supabase Auth with Sign in with Apple.

Gated on: Xcode install, a Supabase project.
