import CoreLocation

@MainActor
final class MapViewModel: ObservableObject {
    @Published private(set) var friends: [NearbyFriendResponse] = []
    @Published private(set) var hasLoadedOnce = false
    @Published var selectedFriend: NearbyFriendResponse?
    @Published private(set) var myStatus: StatusResponse?

    private let apiClient: APIClient
    private var pollingTask: Task<Void, Never>?

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    /// Starts fetching nearby friends and posting the device's location on
    /// the same 15s cadence (matches web's polling interval). Stop with
    /// `stopPolling()` when the screen disappears.
    func startPolling(
        interval: TimeInterval = 15,
        locationProvider: @escaping () -> CLLocationCoordinate2D?,
        onUnauthorized: @escaping () -> Void
    ) {
        guard pollingTask == nil else { return }
        pollingTask = Task {
            while !Task.isCancelled {
                await refresh(locationProvider: locationProvider, onUnauthorized: onUnauthorized)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Refreshes the status bubble shown on the user's own map marker.
    /// Called on appear and after the status-editing sheet dismisses — not
    /// folded into the 15s poll loop, since only this app instance can
    /// change it (no need to watch for external updates as often as
    /// friends' positions).
    func refreshMyStatus() async {
        myStatus = try? await apiClient.myStatus()
    }

    /// A single fetch-friends-then-post-location cycle, exposed separately
    /// from the polling loop so it can be tested without waiting on a timer.
    func refresh(
        locationProvider: () -> CLLocationCoordinate2D?,
        onUnauthorized: () -> Void
    ) async {
        do {
            friends = try await apiClient.nearbyFriends()
            hasLoadedOnce = true
        } catch let error as APIError {
            if case .unauthorized = error {
                onUnauthorized()
                return
            }
        } catch {}

        guard let coordinate = locationProvider() else { return }
        do {
            _ = try await apiClient.updateLocation(
                LocationUpdateRequest(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
        } catch let error as APIError {
            if case .unauthorized = error {
                onUnauthorized()
            }
        } catch {}
    }
}
