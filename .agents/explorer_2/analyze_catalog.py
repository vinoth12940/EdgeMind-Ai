import json
import re
import uuid

NAMESPACE_MODEL_CATALOG = uuid.UUID("A1B2C3D4-E5F6-7890-ABCD-EF1234567890")

def deterministic_id(display_name, variant):
    name = f"{display_name}::{variant}"
    return str(uuid.uuid5(NAMESPACE_MODEL_CATALOG, name)).upper()

# Read MockCatalogData.swift
with open("EdgeMindAi/State/MockCatalogData.swift", "r") as f:
    catalog_text = f.read()

# Read RuntimeProfiles.json
with open("EdgeMindAi/Resources/RuntimeProfiles.json", "r") as f:
    profiles_data = json.load(f)

profiles_by_id = {p["catalogID"].upper(): p for p in profiles_data}

# Parse ModelCatalogItem blocks
# Matches ModelCatalogItem( ... )
# Let's extract items
pattern = re.compile(r'ModelCatalogItem\s*\((.*?)\n\s*\)', re.DOTALL)
matches = pattern.findall(catalog_text)

items = []
for m in matches:
    # parse fields
    item = {}
    
    id_match = re.search(r'id:\s*UUID\(uuidString:\s*"([^"]+)"\)', m)
    if id_match:
        item["explicit_id"] = id_match.group(1).upper()
    else:
        item["explicit_id"] = None
        
    name_match = re.search(r'displayName:\s*"([^"]+)"', m)
    item["displayName"] = name_match.group(1) if name_match else "UNKNOWN"
    
    variant_match = re.search(r'variant:\s*"([^"]+)"', m)
    item["variant"] = variant_match.group(1) if variant_match else "UNKNOWN"
    
    family_match = re.search(r'family:\s*\.([a-zA-Z0-9]+)', m)
    item["family"] = family_match.group(1) if family_match else "UNKNOWN"
    
    runtime_match = re.search(r'runtimeType:\s*\.([a-zA-Z0-9]+)', m)
    item["runtimeType"] = runtime_match.group(1) if runtime_match else "gguf" # default in init is .gguf
    
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
    
    item["supportsVision"] = "supportsVision: true" in m
    item["sourceSupportsVision"] = "sourceSupportsVision: true" in m or ("sourceSupportsVision: false" not in m and item["supportsVision"])
    item["supportsReasoning"] = "supportsReasoning: true" in m
    item["supportsToolCalling"] = "supportsToolCalling: true" in m
    item["isThinkingModel"] = "isThinkingModel: true" in m
    item["recommendedForIPhone"] = "recommendedForIPhone: true" in m
    
    calc_id = deterministic_id(item["displayName"], item["variant"])
    item["computed_id"] = calc_id
    item["effective_id"] = item["explicit_id"] if item["explicit_id"] else calc_id
    
    items.append(item)

print(f"Total parsed items in MockCatalogData.swift: {len(items)}")
print(f"Total profiles in RuntimeProfiles.json: {len(profiles_data)}")

# Check duplicate IDs in catalog
seen_ids = {}
duplicate_ids = []
for it in items:
    eff = it["effective_id"]
    if eff in seen_ids:
        duplicate_ids.append((eff, it["displayName"], seen_ids[eff]))
    seen_ids[eff] = it["displayName"]

print(f"Duplicate catalog IDs: {len(duplicate_ids)}")
for d in duplicate_ids:
    print(f"  {d}")

# Check missing profiles for catalog items
missing_profiles = []
for it in items:
    eff = it["effective_id"]
    if eff not in profiles_by_id:
        missing_profiles.append((eff, it["displayName"], it["variant"]))

print(f"\nCatalog items missing from RuntimeProfiles.json: {len(missing_profiles)}")
for m in missing_profiles:
    print(f"  ID: {m[0]} | Name: {m[1]} | Variant: {m[2]}")

# Check stale profiles in RuntimeProfiles.json
catalog_id_set = set(it["effective_id"] for it in items)
stale_profiles = []
for p in profiles_data:
    cid = p["catalogID"].upper()
    if cid not in catalog_id_set:
        stale_profiles.append(cid)

print(f"\nStale profiles in RuntimeProfiles.json (not in catalog): {len(stale_profiles)}")
for s in stale_profiles:
    print(f"  {s}")

# Check legacy models
legacy_names = [
    "TinyLlama 1.1B Chat (MLX)",
    "TinyLlama 1.1B Chat (GGUF)",
    "StableLM 2 Zephyr 1.6B (MLX)",
    "StableLM 2 Zephyr 1.6B (GGUF)",
    "Gemma 3 270M Instruct (MLX)"
]
print("\n--- Legacy Models Status ---")
for leg in legacy_names:
    found = [it for it in items if it["displayName"] == leg]
    if found:
        it = found[0]
        eff = it["effective_id"]
        in_prof = eff in profiles_by_id
        print(f"FOUND: '{leg}' | ID: {eff} | Has Profile: {in_prof}")
    else:
        print(f"NOT FOUND: '{leg}'")
