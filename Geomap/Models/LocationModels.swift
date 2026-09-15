import Foundation

struct LocationUpdateRequest: Encodable {
    let latitude: Double
    let longitude: Double
}

struct LocationResponse: Decodable {
    let userId: UUID
    let latitude: Double
    let longitude: Double
    let updatedAt: Date
}
