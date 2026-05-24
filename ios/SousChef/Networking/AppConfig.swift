import Foundation

// AppConfig — runtime configuration for the iOS app.
//
// Depends on:     nothing.
// Depended on by: AuthModel, APIClient (for the URLs and the publishable key).
// Why it exists:  one place that holds the backend + Supabase URLs and the
//                 publishable key, so switching to a deployed backend later
//                 is a one-line edit.
enum AppConfig {
    /// The Go backend's base URL. The simulator can reach `localhost:8080`
    /// directly, but a real phone has to hit the Mac mini's LAN address —
    /// dev's mac mini is `192.168.1.132`. ATS allows http on local networks
    /// (`NSAllowsLocalNetworking` in Info.plist), so this works without TLS.
    /// Flip to the deployed URL when Phase 5 lands.
    static let backendBaseURL = URL(string: "http://192.168.1.132:8080")!

    /// The Supabase project URL — same value the backend reads from its
    /// `SUPABASE_PROJECT_URL` env var.
    static let supabaseProjectURL = URL(string: "https://hssqzhwtwpvblfdmqzpw.supabase.co")!

    /// The Supabase publishable (anon) key. Per Supabase's docs, the
    /// publishable key is safe to ship to clients; the service-role
    /// (secret) key never leaves the backend.
    static let supabasePublishableKey = "sb_publishable_ud3NHz3MeUCUPTIg-GEP7w_2KjsChUk"
}
