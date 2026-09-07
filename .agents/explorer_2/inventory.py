import json
import re

with open("EdgeMindAi/State/MockCatalogData.swift", "r") as f:
    catalog_text = f.read()

with open("EdgeMindAi/Resources/RuntimeProfiles.json", "r") as f:
    profiles_data = json.load(f)

profiles_by_id = {p["catalogID"].upper(): p for p in profiles_data}

# Parse ModelCatalogItem blocks
pattern = re.compile(r'ModelCatalogItem\s*\((.*?)\n\s*\)', re.DOTALL)
matches = pattern.findall(catalog_text)

items = []
for m in matches:
    item = {}
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
    
    item["supportsVision"] = "supportsVision: true" in m
    item["sourceSupportsVision"] = "sourceSupportsVision: true" in m
    item["supportsReasoning"] = "supportsReasoning: true" in m
    item["supportsToolCalling"] = "supportsToolCalling: true" in m
    item["isThinkingModel"] = "isThinkingModel: true" in m
    item["recommendedForIPhone"] = "recommendedForIPhone: true" in m
    
    items.append(item)

# Categorize and print by family
by_family = {}
for it in items:
    by_family.setdefault(it["family"], []).append(it)

for fam, fam_items in sorted(by_family.items()):
    print(f"\n=== Family: {fam} ({len(fam_items)} models) ===")
    for it in fam_items:
        print(f"- {it['displayName']} [{it['variant']}] ({it['runtimeType']})")
        print(f"  params: {it['parameterSize']}, disk: {it['diskSize']}, ctx: {it['contextWindow']}, tier: {it['minimumTier']}")
        flags = []
        if it["supportsVision"]: flags.append("vision")
        if it["sourceSupportsVision"]: flags.append("sourceVision")
        if it["supportsReasoning"]: flags.append("reasoning")
        if it["supportsToolCalling"]: flags.append("tools")
        if it["isThinkingModel"]: flags.append("thinking")
        if it["recommendedForIPhone"]: flags.append("recommended")
        print(f"  flags: {', '.join(flags) if flags else 'none'}")
        if it["mlxModelID"]: print(f"  mlxModelID: {it['mlxModelID']}")
        if it["downloadURL"]: print(f"  downloadURL: {it['downloadURL']}")
