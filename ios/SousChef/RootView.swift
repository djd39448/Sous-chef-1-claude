import SwiftUI

/// The five primary tabs.
enum Tab: String, CaseIterable, Identifiable {
    case home, plan, cook, shop, chat
    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: return "Home"
        case .plan: return "Plan"
        case .cook: return "Cookbook"
        case .shop: return "Shopping"
        case .chat: return "Chat"
        }
    }
    var icon: String {
        switch self {
        case .home: return "home"
        case .plan: return "calendar"
        case .cook: return "book"
        case .shop: return "cart"
        case .chat: return "chat"
        }
    }
    var iconActive: String {
        switch self {
        case .home: return "homeFill"
        case .plan: return "calendar"
        case .cook: return "bookFill"
        case .shop: return "cartFill"
        case .chat: return "chatFill"
        }
    }
}

/// Root: the sign-in gate, then the main tabbed app.
struct RootView: View {
    @Environment(AuthModel.self) private var auth

    var body: some View {
        Group {
            if auth.isSignedIn {
                MainView()
            } else {
                SignInScreen()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: auth.isSignedIn)
    }
}

/// The signed-in app: five tabs behind a custom frosted tab bar, with the
/// recipe detail presented full-screen over everything.
struct MainView: View {
    @State private var tab: Tab = .home
    @State private var recipeSource: RecipeSource?

    var body: some View {
        tabContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CustomTabBar(active: tab) { tab = $0 }
            }
            .fullScreenCover(item: $recipeSource) { source in
                RecipeScreen(source: source) { recipeSource = nil }
            }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .home:
            NavigationStack {
                HomeScreen(goToTab: { tab = $0 },
                           openRecipe: { recipeSource = $0 })
            }
        case .plan:
            NavigationStack {
                PlanScreen(goToTab: { tab = $0 },
                           openRecipe: { recipeSource = $0 })
            }
        case .cook:
            NavigationStack {
                CookbookScreen(openRecipe: { recipeSource = $0 })
            }
        case .shop:
            NavigationStack { ShoppingScreen() }
        case .chat:
            ChatScreen()   // no nav stack — composer pins via safeAreaInset
        }
    }
}

/// The custom bottom tab bar — five items, cream frosted glass, terracotta active.
struct CustomTabBar: View {
    let active: Tab
    let onSelect: (Tab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { item in
                let on = item == active
                Button { onSelect(item) } label: {
                    VStack(spacing: 2) {
                        SCIcon(on ? item.iconActive : item.icon,
                               size: 24,
                               color: on ? Theme.terra : Theme.ink3,
                               weight: on ? .semibold : .regular)
                        Text(item.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(on ? Theme.terra : Theme.ink3)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Theme.bg.opacity(0.82)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) { Hairline() }
    }
}
