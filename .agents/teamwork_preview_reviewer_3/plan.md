# Round 3 Adversarial Review Plan

## Objective
Thoroughly audit, challenge, and break the Round 2 implementation of the documentation synchronization and freshness validation engine for Edge Mind Ai. Fix any latent defects, robustness weaknesses, path/invocation flaws, or unverified documentation parity claims. Ensure 100% adherence to all task requirements.

## Step 1: Independent Requirement Analysis
- Understand R1, R2, R3 independent of prior reviewer reports.
- Catalog ground truth state across MockCatalogData.swift, RuntimeProfiles.json, project.yml, test suites, search providers, input modes, tiers.

## Step 2: Codebase & Script Inspection (Attack Phase)
- Test script invocation from different CWDs: root, scripts/, subdirectories, arbitrary absolute paths.
- Test CLI flags: -v, --verbose, --help, unrecognized flags, exit codes.
- Inspect scripts/verify_docs_freshness.py:
  - Are regex patterns brittle?
  - Does it handle edge cases in catalog parsing (multiline comments, string literals with parenthesis, trailing commas, custom formatting)?
  - Does it check all files: README.md, AGENTS.md, APP_STORE_LISTING.md, APP_STORE_REVIEW_NOTES.md, CLAUDE.md, docs/product.md, docs/runtime-evaluation.md?
  - Are all metrics in README verified (chat models, runtimes, search providers, labs, unit tests, files, LOC)?
  - Are versions and build numbers verified consistently across all references?
- Inspect EdgeMindAiTests/DocumentationFreshnessTests.swift:
  - Does the test mirror the Python script's checks?
  - How does it find the repository root in CI/Xcode environment?
  - Does it test catalog count, runtime distribution, versions, runtime profiles sync, README metrics?
  - Are there any edge case failures or missing validations?
- Inspect documentation files for any subtle stale details.

## Step 3: Run Baseline Verification & Probing
- Run Python verification script directly and with various flags/CWDs.
- Run XCTest suite (DocumentationFreshnessTests and full suite).
- Run negative injection tests:
  - Intentionally desynchronize counts, versions, profiles, doc text to verify loud and descriptive failures.

## Step 4: Fix Identified Flaws
- Apply precise fixes to scripts/verify_docs_freshness.py, DocumentationFreshnessTests.swift, or documentation files.
- Regenerate Xcode project if needed (xcodegen generate).

## Step 5: Final Re-Verification & Handoff
- Re-run all test suites and negative injection tests.
- Produce handoff.md and send completion report to parent.
