# Reviewer Test Plan: Documentation Freshness & Synchronization Engine

## Objectives
1. Understand the exact requirements from <original_task> independently:
   - R1: Automated doc freshness checker script (scripts/verify_docs_freshness.py) & unit test (EdgeMindAiTests/DocumentationFreshnessTests.swift).
     - Validates model catalog count and runtime distribution in MockCatalogData.swift matches all documented counts across README.md, AGENTS.md, APP_STORE_LISTING.md, and APP_STORE_REVIEW_NOTES.md.
     - Validates project.yml version (MARKETING_VERSION: 0.3.0, CURRENT_PROJECT_VERSION: 6) matches version references in AGENTS.md and APP_STORE_LISTING.md.
     - Validates 100% synchronization of catalog items with RuntimeProfiles.json (zero un-profiled catalog entries, zero stale profile UUIDs).
     - Validates that test counts and file metrics in README.md remain accurate.
   - R2: Developer instructions & pre-commit/workflow rules in AGENTS.md and CLAUDE.md:
     - Workflow checklist updated: whenever MockCatalogData.swift, project.yml, or runtime profiles change, run freshness verification before committing.
     - Document exact commands: python3 scripts/verify_docs_freshness.py and xcodebuild test -only-testing EdgeMindAiTests/DocumentationFreshnessTests.
   - R3: Repository Cleanliness & Doc Parity:
     - Ensure ALL current documentation files (AGENTS.md, README.md, CLAUDE.md, APP_STORE_LISTING.md, APP_STORE_REVIEW_NOTES.md, docs/product.md, docs/runtime-evaluation.md) pass the freshness check with 0 warnings and 0 errors.

## Adversarial Attacks & Breaking Strategy
1. R3 Coverage Gap Analysis:
   - Check docs/product.md and docs/runtime-evaluation.md. Are all numbers/versions in them verified?
   - What about docs/privacy.html?
2. Catalog Parser Robustness & Precision
3. Version & Build Number Parsing Across all docs
4. Simulator / Destination Consistency
5. Negative Injections
