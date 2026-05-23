import Foundation

// APIError — the typed error every networking call throws.
//
// Depends on:     Foundation.
// Depended on by: APIClient, SupabaseAuthClient, AuthModel, every view that
//                 surfaces a network error to the user.
// Why it exists:  one shape for "something went wrong with a request" so
//                 callers can switch on the cause and surface useful copy.
enum APIError: LocalizedError {
    case network(URLError)
    case badResponse(status: Int, body: String)
    case decoding(Error)
    case missingAuth
    case other(String)

    var errorDescription: String? {
        switch self {
        case .network(let e):
            return "Network error: \(e.localizedDescription)"
        case .badResponse(let status, let body):
            return body.isEmpty
                ? "Server returned \(status)"
                : "Server returned \(status): \(body)"
        case .decoding(let e):
            return "Couldn't read the server response: \(e.localizedDescription)"
        case .missingAuth:
            return "You need to sign in to do that."
        case .other(let s):
            return s
        }
    }
}
