import SwiftUI
import Foundation

extension Color {
    /// Creates a Color from OKLCH — lightness 0...1, chroma, hue in degrees.
    /// The design system (shared.jsx) is authored entirely in `oklch()`, so the
    /// conversion is done here once rather than hand-rounding every token.
    init(oklch lightness: Double, _ chroma: Double, _ hueDegrees: Double) {
        let h = hueDegrees * .pi / 180
        let a = chroma * cos(h)
        let b = chroma * sin(h)

        // OKLab → LMS → linear sRGB (Björn Ottosson's matrices).
        let lPrime = lightness + 0.3963377774 * a + 0.2158037573 * b
        let mPrime = lightness - 0.1055613458 * a - 0.0638541728 * b
        let sPrime = lightness - 0.0894841775 * a - 1.2914855480 * b
        let l = lPrime * lPrime * lPrime
        let m = mPrime * mPrime * mPrime
        let s = sPrime * sPrime * sPrime

        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let blue = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

        func encode(_ x: Double) -> Double {
            let v = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1.0 / 2.4) - 0.055
            return min(1, max(0, v))
        }
        self.init(.sRGB, red: encode(r), green: encode(g), blue: encode(blue), opacity: 1)
    }
}

/// Sous Chef design tokens — the SwiftUI port of `T` in shared.jsx.
enum Theme {
    // Surfaces & ink.
    static let bg        = Color(oklch: 0.972, 0.012, 78)   // warm cream page
    static let card      = Color.white
    static let elev      = Color(oklch: 0.955, 0.014, 75)   // softer cream surface
    static let ink       = Color(oklch: 0.22, 0.018, 50)    // warm near-black
    static let ink2      = Color(oklch: 0.46, 0.018, 50)
    static let ink3      = Color(oklch: 0.62, 0.014, 50)
    static let ink4      = Color(oklch: 0.78, 0.010, 50)
    static let hairline  = Color(oklch: 0.91, 0.010, 60)
    static let hairline2 = Color(oklch: 0.95, 0.010, 60)

    // Accents.
    static let terra      = Color(oklch: 0.625, 0.150, 38)  // terracotta primary
    static let terraDeep  = Color(oklch: 0.520, 0.150, 38)
    static let terraSoft  = Color(oklch: 0.940, 0.035, 45)
    static let sage       = Color(oklch: 0.605, 0.060, 145)
    static let sageSoft   = Color(oklch: 0.945, 0.022, 145)
    static let butter     = Color(oklch: 0.860, 0.115, 92)
    static let butterSoft = Color(oklch: 0.960, 0.040, 92)

    /// Display face. The prototype uses Fraunces; this port uses the system
    /// serif (New York) — native, Dynamic-Type aware, nothing to bundle.
    /// Swapping in Fraunces later is a one-function change here plus a font file.
    static func display(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Body face — SF Pro / the system sans-serif.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Accent color for a Canonical Food Object category (see CAT_COLORS).
    static func category(_ category: String) -> Color {
        switch category {
        case "produce":   return sage
        case "meat":      return terra
        case "dairy":     return Color(oklch: 0.78, 0.06, 70)
        case "seafood":   return Color(oklch: 0.62, 0.08, 230)
        case "bakery":    return Color(oklch: 0.72, 0.10, 60)
        case "frozen":    return Color(oklch: 0.72, 0.06, 220)
        case "pantry":    return Color(oklch: 0.55, 0.04, 60)
        case "beverages": return Color(oklch: 0.55, 0.10, 195)
        default:          return ink3
        }
    }
}
