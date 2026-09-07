#!/usr/bin/env python3
"""
verify_docs_freshness.py - Automated Documentation Freshness & Synchronization Engine for Edge Mind Ai.

Validates that documentation across the repository is 100% in sync with ground-truth code state:
1. Model catalog count and runtime distribution in MockCatalogData.swift matches all documented counts.
2. project.yml version (MARKETING_VERSION and CURRENT_PROJECT_VERSION) matches documented versions.
3. 100% synchronization of catalog items with RuntimeProfiles.json (0 un-profiled entries, 0 stale UUIDs).
4. Unit test counts and file metrics in README.md remain accurate.
5. All docs pass with 0 errors.

Usage:
    python3 scripts/verify_docs_freshness.py [--verbose] [--repo-root PATH]
"""

import argparse
import glob
import json
import os
import re
import sys
import uuid
from collections import Counter
from pathlib import Path

# DeterministicID namespace from DeterministicID.swift
CATALOG_NAMESPACE = uuid.UUID("A1B2C3D4-E5F6-7890-ABCD-EF1234567890")

# Fallback mapping of model families to AI lab names
DEFAULT_FAMILY_LAB_MAP = {
    "gemma": "Google DeepMind",
    "granite": "IBM",
    "llama": "Meta",
    "qwen": "Alibaba Cloud",
    "phi": "Microsoft",
    "mistral": "Mistral AI",
    "deepSeek": "DeepSeek",
    "smolLM": "Hugging Face",
    "smolVLM": "Hugging Face",
    "appleIntelligence": "Apple",
    "lfm": "Liquid AI",
    "stableLM": "Stability AI",
    "openELM": "Apple",
    "tinyLlama": "StatNLP",
    "kokoro": "Hexgrad / MLX Community",
    "mlxCommunity": "MLX Community",
}


