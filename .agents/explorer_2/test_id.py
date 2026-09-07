import json
import re
import uuid

# Deterministic UUID v5 function matching Swift
NAMESPACE_MODEL_CATALOG = uuid.UUID("A1B2C3D4-E5F6-7890-ABCD-EF1234567890")

def deterministic_id(display_name, variant):
    name = f"{display_name}::{variant}"
    return str(uuid.uuid5(NAMESPACE_MODEL_CATALOG, name)).upper()

print("Deterministic ID test:")
print("Apple Intelligence :: System Foundation Model =", deterministic_id("Apple Intelligence", "System Foundation Model"))
