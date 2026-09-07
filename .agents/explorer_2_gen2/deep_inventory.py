import json
import re
import uuid

NAMESPACE_MODEL_CATALOG = uuid.UUID("A1B2C3D4-E5F6-7890-ABCD-EF1234567890")

def deterministic_id(display_name, variant):
    return str(uuid.uuid5(NAMESPACE_MODEL_CATALOG, f"{display_name}::{variant}")).upper()

with open("EdgeMindAi/State/MockCatalogData.swift", "r") as f:
    catalog_text = f.read()

with open("EdgeMindAi/Resources/RuntimeProfiles.json", "r") as f:
    profiles_data = json.load(f)

profiles_by_id = {p["catalogID"].upper(): p for p in profiles_data}

pattern = re.compile(r'ModelCatalogItem\s*\((.*?)\n\s*\)', re.DOTALL)
matches = pattern.findall(catalog_text)

catalog_items = []
for idx, m in enumerate(matches):
    item = {"raw": m, "index": idx}
    for field in ["displayName", "variant", "family", "parameterSize", "quantization", "diskSize", "contextWindow", "runtimeType", "mlxModelID", "minimumTier", "runtimeStatus"]:
        match = re.search(rf'{field}:\s*([^\n,]+)', m)
        if match:
            val = match.group(1).strip().strip('"').strip('.')
            item[field] = val
        else:
            item[field] = None
            
    id_match = re.search(r'id:\s*UUID\(uuidString:\s*"([^"]+)"\)', m)
    item["explicit_id"] = id_match.group(1).upper() if id_match else None
    
    url_match = re.search(r'downloadURL:\s*URL\(string:\s*"([^"]+)"\)', m)
    item["downloadURL"] = url_match.group(1) if url_match else None
    
    verdict_match = re.search(r'auditVerdict:\s*([^\n,]+)', m)
    item["auditVerdict"] = verdict_match.group(1).strip() if verdict_match else None
    
    item["supportsVision"] = "supportsVision: true" in m
    item["sourceSupportsVision"] = "sourceSupportsVision: true" in m
    item["supportsReasoning"] = "supportsReasoning: true" in m
    item["supportsToolCalling"] = "supportsToolCalling: true" in m
    item["isThinkingModel"] = "isThinkingModel: true" in m
    item["recommendedForIPhone"] = "recommendedForIPhone: true" in m
    
    calc_id = deterministic_id(item["displayName"], item["variant"])
    item["computed_id"] = calc_id
    item["effective_id"] = item["explicit_id"] if item["explicit_id"] else calc_id
    item["has_profile"] = item["effective_id"] in profiles_by_id
    if item["has_profile"]:
        item["profile"] = profiles_by_id[item["effective_id"]]
        
    catalog_items.append(item)

