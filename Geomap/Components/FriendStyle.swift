import SwiftUI

extension FriendDegree {
    /// Placeholder pair — reconcile with web's WEB_MAP_UPGRADE.md colors
    /// once that's finalized.
    var ringColor: Color {
        switch self {
        case .firstDegree: return .blue
        case .secondDegree: return .orange
        }
    }
}

extension StatusResponse {
    /// The text to show for this status, or nil if there's nothing to show
    /// (an empty status is valid, per the backend's design).
    var displayText: String? {
        if let customText, !customText.isEmpty {
            return customText
        }
        guard let presetLabel else { return nil }
        if let presetEmoji, !presetEmoji.isEmpty {
            return "\(presetEmoji) \(presetLabel)"
        }
        return presetLabel
    }
}
