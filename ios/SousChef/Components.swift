import SwiftUI

// Shared UI components — the SwiftUI port of the components in shared.jsx.

/// A line icon. The prototype ships a custom SVG set; each maps to an SF Symbol.
struct SCIcon: View {
    let name: String
    var size: CGFloat = 22
    var color: Color = Theme.ink
    var weight: Font.Weight = .regular

    init(_ name: String, size: CGFloat = 22, color: Color = Theme.ink, weight: Font.Weight = .regular) {
        self.name = name
        self.size = size
        self.color = color
        self.weight = weight
    }

    var body: some View {
        Image(systemName: SCIcon.symbol(name))
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
    }

    /// Maps a design icon name to its SF Symbol equivalent.
    static func symbol(_ name: String) -> String {
        switch name {
        case "home":      return "house"
        case "homeFill":  return "house.fill"
        case "calendar":  return "calendar"
        case "book":      return "book.closed"
        case "bookFill":  return "book.closed.fill"
        case "cart":      return "cart"
        case "cartFill":  return "cart.fill"
        case "chat":      return "bubble.left"
        case "chatFill":  return "bubble.left.fill"
        case "plus":      return "plus"
        case "chevR":     return "chevron.right"
        case "chevL":     return "chevron.left"
        case "chevD":     return "chevron.down"
        case "search":    return "magnifyingglass"
        case "sparkle":   return "sparkles"
        case "close":     return "xmark"
        case "send":      return "paperplane.fill"
        case "clock":     return "clock"
        case "people":    return "person.2"
        case "flame":     return "flame"
        case "bookmark":  return "bookmark"
        case "bookmarkF": return "bookmark.fill"
        case "swap":      return "arrow.2.squarepath"
        case "settings":  return "gearshape"
        case "bell":      return "bell"
        case "apple":     return "applelogo"
        case "check":     return "checkmark"
        case "filter":    return "line.3.horizontal.decrease"
        case "photo":     return "photo"
        case "dot":       return "circle.fill"
        case "edit":      return "square.and.pencil"
        default:          return "questionmark"
        }
    }
}

/// A circular, tappable icon button (~36pt).
struct IconButton: View {
    let icon: String
    var color: Color = Theme.ink
    var size: CGFloat = 36
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            SCIcon(icon, size: 22, color: color)
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }
}

/// A pill / chip — used for filters and chat suggestions.
struct Chip: View {
    let label: String
    var active: Bool = false
    var icon: String? = nil
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    SCIcon(icon, size: 14, color: active ? Theme.bg : Theme.ink)
                }
                Text(label).font(Theme.sans(13, weight: .medium))
            }
            .foregroundStyle(active ? Theme.bg : Theme.ink)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(active ? Theme.ink : Theme.card)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: active ? 0 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// The primary filled action button (52pt tall).
struct PrimaryButton: View {
    let label: String
    var icon: String? = nil
    var fill: Bool = false
    var color: Color = Theme.terra
    var textColor: Color = .white
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { SCIcon(icon, size: 18, color: textColor) }
                Text(label).font(Theme.sans(16, weight: .semibold))
            }
            .foregroundStyle(textColor)
            .frame(maxWidth: fill ? .infinity : nil)
            .frame(height: 52)
            .padding(.horizontal, fill ? 0 : 22)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The custom large-title navigation bar (replaces the system nav bar).
struct NavBar: View {
    var title: String? = nil
    var largeTitle: String? = nil
    var leading: AnyView? = nil
    var trailing: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 4) { leading }
                    .frame(minWidth: 38, alignment: .leading)
                Spacer(minLength: 0)
                if let title, largeTitle == nil {
                    Text(title)
                        .font(Theme.sans(17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) { trailing }
                    .frame(minWidth: 38, alignment: .trailing)
            }
            .frame(height: 38)

            if let largeTitle {
                Text(largeTitle)
                    .font(Theme.display(38, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }
}

/// A remote food photo with a warm gradient placeholder while it loads.
struct FoodImage: View {
    let url: String

    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                LinearGradient(
                    colors: [Theme.elev, Theme.butterSoft],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        }
    }
}

/// A small colored dot indicating a food category.
struct CatDot: View {
    let category: String
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(Theme.category(category))
            .frame(width: size, height: size)
    }
}

/// A hairline divider.
struct Hairline: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

extension View {
    /// Wraps a view in the standard white card surface: rounded, hairline border.
    func cardSurface(_ radius: CGFloat, border: Color = Theme.hairline2) -> some View {
        self
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
    }
}
