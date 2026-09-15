import XCTest
@testable import Geomap

final class KeychainServiceTests: XCTestCase {
    private let keychain = KeychainService.shared

    override func tearDown() {
        keychain.deleteToken()
        super.tearDown()
    }

    func testSaveAndRetrieveToken() {
        keychain.saveToken("token-one")
        XCTAssertEqual(keychain.getToken(), "token-one")
    }

    func testSavingTwiceOverwritesPreviousToken() {
        keychain.saveToken("token-one")
        keychain.saveToken("token-two")
        XCTAssertEqual(keychain.getToken(), "token-two")
    }

    func testDeleteRemovesToken() {
        keychain.saveToken("token-one")
        keychain.deleteToken()
        XCTAssertNil(keychain.getToken())
    }

    func testGetTokenWithNothingStoredReturnsNil() {
        keychain.deleteToken()
        XCTAssertNil(keychain.getToken())
    }
}
