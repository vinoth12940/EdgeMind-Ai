import json

with open("EdgeMindAi/Resources/RuntimeProfiles.json", "r") as f:
    profiles = json.load(f)

with open("EdgeMindAi/State/MockCatalogData.swift", "r") as f:
    catalog_text = f.read()

import re, uuid
NAMESPACE_MODEL_CATALOG = uuid.UUID("A1B2C3D4-E5F6-7890-ABCD-EF1234567890")
def deterministic_id(name, variant):
    return str(uuid.uuid5(NAMESPACE_MODEL_CATALOG, f"{name}::{variant}")).upper()

pattern = re.compile(r'ModelCatalogItem\s*\((.*?)\n\s*\)', re.DOTALL)
matches = pattern.findall(catalog_text)

catalog = {}
for m in matches:
    name_m = re.search(r'displayName:\s*"([^"]+)"', m)
    var_m = re.search(r'variant:\s*"([^"]+)"', m)
    id_m = re.search(r'id:\s*UUID\(uuidString:\s*"([^"]+)"\)', m)
    if name_m and var_m:
        name = name_m.group(1)
        var = var_m.group(1)
        eff_id = id_m.group(1).upper() if id_m else deterministic_id(name, var)
        catalog[eff_id] = (name, var)

for p in profiles:
    cid = p["catalogID"].upper()
    name, var = catalog.get(cid, ("UNKNOWN", "UNKNOWN"))
    if "Qwen" in name:
        print(f"{name} [{var}] ({cid}):")
        print(f"  thinking: {p.get('verifiedThinking')}")
        print(f"  tools: {p.get('verifiedToolCalling')}")
        print(f"  vision: {p.get('verifiedVision')}")
        print(f"  verdict: {p.get('auditVerdict')}")
        print(f"  inputModes: {p.get('verifiedInputModes')}")
