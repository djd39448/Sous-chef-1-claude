import SwiftUI

// RecipeImage — the canonical view for "the photo of a dish."
//
// Depends on:     Theme, SCIcon.
// Depended on by: HomeScreen (tonight hero, week-strip cards),
//                 PlanScreen (meal rows), CookbookScreen (featured + grid),
//                 RecipeScreen (large hero).
// Why it exists:  the original port shipped keyword-matched stock photos
//                 (ImageLookup) that frequently mismatched the dish.
//                 Dave's feedback (2026-05-24): drop the placeholder photos
//                 entirely and either show the persisted AI image or a
//                 "Tap to generate" panel. This view encapsulates that
//                 contract — pass the row's `imageUrl`, optionally pass an
//                 `onGenerate` callback for surfaces where one-tap
//                 generation is appropriate, and the right thing renders.
struct RecipeImage: View {
    /// Persisted image URL — `data:image/png;base64,…`. Nil means no
    /// image has been generated yet for this recipe.
    let url: String?

    /// When true, the placeholder strips its "Tap to generate" text and
    /// shrinks the sparkle — for small thumbnails (Plan rows,
    /// Home week strip). Tapping a compact placeholder still fires
    /// `onGenerate` if provided; otherwise the placeholder is purely
    /// decorative.
    var compact: Bool = false

    /// Optional regenerate callback. When non-nil the placeholder becomes
    /// a Button. Set this for large surfaces where one-tap regeneration
    /// is the obvious action (Recipe hero); leave it nil for list
    /// thumbnails where the user would go into the recipe screen instead.
    var onGenerate: (() -> Void)? = nil

    /// When true the placeholder is replaced with a dim spinner overlay
    /// (driven by the caller's regenerate-in-flight state).
    var isGenerating: Bool = false

    var body: some View {
        ZStack {
            if let img = decoded {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else if let onGenerate {
                Button(action: onGenerate) { placeholder }
                    .buttonStyle(.plain)
                    .disabled(isGenerating)
            } else {
                placeholder
            }

            if isGenerating {
                Color.black.opacity(0.45)
                VStack(spacing: 8) {
                    ProgressView().tint(.white)
                    if !compact {
                        Text("Generating photo…")
                            .font(Theme.sans(13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    /// Decode the `data:image/png;base64,…` URL into a UIImage. Returns
    /// nil for any unparseable input (including nil URLs).
    private var decoded: UIImage? {
        guard let s = url,
              let comma = s.firstIndex(of: ","),
              let data = Data(base64Encoded: String(s[s.index(after: comma)...])) else {
            return nil
        }
        return UIImage(data: data)
    }

    private var placeholder: some View {
        ZStack {
            Theme.terraSoft
            if compact {
                SCIcon("sparkle", size: 20, color: Theme.terraDeep, weight: .bold)
            } else {
                VStack(spacing: 8) {
                    SCIcon("sparkle", size: 30, color: Theme.terraDeep, weight: .bold)
                    if onGenerate != nil {
                        Text("Tap to generate image")
                            .font(Theme.sans(12, weight: .semibold))
                            .foregroundStyle(Theme.terraDeep)
                            .tracking(0.3)
                    }
                }
                .padding(12)
            }
        }
    }
}
