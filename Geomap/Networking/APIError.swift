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

/// Lenient shape for whatever error body the backend sends back — the
/// OpenAPI contract doesn't document error responses, so this tolerates
/// a few common Spring Boot shapes rather than assuming one exact format.
struct BackendErrorBody: Decodable {
    let message: String?
    let error: String?
    let errors: [String: String]?
}
