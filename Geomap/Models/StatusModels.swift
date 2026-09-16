import Foundation

struct StatusPresetOptionResponse: Decodable, Identifiable, Hashable {
    let id: UUID
    let label: String
    let emoji: String
}

/// Setting a status is exclusive — exactly one of `presetOptionId` or
/// `customText`, never both (the backend 400s otherwise). Clearing a
/// status means sending both explicitly as `null`, not omitting them, so
/// this can't use Swift's default Optional-encoding (which omits nil
/// keys via `encodeIfPresent`) — the custom `encode(to:)` below forces
/// both keys to always be present.
struct StatusUpdateRequest: Encodable {
    let presetOptionId: UUID?
    let customText: String?
    let durationMinutes: Int?

    private enum CodingKeys: String, CodingKey {
        case presetOptionId, customText, durationMinutes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(presetOptionId, forKey: .presetOptionId)
        try container.encode(customText, forKey: .customText)
        try container.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
    }
}
