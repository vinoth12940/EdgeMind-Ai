import XCTest
@testable import LocalAIEdgeApp

final class AppSettingsTests: XCTestCase {
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
