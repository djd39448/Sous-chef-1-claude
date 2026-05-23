import Foundation

// APIClient — the single HTTP client every view uses to talk to the Go
// backend. Wraps URLSession with the bearer-token header from AuthModel,
// JSON encode/decode, and unified error handling.
//
// Depends on:     AppConfig, AuthModel, APIError, URLSession, Foundation.
// Depended on by: every screen that fetches or mutates remote data.
// Why it exists:  one place that knows the wire format (camelCase row
//                 columns, ISO-8601 timestamps with fractional seconds)
//                 and the auth header — sc-04 forbids scattering
//                 URLSession calls through views and models.
struct APIClient {
    let baseURL: URL
    let auth: AuthModel

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path: path, method: "GET", body: nil)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, _ body: B) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await request(path: path, method: "POST", body: data)
    }

    func patch<T: Decodable, B: Encodable>(_ path: String, _ body: B) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await request(path: path, method: "PATCH", body: data)
    }

    func delete(_ path: String) async throws {
        _ = try await rawRequest(path: path, method: "DELETE", body: nil)
    }

    // MARK: - Internal

    private func request<T: Decodable>(path: String, method: String, body: Data?) async throws -> T {
        let data = try await rawRequest(path: path, method: method, body: body)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func rawRequest(path: String, method: String, body: Data?) async throws -> Data {
        guard let token = auth.session?.accessToken else { throw APIError.missingAuth }

        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = body

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch let e as URLError {
            throw APIError.network(e)
        }
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.other("non-HTTP response")
        }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.badResponse(status: http.statusCode,
                                       body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// Shared JSON decoder. Accepts ISO-8601 timestamps both with and without
    /// fractional seconds (Go's `time.Time` emits fractional; the iOS
    /// `.iso8601` strategy alone would reject those).
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let s = try container.decode(String.self)
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFrac.date(from: s) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date format: \(s)")
        }
        return d
    }()
}