# Group inventory into required sections
categories = [
    ("VLMs", [
        ("Google Gemma 4 E2B (LiteRT-LM)", lambda it: "gemma 4 e2b" in it["displayName"].lower() and it["runtimeType"] == "liteRTLM"),
        ("SmolVLM2 500M (MLX)", lambda it: "smolvlm2" in it["displayName"].lower() and "500m" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
        ("SmolVLM2 2.2B (MLX)", lambda it: "smolvlm2" in it["displayName"].lower() and "2.2b" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
        ("Qwen 3.5 VL 0.8B (MLX)", lambda it: "qwen 3.5 vl" in it["displayName"].lower() and "0.8b" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
        ("Qwen 3.5 VL 4B (MLX)", lambda it: "qwen 3.5 vl" in it["displayName"].lower() and "4b" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
        ("Liquid AI LFM 2.5 VL 1.6B (MLX)", lambda it: "lfm" in it["displayName"].lower() and "vl" in it["displayName"].lower() and "1.6b" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
    ]),
    ("Edge Text & Reasoning: Qwen 3.5 (0.8B / 2B MLX & GGUF)", [
        ("Qwen 3.5 0.8B (MLX)", lambda it: "qwen 3.5" in it["displayName"].lower() and "0.8b" in it["displayName"].lower() and it["runtimeType"] == "mlx" and "vl" not in it["displayName"].lower()),
        ("Qwen 3.5 2B (MLX)", lambda it: "qwen 3.5" in it["displayName"].lower() and "2b" in it["displayName"].lower() and it["runtimeType"] == "mlx" and "vl" not in it["displayName"].lower()),
        ("Qwen 3.5 0.8B (GGUF)", lambda it: "qwen 3.5" in it["displayName"].lower() and "0.8b" in it["displayName"].lower() and it["runtimeType"] == "gguf" and "vl" not in it["displayName"].lower()),
        ("Qwen 3.5 2B (GGUF)", lambda it: "qwen 3.5" in it["displayName"].lower() and "2b" in it["displayName"].lower() and it["runtimeType"] == "gguf" and "vl" not in it["displayName"].lower()),
    ]),
    ("Edge Text & Reasoning: Qwen 3 2507 Thinking (0.6B / 1.7B / 4B MLX & GGUF)", [
        ("Qwen 3 0.6B (MLX)", lambda it: "qwen 3" in it["displayName"].lower() and "0.6b" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
        ("Qwen 3 1.7B (MLX)", lambda it: "qwen 3" in it["displayName"].lower() and "1.7b" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
        ("Qwen 3 4B 2507 Thinking (MLX)", lambda it: "qwen 3" in it["displayName"].lower() and "4b" in it["displayName"].lower() and "thinking" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
        ("Qwen 3 0.6B (GGUF)", lambda it: "qwen 3" in it["displayName"].lower() and "0.6b" in it["displayName"].lower() and it["runtimeType"] == "gguf"),
        ("Qwen 3 1.7B (GGUF)", lambda it: "qwen 3" in it["displayName"].lower() and "1.7b" in it["displayName"].lower() and it["runtimeType"] == "gguf"),
        ("Qwen 3 4B 2507 Thinking (GGUF)", lambda it: "qwen 3" in it["displayName"].lower() and "4b" in it["displayName"].lower() and "thinking" in it["displayName"].lower() and it["runtimeType"] == "gguf"),
    ]),
    ("Edge Text & Reasoning: Other Premier 2026 Models", [
        ("Liquid AI LFM 2.5 350M", lambda it: "lfm" in it["displayName"].lower() and "350m" in it["displayName"].lower()),
        ("Liquid AI LFM 2.5 1.2B Thinking", lambda it: "lfm" in it["displayName"].lower() and "1.2b" in it["displayName"].lower() and "thinking" in it["displayName"].lower()),
        ("IBM Granite 3.3 2B (MLX)", lambda it: "granite 3.3 2b" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
        ("IBM Granite 3.3 2B (GGUF)", lambda it: "granite 3.3 2b" in it["displayName"].lower() and it["runtimeType"] == "gguf"),
        ("Mistral Ministral 3 3B (MLX)", lambda it: "ministral 3 3b" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
        ("Mistral Ministral 3 3B (GGUF)", lambda it: "ministral 3 3b" in it["displayName"].lower() and it["runtimeType"] == "gguf"),
        ("DeepSeek R1 Distill Qwen 1.5B (MLX)", lambda it: "deepseek" in it["displayName"].lower() and "1.5b" in it["displayName"].lower() and it["runtimeType"] == "mlx"),
        ("DeepSeek R1 Distill Qwen 1.5B (GGUF)", lambda it: "deepseek" in it["displayName"].lower() and "1.5b" in it["displayName"].lower() and it["runtimeType"] == "gguf"),
        ("Apple Intelligence Foundation Models", lambda it: it["family"] == "appleIntelligence"),
    ])
]

for cat_title, req_list in categories:
    print(f"\n==========================================")
    print(f"CATEGORY: {cat_title}")
    print(f"==========================================")
    for title, predicate in req_list:
        matches = [it for it in catalog_items if predicate(it)]
        if not matches:
            print(f"\n[STATUS: MISSING] {title}")
        else:
            for m in matches:
                print(f"\n[STATUS: PRESENT] {title} -> {m['displayName']}")
                print(f"  ID: {m['effective_id']} (explicit: {m['explicit_id'] is not None}, computed: {m['computed_id']})")
                print(f"  variant: {m['variant']}, family: {m['family']}, runtimeType: {m['runtimeType']}")
                print(f"  params: {m['parameterSize']}, disk: {m['diskSize']}, ctx: {m['contextWindow']}, minTier: {m['minimumTier']}")
                print(f"  runtimeStatus: {m['runtimeStatus']}, auditVerdict: {m['auditVerdict']}")
                flags = []
                for f in ["supportsVision", "sourceSupportsVision", "supportsReasoning", "supportsToolCalling", "isThinkingModel", "recommendedForIPhone"]:
                    if m[f]: flags.append(f)
                print(f"  flags: {', '.join(flags)}")
                if m['mlxModelID']: print(f"  mlxModelID: {m['mlxModelID']}")
                if m['downloadURL']: print(f"  downloadURL: {m['downloadURL']}")
                if m['has_profile']:
                    p = m['profile']
                    print(f"  Profile sync: YES (thinking={p.get('verifiedThinking')}, tools={p.get('verifiedToolCalling')}, vision={p.get('verifiedVision')}, verdict={p.get('auditVerdict')})")
                else:
                    print(f"  Profile sync: NO (MISSING FROM RuntimeProfiles.json)")