class FreshnessChecker:
    def __init__(self, repo_root: Path, verbose: bool = False):
        self.repo_root = repo_root.resolve()
        self.verbose = verbose
        self.errors = []
        self.warnings = []
        self.passes = []

    def log_pass(self, msg: str):
        self.passes.append(msg)
        if self.verbose:
            print(f"  [PASS] {msg}")

    def log_error(self, msg: str):
        self.errors.append(msg)
        print(f"  [FAIL] {msg}", file=sys.stderr)

    def log_warning(self, msg: str):
        self.warnings.append(msg)
        print(f"  [WARN] {msg}", file=sys.stderr)

    def read_file(self, relative_path: str) -> str:
        p = self.repo_root / relative_path
        if not p.is_file():
            self.log_error(f"Missing required file: {relative_path}")
            return ""
        return p.read_text(encoding="utf-8")

    def extract_family_lab_map(self):
        content = self.read_file("EdgeMindAi/Models/ModelCatalogItem.swift")
        lab_map = dict(DEFAULT_FAMILY_LAB_MAP)
        if not content:
            return lab_map

        m_switch = re.search(r'var\s+lab:\s*String\s*\{[^}]*switch\s+self\s*\{([^}]+)\}', content, re.DOTALL)
        if m_switch:
            switch_body = m_switch.group(1)
            cases = re.findall(r'case\s+([^:]+):\s*return\s*"([^"]+)"', switch_body)
            for case_list, lab_name in cases:
                for item in case_list.split(','):
                    k = item.strip().lstrip('.')
                    if k:
                        lab_map[k] = lab_name
        return lab_map

    def extract_catalog_data(self):
        content = self.read_file("EdgeMindAi/State/MockCatalogData.swift")
        if not content:
            return None

        # Strip block comments /* ... */
        clean_content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
        # Filter line comments // ...
        clean_lines = [l for l in clean_content.splitlines() if not l.strip().startswith('//')]
        clean_content = '\n'.join(clean_lines)

        # Split on ModelCatalogItem(
        raw_items = clean_content.split("ModelCatalogItem(")[1:]
        items = []

        for raw in raw_items:
            m_id = re.search(r'id:\s*UUID\(uuidString:\s*"([^"]+)"\)', raw)
            m_name = re.search(r'displayName:\s*"([^"]+)"', raw)
            m_var = re.search(r'variant:\s*"([^"]+)"', raw)
            m_rt = re.search(r'runtimeType:\s*\.([a-zA-Z]+)', raw)
            m_fam = re.search(r'family:\s*\.([a-zA-Z0-9]+)', raw)

            if not m_name or not m_var:
                continue

            display_name = m_name.group(1)
            variant = m_var.group(1)
            runtime_type = m_rt.group(1) if m_rt else "gguf"
            family = m_fam.group(1) if m_fam else "unknown"

            if m_id:
                item_id = uuid.UUID(m_id.group(1))
            else:
                item_id = uuid.uuid5(CATALOG_NAMESPACE, f"{display_name}::{variant}")

            items.append({
                "id": str(item_id).upper(),
                "displayName": display_name,
                "variant": variant,
                "runtimeType": runtime_type,
                "family": family,
            })

        lab_map = self.extract_family_lab_map()
        runtime_counts = Counter(it["runtimeType"] for it in items)
        families = set(it["family"] for it in items)
        labs = set(lab_map.get(f, f) for f in families)

        return {
            "items": items,
            "total_count": len(items),
            "runtime_counts": runtime_counts,
            "catalog_ids": {it["id"] for it in items},
            "labs_count": len(labs),
            "labs": labs,
        }

    def extract_runtime_profiles(self):
        content = self.read_file("EdgeMindAi/Resources/RuntimeProfiles.json")
        if not content:
            return None
        try:
            data = json.loads(content)
            profile_ids = {p["catalogID"].upper() for p in data if "catalogID" in p}
            return {
                "profiles": data,
                "total_count": len(data),
                "profile_ids": profile_ids,
            }
        except Exception as e:
            self.log_error(f"Failed to parse RuntimeProfiles.json: {e}")
            return None

    def extract_project_version(self):
        content = self.read_file("project.yml")
        if not content:
            return None

        m_ver = re.search(r'MARKETING_VERSION:\s*([0-9\.]+)', content)
        m_build = re.search(r'CURRENT_PROJECT_VERSION:\s*([0-9]+)', content)
        m_bundle = re.search(r'PRODUCT_BUNDLE_IDENTIFIER:\s*([a-zA-Z0-9\.\-_]+)', content)
        m_target = re.search(r'deploymentTarget:\s*\n\s*iOS:\s*([0-9\.]+)', content)

        if not m_ver or not m_build:
            self.log_error("Could not extract MARKETING_VERSION or CURRENT_PROJECT_VERSION from project.yml")
            return None

        return {
            "marketing_version": m_ver.group(1),
            "build_number": m_build.group(1),
            "bundle_identifier": m_bundle.group(1) if m_bundle else None,
            "deployment_target": m_target.group(1) if m_target else None,
        }

    def extract_codebase_metrics(self):
        app_files = list(self.repo_root.glob("EdgeMindAi/**/*.swift"))
        test_files = list(self.repo_root.glob("EdgeMindAiTests/**/*.swift"))
        all_swift_files = app_files + test_files

        total_lines = 0
        for f in all_swift_files:
            try:
                with open(f, encoding="utf-8", errors="ignore") as fp:
                    total_lines += sum(1 for _ in fp)
            except Exception:
                pass

        total_unit_tests = 0
        for f in test_files:
            try:
                content = f.read_text(encoding="utf-8", errors="ignore")
                # Strip block comments /* ... */
                no_block = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
                # Ignore single-line comments // ... and private/fileprivate helpers
                clean_lines = [
                    l for l in no_block.splitlines()
                    if not l.strip().startswith('//')
                    and not l.strip().startswith('private')
                    and not l.strip().startswith('fileprivate')
                ]
                clean_code = '\n'.join(clean_lines)
                tests = re.findall(r'(?:^|\n)\s*(?:@\w+\s+)*(?:override\s+)?func\s+test[A-Za-z0-9_]*\s*\(\s*\)', clean_code)
                total_unit_tests += len(tests)
            except Exception:
                pass

        # Extract search providers count dynamically from AppSettings.swift
        search_providers_count = 4
        settings_content = self.read_file("EdgeMindAi/Models/AppSettings.swift")
        if settings_content:
            m_sp = re.search(r'enum\s+WebSearchProvider\s*:\s*[^{]+\{([^}]+)\}', settings_content)
            if m_sp:
                cases = re.findall(r'case\s+([a-zA-Z0-9_]+)', m_sp.group(1))
                active_cases = [c for c in cases if c != "none"]
                if active_cases:
                    search_providers_count = len(active_cases)

        return {
            "total_swift_files": len(all_swift_files),
            "app_swift_files": len(app_files),
            "test_swift_files": len(test_files),
            "total_lines": total_lines,
            "total_unit_tests": total_unit_tests,
            "search_providers_count": search_providers_count,
        }

    # MARK: - Validation Checks

    def check_runtime_profiles_sync(self, catalog_data, profile_data):
        print("\n--- Validating Catalog <-> RuntimeProfiles.json 100% Sync ---")
        cat_ids = catalog_data["catalog_ids"]
        prof_ids = profile_data["profile_ids"]

        missing_in_profiles = cat_ids - prof_ids
        stale_in_profiles = prof_ids - cat_ids

        if missing_in_profiles:
            for mid in missing_in_profiles:
                item = next((it for it in catalog_data["items"] if it["id"] == mid), None)
                name = item["displayName"] if item else mid
                self.log_error(f"Catalog item un-profiled in RuntimeProfiles.json: {name} (ID: {mid})")
        else:
            self.log_pass(f"All {len(cat_ids)} catalog items are profiled in RuntimeProfiles.json")

        if stale_in_profiles:
            for sid in stale_in_profiles:
                self.log_error(f"Stale profile found in RuntimeProfiles.json for removed catalog ID: {sid}")
        else:
            self.log_pass(f"Zero stale profile entries in RuntimeProfiles.json ({len(prof_ids)} total profiles)")

        if catalog_data["total_count"] != profile_data["total_count"]:
            self.log_error(
                f"Count mismatch: {catalog_data['total_count']} catalog items vs {profile_data['total_count']} profiles"
            )

    def check_project_versions(self, version_data):
        print("\n--- Validating Version & Project Configuration Synchronizations ---")
        ver = version_data["marketing_version"]
        build = version_data["build_number"]
        bundle_id = version_data.get("bundle_identifier")
        min_ios = version_data.get("deployment_target")
        self.log_pass(f"Ground-truth project.yml version: {ver} (build {build})")
        if bundle_id:
            self.log_pass(f"Ground-truth project.yml bundle ID: {bundle_id}")
        if min_ios:
            self.log_pass(f"Ground-truth project.yml min deployment target: iOS {min_ios}")

        # Check AGENTS.md
        agents_content = self.read_file("AGENTS.md")
        if agents_content:
            m_agents = re.search(r'version\s+`?([0-9\.]+)`?,\s+build\s+`?([0-9]+)`?', agents_content)
            if m_agents:
                a_ver, a_build = m_agents.group(1), m_agents.group(2)
                if a_ver == ver and a_build == build:
                    self.log_pass(f"AGENTS.md App Store state matches version {ver}, build {build}")
                else:
                    self.log_error(f"AGENTS.md version mismatch: states {a_ver} (build {a_build}) but project.yml is {ver} (build {build})")
            else:
                self.log_error("Could not find App Store state version string in AGENTS.md")

            if bundle_id:
                m_a_bundle = re.search(r'\*\*Bundle ID:\*\*\s*`?([a-zA-Z0-9\.\-_]+)`?', agents_content)
                if m_a_bundle:
                    if m_a_bundle.group(1) == bundle_id:
                        self.log_pass(f"AGENTS.md Bundle ID matches '{bundle_id}'")
                    else:
                        self.log_error(f"AGENTS.md Bundle ID mismatch: '{m_a_bundle.group(1)}' vs '{bundle_id}'")
                else:
                    self.log_error("Could not find '**Bundle ID:**' in AGENTS.md")

        # Check APP_STORE_LISTING.md
        listing_content = self.read_file("APP_STORE_LISTING.md")
        if listing_content:
            # Header check: version 0.3.0
            m_list_head = re.search(r'\(version\s+([0-9\.]+)\)', listing_content)
            if m_list_head:
                l_ver = m_list_head.group(1)
                if l_ver == ver:
                    self.log_pass(f"APP_STORE_LISTING.md header matches version {ver}")
                else:
                    self.log_error(f"APP_STORE_LISTING.md header version mismatch: {l_ver} vs {ver}")
            else:
                self.log_error("Could not find '(version X.X.X)' in APP_STORE_LISTING.md header")

            # Build check: Build 0.3.0 (6)
            m_list_build = re.search(r'Build\s+([0-9\.]+)\s+\(([0-9]+)\)', listing_content)
            if m_list_build:
                lb_ver, lb_build = m_list_build.group(1), m_list_build.group(2)
                if lb_ver == ver and lb_build == build:
                    self.log_pass(f"APP_STORE_LISTING.md checklist matches Build {ver} ({build})")
                else:
                    self.log_error(f"APP_STORE_LISTING.md checklist build mismatch: Build {lb_ver} ({lb_build}) vs Build {ver} ({build})")
            else:
                self.log_error("Could not find 'Build X.X.X (N)' in APP_STORE_LISTING.md checklist")

            # Next version submission command approval text
            m_apprv = re.search(r'Once\s+([0-9\.]+)\s+is\s+approved', listing_content)
            if m_apprv:
                apprv_ver = m_apprv.group(1)
                if apprv_ver == ver:
                    self.log_pass(f"APP_STORE_LISTING.md next-version approval text matches version {ver}")
                else:
                    self.log_error(f"APP_STORE_LISTING.md next-version approval text mismatch: {apprv_ver} vs {ver}")
            else:
                self.log_error("Could not find 'Once X.X.X is approved' in APP_STORE_LISTING.md")

            if bundle_id:
                m_l_bundle = re.search(r'\|\s*\*\*Bundle ID\*\*\s*\|\s*`?([a-zA-Z0-9\.\-_]+)`?', listing_content)
                if m_l_bundle:
                    if m_l_bundle.group(1) == bundle_id:
                        self.log_pass(f"APP_STORE_LISTING.md Bundle ID matches '{bundle_id}'")
                    else:
                        self.log_error(f"APP_STORE_LISTING.md Bundle ID mismatch: '{m_l_bundle.group(1)}' vs '{bundle_id}'")
                else:
                    self.log_error("Could not find '| **Bundle ID** |' in APP_STORE_LISTING.md")

        # Check docs/runtime-evaluation.md
        rt_content = self.read_file("docs/runtime-evaluation.md")
        if rt_content:
            m_rt_ver = re.search(r'Status:\s*Validated\s*&\s*In\s*Production\s*\(v([0-9\.]+)\)', rt_content)
            if m_rt_ver:
                rt_ver = m_rt_ver.group(1)
                if rt_ver == ver:
                    self.log_pass(f"docs/runtime-evaluation.md status matches version v{ver}")
                else:
                    self.log_error(f"docs/runtime-evaluation.md status version mismatch: v{rt_ver} vs v{ver}")
            else:
                self.log_error("Could not find 'Status: Validated & In Production (vX.X.X)' in docs/runtime-evaluation.md")

        # Check README.md project settings
        readme_content = self.read_file("README.md")
        if readme_content:
            if bundle_id:
                m_r_bundle = re.search(r'\|\s*Bundle ID\s*\|\s*`?([a-zA-Z0-9\.\-_]+)`?\s*\|', readme_content)
                if m_r_bundle:
                    if m_r_bundle.group(1) == bundle_id:
                        self.log_pass(f"README.md Bundle ID matches '{bundle_id}'")
                    else:
                        self.log_error(f"README.md Bundle ID mismatch: '{m_r_bundle.group(1)}' vs '{bundle_id}'")
                else:
                    self.log_error("Could not find '| Bundle ID |' in README.md")

            if min_ios:
                m_r_target = re.search(r'\|\s*Min deployment target\s*\|\s*iOS\s+([0-9\.]+)\s*\|', readme_content)
                if m_r_target:
                    if m_r_target.group(1) == min_ios:
                        self.log_pass(f"README.md Min deployment target matches 'iOS {min_ios}'")
                    else:
                        self.log_error(f"README.md Min deployment target mismatch: 'iOS {m_r_target.group(1)}' vs 'iOS {min_ios}'")
                else:
                    self.log_error("Could not find '| Min deployment target |' in README.md")

    def check_catalog_counts_and_runtimes(self, catalog_data):
        print("\n--- Validating Model Catalog Counts & Runtime Distributions ---")
        total = catalog_data["total_count"]
        gguf = catalog_data["runtime_counts"].get("gguf", 0)
        mlx = catalog_data["runtime_counts"].get("mlx", 0)
        litert = catalog_data["runtime_counts"].get("liteRTLM", 0)
        foundation = catalog_data["runtime_counts"].get("foundationModels", 0)

        self.log_pass(f"Ground-truth catalog count: {total} (MLX: {mlx}, GGUF: {gguf}, LiteRT-LM: {litert}, Foundation: {foundation})")

        # Validate that the 4 known runtimes completely partition the catalog
        runtime_sum = gguf + mlx + litert + foundation
        if runtime_sum != total:
            self.log_error(f"Runtime partition mismatch: sum of runtimes ({runtime_sum}) does not equal total catalog count ({total})")
        else:
            self.log_pass(f"Runtimes completely partition catalog: {runtime_sum} == {total}")

        # 1. README.md
        readme = self.read_file("README.md")
        if readme:
            # Summary intro
            m_intro = re.search(r'curated\s+chat\s+catalog\s+of\s+(\d+)\s+runtime-backed\s+models', readme)
            if m_intro:
                val = int(m_intro.group(1))
                if val == total:
                    self.log_pass(f"README.md intro catalog count matches {total}")
                else:
                    self.log_error(f"README.md intro catalog count mismatch: stated {val} vs actual {total}")
            else:
                self.log_error("Could not find 'curated chat catalog of <N> runtime-backed models' in README.md")

            # Highlights list
            m_hl = re.search(r'-\s+\*\*(\d+)\s+chat\s+models\*\*\s+across', readme)
            if m_hl:
                val = int(m_hl.group(1))
                if val == total:
                    self.log_pass(f"README.md highlights catalog count matches {total}")
                else:
                    self.log_error(f"README.md highlights catalog count mismatch: stated {val} vs actual {total}")
            else:
                self.log_error("Could not find '- **<N> chat models** across' in README.md")

            # Highlights runtime distribution bullet
            m_hl_rt = re.search(
                r'-\s+\*\*(\d+)\s+GGUF\s+models\*\*\s+\(llama\.cpp\s+runtime\),\s+\*\*(\d+)\s+MLX\s+models\*\*\s+\(Apple\s+MLX\s+runtime\),\s+\*\*(\d+)\s+LiteRT-LM\s+models\*\*,\s+and\s+\*\*(\d+)\s+Apple\s+Foundation\s+Models\s+entry\*\*',
                readme,
            )
            if m_hl_rt:
                g_val, m_val, l_val, f_val = int(m_hl_rt.group(1)), int(m_hl_rt.group(2)), int(m_hl_rt.group(3)), int(m_hl_rt.group(4))
                if (g_val, m_val, l_val, f_val) == (gguf, mlx, litert, foundation):
                    self.log_pass(f"README.md highlights runtime distribution matches (GGUF: {gguf}, MLX: {mlx}, LiteRT-LM: {litert}, Foundation: {foundation})")
                else:
                    self.log_error(
                        f"README.md highlights runtime distribution mismatch: stated ({g_val}, {m_val}, {l_val}, {f_val}) vs actual ({gguf}, {mlx}, {litert}, {foundation})"
                    )
            else:
                self.log_error("Could not find '- **<N> GGUF models** ..., **<N> MLX models** ...' in README.md")

            # Table rows
            table_checks = [
                (r'\|\s*Model catalog entries\s*\|\s*(\d+)\s*\|', total, "Model catalog entries"),
                (r'\|\s*GGUF models\s*\|\s*(\d+)\s*\|', gguf, "GGUF models"),
                (r'\|\s*MLX models\s*\|\s*(\d+)\s*\|', mlx, "MLX models"),
                (r'\|\s*LiteRT-LM models\s*\|\s*(\d+)\s*\|', litert, "LiteRT-LM models"),
                (r'\|\s*Apple Foundation Models\s*\|\s*(\d+)\s*\|', foundation, "Apple Foundation Models"),
            ]
            for pattern, expected, label in table_checks:
                m = re.search(pattern, readme)
                if m:
                    val = int(m.group(1))
                    if val == expected:
                        self.log_pass(f"README.md table '{label}' matches {expected}")
                    else:
                        self.log_error(f"README.md table '{label}' mismatch: stated {val} vs actual {expected}")
                else:
                    self.log_error(f"README.md table '{label}' row not found")

        # 2. AGENTS.md
        agents = self.read_file("AGENTS.md")
        if agents:
            m_cat = re.search(r'currently\s*~?(\d+)\s*(?:entries|models)\s*spanning', agents)
            if m_cat:
                val = int(m_cat.group(1))
                if val == total:
                    self.log_pass(f"AGENTS.md catalog count matches {total}")
                else:
                    self.log_error(f"AGENTS.md catalog count mismatch: stated {val} vs actual {total}")
            else:
                self.log_error("Could not find 'currently ~?<N> entries spanning' in AGENTS.md")

        # 3. APP_STORE_LISTING.md
        listing = self.read_file("APP_STORE_LISTING.md")
        if listing:
            m_list_desc = re.search(r'curated\s+catalog\s+of\s+(\d+)\s+open\s+models', listing)
            if m_list_desc:
                val = int(m_list_desc.group(1))
                if val == total:
                    self.log_pass(f"APP_STORE_LISTING.md description catalog count matches {total}")
                else:
                    self.log_error(f"APP_STORE_LISTING.md description count mismatch: stated {val} vs actual {total}")
            else:
                self.log_error("Could not find 'curated catalog of <N> open models' in APP_STORE_LISTING.md")

            m_list_models = re.search(r'curated\s+catalog\s+of\s+(\d+)\s+local\s+models', listing)
            if m_list_models:
                val = int(m_list_models.group(1))
                if val == total:
                    self.log_pass(f"APP_STORE_LISTING.md models tab catalog count matches {total}")
                else:
                    self.log_error(f"APP_STORE_LISTING.md models tab count mismatch: stated {val} vs actual {total}")
            else:
                self.log_error("Could not find 'curated catalog of <N> local models' in APP_STORE_LISTING.md")

        # 4. APP_STORE_REVIEW_NOTES.md
        review_notes = self.read_file("APP_STORE_REVIEW_NOTES.md")
        if review_notes:
            m_rev = re.search(r'curated,\s*device-audited\s+catalog\s+of\s+(\d+)\s+models\s+only', review_notes)
            if m_rev:
                val = int(m_rev.group(1))
                if val == total:
                    self.log_pass(f"APP_STORE_REVIEW_NOTES.md catalog count matches {total}")
                else:
                    self.log_error(f"APP_STORE_REVIEW_NOTES.md count mismatch: stated {val} vs actual {total}")
            else:
                # If phrase is without count, flag to ensure precision
                m_plain = re.search(r'curated,\s*device-audited\s+catalog\s+only', review_notes)
                if m_plain:
                    self.log_error(
                        f"APP_STORE_REVIEW_NOTES.md missing explicit catalog count: expected 'curated, device-audited catalog of {total} models only'"
                    )
                else:
                    self.log_error("Could not find catalog description in APP_STORE_REVIEW_NOTES.md")

    def check_codebase_metrics(self, metrics_data, catalog_data):
        print("\n--- Validating README.md Codebase Metrics ---")
        readme = self.read_file("README.md")
        if not readme:
            return

        # Unit tests count
        actual_tests = metrics_data["total_unit_tests"]
        m_tests = re.search(r'\|\s*Unit tests\s*\|\s*(\d+)\s+XCTest\s+test\s+cases', readme)
        if m_tests:
            val = int(m_tests.group(1))
            if val == actual_tests:
                self.log_pass(f"README.md unit test count matches {actual_tests}")
            else:
                self.log_error(f"README.md unit test count mismatch: stated {val} vs actual {actual_tests}")
        else:
            self.log_error("Could not find '| Unit tests | <N> XCTest test cases' in README.md")

        # Swift files count
        actual_files = metrics_data["total_swift_files"]
        m_files = re.search(r'\|\s*Swift files\s*\|\s*~?(\d+)\s*\|', readme)
        if m_files:
            val = int(m_files.group(1))
            if abs(val - actual_files) <= 1:
                self.log_pass(f"README.md Swift files count (~{val}) is within tolerance of actual {actual_files}")
            else:
                self.log_error(f"README.md Swift files count mismatch: stated ~{val} vs actual {actual_files}")
        else:
            self.log_error("Could not find '| Swift files | ~<N> |' in README.md")

        # Lines of code count
        actual_lines = metrics_data["total_lines"]
        m_loc = re.search(r'\|\s*Lines of code\s*\|\s*~?([0-9,]+)\s*\|', readme)
        if m_loc:
            doc_loc = int(m_loc.group(1).replace(",", ""))
            if abs(doc_loc - actual_lines) <= 2500:
                self.log_pass(f"README.md Lines of code (~{doc_loc:,}) is within tolerance of actual {actual_lines:,}")
            else:
                self.log_error(f"README.md Lines of code drifted significantly: stated ~{doc_loc:,} vs actual {actual_lines:,}")
        else:
            self.log_error("Could not find '| Lines of code | ~<N> |' in README.md")

        # AI Labs count
        actual_labs = catalog_data["labs_count"]
        m_labs = re.search(r'\|\s*AI Labs\s*\|\s*(\d+)\s*\|', readme)
        if m_labs:
            val = int(m_labs.group(1))
            if val == actual_labs:
                self.log_pass(f"README.md AI Labs count matches {actual_labs}")
            else:
                self.log_error(f"README.md AI Labs count mismatch: stated {val} vs actual {actual_labs}")
        else:
            self.log_error("Could not find '| AI Labs | <N> |' in README.md")

        # Search providers count
        actual_sp = metrics_data["search_providers_count"]
        m_sp = re.search(r'\|\s*Search providers\s*\|\s*(\d+)\s*\|', readme)
        if m_sp:
            val = int(m_sp.group(1))
            if val == actual_sp:
                self.log_pass(f"README.md Search providers count matches {actual_sp}")
            else:
                self.log_error(f"README.md Search providers count mismatch: stated {val} vs actual {actual_sp}")
        else:
            self.log_error("Could not find '| Search providers | <N> |' in README.md")

    def check_runtime_architecture_docs(self, catalog_data):
        print("\n--- Validating Runtime Architecture Across All Docs (R2 & R3) ---")

        # 1. docs/product.md
        product_content = self.read_file("docs/product.md")
        if product_content:
            m_prod = re.search(
                r'across\s+four\s+runtimes\s+\(llama\.cpp\s+GGUF,\s+Apple\s+MLX,\s+LiteRT-LM,\s+and\s+Apple\s+Foundation\s+Models\)',
                product_content,
            )
            if m_prod:
                self.log_pass("docs/product.md accurately documents all 4 runtime backends")
            else:
                self.log_error(
                    "docs/product.md does not match expected 4 runtimes: '(llama.cpp GGUF, Apple MLX, LiteRT-LM, and Apple Foundation Models)'"
                )

        # 2. CLAUDE.md
        claude_content = self.read_file("CLAUDE.md")
        if claude_content:
            m_cl_rt = re.search(
                r'across\s+\*\*four\s+runtimes\*\*\s+—\s+llama\.cpp\s+\(GGUF\),\s+Apple\s+MLX,\s+LiteRT-LM,\s+and\s+Apple\s+Foundation\s+Models',
                claude_content,
            )
            if m_cl_rt:
                self.log_pass("CLAUDE.md accurately documents all 4 runtime backends")
            else:
                self.log_error("CLAUDE.md does not accurately document the 4 runtime backends")

            if "python3 scripts/verify_docs_freshness.py" in claude_content and "EdgeMindAiTests/DocumentationFreshnessTests" in claude_content:
                self.log_pass("CLAUDE.md includes mandatory freshness verification commands")
            else:
                self.log_error("CLAUDE.md is missing mandatory freshness verification commands")

        # 3. docs/runtime-evaluation.md
        rt_content = self.read_file("docs/runtime-evaluation.md")
        if rt_content:
            required_sections = [
                ("llama.cpp (`.gguf`)", "GGUF runtime"),
                ("Apple MLX (`.mlx`)", "MLX runtime"),
                ("LiteRT-LM (`.litertlm`)", "LiteRT-LM runtime"),
                ("Apple Foundation Models (`.foundationModels`)", "Foundation Models runtime"),
            ]
            for sec_text, label in required_sections:
                if sec_text in rt_content:
                    self.log_pass(f"docs/runtime-evaluation.md documents {label}")
                else:
                    self.log_error(f"docs/runtime-evaluation.md missing section for {label}: '{sec_text}'")

        # 4. AGENTS.md
        agents_content = self.read_file("AGENTS.md")
        if agents_content:
            if "python3 scripts/verify_docs_freshness.py" in agents_content and "EdgeMindAiTests/DocumentationFreshnessTests" in agents_content:
                self.log_pass("AGENTS.md includes mandatory freshness verification commands")
            else:
                self.log_error("AGENTS.md is missing mandatory freshness verification commands")

        # 5. README.md
        readme_content = self.read_file("README.md")
        if readme_content:
            m_readme_rt = re.search(
                r'powered\s+by\s+\*\*llama\.cpp\*\*\s+\(GGUF\s+models\),\s+\*\*Apple\s+MLX\*\*\s+\(MLX\s+models\),\s+\*\*LiteRT-LM\*\*,\s+and\s+Apple\s+Foundation\s+Models',
                readme_content,
            )
            if m_readme_rt:
                self.log_pass("README.md accurately documents all 4 runtime backends")
            else:
                self.log_error("README.md does not accurately document the 4 runtime backends")

    def run(self) -> int:
        print("=" * 65)
        print("Edge Mind Ai - Documentation Freshness & Sync Engine")
        print("=" * 65)
        print(f"Repository Root: {self.repo_root}")

        cat_data = self.extract_catalog_data()
        prof_data = self.extract_runtime_profiles()
        ver_data = self.extract_project_version()
        metric_data = self.extract_codebase_metrics()

        if not (cat_data and prof_data and ver_data and metric_data):
            self.log_error("Failed to extract ground-truth codebase data. Aborting.")
            return 1

        self.check_runtime_profiles_sync(cat_data, prof_data)
        self.check_project_versions(ver_data)
        self.check_catalog_counts_and_runtimes(cat_data)
        self.check_codebase_metrics(metric_data, cat_data)
        self.check_runtime_architecture_docs(cat_data)

        print("\n" + "=" * 65)
        print("Freshness Engine Summary:")
        print(f"  Passed Checks : {len(self.passes)}")
        print(f"  Warnings      : {len(self.warnings)}")
        print(f"  Errors/Failed : {len(self.errors)}")
        print("=" * 65)

        if self.errors:
            print("\nVerification FAILED with errors:")
            for err in self.errors:
                print(f"  ❌ {err}")
            return 1

        print("\nAll documentation freshness checks PASSED with 0 errors! ✨")
        return 0


