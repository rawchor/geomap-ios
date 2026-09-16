import Foundation
@testable import Geomap

@MainActor
final class MockNotifier: NotificationPosting {
    private(set) var posted: [(friendDisplayName: String, preview: String)] = []

    func postNewMessageNotification(friendDisplayName: String, preview: String) {
        posted.append((friendDisplayName, preview))
    }
}
