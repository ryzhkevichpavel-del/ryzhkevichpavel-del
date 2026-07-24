#!/usr/bin/env python3
from pathlib import Path
import base64, io, tarfile
root = Path(__file__).resolve().parent
parts = root / "bootstrap_parts"
data = "".join(p.read_text().strip() for p in sorted(parts.glob("part*.b64")))
with tarfile.open(fileobj=io.BytesIO(base64.b64decode(data)), mode="r:gz") as tf:
    tf.extractall(root)
print("Materialized tihiy-bereg source tree")