def main():
    parser = argparse.ArgumentParser(description="Verify Edge Mind Ai documentation freshness")
    parser.add_argument("--repo-root", default=None, help="Path to Edge Mind Ai repo root")
    parser.add_argument("--verbose", "-v", action="store_true", help="Print verbose pass messages")
    args = parser.parse_args()

    if args.repo_root:
        repo_root = Path(args.repo_root)
    else:
        # Smart repository root resolution:
        # 1. Current working directory (if project.yml and EdgeMindAi exist here)
        # 2. Parent of current working directory (e.g., if invoked from scripts/)
        # 3. Location relative to this script file (__file__/../../)
        cwd = Path.cwd()
        script_dir = Path(__file__).resolve().parent
        if (cwd / "project.yml").is_file() and (cwd / "EdgeMindAi").is_dir():
            repo_root = cwd
        elif (cwd.parent / "project.yml").is_file() and (cwd.parent / "EdgeMindAi").is_dir():
            repo_root = cwd.parent
        elif (script_dir.parent / "project.yml").is_file() and (script_dir.parent / "EdgeMindAi").is_dir():
            repo_root = script_dir.parent
        else:
            repo_root = cwd

    # If invoked directly pointing to scripts/, step up to repo root
    if repo_root.name == "scripts":
        repo_root = repo_root.parent

    checker = FreshnessChecker(repo_root=repo_root, verbose=args.verbose)
    sys.exit(checker.run())


if __name__ == "__main__":
    main()
