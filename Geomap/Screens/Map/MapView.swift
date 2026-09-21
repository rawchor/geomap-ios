import SwiftUI
import MapKit

private let radiusMeters: CLLocationDistance = 20_000
private let minSpanDegrees = 0.005
private let maxSpanDegrees = 60.0

struct MapView: View {
    let currentUser: User

    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var locationService = LocationService()
    @StateObject private var viewModel = MapViewModel()
    @StateObject private var unreadStore: UnreadMessagesStore
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var currentRegion: MKCoordinateRegion?
    @State private var hasCenteredOnUser = false
    @State private var isShowingMyStatus = false
    @State private var isShowingConversations = false
    @State private var selectedCluster: MapCluster?
    @State private var pendingClusterSelection: MapPerson?

    init(currentUser: User) {
        self.currentUser = currentUser
        _unreadStore = StateObject(wrappedValue: UnreadMessagesStore(currentUserId: currentUser.id))
    }

    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                if let userCoordinate = locationService.currentLocation?.coordinate {
                    MapPolygon(coordinates: radiusMaskCoordinates(center: userCoordinate))
                        .foregroundStyle(Color.black.opacity(0.35))
                    MapCircle(center: userCoordinate, radius: radiusMeters)
                        .foregroundStyle(.clear)
                        .stroke(.blue.opacity(0.6), lineWidth: 2)
                }

                // Locked previews are excluded from clustering — they're
                // always rendered individually (faded, unlabeled, non-
                // interactive), a distinct case from the regular
                // overlapping-status problem clustering solves.
                ForEach(mapClusters) { cluster in
                    if let person = cluster.members.first, cluster.members.count == 1 {
                        Annotation(person.displayName, coordinate: person.coordinate) {
                            singlePersonMarker(person)
                        }
                    } else {
                        Annotation("", coordinate: cluster.coordinate) {
                            clusterMarker(cluster)
                                .onTapGesture { selectedCluster = cluster }
                        }
                    }
                }

