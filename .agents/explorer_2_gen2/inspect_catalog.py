import json
import re
import uuid

NAMESPACE_MODEL_CATALOG = uuid.UUID("A1B2C3D4-E5F6-7890-ABCD-EF1234567890")

def deterministic_id(display_name, variant):
    name = f"{display_name}::{variant}"
    return str(uuid.uuid5(NAMESPACE_MODEL_CATALOG, name)).upper()

with open("EdgeMindAi/State/MockCatalogData.swift", "r") as f:
    catalog_text = f.read()

with open("EdgeMindAi/Resources/RuntimeProfiles.json", "r") as f:
    profiles_data = json.load(f)

profiles_by_id = {p["catalogID"].upper(): p for p in profiles_data}

# Parse ModelCatalogItem blocks
pattern = re.compile(r'ModelCatalogItem\s*\((.*?)\n\s*\)', re.DOTALL)
matches = pattern.findall(catalog_text)

items = []
for idx, m in enumerate(matches):
    item = {"index": idx}
    
    id_match = re.search(r'id:\s*UUID\(uuidString:\s*"([^"]+)"\)', m)
    item["explicit_id"] = id_match.group(1).upper() if id_match else None
    
    name_match = re.search(r'displayName:\s*"([^"]+)"', m)
    item["displayName"] = name_match.group(1) if name_match else "UNKNOWN"
    
    variant_match = re.search(r'variant:\s*"([^"]+)"', m)
    item["variant"] = variant_match.group(1) if variant_match else "UNKNOWN"
    
    family_match = re.search(r'family:\s*\.([a-zA-Z0-9]+)', m)
    item["family"] = family_match.group(1) if family_match else "UNKNOWN"
    
    runtime_match = re.search(r'runtimeType:\s*\.([a-zA-Z0-9]+)', m)
    item["runtimeType"] = runtime_match.group(1) if runtime_match else "gguf"
    
    mlx_match = re.search(r'mlxModelID:\s*"([^"]+)"', m)
    item["mlxModelID"] = mlx_match.group(1) if mlx_match else None
    
    url_match = re.search(r'downloadURL:\s*URL\(string:\s*"([^"]+)"\)', m)
    item["downloadURL"] = url_match.group(1) if url_match else None
    
    param_match = re.search(r'parameterSize:\s*"([^"]+)"', m)
    item["parameterSize"] = param_match.group(1) if param_match else ""
    
    disk_match = re.search(r'diskSize:\s*"([^"]+)"', m)
    item["diskSize"] = disk_match.group(1) if disk_match else ""
    
    ctx_match = re.search(r'contextWindow:\s*"([^"]+)"', m)
    item["contextWindow"] = ctx_match.group(1) if ctx_match else "4K"
    
    tier_match = re.search(r'minimumTier:\s*\.([a-zA-Z0-9]+)', m)
    item["minimumTier"] = tier_match.group(1) if tier_match else "standard"
    
    status_match = re.search(r'runtimeStatus:\s*\.([a-zA-Z0-9]+)', m)
    item["runtimeStatus"] = status_match.group(1) if status_match else None
    
    verdict_match = re.search(r'auditVerdict:\s*\.([a-zA-Z0-9]+)', m)
    item["auditVerdict"] = verdict_match.group(1) if verdict_match else None
    
    primary_use_match = re.search(r'primaryUse:\s*\.([a-zA-Z0-9]+)', m)
    item["primaryUse"] = primary_use_match.group(1) if primary_use_match else "chat"
    
    item["supportsVision"] = "supportsVision: true" in m
    item["sourceSupportsVision"] = "sourceSupportsVision: true" in m
    item["supportsReasoning"] = "supportsReasoning: true" in m
    item["supportsToolCalling"] = "supportsToolCalling: true" in m
    item["isThinkingModel"] = "isThinkingModel: true" in m
    item["recommendedForIPhone"] = "recommendedForIPhone: true" in m
    
    calc_id = deterministic_id(item["displayName"], item["variant"])
    item["computed_id"] = calc_id
    item["effective_id"] = item["explicit_id"] if item["explicit_id"] else calc_id
    
    items.append(item)

print(f"Total catalog items: {len(items)}")
print(f"Total runtime profiles: {len(profiles_data)}")

legacy_targets = [
    "TinyLlama 1.1B Chat (MLX)",
    "TinyLlama 1.1B Chat (GGUF)",
    "StableLM 2 Zephyr 1.6B (MLX)",
    "StableLM 2 Zephyr 1.6B (GGUF)",
    "Gemma 3 270M Instruct (MLX)"
]
print("\n=== Legacy Models Check ===")
for leg in legacy_targets:
    matches_leg = [it for it in items if leg.lower() in it["displayName"].lower()]
    if matches_leg:
        for it in matches_leg:
            print(f"  FOUND LEGACY: index={it['index']}, displayName='{it['displayName']}', variant='{it['variant']}', ID={it['effective_id']}, in_profiles={it['effective_id'] in profiles_by_id}")
    else:
        print(f"  NOT FOUND: '{leg}'")

print("\n=== Other potential legacy models in catalog ===")
for it in items:
    dn = it["displayName"].lower()
    if "tinyllama" in dn or "stablelm" in dn or ("gemma" in dn and "270m" in dn):
        print(f"  Legacy candidate: index={it['index']}, name='{it['displayName']}', variant='{it['variant']}', ID={it['effective_id']}")

