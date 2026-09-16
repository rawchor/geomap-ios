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

    func testStatusResponseDecodesPresetFields() throws {
        let json = """
        {
            "presetOptionId": "d39ad7d6-d739-4874-b716-ad81ded6a1f5",
            "presetLabel": "Grabbing coffee",
            "presetEmoji": "☕",
            "customText": null
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(StatusResponse.self, from: json)

        XCTAssertEqual(status.presetLabel, "Grabbing coffee")
        XCTAssertEqual(status.presetEmoji, "☕")
        XCTAssertNil(status.customText)
        XCTAssertEqual(status.displayText, "☕ Grabbing coffee")
    }

    func testStatusResponseDisplayTextPrefersCustomText() {
        let status = StatusResponse(presetOptionId: nil, presetLabel: nil, presetEmoji: nil, customText: "at the corner cafe")
        XCTAssertEqual(status.displayText, "at the corner cafe")
    }

    func testStatusResponseDisplayTextNilWhenEmpty() {
        let status = StatusResponse(presetOptionId: nil, presetLabel: nil, presetEmoji: nil, customText: nil)
        XCTAssertNil(status.displayText)
    }

    func testStatusPresetOptionResponseDecodesContractShape() throws {
        let json = """
        { "id": "d39ad7d6-d739-4874-b716-ad81ded6a1f5", "label": "Free to hang", "emoji": "🙌" }
        """.data(using: .utf8)!

        let preset = try JSONDecoder().decode(StatusPresetOptionResponse.self, from: json)

        XCTAssertEqual(preset.label, "Free to hang")
        XCTAssertEqual(preset.emoji, "🙌")
    }

    func testStatusUpdateRequestEncodesExplicitNullsWhenClearing() throws {
        // The backend's "clear status" semantics require both keys present
        // with null, not omitted — Swift's default Optional encoding would
        // otherwise silently drop them via encodeIfPresent.
        let request = StatusUpdateRequest(presetOptionId: nil, customText: nil, durationMinutes: nil)
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertTrue(json?.keys.contains("presetOptionId") ?? false)
        XCTAssertTrue(json?.keys.contains("customText") ?? false)
        XCTAssertTrue(json?["presetOptionId"] is NSNull)
        XCTAssertTrue(json?["customText"] is NSNull)
        XCTAssertFalse(json?.keys.contains("durationMinutes") ?? true)
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

    func testChatMessageResponseDecodesContractShape() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = """
        {
            "id": "d39ad7d6-d739-4874-b716-ad81ded6a1f5",
            "senderId": "11111111-1111-1111-1111-111111111111",
            "recipientId": "22222222-2222-2222-2222-222222222222",
            "content": "hey",
            "sentAt": "2026-09-16T13:03:02Z",
            "readAt": null
        }
        """.data(using: .utf8)!

        let message = try decoder.decode(ChatMessageResponse.self, from: json)

        XCTAssertEqual(message.content, "hey")
        XCTAssertNil(message.readAt)
    }

    func testConversationResponseDecodesWithNilLastMessage() throws {
        let json = """
        {
            "friendId": "d39ad7d6-d739-4874-b716-ad81ded6a1f5",
            "displayName": "Anna",
            "profilePhotoUrl": null,
            "lastMessage": null,
            "lastMessageSentAt": null
        }
        """.data(using: .utf8)!

        let conversation = try JSONDecoder().decode(ConversationResponse.self, from: json)

        XCTAssertEqual(conversation.displayName, "Anna")
        XCTAssertNil(conversation.lastMessage)
        XCTAssertEqual(conversation.id, conversation.friendId)
    }
}
