import Foundation

// SupabaseAuthClient — talks directly to Supabase Auth's REST endpoints
// (`/auth/v1/signup`, `/auth/v1/token`) using the publishable key.
//
// Depends on:     APIError, AuthSession, AppConfig, URLSession.
// Depended on by: AuthModel.
// Why it exists:  rolling our own thin client avoids pulling in the full
//                 supabase-swift SDK as a Swift Package dependency. The
//                 surface we need is small (sign-up, sign-in, refresh),
//                 and `signInWithIdToken` will be added here when Sign in
//                 with Apple lands.
struct SupabaseAuthClient {
    let projectURL: URL
    let apiKey: String

    /// Create a new user with email + password. The session is returned
    /// only when the project has email confirmation disabled; otherwise
    /// throws `.other("…confirm your email…")`.
    func signUp(email: String, password: String) async throws -> AuthSession {
        let url = projectURL.appendingPathComponent("auth/v1/signup")
        let raw = try await postJSON(url: url, body: ["email": email, "password": password])
        return try sessionFrom(data: raw)
    }

    /// Sign in an existing user with email + password.
    func signIn(email: String, password: String) async throws -> AuthSession {
        let url = tokenURL(grant: "password")
        let raw = try await postJSON(url: url, body: ["email": email, "password": password])
        return try sessionFrom(data: raw)
    }

    /// Exchange a refresh token for a fresh session.
    func refresh(refreshToken: String) async throws -> AuthSession {
        let url = tokenURL(grant: "refresh_token")
        let raw = try await postJSON(url: url, body: ["refresh_token": refreshToken])
        return try sessionFrom(data: raw)
    }

    // MARK: - Internal

    private func tokenURL(grant: String) -> URL {
        var c = URLComponents(url: projectURL.appendingPathComponent("auth/v1/token"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "grant_type", value: grant)]
        return c.url!
    }

    private func postJSON(url: URL, body: [String: String]) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.other("non-HTTP response from Supabase Auth")
        }
        if !(200..<300).contains(http.statusCode) {
            // Supabase returns { error_description, msg, ... } on failures —
            // surface that text if present, otherwise just the body.
            let bodyText = parseError(data: data) ?? String(data: data, encoding: .utf8) ?? ""
            throw APIError.badResponse(status: http.statusCode, body: bodyText)
        }
        return data
    }

    private func parseError(data: Data) -> String? {
        struct ErrBody: Decodable {
            let error_description: String?
            let msg: String?
            let message: String?
        }
        if let e = try? JSONDecoder().decode(ErrBody.self, from: data) {
            return e.error_description ?? e.msg ?? e.message
        }
        return nil
    }

    private func sessionFrom(data: Data) throws -> AuthSession {
        struct GoTrueResponse: Decodable {
            let access_token: String?
            let refresh_token: String?
            let expires_in: Int?
            let user: GoTrueUser?
        }
        struct GoTrueUser: Decodable {
            let id: String
            let email: String?
        }
        let decoded: GoTrueResponse
        do {
            decoded = try JSONDecoder().decode(GoTrueResponse.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
        guard let access = decoded.access_token,
              let refresh = decoded.refresh_token,
              let expiresIn = decoded.expires_in,
              let user = decoded.user else {
            throw APIError.other(
                "Account created — please check your email to confirm before signing in.")
        }
        return AuthSession(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            userId: user.id,
            email: user.email
        )
    }
}
