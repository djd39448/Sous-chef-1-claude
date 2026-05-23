import SwiftUI

// EmailSignInSheet — modal email + password sign-in for development.
//
// Depends on:     AuthModel (via the environment), Theme.
// Depended on by: SignInScreen (presented as a `.sheet`).
// Why it exists:  Sign in with Apple requires an Apple Developer Program
//                 enrollment and the Supabase Apple provider configured;
//                 until that lands this sheet covers the dev sign-in path
//                 (the design's "Continue with email" option). Once SIWA
//                 is wired up, this sheet stays as the fallback.
struct EmailSignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthModel.self) private var auth

    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .signIn
    @State private var error: String?
    @State private var loading = false

    enum Mode { case signIn, signUp }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                }
                Section {
                    Button(mode == .signIn ? "Sign in" : "Create account") {
                        Task { await submit() }
                    }
                    .disabled(loading || email.isEmpty || password.isEmpty)

                    Button(mode == .signIn
                           ? "Need an account? Create one"
                           : "Have an account? Sign in") {
                        mode = (mode == .signIn) ? .signUp : .signIn
                        error = nil
                    }
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.terra)
                }
                if let error {
                    Section {
                        Text(error)
                            .font(Theme.sans(13))
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(mode == .signIn ? "Sign in" : "Create account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if loading {
                    ProgressView().tint(Theme.terra)
                }
            }
        }
    }

    private func submit() async {
        loading = true
        defer { loading = false }
        error = nil
        do {
            if mode == .signIn {
                try await auth.signIn(email: email, password: password)
            } else {
                try await auth.signUp(email: email, password: password)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
