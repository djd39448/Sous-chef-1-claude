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

    func put<T: Decodable, B: Encodable>(_ path: String, _ body: B) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await request(path: path, method: "PUT", body: data)
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
        } catch let e as URLError where e.code == .cancelled {
            throw APIError.cancelled
        } catch let e as URLError {
            throw APIError.network(e)
        }
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.other("non-HTTP response")
        }
        if http.statusCode == 401 {
            // Token is invalid or expired — bounce the user back to SignIn
            // rather than getting stuck on an error card with no escape.
            auth.signOut()
            throw APIError.missingAuth
        }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.badResponse(status: http.statusCode,
                                       body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // MARK: - Server-Sent Events

    /// One frame of a Server-Sent Events stream — the JSON payload that
    /// followed `data: `. Multi-line events are concatenated with `\n`,
    /// matching the SSE spec; our backend always emits one `data:` line
    /// per event, but the reader handles both.
    struct SSEEvent: Sendable {
        let data: String
    }

    /// Open a streaming POST to `path` (or any method) and yield each
    /// `data:` frame as it arrives. Closes naturally when the server
    /// closes the connection; throws if the request fails or auth is
    /// missing. On 401 the user is signed out so the UI bounces back to
    /// SignIn rather than getting stuck.
    func stream<Body: Encodable>(
        path: String,
        method: String = "POST",
        body: Body
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let token = auth.session?.accessToken else {
                    continuation.finish(throwing: APIError.missingAuth)
                    return
                }
                let url = baseURL.appendingPathComponent(path)
                var req = URLRequest(url: url)
                req.httpMethod = method
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                req.timeoutInterval = 300   // long-lived stream — OpenAI completions can stretch
                do {
                    req.httpBody = try JSONEncoder().encode(body)
                } catch {
                    continuation.finish(throwing: APIError.decoding(error))
                    return
                }

                do {
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse else {
                        continuation.finish(throwing: APIError.other("non-HTTP response"))
                        return
                    }
                    if http.statusCode == 401 {
                        await MainActor.run { auth.signOut() }
                        continuation.finish(throwing: APIError.missingAuth)
                        return
                    }
                    if !(200..<300).contains(http.statusCode) {
                        continuation.finish(throwing: APIError.badResponse(
                            status: http.statusCode, body: ""))
                        return
                    }

                    // Read raw bytes ourselves rather than via
                    // `bytes.lines`. `URLSession.bytes(for:).lines`
                    // has a long-standing quirk where it can buffer
                    // a whole SSE response and deliver every line at
                    // EOF — when the iOS recipe screen was getting
                    // `events=1 decodeFails=1` for a 488-event recipe
                    // stream that the server flushed cleanly, that
                    // was this bug. Reading raw bytes and framing on
                    // `\n\n` ourselves emits each event as it lands.
                    var rxBuf: [UInt8] = []
                    for try await byte in bytes {
                        rxBuf.append(byte)
                        // Look for the event boundary "\n\n" at the
                        // tail. `\r\n\r\n` also accepted — RFC says
                        // SSE accepts both line endings.
                        if isEventBoundary(rxBuf) {
                            let raw = String(bytes: rxBuf, encoding: .utf8) ?? ""
                            rxBuf.removeAll(keepingCapacity: true)
                            if let payload = sseFrameToPayload(raw),
                               !payload.isEmpty {
                                continuation.yield(SSEEvent(data: payload))
                            }
                        }
                    }
                    // Flush trailing partial event (no terminator before EOF).
                    if !rxBuf.isEmpty {
                        let raw = String(bytes: rxBuf, encoding: .utf8) ?? ""
                        if let payload = sseFrameToPayload(raw),
                           !payload.isEmpty {
                            continuation.yield(SSEEvent(data: payload))
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let e as URLError where e.code == .cancelled {
                    continuation.finish()
                } catch let e as URLError {
                    continuation.finish(throwing: APIError.network(e))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func parseDataLine(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count)
        let trimmed = payload.hasPrefix(" ") ? String(payload.dropFirst()) : String(payload)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// True when the tail of `buf` is `\n\n` or `\r\n\r\n` — the SSE
    /// event-terminator. Cheap to call on every byte; we only inspect
    /// at most the last 4 bytes.
    private func isEventBoundary(_ buf: [UInt8]) -> Bool {
        let lf: UInt8 = 0x0A
        let cr: UInt8 = 0x0D
        let n = buf.count
        if n >= 2, buf[n - 1] == lf, buf[n - 2] == lf { return true }
        if n >= 4,
           buf[n - 1] == lf, buf[n - 2] == cr,
           buf[n - 3] == lf, buf[n - 4] == cr {
            return true
        }
        return false
    }

    /// Convert one SSE event frame (raw text up to and including the
    /// trailing `\n\n`) into the concatenated payload of its `data:`
    /// lines. Non-`data:` lines (comments, heartbeats) are skipped.
    private func sseFrameToPayload(_ frame: String) -> String? {
        var parts: [String] = []
        // Split on either kind of newline so we cope with whatever the
        // server emits.
        let lines = frame.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        for line in lines {
            if line.isEmpty { continue }
            let s = String(line)
            if let payload = parseDataLine(s) {
                parts.append(payload)
            }
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n")
    }

    /// Shared JSON decoder. Accepts ISO-8601 timestamps with up to 9
    /// fractional-second digits — Go's `time.Time` emits RFC3339Nano
    /// (`…20.977852-04:00`), and iOS's `ISO8601DateFormatter` only handles
    /// up to 3, so anything beyond is truncated before parsing.
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let s = raw.replacingOccurrences(
                of: #"(\.\d{3})\d+"#,
                with: "$1",
                options: .regularExpression
            )
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFrac.date(from: s) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            // ISO8601DateFormatter without fractional seconds doesn't like
            // a fractional component being present either, so strip it.
            let noFrac = s.replacingOccurrences(
                of: #"\.\d+"#,
                with: "",
                options: .regularExpression
            )
            if let date = plain.date(from: noFrac) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date format: \(raw)")
        }
        return d
    }()
}
