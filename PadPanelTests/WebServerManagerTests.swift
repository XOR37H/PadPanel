import XCTest
import Combine
@testable import PadPanel

final class WebServerManagerTests: XCTestCase {

    private var settings: SettingsManager!
    private static let suiteName = "test.ultrakiosk.webserver"

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.testSuite(name: Self.suiteName)
        settings = SettingsManager(userDefaults: defaults)
    }

    override func tearDown() {
        settings = nil
        UserDefaults.testSuite(name: Self.suiteName).removeSuite(name: Self.suiteName)
        super.tearDown()
    }

    func testWebServerSettings_defaultValues() {
        XCTAssertTrue(settings.enableWebServer)
        XCTAssertEqual(settings.webServerPort, 8080)
        XCTAssertEqual(settings.webServerPassword, "")
    }

    func testWebServerSettings_persistence() {
        settings.enableWebServer = false
        settings.webServerPort = 9090
        settings.webServerPassword = "secretPassword123"
        settings.saveSettings()

        let reloaded = SettingsManager(userDefaults: UserDefaults.testSuite(name: Self.suiteName))
        XCTAssertFalse(reloaded.enableWebServer)
        XCTAssertEqual(reloaded.webServerPort, 9090)
        XCTAssertEqual(reloaded.webServerPassword, "secretPassword123")
    }

    func testWebServerManager_stopClearsErrorAndStatus() {
        let manager = WebServerManager.shared
        manager.stop()

        XCTAssertFalse(manager.isRunning)
        XCTAssertEqual(manager.serverURL, "")
        XCTAssertNil(manager.lastError)
    }
}
