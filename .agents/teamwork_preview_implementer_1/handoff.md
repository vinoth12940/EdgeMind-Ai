# Documentation Freshness & Synchronization Engine - Handoff

## Overview
Built an automated documentation synchronization and freshness validation engine for Edge Mind Ai so that any future code, catalog, or version change must update documentation with zero stale details.

## Deliverables

### 1. Python Freshness Verification Engine (`scripts/verify_docs_freshness.py`)
- Executable Python 3 verification script with zero external dependencies.
- Extracts ground-truth state:
  - Model catalog count and runtime distribution from `EdgeMindAi/State/MockCatalogData.swift` (46 total: 25 MLX, 18 GGUF, 2 LiteRT-LM, 1 FoundationModels).
  - Stable namespaced UUID v5 generation using `UUID("A1B2C3D4-E5F6-7890-ABCD-EF1234567890")`.
  - Project version and build number from `project.yml` (`MARKETING_VERSION: 0.3.0`, `CURRENT_PROJECT_VERSION: 6`).
  - Unit test counts and file metrics across Swift codebase (315 XCTest cases, 102 Swift files, 10 AI Labs, 4 Search providers).
- Validates 100% synchronization:
  - Catalog <-> `RuntimeProfiles.json` (zero un-profiled items, zero stale profile UUIDs).
  - Version consistency across `project.yml`, `AGENTS.md`, `APP_STORE_LISTING.md`, `docs/runtime-evaluation.md`.
  - Catalog counts across `README.md`, `AGENTS.md`, `APP_STORE_LISTING.md`, and `APP_STORE_REVIEW_NOTES.md`.
  - Codebase metrics table in `README.md`.
- Returns exit code 0 on success, exit code 1 with descriptive error messages on failure.

### 2. XCTest Unit Test Suite (`EdgeMindAiTests/DocumentationFreshnessTests.swift`)
- Swift XCTest suite validating the exact same freshness invariants natively inside Xcode/CI:
  - `test_catalogItems_matchRuntimeProfilesExactly_zeroUnprofiledZeroStale()`
  - `test_catalogCountAndRuntimeDistribution_matchesREADME()`
  - `test_catalogCount_matchesAGENTS_APPSTORE_REVIEWNOTES()`
  - `test_projectYMLVersion_matchesAGENTS_APPSTORE_docs()`
  - `test_codebaseMetricsInREADME_areAccurate()`
- All 5 test cases pass cleanly in `xcodebuild test`.

### 3. Developer Guidance & Workflow Rules (`AGENTS.md`, `CLAUDE.md`)
- `AGENTS.md`:
  - Added documentation freshness verification command to `Build & Test Commands`.
  - Added Step 7 to `Adding a New Model to the Catalog` checklist enforcing freshness check before commits.
  - Aligned model catalog entry count to exact 46 models.
- `CLAUDE.md`:
  - Added freshness verification script and test command to `Build & Test`.
  - Added workflow rule to `When editing common things` checklist.

### 4. Repository Cleanliness & Parity
- `APP_STORE_REVIEW_NOTES.md`: added explicit catalog count of 46 models.
- `README.md`: updated Swift file count (`~102`) and unit test count (`315 XCTest test cases`).
- `EdgeMindAi.xcodeproj`: regenerated via `xcodegen generate`.
- `python3 scripts/verify_docs_freshness.py`: passes with 22/22 checks, 0 warnings, 0 errors.

## Verification Record
- **Python Verification Script**:
  - Command: `python3 scripts/verify_docs_freshness.py -v`
  - Result: 22 passed checks, 0 warnings, 0 errors (Exit code 0).
- **Unit Test Execution**:
  - Command: `xcodebuild test -project EdgeMindAi.xcodeproj -scheme EdgeMindAi -destination 'platform=iOS Simulator,name=LocalAI iPhone 17 Pro' -only-testing EdgeMindAiTests/DocumentationFreshnessTests`
  - Result: 5 tests executed, 0 failures, TEST SUCCEEDED.
  - Combined suite (`CatalogConsistencyTests`, `DocumentationFreshnessTests`, `RuntimeProfileTests`): 25 tests executed, 0 failures, TEST SUCCEEDED.
- **Negative / Failure Injection Testing**:
  1. Injected catalog count mismatch (46 -> 99 in `README.md`):
     - `verify_docs_freshness.py` caught: `README.md intro catalog count mismatch: stated 99 vs actual 46` (Exit code 1).
     - `DocumentationFreshnessTests` failed with: `XCTAssertTrue failed - README.md intro does not reflect current catalog count of 46`.
  2. Injected version mismatch (0.3.0 -> 0.4.0 in `APP_STORE_LISTING.md`):
     - `verify_docs_freshness.py` caught: `APP_STORE_LISTING.md header version mismatch: 0.4.0 vs 0.3.0` (Exit code 1).
  3. Injected stale runtime profile UUID into `RuntimeProfiles.json`:
     - `verify_docs_freshness.py` caught: `Stale profile found in RuntimeProfiles.json for removed catalog ID: 00000000-0000-0000-0000-000000000000` and `Count mismatch: 46 catalog items vs 47 profiles` (Exit code 1).