print("\n=== Required 2026 Edge Models Check ===")
required_checks = [
    ("Gemma 4 E2B LiteRT-LM", lambda it: "gemma 4 e2b" in it["displayName"].lower() and it["runtimeType"] == "liteRTLM"),
    ("SmolVLM2 500M MLX", lambda it: "smolvlm2" in it["displayName"].lower() and "500m" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
    ("SmolVLM2 2.2B MLX", lambda it: "smolvlm2" in it["displayName"].lower() and "2.2b" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
    ("Qwen 3.5 VL 0.8B MLX", lambda it: "qwen 3.5 vl" in it["displayName"].lower() and "0.8b" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
    ("Qwen 3.5 VL 4B MLX", lambda it: "qwen 3.5 vl" in it["displayName"].lower() and "4b" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
    ("LFM 2.5 VL 1.6B MLX", lambda it: "lfm" in it["displayName"].lower() and "vl" in it["displayName"].lower() and "1.6b" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
    
    ("Qwen 3.5 0.8B MLX", lambda it: "qwen 3.5" in it["displayName"].lower() and "0.8b" in it["displayName"].lower() and it["runtimeType"] == "mlx" and "vl" not in it["displayName"].lower()),
    ("Qwen 3.5 2B MLX", lambda it: "qwen 3.5" in it["displayName"].lower() and "2b" in it["displayName"].lower() and it["runtimeType"] == "mlx" and "vl" not in it["displayName"].lower()),
    ("Qwen 3.5 0.8B GGUF", lambda it: "qwen 3.5" in it["displayName"].lower() and "0.8b" in it["displayName"].lower() and it["runtimeType"] == "gguf" and "vl" not in it["displayName"].lower()),
    ("Qwen 3.5 2B GGUF", lambda it: "qwen 3.5" in it["displayName"].lower() and "2b" in it["displayName"].lower() and it["runtimeType"] == "gguf" and "vl" not in it["displayName"].lower()),
    
    ("Qwen 3 2507 Thinking 0.6B MLX", lambda it: "qwen 3" in it["displayName"].lower() and "0.6b" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
    ("Qwen 3 2507 Thinking 1.7B MLX", lambda it: "qwen 3" in it["displayName"].lower() and "1.7b" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
    ("Qwen 3 2507 Thinking 4B MLX", lambda it: "qwen 3" in it["displayName"].lower() and "4b" in it["displayName"].lower() and "thinking" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
    ("Qwen 3 2507 Thinking 0.6B GGUF", lambda it: "qwen 3" in it["displayName"].lower() and "0.6b" in it["displayName"].lower() and it["runtimeType"] == "gguf"),
    ("Qwen 3 2507 Thinking 1.7B GGUF", lambda it: "qwen 3" in it["displayName"].lower() and "1.7b" in it["displayName"].lower() and it["runtimeType"] == "gguf"),
    ("Qwen 3 2507 Thinking 4B GGUF", lambda it: "qwen 3" in it["displayName"].lower() and "4b" in it["displayName"].lower() and "thinking" in it["displayName"].lower() and it["runtimeType"] == "gguf"),
    
    ("LFM 2.5 350M", lambda it: "lfm" in it["displayName"].lower() and "350m" in it["displayName"].lower()),
    ("LFM 2.5 1.2B Thinking", lambda it: "lfm" in it["displayName"].lower() and "1.2b" in it["displayName"].lower() and "thinking" in it["displayName"].lower()),
    
    ("Granite 3.3 2B MLX", lambda it: "granite 3.3 2b" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
    ("Granite 3.3 2B GGUF", lambda it: "granite 3.3 2b" in it["displayName"].lower() and it["runtimeType"] == "gguf"),
    
    ("Ministral 3 3B MLX", lambda it: "ministral 3 3b" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
    ("Ministral 3 3B GGUF", lambda it: "ministral 3 3b" in it["displayName"].lower() and it["runtimeType"] == "gguf"),
    
    ("DeepSeek R1 Distill Qwen 1.5B MLX", lambda it: "deepseek" in it["displayName"].lower() and "1.5b" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
    ("DeepSeek R1 Distill Qwen 1.5B GGUF", lambda it: "deepseek" in it["displayName"].lower() and "1.5b" in it["displayName"].lower() and it["runtimeType"] == "gguf"),
    
    ("Apple Intelligence", lambda it: it["family"] == "appleIntelligence")
]

for label, predicate in required_checks:
    found = [it for it in items if predicate(it)]
    if found:
        desc = [f"{x['displayName']} [{x['variant']}] ({x['effective_id']})" for x in found]
        print(f"  [OK] {label}: found {len(found)} item(s): {desc}")
    else:
        print(f"  [MISSING] {label}")

print("\n=== Explicit vs Deterministic IDs ===")
explicit_mismatches = []
for it in items:
    if it["explicit_id"]:
        if it["explicit_id"] != it["computed_id"]:
            explicit_mismatches.append((it["displayName"], it["variant"], it["explicit_id"], it["computed_id"]))

print(f"Items with explicit ID != computed UUIDv5: {len(explicit_mismatches)}")
for m in explicit_mismatches:
    print(f"  {m[0]} [{m[1]}]:\n    explicit: {m[2]}\n    computed: {m[3]}")

print("\n=== Profile Sync ===")
missing_profiles = [it for it in items if it["primaryUse"] == "chat" and it["effective_id"] not in profiles_by_id]
print(f"Catalog items missing RuntimeProfile: {len(missing_profiles)}")
for it in missing_profiles:
    print(f"  Missing profile: {it['displayName']} [{it['variant']}] -> ID: {it['effective_id']}")

catalog_ids = set(it["effective_id"] for it in items)
stale_profiles = [p for p in profiles_data if p["catalogID"].upper() not in catalog_ids]
print(f"Stale profiles in RuntimeProfiles.json: {len(stale_profiles)}")
for p in stale_profiles:
    print(f"  Stale profile ID: {p['catalogID']}")
