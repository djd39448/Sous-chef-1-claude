import SwiftUI

/// The pre-auth screen: hero photo, brand, and the sign-in options.
struct SignInScreen: View {
    var onSignIn: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            FoodImage(url: Food.pasta)
                .frame(height: 460)
                .clipped()
                .overlay(heroGradient)

            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 24)
                buttons
            }
            .padding(.horizontal, 28)
            .padding(.top, -64)            // overlap the hero
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Theme.bg)
        .ignoresSafeArea(edges: .top)
    }

    private var heroGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.15), location: 0.0),
                .init(color: .black.opacity(0.0), location: 0.30),
                .init(color: Theme.bg, location: 0.92),
                .init(color: Theme.bg, location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                SCIcon("sparkle", size: 12, color: Theme.terraDeep, weight: .bold)
                Text("AI KITCHEN PARTNER")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
            }
            .foregroundStyle(Theme.terraDeep)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.terraSoft)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            (Text("Sous\n").foregroundColor(Theme.ink)
             + Text("Chef").foregroundColor(Theme.terra).italic())
                .font(Theme.display(52, weight: .regular))
                .tracking(-1.8)
                .lineSpacing(-2)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Text("Decide what's for dinner, plan your week, and shop without thinking.")
                .font(Theme.sans(16))
                .foregroundStyle(Theme.ink2)
                .lineSpacing(3)
                .frame(maxWidth: 290, alignment: .leading)
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button(action: onSignIn) {
                HStack(spacing: 8) {
                    SCIcon("apple", size: 20, color: .white)
                    Text("Sign in with Apple").font(Theme.sans(16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Theme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onSignIn) {
                HStack(spacing: 10) {
                    GoogleGLogo(size: 18)
                    Text("Continue with Google").font(Theme.sans(16, weight: .semibold))
                }
                .foregroundStyle(Color(white: 0.12))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button(action: onSignIn) {
                Text("Continue with email")
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.plain)

            Text("By continuing you agree to our Terms\nand Privacy Policy.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink3)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.bottom, 38)
    }
}

/// A simplified four-color Google mark for the "Continue with Google" button.
struct GoogleGLogo: View {
    var size: CGFloat = 18

    private let blue   = Color(red: 0.259, green: 0.522, blue: 0.957)
    private let red    = Color(red: 0.918, green: 0.263, blue: 0.208)
    private let yellow = Color(red: 0.984, green: 0.737, blue: 0.020)
    private let green  = Color(red: 0.204, green: 0.659, blue: 0.325)

    var body: some View {
        let lineWidth = size * 0.30
        ZStack {
            Circle().trim(from: 0.875, to: 1.125).stroke(red,    style: .init(lineWidth: lineWidth))
            Circle().trim(from: 0.125, to: 0.375).stroke(green,  style: .init(lineWidth: lineWidth))
            Circle().trim(from: 0.375, to: 0.625).stroke(yellow, style: .init(lineWidth: lineWidth))
            Circle().trim(from: 0.625, to: 0.875).stroke(blue,   style: .init(lineWidth: lineWidth))
            Rectangle()
                .fill(blue)
                .frame(width: size * 0.40, height: lineWidth)
                .offset(x: size * 0.22)
        }
        .frame(width: size, height: size)
        .padding(lineWidth / 2)
    }
}
