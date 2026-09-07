// EdgeMindAiTests/DocumentationFreshnessTests.swift
import XCTest
@testable import EdgeMindAi

/// Automated Documentation Freshness & Synchronization Test Suite.
///
/// Validates that repository documentation remains 100% synchronized with the
/// ground-truth codebase state:
/// 1. Catalog item count and runtime distribution in `MockCatalogData.swift`
///    match all documented numbers across `README.md`, `AGENTS.md`, `APP_STORE_LISTING.md`,
///    and `APP_STORE_REVIEW_NOTES.md`.
/// 2. `project.yml` version and build number match references in `AGENTS.md`,
///    `APP_STORE_LISTING.md`, and `docs/runtime-evaluation.md`.
/// 3. Catalog items and `RuntimeProfiles.json` are 100% synchronized (zero un-profiled entries,
///    zero stale profile UUIDs).
/// 4. Unit test counts and file metrics in `README.md` remain accurate.
final class DocumentationFreshnessTests: XCTestCase {

    private var repoRoot: URL {
        let testFileURL = URL(fileURLWithPath: #filePath)
        return testFileURL.deletingLastPathComponent().deletingLastPathComponent()
    }

    private func readFile(_ relativePath: String) throws -> String {
        let fileURL = repoRoot.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            XCTFail("Required file does not exist at path: \(fileURL.path)")
            throw FreshnessError.fileNotFound(relativePath)
        }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func loadRuntimeProfiles() throws -> [RuntimeProfile] {
        let workspaceURL = repoRoot.appendingPathComponent("EdgeMindAi/Resources/RuntimeProfiles.json")
        if FileManager.default.fileExists(atPath: workspaceURL.path) {
            let data = try Data(contentsOf: workspaceURL)
            return try JSONDecoder().decode([RuntimeProfile].self, from: data)
        }
        if let bundleURL = Bundle(for: DocumentationFreshnessTests.self).url(forResource: "RuntimeProfiles", withExtension: "json") {
            let data = try Data(contentsOf: bundleURL)
            return try JSONDecoder().decode([RuntimeProfile].self, from: data)
        }
        throw FreshnessError.fileNotFound("EdgeMindAi/Resources/RuntimeProfiles.json")
    }

    private func extractProjectConfiguration() throws -> (marketingVersion: String, buildNumber: String, bundleIdentifier: String?, deploymentTarget: String?) {
        let content = try readFile("project.yml")
        guard let marketingVersion = content.firstCaptureGroup(for: #"MARKETING_VERSION:\s*([0-9\.]+)"#),
              let buildNumber = content.firstCaptureGroup(for: #"CURRENT_PROJECT_VERSION:\s*([0-9]+)"#) else {
            XCTFail("Could not extract MARKETING_VERSION or CURRENT_PROJECT_VERSION from project.yml")
            throw FreshnessError.patternNotFound
        }
        let bundleIdentifier = content.firstCaptureGroup(for: #"PRODUCT_BUNDLE_IDENTIFIER:\s*([a-zA-Z0-9\.\-_]+)"#)
        let deploymentTarget = content.firstCaptureGroup(for: #"deploymentTarget:\s*\n\s*iOS:\s*([0-9\.]+)"#)
        return (marketingVersion, buildNumber, bundleIdentifier, deploymentTarget)
    }

    private func countAllTestMethods() throws -> Int {
        let fm = FileManager.default
        let testsDir = repoRoot.appendingPathComponent("EdgeMindAiTests")
        guard let enumerator = fm.enumerator(at: testsDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return 0
        }

        var testFileURLs: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "swift" {
                testFileURLs.append(fileURL)
            }
        }

        var totalTests = 0
        let testFuncRegex = try NSRegularExpression(pattern: #"(?:^|\n)\s*(?:@\w+\s+)*(?:override\s+)?func\s+(test[A-Za-z0-9_]*)\s*\(\s*\)"#)
        for fileURL in testFileURLs {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            // Strip block comments /* ... */
            let noBlock = content.replacingOccurrences(of: #"(?s)/\*.*?\*/"#, with: "", options: .regularExpression)
            // Ignore single-line comments // ... and private/fileprivate helpers
            let cleanLines = noBlock.components(separatedBy: .newlines).filter {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("private") && !trimmed.hasPrefix("fileprivate")
            }
            let cleanCode = cleanLines.joined(separator: "\n")
            let nsContent = cleanCode as NSString
            let matches = testFuncRegex.matches(in: cleanCode, range: NSRange(location: 0, length: nsContent.length))
            totalTests += matches.count
        }
        return totalTests
    }

    private func countAllSwiftFilesAndLines() throws -> (appCount: Int, testCount: Int, totalCount: Int, totalLines: Int) {
        let fm = FileManager.default
        let appDir = repoRoot.appendingPathComponent("EdgeMindAi")
        let testsDir = repoRoot.appendingPathComponent("EdgeMindAiTests")

        func swiftFilesIn(directory: URL) -> [URL] {
            guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
            var files: [URL] = []
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "swift" {
                    files.append(fileURL)
                }
            }
            return files
        }

        let appFiles = swiftFilesIn(directory: appDir)
        let testFiles = swiftFilesIn(directory: testsDir)
        let allFiles = appFiles + testFiles

        var totalLines = 0
        for fileURL in allFiles {
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                totalLines += content.components(separatedBy: .newlines).count
            }
        }

        return (appFiles.count, testFiles.count, allFiles.count, totalLines)
    }

    // MARK: - Tests

    /// Invariant: 100% synchronization of catalog items with RuntimeProfiles.json.
    /// Zero un-profiled catalog entries, zero stale profile UUIDs.
    func test_catalogItems_matchRuntimeProfilesExactly_zeroUnprofiledZeroStale() throws {
        let catalogItems = MockCatalogData.items
        let profiles = try loadRuntimeProfiles()

        let catalogIDs = Set(catalogItems.map(\.id))
        let profileIDs = Set(profiles.map(\.catalogID))

        let missingInProfiles = catalogIDs.subtracting(profileIDs)
        let staleInProfiles = profileIDs.subtracting(catalogIDs)

        XCTAssertTrue(
            missingInProfiles.isEmpty,
            "Found un-profiled catalog items in RuntimeProfiles.json: \(missingInProfiles)"
        )
        XCTAssertTrue(
            staleInProfiles.isEmpty,
            "Found stale profiles in RuntimeProfiles.json not matching any catalog item: \(staleInProfiles)"
        )
        XCTAssertEqual(
            catalogItems.count,
            profiles.count,
            "Count mismatch: \(catalogItems.count) catalog items vs \(profiles.count) runtime profiles"
        )
    }

    /// Invariant: Catalog count and runtime distribution in MockCatalogData.swift match README.md.
    func test_catalogCountAndRuntimeDistribution_matchesREADME() throws {
        let catalogItems = MockCatalogData.items
        let totalCount = catalogItems.count
        let ggufCount = catalogItems.filter { $0.runtimeType == .gguf }.count
        let mlxCount = catalogItems.filter { $0.runtimeType == .mlx }.count
        let litertCount = catalogItems.filter { $0.runtimeType == .liteRTLM }.count
        let foundationCount = catalogItems.filter { $0.runtimeType == .foundationModels }.count

        let readme = try readFile("README.md")

        // Intro sentence
        let expectedIntroPattern = #"curated\s+chat\s+catalog\s+of\s+"# + "\(totalCount)" + #"\s+runtime-backed\s+models"#
        XCTAssertTrue(
            readme.matches(pattern: expectedIntroPattern),
            "README.md intro does not reflect current catalog count of \(totalCount)"
        )

        // Highlights list
        let expectedHighlightsPattern = #"-\s+\*\*"# + "\(totalCount)" + #"\s+chat\s+models\*\*\s+across"#
        XCTAssertTrue(
            readme.matches(pattern: expectedHighlightsPattern),
            "README.md highlights list does not reflect current catalog count of \(totalCount)"
        )

        // Highlights runtime distribution bullet
        let expectedHighlightsRT = #"-\s+\*\*"# + "\(ggufCount)" + #"\s+GGUF\s+models\*\*\s+\(llama\.cpp\s+runtime\),\s+\*\*"# + "\(mlxCount)" + #"\s+MLX\s+models\*\*\s+\(Apple\s+MLX\s+runtime\),\s+\*\*"# + "\(litertCount)" + #"\s+LiteRT-LM\s+models\*\*,\s+and\s+\*\*"# + "\(foundationCount)" + #"\s+Apple\s+Foundation\s+Models\s+entry\*\*"#
        XCTAssertTrue(
            readme.matches(pattern: expectedHighlightsRT),
            "README.md highlights runtime distribution bullet does not match (GGUF: \(ggufCount), MLX: \(mlxCount), LiteRT: \(litertCount), Foundation: \(foundationCount))"
        )

        // Runtime completeness partition check
        XCTAssertEqual(
            totalCount,
            ggufCount + mlxCount + litertCount + foundationCount,
            "Runtime distribution must account for 100% of catalog items (\(totalCount) != \(ggufCount)+\(mlxCount)+\(litertCount)+\(foundationCount))"
        )

        // Table rows
        XCTAssertTrue(
            readme.matches(pattern: #"\|\s*Model catalog entries\s*\|\s*"# + "\(totalCount)" + #"\s*\|"#),
            "README.md table 'Model catalog entries' does not match catalog count \(totalCount)"
        )
        XCTAssertTrue(
            readme.matches(pattern: #"\|\s*GGUF models\s*\|\s*"# + "\(ggufCount)" + #"\s*\|"#),
            "README.md table 'GGUF models' does not match count \(ggufCount)"
        )
        XCTAssertTrue(
            readme.matches(pattern: #"\|\s*MLX models\s*\|\s*"# + "\(mlxCount)" + #"\s*\|"#),
            "README.md table 'MLX models' does not match count \(mlxCount)"
        )
        XCTAssertTrue(
            readme.matches(pattern: #"\|\s*LiteRT-LM models\s*\|\s*"# + "\(litertCount)" + #"\s*\|"#),
            "README.md table 'LiteRT-LM models' does not match count \(litertCount)"
        )
        XCTAssertTrue(
            readme.matches(pattern: #"\|\s*Apple Foundation Models\s*\|\s*"# + "\(foundationCount)" + #"\s*\|"#),
            "README.md table 'Apple Foundation Models' does not match count \(foundationCount)"
        )
    }

    /// Invariant: Catalog count matches AGENTS.md, APP_STORE_LISTING.md, and APP_STORE_REVIEW_NOTES.md.
    func test_catalogCount_matchesAGENTS_APPSTORE_REVIEWNOTES() throws {
        let totalCount = MockCatalogData.items.count

        // 1. AGENTS.md
        let agents = try readFile("AGENTS.md")
        let expectedAgentsPattern = #"currently\s*~?"# + "\(totalCount)" + #"\s*(?:entries|models)\s*spanning"#
        XCTAssertTrue(
            agents.matches(pattern: expectedAgentsPattern),
            "AGENTS.md does not document the current catalog count of \(totalCount)"
        )

        // 2. APP_STORE_LISTING.md
        let listing = try readFile("APP_STORE_LISTING.md")
        let expectedListingDesc = #"curated\s+catalog\s+of\s+"# + "\(totalCount)" + #"\s+open\s+models"#
        let expectedListingModels = #"curated\s+catalog\s+of\s+"# + "\(totalCount)" + #"\s+local\s+models"#
        XCTAssertTrue(
            listing.matches(pattern: expectedListingDesc),
            "APP_STORE_LISTING.md description does not document the current catalog count of \(totalCount)"
        )
        XCTAssertTrue(
            listing.matches(pattern: expectedListingModels),
            "APP_STORE_LISTING.md models tab does not document the current catalog count of \(totalCount)"
        )

        // 3. APP_STORE_REVIEW_NOTES.md
        let reviewNotes = try readFile("APP_STORE_REVIEW_NOTES.md")
        let expectedReviewNotes = #"curated,\s*device-audited\s+catalog\s+of\s+"# + "\(totalCount)" + #"\s+models\s+only"#
        XCTAssertTrue(
            reviewNotes.matches(pattern: expectedReviewNotes),
            "APP_STORE_REVIEW_NOTES.md does not document the current catalog count of \(totalCount)"
        )
    }

    /// Invariant: project.yml MARKETING_VERSION, CURRENT_PROJECT_VERSION, PRODUCT_BUNDLE_IDENTIFIER,
    /// and deploymentTarget match references across docs.
    func test_projectYMLVersion_matchesAGENTS_APPSTORE_docs() throws {
        let (version, build, bundleIdentifier, deploymentTarget) = try extractProjectConfiguration()

        // 1. AGENTS.md
        let agents = try readFile("AGENTS.md")
        let expectedAgentsVersion = #"version\s+`?"# + NSRegularExpression.escapedPattern(for: version) + #"`?,\s+build\s+`?"# + build + #"`?"#
        XCTAssertTrue(
            agents.matches(pattern: expectedAgentsVersion),
            "AGENTS.md does not match project.yml version \(version), build \(build)"
        )

        // 2. APP_STORE_LISTING.md
        let listing = try readFile("APP_STORE_LISTING.md")
        let expectedListingHeader = #"\(version\s+"# + NSRegularExpression.escapedPattern(for: version) + #"\)"#
        let expectedListingBuild = #"Build\s+"# + NSRegularExpression.escapedPattern(for: version) + #"\s+\("# + build + #"\)"#
        let expectedApprovalPattern = #"Once\s+"# + NSRegularExpression.escapedPattern(for: version) + #"\s+is\s+approved"#
        XCTAssertTrue(
            listing.matches(pattern: expectedListingHeader),
            "APP_STORE_LISTING.md header does not match version \(version)"
        )
        XCTAssertTrue(
            listing.matches(pattern: expectedListingBuild),
            "APP_STORE_LISTING.md checklist does not match Build \(version) (\(build))"
        )
        XCTAssertTrue(
            listing.matches(pattern: expectedApprovalPattern),
            "APP_STORE_LISTING.md next-version approval text does not match version \(version)"
        )

        // 3. docs/runtime-evaluation.md
        let runtimeEvaluation = try readFile("docs/runtime-evaluation.md")
        let expectedRtVersion = #"Status:\s*Validated\s*&\s*In\s*Production\s*\(v"# + NSRegularExpression.escapedPattern(for: version) + #"\)"#
        XCTAssertTrue(
            runtimeEvaluation.matches(pattern: expectedRtVersion),
            "docs/runtime-evaluation.md does not match version v\(version)"
        )

        // 4. Bundle ID consistency
        if let bundleID = bundleIdentifier {
            let escapedBundleID = NSRegularExpression.escapedPattern(for: bundleID)
            XCTAssertTrue(
                agents.matches(pattern: #"\*\*Bundle ID:\*\*\s*`?"# + escapedBundleID + #"`?"#),
                "AGENTS.md Bundle ID does not match project.yml bundle ID \(bundleID)"
            )
            XCTAssertTrue(
                listing.matches(pattern: #"\|\s*\*\*Bundle ID\*\*\s*\|\s*`?"# + escapedBundleID + #"`?"#),
                "APP_STORE_LISTING.md Bundle ID does not match project.yml bundle ID \(bundleID)"
            )
            let readme = try readFile("README.md")
            XCTAssertTrue(
                readme.matches(pattern: #"\|\s*Bundle ID\s*\|\s*`?"# + escapedBundleID + #"`?\s*\|"#),
                "README.md Bundle ID does not match project.yml bundle ID \(bundleID)"
            )
        }

        // 5. Min deployment target consistency
        if let minIOS = deploymentTarget {
            let readme = try readFile("README.md")
            let escapedMinIOS = NSRegularExpression.escapedPattern(for: minIOS)
            XCTAssertTrue(
                readme.matches(pattern: #"\|\s*Min deployment target\s*\|\s*iOS\s+"# + escapedMinIOS + #"\s*\|"#),
                "README.md Min deployment target does not match project.yml iOS \(minIOS)"
            )
        }
    }

    /// Invariant: Unit test counts and file metrics in README.md remain accurate.
    func test_codebaseMetricsInREADME_areAccurate() throws {
        let readme = try readFile("README.md")

        // 1. Unit tests count
        let actualTestCount = try countAllTestMethods()
        guard let documentedTestsString = readme.firstCaptureGroup(for: #"\|\s*Unit tests\s*\|\s*(\d+)\s+XCTest\s+test\s+cases"#),
              let documentedTestCount = Int(documentedTestsString) else {
            XCTFail("Could not parse Unit tests count row from README.md")
            return
        }
        XCTAssertEqual(
            documentedTestCount,
            actualTestCount,
            "README.md unit test count (\(documentedTestCount)) does not match actual XCTest methods (\(actualTestCount))"
        )

        // 2. Swift files count and Lines of code count
        let (_, _, actualTotalFiles, actualTotalLines) = try countAllSwiftFilesAndLines()
        guard let documentedFilesString = readme.firstCaptureGroup(for: #"\|\s*Swift files\s*\|\s*~?(\d+)\s*\|"#),
              let documentedFileCount = Int(documentedFilesString) else {
            XCTFail("Could not parse Swift files count row from README.md")
            return
        }
        XCTAssertLessThanOrEqual(
            abs(documentedFileCount - actualTotalFiles),
            1,
            "README.md Swift files count (~\(documentedFileCount)) drifted from actual count (\(actualTotalFiles))"
        )

        guard let documentedLOCString = readme.firstCaptureGroup(for: #"\|\s*Lines of code\s*\|\s*~?([0-9,]+)\s*\|"#),
              let documentedLOC = Int(documentedLOCString.replacingOccurrences(of: ",", with: "")) else {
            XCTFail("Could not parse Lines of code count row from README.md")
            return
        }
        XCTAssertLessThanOrEqual(
            abs(documentedLOC - actualTotalLines),
            2500,
            "README.md Lines of code (~\(documentedLOC)) drifted from actual lines (\(actualTotalLines))"
        )

        // 3. AI Labs count
        let uniqueLabs = Set(MockCatalogData.items.map(\.family.lab)).count
        guard let documentedLabsString = readme.firstCaptureGroup(for: #"\|\s*AI Labs\s*\|\s*(\d+)\s*\|"#),
              let documentedLabsCount = Int(documentedLabsString) else {
            XCTFail("Could not parse AI Labs count row from README.md")
            return
        }
        XCTAssertEqual(
            documentedLabsCount,
            uniqueLabs,
            "README.md AI Labs count (\(documentedLabsCount)) does not match actual labs count (\(uniqueLabs))"
        )

        // 4. Search providers count (dynamic from AppSettings)
        let actualSearchProvidersCount = AppSettings.WebSearchProvider.allCases.filter { $0 != .none }.count
        guard let documentedSearchProvidersString = readme.firstCaptureGroup(for: #"\|\s*Search providers\s*\|\s*(\d+)\s*\|"#),
              let documentedSearchProvidersCount = Int(documentedSearchProvidersString) else {
            XCTFail("Could not parse Search providers count row from README.md")
            return
        }
        XCTAssertEqual(
            documentedSearchProvidersCount,
            actualSearchProvidersCount,
            "README.md Search providers count (\(documentedSearchProvidersCount)) does not match actual count (\(actualSearchProvidersCount))"
        )
    }

    /// Invariant: Runtimes and developer freshness rules are consistent across product.md, CLAUDE.md,
    /// runtime-evaluation.md, and AGENTS.md (R2 & R3 compliance).
    func test_runtimeArchitectureConsistencyAcrossAllDocs() throws {
        // 1. docs/product.md
        let product = try readFile("docs/product.md")
        XCTAssertTrue(
            product.matches(pattern: #"across\s+four\s+runtimes\s+\(llama\.cpp\s+GGUF,\s+Apple\s+MLX,\s+LiteRT-LM,\s+and\s+Apple\s+Foundation\s+Models\)"#),
            "docs/product.md does not accurately document the 4 on-device runtimes"
        )

        // 2. CLAUDE.md
        let claude = try readFile("CLAUDE.md")
        XCTAssertTrue(
            claude.matches(pattern: #"across\s+\*\*four\s+runtimes\*\*\s+—\s+llama\.cpp\s+\(GGUF\),\s+Apple\s+MLX,\s+LiteRT-LM,\s+and\s+Apple\s+Foundation\s+Models"#),
            "CLAUDE.md does not accurately document the 4 on-device runtimes"
        )
        XCTAssertTrue(
            claude.contains("python3 scripts/verify_docs_freshness.py"),
            "CLAUDE.md missing python freshness verification command"
        )
        XCTAssertTrue(
            claude.contains("EdgeMindAiTests/DocumentationFreshnessTests"),
            "CLAUDE.md missing DocumentationFreshnessTests command"
        )

        // 3. docs/runtime-evaluation.md
        let runtimeEval = try readFile("docs/runtime-evaluation.md")
        XCTAssertTrue(
            runtimeEval.contains("llama.cpp (`.gguf`)"),
            "docs/runtime-evaluation.md missing GGUF runtime section"
        )
        XCTAssertTrue(
            runtimeEval.contains("Apple MLX (`.mlx`)"),
            "docs/runtime-evaluation.md missing MLX runtime section"
        )
        XCTAssertTrue(
            runtimeEval.contains("LiteRT-LM (`.litertlm`)"),
            "docs/runtime-evaluation.md missing LiteRT-LM runtime section"
        )
        XCTAssertTrue(
            runtimeEval.contains("Apple Foundation Models (`.foundationModels`)"),
            "docs/runtime-evaluation.md missing Apple Foundation Models runtime section"
        )

        // 4. AGENTS.md
        let agents = try readFile("AGENTS.md")
        XCTAssertTrue(
            agents.contains("python3 scripts/verify_docs_freshness.py"),
            "AGENTS.md missing python freshness verification command"
        )
        XCTAssertTrue(
            agents.contains("EdgeMindAiTests/DocumentationFreshnessTests"),
            "AGENTS.md missing DocumentationFreshnessTests command"
        )

        // 5. README.md
        let readme = try readFile("README.md")
        XCTAssertTrue(
            readme.matches(pattern: #"powered\s+by\s+\*\*llama\.cpp\*\*\s+\(GGUF\s+models\),\s+\*\*Apple\s+MLX\*\*\s+\(MLX\s+models\),\s+\*\*LiteRT-LM\*\*,\s+and\s+Apple\s+Foundation\s+Models"#),
            "README.md does not accurately document the 4 on-device runtimes"
        )
    }
}

// MARK: - Helper Types and Extensions

private enum FreshnessError: Error {
    case fileNotFound(String)
    case patternNotFound
    case regexNotFound
}

private extension String {
    func matches(pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let nsString = self as NSString
        let range = NSRange(location: 0, length: nsString.length)
        return regex.firstMatch(in: self, options: [], range: range) != nil
    }

    func firstCaptureGroup(for pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsString = self as NSString
        let range = NSRange(location: 0, length: nsString.length)
        guard let match = regex.firstMatch(in: self, options: [], range: range),
              match.numberOfRanges > 1 else { return nil }
        let captureRange = match.range(at: 1)
        guard captureRange.location != NSNotFound else { return nil }
        return nsString.substring(with: captureRange)
    }
}
