import re

with open("EdgeMindAi/State/MockCatalogData.swift", "r") as f:
    text = f.read()

pattern = re.compile(r'ModelCatalogItem\s*\((.*?)\n\s*\)', re.DOTALL)
matches = pattern.findall(text)

print(f"Total models: {len(matches)}\n")
for idx, m in enumerate(matches):
    name_m = re.search(r'displayName:\s*"([^"]+)"', m)
    name = name_m.group(1) if name_m else "UNKNOWN"
    
    var_m = re.search(r'variant:\s*"([^"]+)"', m)
    variant = var_m.group(1) if var_m else ""
    
    rt_m = re.search(r'runtimeType:\s*\.([a-zA-Z0-9]+)', m)
    rt = rt_m.group(1) if rt_m else "gguf"
    
    fam_m = re.search(r'family:\s*\.([a-zA-Z0-9]+)', m)
    fam = fam_m.group(1) if fam_m else ""
    
    id_m = re.search(r'id:\s*UUID\(uuidString:\s*"([^"]+)"\)', m)
    exp_id = id_m.group(1) if id_m else "computed"
    
    mlx_m = re.search(r'mlxModelID:\s*"([^"]+)"', m)
    mlx = mlx_m.group(1) if mlx_m else ""
    
    url_m = re.search(r'downloadURL:\s*URL\(string:\s*"([^"]+)"\)', m)
    url = url_m.group(1) if url_m else ""
    
    print(f"{idx+1:2d}. [{fam:12s}] {name} | {variant} | {rt} | ID: {exp_id}")
    if mlx: print(f"     mlx: {mlx}")
    if url: print(f"     url: {url}")
