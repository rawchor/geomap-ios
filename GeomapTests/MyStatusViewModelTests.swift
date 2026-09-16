import XCTest
@testable import Geomap

@MainActor
final class MyStatusViewModelTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeViewModel() -> MyStatusViewModel {
        let apiClient = APIClient(
            baseURL: URL(string: "http://localhost:8080")!,
            session: MockURLProtocol.makeSession(),
            tokenProvider: { "test-token" }
        )
        return MyStatusViewModel(apiClient: apiClient)
    }

    private let coffeePresetId = UUID(uuidString: "d39ad7d6-d739-4874-b716-ad81ded6a1f5")!

    func testSearchTextTruncatesAtThirtyCharacters() {
        let viewModel = makeViewModel()
        viewModel.searchText = String(repeating: "a", count: 50)
        XCTAssertEqual(viewModel.searchText.count, MyStatusViewModel.customTextLimit)
    }

    func testLoadInitialDataPopulatesPresetsAndCurrentStatus() async {
        MockURLProtocol.requestHandler = { [coffeePresetId] request in
            if request.url!.path == "/status/presets" {
                let body = """
                [{"id":"\(coffeePresetId)","label":"Grabbing coffee","emoji":"☕"}]
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            }
            let body = """
            {"presetOptionId":null,"presetLabel":null,"presetEmoji":null,"customText":"Reading"}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        let viewModel = makeViewModel()
        await viewModel.loadInitialData()

        XCTAssertEqual(viewModel.presets.count, 1)
        XCTAssertEqual(viewModel.currentStatus?.customText, "Reading")
        // searchText intentionally stays empty on load — it's an input for
        // choosing a *new* status, not a mirror of the current one (which
        // the bubble above it already shows); pre-filling it with the
        // decorated display text would filter every preset out of
        // filteredPresets on open.
        XCTAssertEqual(viewModel.searchText, "")
    }

    func testMatchingPresetResolvesCaseInsensitively() async {
        MockURLProtocol.requestHandler = { [coffeePresetId] request in
            if request.url!.path == "/status/presets" {
                let body = """
                [{"id":"\(coffeePresetId)","label":"Grabbing coffee","emoji":"☕"}]
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            }
            let body = """
            {"presetOptionId":null,"presetLabel":null,"presetEmoji":null,"customText":null}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        let viewModel = makeViewModel()
        await viewModel.loadInitialData()

        viewModel.searchText = "grabbing coffee"
        XCTAssertEqual(viewModel.matchingPreset?.id, coffeePresetId)
        XCTAssertFalse(viewModel.canSaveAsCustomText)

        viewModel.searchText = "on a hike"
        XCTAssertNil(viewModel.matchingPreset)
        XCTAssertTrue(viewModel.canSaveAsCustomText)
    }

    func testSelectPresetSendsPresetOptionIdOnly() async {
        var capturedBody: [String: Any]?
        MockURLProtocol.requestHandler = { [coffeePresetId] request in
            if request.url!.path == "/status/presets" {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, "[]".data(using: .utf8)!)
            }
            if request.url!.path == "/status/me" {
                let body = """
                {"presetOptionId":null,"presetLabel":null,"presetEmoji":null,"customText":null}
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            }
            capturedBody = try? JSONSerialization.jsonObject(with: request.capturedBodyData() ?? Data()) as? [String: Any]
            let body = """
            {"presetOptionId":"\(coffeePresetId)","presetLabel":"Grabbing coffee","presetEmoji":"☕","customText":null}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        let viewModel = makeViewModel()
        await viewModel.loadInitialData()
        await viewModel.selectPreset(StatusPresetOptionResponse(id: coffeePresetId, label: "Grabbing coffee", emoji: "☕"))

        XCTAssertEqual(viewModel.currentStatus?.presetLabel, "Grabbing coffee")
        XCTAssertEqual(capturedBody?["presetOptionId"] as? String, coffeePresetId.uuidString)
        XCTAssertTrue(capturedBody?["customText"] is NSNull)
        // Regression: searchText must not be re-filled with the decorated
        // "☕ Grabbing coffee" display text after saving, or filteredPresets
        // would filter out every preset (none contain the emoji) on the
        // very next render.
        XCTAssertEqual(viewModel.searchText, "")
    }

    func testClearStatusSendsBothFieldsExplicitlyNull() async {
        var capturedBody: [String: Any]?
        MockURLProtocol.requestHandler = { request in
            if request.url!.path == "/status/presets" {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, "[]".data(using: .utf8)!)
            }
            if request.url!.path == "/status/me" {
                let body = """
                {"presetOptionId":null,"presetLabel":null,"presetEmoji":null,"customText":"Reading"}
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            }
            capturedBody = try? JSONSerialization.jsonObject(with: request.capturedBodyData() ?? Data()) as? [String: Any]
            let body = """
            {"presetOptionId":null,"presetLabel":null,"presetEmoji":null,"customText":null}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        let viewModel = makeViewModel()
        await viewModel.loadInitialData()
        await viewModel.clearStatus()

        XCTAssertNil(viewModel.currentStatus?.displayText)
        XCTAssertTrue(capturedBody?["presetOptionId"] is NSNull)
        XCTAssertTrue(capturedBody?["customText"] is NSNull)
    }
}

private extension URLRequest {
    /// Once a request passes through a custom URLProtocol, the URL loading
    /// system sometimes moves the body into httpBodyStream and leaves
    /// httpBody nil — fall back to draining the stream so tests can
    /// reliably inspect what was actually sent either way.
    func capturedBodyData() -> Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
