import uuid

NAMESPACE_MODEL_CATALOG = uuid.UUID("A1B2C3D4-E5F6-7890-ABCD-EF1234567890")

def det_id(display_name, variant):
    name = f"{display_name}::{variant}"
    return str(uuid.uuid5(NAMESPACE_MODEL_CATALOG, name)).upper()

candidates = [
    ("SmolVLM2 2.2B Instruct (MLX)", "4-bit MLX · Vision"),
    ("Qwen 3.5 0.8B Instruct (MLX)", "4-bit MLX"),
    ("Qwen 3 0.6B (GGUF)", "Q4_K_M GGUF · Latest"),
    ("Qwen 3 1.7B (GGUF)", "Q4_K_M GGUF · Latest"),
]

for name, var in candidates:
    print(f"{name} | {var} -> {det_id(name, var)}")
