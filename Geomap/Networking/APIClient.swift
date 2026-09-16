import Foundation

final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let baseURL: URL
    private let tokenProvider: () -> String?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: string) {
                return date
            }
            if let date = ISO8601DateFormatter.standard.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unrecognized date format: \(string)"
            )
        }
        return decoder
    }()

    init(
        baseURL: URL = Config.apiBaseURL,
        session: URLSession = .shared,
        tokenProvider: @escaping () -> String? = { KeychainService.shared.getToken() }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    // MARK: - Endpoints

    func register(_ request: RegisterRequest) async throws -> AuthResponse {
        try await send(path: "/auth/register", method: "POST", body: request, requiresAuth: false)
    }

    func login(_ request: LoginRequest) async throws -> AuthResponse {
        try await send(path: "/auth/login", method: "POST", body: request, requiresAuth: false)
    }

    func me() async throws -> AuthResponse {
        try await send(path: "/auth/me", method: "GET", body: EmptyBody?.none, requiresAuth: true)
    }

    func updateLocation(_ request: LocationUpdateRequest) async throws -> LocationResponse {
        try await send(path: "/location", method: "POST", body: request, requiresAuth: true)
    }

    func nearbyFriends() async throws -> [NearbyFriendResponse] {
        try await send(path: "/friends/nearby", method: "GET", body: EmptyBody?.none, requiresAuth: true)
    }

    func statusPresets() async throws -> [StatusPresetOptionResponse] {
        try await send(path: "/status/presets", method: "GET", body: EmptyBody?.none, requiresAuth: true)
    }

    func myStatus() async throws -> StatusResponse {
        try await send(path: "/status/me", method: "GET", body: EmptyBody?.none, requiresAuth: true, allowsEmptyBody: true)
    }

    func updateStatus(_ request: StatusUpdateRequest) async throws -> StatusResponse {
        try await send(path: "/status", method: "POST", body: request, requiresAuth: true, allowsEmptyBody: true)
    }

    func conversations() async throws -> [ConversationResponse] {
        try await send(path: "/chat/conversations", method: "GET", body: EmptyBody?.none, requiresAuth: true)
    }

    func chatMessages(friendId: UUID, before: Date? = nil, limit: Int? = nil) async throws -> [ChatMessageResponse] {
        var queryItems: [URLQueryItem] = []
        if let before {
            queryItems.append(URLQueryItem(name: "before", value: ISO8601DateFormatter().string(from: before)))
        }
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        return try await send(
            path: "/chat/\(friendId)/messages",
            method: "GET",
            body: EmptyBody?.none,
            requiresAuth: true,
            queryItems: queryItems
        )
    }

    // MARK: - Core request/response handling

    private struct EmptyBody: Encodable {}

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body?,
        requiresAuth: Bool,
        allowsEmptyBody: Bool = false,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        var url = baseURL.appendingPathComponent(path)
        if !queryItems.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = queryItems
            url = components.url!
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if requiresAuth {
            guard let token = tokenProvider() else {
                throw APIError.unauthorized(message: nil)
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.network(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200..<300:
            do {
                // Verified live: GET /status/me and POST /status return a
                // genuinely empty 200 body (Content-Length: 0), not `{}`,
                // when no status is set — undocumented in the OpenAPI
                // schema. StatusResponse's fields are all optional, so
                // decoding from an empty object yields the correct
                // all-nil result; decoding empty Data directly would
                // throw before even reaching that point.
                let dataToDecode = (allowsEmptyBody && data.isEmpty) ? Data("{}".utf8) : data
                return try decoder.decode(Response.self, from: dataToDecode)
            } catch {
                throw APIError.decoding(error)
            }
        case 401:
            throw APIError.unauthorized(message: extractMessage(from: data))
        case 400:
            throw APIError.validationFailed(extractFieldErrors(from: data))
        default:
            throw APIError.server(status: httpResponse.statusCode, message: extractMessage(from: data))
        }
    }

    private func extractMessage(from data: Data) -> String? {
        guard let body = try? decoder.decode(BackendErrorBody.self, from: data) else {
            return nil
        }
        return body.message
    }

    private func extractFieldErrors(from data: Data) -> [String: String] {
        guard let body = try? decoder.decode(BackendErrorBody.self, from: data) else {
            return [:]
        }
        if let fieldErrors = body.fieldErrors, !fieldErrors.isEmpty {
            return fieldErrors
        }
        if let message = body.message {
            return ["_": message]
        }
        return [:]
    }
}

private extension ISO8601DateFormatter {
    static let standard = ISO8601DateFormatter()

    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
