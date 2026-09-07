import uuid

NAMESPACE_MODEL_CATALOG = uuid.UUID("A1B2C3D4-E5F6-7890-ABCD-EF1234567890")
def deterministic_id(name, variant):
    return str(uuid.uuid5(NAMESPACE_MODEL_CATALOG, f"{name}::{variant}")).upper()

candidates = [
    ("SmolVLM2 2.2B Instruct (MLX)", "4-bit MLX · Vision"),
    ("Qwen 3.5 0.8B Instruct (MLX)", "4-bit MLX"),
    ("Qwen 3 0.6B (GGUF)", "Q4_K_M GGUF · Latest"),
    ("Qwen 3 0.6B 2507 Thinking (GGUF)", "Q4_K_M GGUF · Latest"),
    ("Qwen 3 1.7B (GGUF)", "Q4_K_M GGUF · Latest"),
    ("Qwen 3 1.7B 2507 Thinking (GGUF)", "Q4_K_M GGUF · Latest"),
]

for name, var in candidates:
    print(f"{name} [{var}] -> {deterministic_id(name, var)}")
