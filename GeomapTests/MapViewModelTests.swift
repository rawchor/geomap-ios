import XCTest
import CoreLocation
@testable import Geomap

@MainActor
final class MapViewModelTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeViewModel() -> MapViewModel {
        let apiClient = APIClient(
            baseURL: URL(string: "http://localhost:8080")!,
            session: MockURLProtocol.makeSession(),
            tokenProvider: { "test-token" }
        )
        return MapViewModel(apiClient: apiClient)
    }

    func testRefreshPopulatesFriendsAndPostsLocation() async {
        var updateLocationCalled = false
        MockURLProtocol.requestHandler = { request in
            if request.url!.path == "/friends/nearby" {
                let body = """
                [{"userId":"d39ad7d6-d739-4874-b716-ad81ded6a1f5","displayName":"Friend","latitude":1.0,"longitude":2.0,"degree":"FIRST_DEGREE"}]
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            } else {
                updateLocationCalled = true
                XCTAssertEqual(request.url!.path, "/location")
                let body = """
                {"userId":"d39ad7d6-d739-4874-b716-ad81ded6a1f5","latitude":10.0,"longitude":20.0,"updatedAt":"2026-01-01T00:00:00Z"}
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            }
        }

        let viewModel = makeViewModel()
        await viewModel.refresh(
            locationProvider: { CLLocationCoordinate2D(latitude: 10, longitude: 20) },
            onUnauthorized: { XCTFail("Should not be unauthorized") }
        )

        XCTAssertEqual(viewModel.friends.count, 1)
        XCTAssertTrue(viewModel.hasLoadedOnce)
        XCTAssertTrue(updateLocationCalled)
    }

    func testRefreshWithoutLocationSkipsPostingLocation() async {
        var locationEndpointHit = false
        MockURLProtocol.requestHandler = { request in
            if request.url!.path == "/location" { locationEndpointHit = true }
            let body = "[]".data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        let viewModel = makeViewModel()
        await viewModel.refresh(locationProvider: { nil }, onUnauthorized: { XCTFail("Should not be unauthorized") })

        XCTAssertFalse(locationEndpointHit)
        XCTAssertTrue(viewModel.hasLoadedOnce)
    }

    func testRefreshWithUnauthorizedFriendsCallsHandlerAndSkipsLocationPost() async {
        var locationEndpointHit = false
        var unauthorizedCalled = false
        MockURLProtocol.requestHandler = { request in
            if request.url!.path == "/location" { locationEndpointHit = true }
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }

        let viewModel = makeViewModel()
        await viewModel.refresh(
            locationProvider: { CLLocationCoordinate2D(latitude: 1, longitude: 1) },
            onUnauthorized: { unauthorizedCalled = true }
        )

        XCTAssertTrue(unauthorizedCalled)
        XCTAssertFalse(locationEndpointHit)
        XCTAssertFalse(viewModel.hasLoadedOnce)
    }

    func testRefreshWithUnauthorizedLocationPostCallsHandler() async {
        var unauthorizedCalled = false
        MockURLProtocol.requestHandler = { request in
            if request.url!.path == "/friends/nearby" {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, "[]".data(using: .utf8)!)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }

        let viewModel = makeViewModel()
        await viewModel.refresh(
            locationProvider: { CLLocationCoordinate2D(latitude: 1, longitude: 1) },
            onUnauthorized: { unauthorizedCalled = true }
        )

        XCTAssertTrue(unauthorizedCalled)
    }
}
