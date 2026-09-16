import Foundation

enum APIError: Error {
    case unauthorized(message: String?)
    case validationFailed([String: String])
    case server(status: Int, message: String?)
    case network(Error)
    case decoding(Error)

    /// A message suitable for inline display (login/register forms, etc.).
    /// Surfaces the backend's own copy rather than inventing custom text.
    var displayMessage: String {
        switch self {
        case .unauthorized(let message):
            return message ?? "Invalid email or password."
        case .validationFailed(let errors):
            return errors.values.first ?? "Please check your input and try again."
        case .server(_, let message):
            return message ?? "Something went wrong. Please try again."
        case .network:
            return "Couldn't connect. Check your internet connection and try again."
        case .decoding:
            return "Something went wrong. Please try again."
        }
    }
}

/// Matches the verified error envelope in ERROR_SHAPES.md — one consistent
/// shape across every error case (400/401/409/500 alike), confirmed live
/// against a running server, not inferred. `fieldErrors` is always present
/// (never omitted) but only non-null for 400 validation failures.
struct BackendErrorBody: Decodable {
    let message: String?
    let fieldErrors: [String: String]?
}
