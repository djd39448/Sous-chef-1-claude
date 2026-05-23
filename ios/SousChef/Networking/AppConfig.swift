import Foundation

// AppConfig — runtime configuration for the iOS app.
//
// Depends on:     nothing.
// Depended on by: AuthModel, APIClient (for the URLs and the publishable key).
// Why it exists:  one place that holds the backend + Supabase URLs and the
//                 publishable key, so switching to a deployed backend later
//                 is a one-line edit.
enum AppConfig {
    /// The Go backend's base URL. Localhost works in the iOS Simulator
    /// against a backend running on the dev Mac. Flip to the deployed
    /// URL when Phase 5 lands.
    static let backendBaseURL = URL(string: "http://localhost:8080")!

    /// The Supabase project URL — same value the backend reads from its
    /// `SUPABASE_PROJECT_URL` env var.
    static let supabaseProjectURL = URL(string: "https://hssqzhwtwpvblfdmqzpw.supabase.co")!

    /// The Supabase publishable (anon) key. Per Supabase's docs, the
    /// publishable key is safe to ship to clients; the service-role
    /// (secret) key never leaves the backend.
    static let supabasePublishableKey = "sb_publishable_ud3NHz3MeUCUPTIg-GEP7w_2KjsChUk"
}
