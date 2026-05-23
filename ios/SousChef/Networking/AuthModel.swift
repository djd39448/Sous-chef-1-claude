import Foundation
import Observation

// AuthModel — the single owner of "is the user signed in, and with what
// token". A SwiftUI `@Observable` so any view that reads `isSignedIn` or
// `session` updates automatically when sign-in / sign-out happens.
//
// Depends on:     AppConfig (URL + key), SupabaseAuthClient, TokenStore.
// Depended on by: RootView (the auth gate), APIClient (reads the access
//                 token), EmailSignInSheet (calls signIn / signUp).
// Why it exists:  one source of truth for the user's sign-in state. The
//                 Keychain is the durable store; this is the in-memory
//                 view of it that SwiftUI observes.
@Observable
final class AuthModel {
    private(set) var session: AuthSession?

    var isSignedIn: Bool { session != nil }

    private let client: SupabaseAuthClient

    init() {
        self.client = SupabaseAuthClient(
            projectURL: AppConfig.supabaseProjectURL,
            apiKey: AppConfig.supabasePublishableKey
        )
        // Resume the previous session from the Keychain, if any.
        self.session = TokenStore.load()
    }

    func signIn(email: String, password: String) async throws {
        let s = try await client.signIn(email: email, password: password)
        try TokenStore.save(s)
        session = s
    }

    func signUp(email: String, password: String) async throws {
        let s = try await client.signUp(email: email, password: password)
        try TokenStore.save(s)
        session = s
    }

    func signOut() {
        TokenStore.clear()
        session = nil
    }
}