                ForEach(viewModel.friends.filter(\.locked)) { friend in
                    Annotation("", coordinate: friend.coordinate) {
                        AvatarView(
                            photoURL: friend.profilePhotoUrl,
                            displayName: friend.displayName,
                            ringColor: friend.degree.ringColor,
                            diameter: 40
                        )
                        .opacity(0.35)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .onMapCameraChange(frequency: .onEnd) { context in
                currentRegion = context.region
            }

            if viewModel.hasLoadedOnce && viewModel.friends.isEmpty {
                emptyStateOverlay
            }

            if locationService.authorizationStatus == .denied || locationService.authorizationStatus == .restricted {
                locationDeniedOverlay
            }
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 12) {
                logoutButton
                messagesButton
            }
            .padding(16)
        }
        .overlay(alignment: .bottomTrailing) {
            zoomControls
                .padding(16)
        }
        .task {
            locationService.requestPermissionAndStart()
        }
        .task {
            await viewModel.refreshMyStatus()
        }
        .task {
            LocalNotifier.shared.requestAuthorization()
        }
        .onAppear {
            viewModel.startPolling(
                locationProvider: { locationService.currentLocation?.coordinate },
                onUnauthorized: { sessionStore.logout() }
            )
            unreadStore.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
            locationService.stopUpdating()
            unreadStore.stopPolling()
        }
        .environmentObject(unreadStore)
        .onChange(of: locationService.currentLocation != nil) { _, hasLocation in
            guard !hasCenteredOnUser, hasLocation, let coordinate = locationService.currentLocation?.coordinate else { return }
            hasCenteredOnUser = true
            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: radiusMeters * 2.2,
                longitudinalMeters: radiusMeters * 2.2
            )
            currentRegion = region
            cameraPosition = .region(region)
        }
        .sheet(item: $viewModel.selectedFriend) { friend in
            FriendDetailView(friend: friend)
                .environmentObject(unreadStore)
        }
        .sheet(isPresented: $isShowingMyStatus, onDismiss: {
            Task { await viewModel.refreshMyStatus() }
        }) {
            MyStatusView()
        }
        .sheet(isPresented: $isShowingConversations) {
            ConversationsListView(currentUserId: currentUser.id)
                .environmentObject(unreadStore)
        }
        .sheet(item: $selectedCluster) { cluster in
            ClusterMembersView(members: cluster.members) { person in
                // Deferred via pendingClusterSelection/onChange below
                // rather than presenting the next sheet directly here:
                // presenting a new sheet in the same tick a different one
                // is being dismissed is unreliable in SwiftUI.
                pendingClusterSelection = person
                selectedCluster = nil
            }
        }
        .onChange(of: selectedCluster == nil) { _, isDismissed in
            guard isDismissed, let person = pendingClusterSelection else { return }
            pendingClusterSelection = nil
            if person.isSelf {
                isShowingMyStatus = true
            } else if let friend = person.friend {
                viewModel.selectedFriend = friend
            }
        }
    }

    /// A single non-self-intersecting polygon path covering the area around
    /// `center` with a circular cutout — SwiftUI's Map doesn't honor
    /// `MKPolygon.interiorPolygons` (the usual UIKit donut-hole technique),
    /// so instead this traces an outer boundary, a zero-width slit in to
    /// the circle, the full circle, and back out through the same slit.
    /// The degenerate slit has no area, so the filled result is exactly the
    /// outer region minus the circle, without depending on any
    /// hole-rendering support.
    ///
    /// The outer boundary is sized relative to `center` (±45°, comfortably
    /// beyond `maxSpanDegrees`'s max zoomed-out viewport) rather than
    /// spanning the whole globe — a near-global box distorts badly enough
    /// under Mercator projection near the poles/antimeridian that it
    /// visibly inverted which side of the path rendered as "inside".
    private func radiusMaskCoordinates(center: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        let halfSpan = 45.0
        let minLat = max(center.latitude - halfSpan, -85)
        let maxLat = min(center.latitude + halfSpan, 85)
        let minLon = center.longitude - halfSpan
        let maxLon = center.longitude + halfSpan
        let outer: [CLLocationCoordinate2D] = [
            CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
            CLLocationCoordinate2D(latitude: minLat, longitude: maxLon),
            CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon),
            CLLocationCoordinate2D(latitude: maxLat, longitude: minLon),
        ]
        let circle = circleCoordinates(center: center, radius: radiusMeters)
        guard let slitPoint = circle.first else { return outer }

        var path = outer
        path.append(outer[0])
        path.append(slitPoint)
        path.append(contentsOf: circle)
        path.append(slitPoint)
        return path
    }

    private func circleCoordinates(
        center: CLLocationCoordinate2D,
        radius: CLLocationDistance,
        pointCount: Int = 128
    ) -> [CLLocationCoordinate2D] {
        let earthRadius: CLLocationDistance = 6_371_000
        let centerLatRad = center.latitude * .pi / 180
        let centerLonRad = center.longitude * .pi / 180
        let angularDistance = radius / earthRadius

        return (0..<pointCount).map { index in
            let bearing = Double(index) / Double(pointCount) * 2 * .pi
            let lat = asin(
                sin(centerLatRad) * cos(angularDistance) + cos(centerLatRad) * sin(angularDistance) * cos(bearing)
            )
            let lon = centerLonRad + atan2(
                sin(bearing) * sin(angularDistance) * cos(centerLatRad),
                cos(angularDistance) - sin(centerLatRad) * sin(lat)
            )
            return CLLocationCoordinate2D(latitude: lat * 180 / .pi, longitude: lon * 180 / .pi)
        }
    }

    /// Unclustered people, freshly recomputed on every relevant change
    /// (friends poll, own status refresh, camera move) so clustering stays
    /// live as the map is panned/zoomed. Locked previews are excluded —
    /// rendered separately, unclustered, in the Map content above.
    private var mapClusters: [MapCluster] {
        var people: [MapPerson] = []
        if let userCoordinate = locationService.currentLocation?.coordinate {
            people.append(MapPerson(
                id: currentUser.id,
                displayName: currentUser.displayName,
                photoURL: nil,
                coordinate: userCoordinate,
                statusText: viewModel.myStatus?.displayText,
                ringColor: .green,
                isSelf: true,
                friend: nil
            ))
        }
        for friend in viewModel.friends where !friend.locked {
            people.append(MapPerson(
                id: friend.userId,
                displayName: friend.displayName,
                photoURL: friend.profilePhotoUrl,
                coordinate: friend.coordinate,
                statusText: friend.status?.displayText,
                ringColor: friend.degree.ringColor,
                isSelf: false,
                friend: friend
            ))
        }
        return buildMapClusters(from: people, visibleSpan: currentRegion?.span)
    }

    private func statusBubble(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(0.15), in: Capsule())
    }

    private func singlePersonMarker(_ person: MapPerson) -> some View {
        VStack(spacing: 4) {
            if let statusText = person.statusText {
                statusBubble(statusText)
            }
            AvatarView(
                photoURL: person.photoURL,
                displayName: person.displayName,
                ringColor: person.ringColor,
                diameter: person.isSelf ? 44 : 40
            )
        }
        .onTapGesture {
            if person.isSelf {
                isShowingMyStatus = true
            } else if let friend = person.friend {
                viewModel.selectedFriend = friend
            }
        }
    }

    /// Overlapping mini avatars standing in for everyone in the cluster —
    /// tapping it "uncovers" them via ClusterMembersView instead of
    /// showing every status bubble stacked illegibly on top of each other.
    private func clusterMarker(_ cluster: MapCluster) -> some View {
        HStack(spacing: -10) {
            ForEach(Array(cluster.members.prefix(4))) { person in
                AvatarView(photoURL: person.photoURL, displayName: person.displayName, ringColor: person.ringColor, diameter: 30)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
            }
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
        .overlay(alignment: .topTrailing) {
            if cluster.members.count > 4 {
                Text("+\(cluster.members.count - 4)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color.gray, in: Circle())
                    .offset(x: 6, y: -6)
            }
        }
    }

    private func zoom(by factor: Double) {
        guard let region = currentRegion else { return }
        let clampedLatitude = min(max(region.span.latitudeDelta * factor, minSpanDegrees), maxSpanDegrees)
        let clampedLongitude = min(max(region.span.longitudeDelta * factor, minSpanDegrees), maxSpanDegrees)
        let newRegion = MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(latitudeDelta: clampedLatitude, longitudeDelta: clampedLongitude)
        )
        currentRegion = newRegion
        withAnimation {
            cameraPosition = .region(newRegion)
        }
    }

    private var zoomControls: some View {
        VStack(spacing: 1) {
            Button {
                zoom(by: 0.5)
            } label: {
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            Divider().frame(width: 30)
            Button {
                zoom(by: 2.0)
            } label: {
                Image(systemName: "minus")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .disabled(currentRegion == nil)
    }

    private var logoutButton: some View {
        // Minimal placeholder until there's a dedicated settings/profile area.
        Button {
            sessionStore.logout()
        } label: {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.headline)
                .padding(10)
                .background(.regularMaterial, in: Circle())
        }
    }

    private var messagesButton: some View {
        Button {
            isShowingConversations = true
        } label: {
            Image(systemName: "message.fill")
                .font(.headline)
                .padding(10)
                .background(.regularMaterial, in: Circle())
        }
        .overlay(alignment: .topTrailing) {
            if unreadStore.unreadCount > 0 {
                Text("\(unreadStore.unreadCount)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color.red, in: Circle())
                    .offset(x: 4, y: -4)
            }
        }
    }

    private var emptyStateOverlay: some View {
        VStack {
            Text("No friends nearby yet")
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 24)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var locationDeniedOverlay: some View {
        VStack(spacing: 16) {
            Text("Location Access Needed")
                .font(.headline)
            Text("Geomap uses your location to show you on the map and find nearby friends. Enable location access in Settings to continue.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(24)
    }
}

private extension NearbyFriendResponse {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
