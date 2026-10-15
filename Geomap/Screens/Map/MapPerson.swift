import CoreLocation
import MapKit
import SwiftUI

/// A unified projection of "self" and "friend" map data, so both can be
/// clustered and rendered through the same code path. `friend` carries the
/// original response back for friends (nil for self) so a tap on a
/// clustered member can still route to the real Friend Detail sheet, which
/// needs fields (degree, mutualFriendName, locked, ...) this lighter
/// struct doesn't itself carry.
struct MapPerson: Identifiable {
    let id: UUID
    let displayName: String
    let photoURL: String?
    let coordinate: CLLocationCoordinate2D
    let statusText: String?
    let ringColor: Color
    let isSelf: Bool
    let friend: NearbyFriendResponse?
}

/// One or more `MapPerson`s close enough together (relative to the current
/// map zoom) to be shown as a single combined marker instead of
/// individually overlapping ones.
struct MapCluster: Identifiable {
    let id: String
    let members: [MapPerson]
    let coordinate: CLLocationCoordinate2D
}

/// Groups people into clusters using a threshold proportional to the
/// current map span, so clusters dissolve back into individual markers as
/// the user zooms in and people become visually separated, and re-form
/// when zoomed out — not a fixed real-world distance. `nil` span falls
/// back to a reasonable default (before the first camera-change callback
/// fires).
func buildMapClusters(from people: [MapPerson], visibleSpan: MKCoordinateSpan?) -> [MapCluster] {
    let threshold: Double
    if let visibleSpan {
        // Cluster anything within ~6% of the visible span — tuned by eye
        // against the seeded test data, not derived from a hard rule.
        threshold = max(visibleSpan.latitudeDelta, visibleSpan.longitudeDelta) * 0.06
    } else {
        threshold = 0.03
    }

    var remaining = people
    var groups: [[MapPerson]] = []
    while let first = remaining.first {
        var group = [first]
        remaining.removeFirst()
        var didGrow = true
        while didGrow {
            didGrow = false
            remaining.removeAll { candidate in
                let isNearGroup = group.contains { member in
                    abs(member.coordinate.latitude - candidate.coordinate.latitude) < threshold
                        && abs(member.coordinate.longitude - candidate.coordinate.longitude) < threshold
                }
                if isNearGroup {
                    group.append(candidate)
                    didGrow = true
                }
                return isNearGroup
            }
        }
        groups.append(group)
    }

    return groups.map { group in
        let avgLat = group.map(\.coordinate.latitude).reduce(0, +) / Double(group.count)
        let avgLon = group.map(\.coordinate.longitude).reduce(0, +) / Double(group.count)
        let key = group.map(\.id.uuidString).sorted().joined(separator: "-")
        return MapCluster(
            id: key,
            members: group,
            coordinate: CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
        )
    }
}
