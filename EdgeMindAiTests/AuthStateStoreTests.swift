import XCTest
@testable import EdgeMindAi

@MainActor
final class AuthStateStoreTests: XCTestCase {
    private let profileKey = "persistedAuthProfile"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: profileKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: profileKey)
        super.tearDown()
    }

    func test_freshStoreStartsAsAnonymousGuest() {
        let store = AuthStateStore()

        XCTAssertTrue(store.isAuthenticated)
        XCTAssertEqual(store.profile?.authMethod, .guest)
        XCTAssertEqual(store.profile?.displayName, "Guest")
    }

    func test_signOutResetsToAnonymousGuestInsteadOfBlockingLaunch() {
        let store = AuthStateStore()
        store.signInWithCredentials(displayName: "Apple Reviewer", email: "")

        XCTAssertEqual(store.profile?.authMethod, .credentials)

        store.signOut()

        XCTAssertTrue(store.isAuthenticated)
        XCTAssertEqual(store.profile?.authMethod, .guest)
        XCTAssertEqual(store.profile?.displayName, "Guest")
    }
}
