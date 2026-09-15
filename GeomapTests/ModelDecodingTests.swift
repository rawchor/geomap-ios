import XCTest
@testable import Geomap

final class ModelDecodingTests: XCTestCase {
    func testAuthResponseDecodesContractShape() throws {
        let json = """
        {
            "token": "abc123",
            "userId": "d39ad7d6-d739-4874-b716-ad81ded6a1f5",
            "email": "test@example.com",
            "displayName": "Test User",
            "subscriptionTier": "PREMIUM"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AuthResponse.self, from: json)

        XCTAssertEqual(response.token, "abc123")
        XCTAssertEqual(response.email, "test@example.com")
        XCTAssertEqual(response.displayName, "Test User")
        XCTAssertEqual(response.userId.uuidString.lowercased(), "d39ad7d6-d739-4874-b716-ad81ded6a1f5")
        XCTAssertEqual(response.subscriptionTier, .premium)
    }

    func testAuthResponseWithNullSubscriptionTierDefaultsUserToFree() throws {
        // Accounts created before this field existed come back with a null
        // tier (a backend data gap) rather than a backfilled "FREE" — this
        // must decode successfully and default sensibly, not crash login.
        let json = """
        {
            "token": "abc123",
            "userId": "d39ad7d6-d739-4874-b716-ad81ded6a1f5",
            "email": "test@example.com",
            "displayName": "Test User",
            "subscriptionTier": null
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AuthResponse.self, from: json)
        XCTAssertNil(response.subscriptionTier)

        let user = User(from: response)
        XCTAssertEqual(user.subscriptionTier, .free)
    }

    func testNearbyFriendResponseDecodesWithNullStatus() throws {
        let json = """
        {
            "userId": "d39ad7d6-d739-4874-b716-ad81ded6a1f5",
            "displayName": "Friend",
            "profilePhotoUrl": null,
            "latitude": 51.5,
            "longitude": -0.1,
            "degree": "SECOND_DEGREE",
            "mutualFriendName": "Mutual Person",
            "status": null,
            "locked": false
        }
        """.data(using: .utf8)!

        let friend = try JSONDecoder().decode(NearbyFriendResponse.self, from: json)

        XCTAssertEqual(friend.degree, .secondDegree)
        XCTAssertEqual(friend.mutualFriendName, "Mutual Person")
        XCTAssertNil(friend.status)
        XCTAssertNil(friend.profilePhotoUrl)
        XCTAssertFalse(friend.locked)
    }

    func testNearbyFriendResponseDecodesLockedPreview() throws {
        let json = """
        {
            "userId": "d39ad7d6-d739-4874-b716-ad81ded6a1f5",
            "displayName": "Julia",
            "profilePhotoUrl": null,
            "latitude": 52.5441,
            "longitude": 21.0122,
            "degree": "SECOND_DEGREE",
            "mutualFriendName": "Anna",
            "status": null,
            "locked": true
        }
        """.data(using: .utf8)!

        let friend = try JSONDecoder().decode(NearbyFriendResponse.self, from: json)

        XCTAssertTrue(friend.locked)
        XCTAssertNil(friend.status)
    }

    func testFriendStatusDecodesPresetAndCustomText() throws {
        let json = """
        { "preset": "GRABBING_COFFEE", "customText": "at the corner cafe" }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(FriendStatus.self, from: json)

        XCTAssertEqual(status.preset, .grabbingCoffee)
        XCTAssertEqual(status.customText, "at the corner cafe")
    }

    func testLocationResponseDecodesFractionalSecondsDate() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractional.date(from: string) { return date }
            let standard = ISO8601DateFormatter()
            if let date = standard.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "bad date")
        }

        let json = """
        {
            "userId": "d39ad7d6-d739-4874-b716-ad81ded6a1f5",
            "latitude": 1.0,
            "longitude": 2.0,
            "updatedAt": "2026-01-01T12:00:00.123Z"
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(LocationResponse.self, from: json)
        XCTAssertEqual(response.latitude, 1.0)
    }
}
