import XCTest
@testable import Geomap

@MainActor
final class AddFriendViewModelTests: XCTestCase {
    private let herId = "d39ad7d6-d739-4874-b716-ad81ded6a1f5"
    private var requests: [(method: String, path: String, body: String)] = []
    private var friendsJSON = "[]"
    private var confirmStatus = "CONFIRMED"
    private var failPath: (path: String, status: Int)?

    override func setUp() {
        super.setUp()
        requests = []
        friendsJSON = "[]"
        confirmStatus = "CONFIRMED"
        failPath = nil
        MockURLProtocol.requestHandler = { [unowned self] request in
            let path = request.url!.path
            let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? bodyFromStream(request)
            self.requests.append((request.httpMethod ?? "", path, body))
            func respond(_ status: Int, _ json: String) -> (HTTPURLResponse, Data) {
                (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, json.data(using: .utf8)!)
            }
            if let failPath = self.failPath, failPath.path == path {
                return respond(failPath.status, #"{"message":"gone","fieldErrors":null}"#)
            }
            switch (request.httpMethod ?? "", path) {
            case ("POST", "/friends/encounter"):
                return respond(200, #"{"token":"MY-TOKEN","expiresAt":"2099-01-01T00:00:00.123456Z"}"#)
            case ("POST", "/friends/encounter/lookup"):
                return respond(200, #"{"userId":"\#(self.herId)","displayName":"Julia","profilePhotoUrl":null}"#)
            case ("POST", "/friends/encounter/confirm"):
                return respond(200, #"{"userId":"\#(self.herId)","displayName":"Julia","profilePhotoUrl":null,"status":"\#(self.confirmStatus)"}"#)
            case ("GET", "/friends"):
                return respond(200, self.friendsJSON)
            case ("DELETE", _):
                return respond(204, "")
            default:
                return respond(404, #"{"message":"nope","fieldErrors":null}"#)
            }
        }
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeViewModel(peer: MockPeerSession, pollInterval: TimeInterval = 0.02, pendingTimeout: TimeInterval = 300) -> AddFriendViewModel {
        let apiClient = APIClient(
            baseURL: URL(string: "http://localhost:8080")!,
            session: MockURLProtocol.makeSession(),
            tokenProvider: { "test-token" }
        )
        return AddFriendViewModel(apiClient: apiClient, peer: peer, pollInterval: pollInterval, pendingTimeout: pendingTimeout)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition", file: file, line: line)
    }

    private var julia: UserProfileResponse {
        UserProfileResponse(userId: UUID(uuidString: herId)!, displayName: "Julia", profilePhotoUrl: nil)
    }

    /// Start, connect a peer and exchange tokens until the confirm screen.
    private func reachConfirming(_ viewModel: AddFriendViewModel, _ peer: MockPeerSession) async {
        await viewModel.start()
        peer.emit(.peerConnected)
        peer.emit(.message(.token("HER-TOKEN")))
        await waitUntil { viewModel.state == .confirming(self.julia) }
    }

    func testStartIssuesCodeAndSendsItWhenPeerConnects() async {
        let peer = MockPeerSession()
        let viewModel = makeViewModel(peer: peer)

        await viewModel.start()
        XCTAssertEqual(viewModel.state, .searching)
        XCTAssertTrue(peer.isStarted)
        XCTAssertEqual(requests.first?.path, "/friends/encounter")

        peer.emit(.peerConnected)
        XCTAssertEqual(peer.sent, [.token("MY-TOKEN")])
    }

    func testReceivedCodeIsLookedUpAndShownForConfirmation() async {
        let peer = MockPeerSession()
        let viewModel = makeViewModel(peer: peer)

        await reachConfirming(viewModel, peer)

        let lookup = requests.first { $0.path == "/friends/encounter/lookup" }
        XCTAssertTrue(lookup?.body.contains("HER-TOKEN") ?? false)
    }

    func testConfirmWhenSecondSideSucceedsImmediately() async {
        let peer = MockPeerSession()
        let viewModel = makeViewModel(peer: peer)
        await reachConfirming(viewModel, peer)

        await viewModel.confirm()

        XCTAssertEqual(viewModel.state, .success(julia))
        XCTAssertEqual(peer.sent.last, .confirmed)
        let confirm = requests.first { $0.path == "/friends/encounter/confirm" }
        XCTAssertTrue(confirm?.body.contains("HER-TOKEN") ?? false)
    }

    func testPendingThenPeerConfirmedMessageCompletes() async {
        confirmStatus = "PENDING"
        let peer = MockPeerSession()
        let viewModel = makeViewModel(peer: peer)
        await reachConfirming(viewModel, peer)

        await viewModel.confirm()
        XCTAssertEqual(viewModel.state, .waitingForOther(julia))

        peer.emit(.message(.confirmed))
        XCTAssertEqual(viewModel.state, .success(julia))
    }

    func testPendingThenFriendsPollingCompletes() async {
        confirmStatus = "PENDING"
        let peer = MockPeerSession()
        let viewModel = makeViewModel(peer: peer)
        await reachConfirming(viewModel, peer)
        await viewModel.confirm()
        XCTAssertEqual(viewModel.state, .waitingForOther(julia))

        friendsJSON = #"[{"userId":"\#(herId)","displayName":"Julia","profilePhotoUrl":null}]"#

        await waitUntil { viewModel.state == .success(self.julia) }
    }

    func testPendingTimesOutIfOtherSideNeverConfirms() async {
        confirmStatus = "PENDING"
        let peer = MockPeerSession()
        let viewModel = makeViewModel(peer: peer, pendingTimeout: 0.1)
        await reachConfirming(viewModel, peer)
        await viewModel.confirm()

        await waitUntil { viewModel.state == .expired }
    }

    func testExpiredCodeOnLookupShowsExpired() async {
        failPath = ("/friends/encounter/lookup", 410)
        let peer = MockPeerSession()
        let viewModel = makeViewModel(peer: peer)
        await viewModel.start()

        peer.emit(.message(.token("STALE")))

        await waitUntil { viewModel.state == .expired }
    }

    func testExpiredCodeOnConfirmShowsExpired() async {
        let peer = MockPeerSession()
        let viewModel = makeViewModel(peer: peer)
        await reachConfirming(viewModel, peer)
        failPath = ("/friends/encounter/confirm", 410)

        await viewModel.confirm()

        XCTAssertEqual(viewModel.state, .expired)
    }

    func testAlreadyFriendsIsDetectedBeforeConfirming() async {
        friendsJSON = #"[{"userId":"\#(herId)","displayName":"Julia","profilePhotoUrl":null}]"#
        let peer = MockPeerSession()
        let viewModel = makeViewModel(peer: peer)
        await viewModel.start()

        peer.emit(.message(.token("HER-TOKEN")))

        await waitUntil { viewModel.state == .alreadyFriends(self.julia) }
    }

    func testCancelWhileConfirmingWithdrawsPendingAndStopsPeer() async {
        let peer = MockPeerSession()
        let viewModel = makeViewModel(peer: peer)
        await reachConfirming(viewModel, peer)

        await viewModel.cancel()

        XCTAssertFalse(peer.isStarted)
        let delete = requests.first { $0.method == "DELETE" }
        XCTAssertEqual(delete?.path.lowercased(), "/friends/\(herId)/pending")
    }

    func testCancelAfterSuccessDoesNotCallDelete() async {
        let peer = MockPeerSession()
        let viewModel = makeViewModel(peer: peer)
        await reachConfirming(viewModel, peer)
        await viewModel.confirm()

        await viewModel.cancel()

        XCTAssertFalse(requests.contains { $0.method == "DELETE" })
    }

    func testSecondCodeIsIgnoredOnceOneIsBeingHandled() async {
        let peer = MockPeerSession()
        let viewModel = makeViewModel(peer: peer)
        await reachConfirming(viewModel, peer)

        peer.emit(.message(.token("OTHER")))

        XCTAssertEqual(requests.filter { $0.path == "/friends/encounter/lookup" }.count, 1)
    }

    func testPeerDisconnectBeforeConfirmReturnsToSearching() async {
        let peer = MockPeerSession()
        let viewModel = makeViewModel(peer: peer)
        await reachConfirming(viewModel, peer)

        peer.emit(.peerDisconnected)

        XCTAssertEqual(viewModel.state, .searching)
    }

    func testPeerMessageRoundTripAndRejectsGarbage() {
        XCTAssertEqual(PeerMessage(data: PeerMessage.token("abc").data), .token("abc"))
        XCTAssertEqual(PeerMessage(data: PeerMessage.confirmed.data), .confirmed)
        XCTAssertNil(PeerMessage(data: Data("not json".utf8)))
        XCTAssertNil(PeerMessage(data: Data(#"{"type":"token","token":""}"#.utf8)))
        XCTAssertNil(PeerMessage(data: Data(#"{"type":"userId","token":"x"}"#.utf8)))
    }
}

private func bodyFromStream(_ request: URLRequest) -> String {
    guard let stream = request.httpBodyStream else { return "" }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let count = stream.read(buffer, maxLength: 1024)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return String(data: data, encoding: .utf8) ?? ""
}
