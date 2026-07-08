import XCTest
@testable import EdgeMindAi

final class AppSettingsTests: XCTestCase {
    func testDefaultSettingsKeepWebSearchOptIn() {
        XCTAssertFalse(AppSettings.default.useSearchByDefault)
        XCTAssertEqual(AppSettings.default.webSearchProvider, .none)
        XCTAssertNil(AppSettings.default.searchGatewayURL)
    }

    func testDecodingLegacySettingsDefaultsAppearanceToSystem() throws {
        let legacyJSON = """
        {
          "systemPrompt": "Legacy prompt",
          "privacyModeEnabled": true,
          "useSearchByDefault": false,
          "voiceModeEnabled": false,
          "voiceModel": "Kokoro 82M",
          "voicePreset": "Balanced",
          "autoPlayVoiceResponses": false,
          "voiceResponseRate": 1.0,
          "webSearchProvider": "None",
          "webSearchAPIKey": "",
          "huggingFaceToken": "",
          "streamProcessorV2Enabled": true,
          "inferenceV2Timeout": 15
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)

        XCTAssertEqual(settings.appearanceMode, .system)
    }

    func testAppearanceModeRoundTripsThroughSettingsEncoding() throws {
        var settings = AppSettings.default
        settings.appearanceMode = .light

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.appearanceMode, .light)
    }
}
