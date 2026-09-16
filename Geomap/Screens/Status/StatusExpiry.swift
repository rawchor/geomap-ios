import Foundation

/// Per ACCEPTANCE_CRITERIA.md: the user picks an expiry at the same time
/// as setting a status. Maps to `StatusUpdateRequest.durationMinutes`.
enum StatusExpiry: CaseIterable, Identifiable {
    case oneHour, fourHours, untilChanged

    var id: Self { self }

    var minutes: Int? {
        switch self {
        case .oneHour: return 60
        case .fourHours: return 240
        case .untilChanged: return nil
        }
    }

    var label: String {
        switch self {
        case .oneHour: return "1 hour"
        case .fourHours: return "4 hours"
        case .untilChanged: return "Until I change it"
        }
    }
}
