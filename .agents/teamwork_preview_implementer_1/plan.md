# Implementation Plan - Documentation Freshness Engine

## Goal
Build an automated documentation synchronization and freshness validation engine for Edge Mind Ai.

## Key Requirements
1. `scripts/verify_docs_freshness.py`: Python verification script.
2. `EdgeMindAiTests/DocumentationFreshnessTests.swift`: XCTest unit test suite.
3. Update `AGENTS.md` and `CLAUDE.md` with developer freshness verification workflow.
4. Audit & update all docs (`README.md`, `AGENTS.md`, `CLAUDE.md`, `APP_STORE_LISTING.md`, `APP_STORE_REVIEW_NOTES.md`, `docs/product.md`, `docs/runtime-evaluation.md`) so all checks pass with 0 errors / 0 warnings.
5. Verification: run script, run XCTest unit tests, verify failure injection detection.

## Steps
1. Inspect ground truth:
   - `EdgeMindAi/State/MockCatalogData.swift`: extract catalog item count, runtime distribution, names/IDs.
   - `EdgeMindAi/Resources/RuntimeProfiles.json`: inspect structure, profile keys/UUIDs, ensure 1:1 mapping with catalog IDs.
   - `project.yml`: parse `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
   - Test files / test suite: inspect tests in `EdgeMindAiTests/`.
   - Documented references:
     - `README.md`
     - `AGENTS.md`
     - `APP_STORE_LISTING.md`
     - `APP_STORE_REVIEW_NOTES.md`
     - `docs/product.md`
     - `docs/runtime-evaluation.md`
2. Implement `scripts/verify_docs_freshness.py`:
   - Comprehensive checks with clear failure messages.
   - CLI flags / exit code 0 on success, >0 on failure.
3. Implement `EdgeMindAiTests/DocumentationFreshnessTests.swift`:
   - Swift XCTest verifying the same invariants in Xcode unit testing.
   - Update `project.yml` if needed and regenerate with `xcodegen generate`.
4. Update `AGENTS.md` and `CLAUDE.md`.
5. Audit and update all docs to ensure 100% freshness and 0 errors.
6. Verify script and test suite. Run failure injection tests.
7. Write handoff.md and report.
