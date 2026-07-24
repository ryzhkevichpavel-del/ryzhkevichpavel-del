#!/usr/bin/env python3
from pathlib import Path
import base64
import io
import tarfile

root = Path(__file__).resolve().parent
project = root / "tihiy-bereg" / "project.godot"

if not project.exists():
    parts = root / "bootstrap_parts"
    data = "".join(p.read_text().strip() for p in sorted(parts.glob("part*.b64")))
    with tarfile.open(fileobj=io.BytesIO(base64.b64decode(data)), mode="r:gz") as tf:
        tf.extractall(root)
    print("Materialized tihiy-bereg source tree")
else:
    print("Source tree already materialized")


def replace(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old in text:
        path.write_text(text.replace(old, new), encoding="utf-8")


project.write_text(project.read_text(encoding="utf-8").replace(
    "anti_aliasing/quality/screen_space_aa=1\n", ""
), encoding="utf-8")

(root / "tihiy-bereg" / "default_bus_layout.tres").write_text(
    '[gd_resource type="AudioBusLayout" format=3]\n\n[resource]\n', encoding="utf-8"
)

sim = root / "tihiy-bereg" / "scripts" / "simulation.gd"
replace(sim,
    "var blend := clampf(rate * falloff * 2.4, 0.0, 0.88)",
    "var smooth_blend: float = clampf(rate * falloff * 2.4, 0.0, 0.88)"
)
replace(sim, "smooth_values[smooth_index], blend)", "smooth_values[smooth_index], smooth_blend)")
replace(sim, "compaction[i] + blend * 0.025", "compaction[i] + smooth_blend * 0.025")
replace(sim,
    "var blend := clampf(rate * falloff * 2.0, 0.0, 0.94)",
    "var flatten_blend: float = clampf(rate * falloff * 2.0, 0.0, 0.94)"
)
replace(sim, "flatten_height, blend)", "flatten_height, flatten_blend)")
replace(sim, "compaction[i] + blend * 0.04", "compaction[i] + flatten_blend * 0.04")

main = root / "tihiy-bereg" / "scripts" / "main.gd"
for old, new in {
    "var y := sim.sample_height(x, z)": "var y: float = sim.sample_height(x, z)",
    "var height := sim.sample_height(point.x, point.z)": "var height: float = sim.sample_height(point.x, point.z)",
    "var ground := sim.sample_height(point.x, point.z)": "var ground: float = sim.sample_height(point.x, point.z)",
    "var ground := sim.sample_height(node.position.x, node.position.z)": "var ground: float = sim.sample_height(node.position.x, node.position.z)",
    "var depth := sim.sample_water_depth(node.position.x, node.position.z)": "var depth: float = sim.sample_water_depth(node.position.x, node.position.z)",
    "var surface := sim.sample_water_surface(node.position.x, node.position.z)": "var surface: float = sim.sample_water_surface(node.position.x, node.position.z)",
    "var flow := sim.sample_flow(node.position.x, node.position.z)": "var flow: Vector2 = sim.sample_flow(node.position.x, node.position.z)",
    "var normal := sim.terrain_normal(node.position.x, node.position.z)": "var normal: Vector3 = sim.terrain_normal(node.position.x, node.position.z)",
    "var ground := sim.sample_height(p.x, p.z)": "var ground: float = sim.sample_height(p.x, p.z)",
    "var flow := sim.sample_flow(p.x, p.z)": "var flow: Vector2 = sim.sample_flow(p.x, p.z)",
}.items():
    replace(main, old, new)

test = root / "tihiy-bereg" / "tests" / "test_simulation.gd"
for old, new in {
    "var sim := BeachSimulation.new(65, 49)": "var sim: BeachSimulation = BeachSimulation.new(65, 49)",
    "var h0 := sim.sample_height(0.0, 6.0)": "var h0: float = sim.sample_height(0.0, 6.0)",
    "var h1 := sim.sample_height(0.0, 6.0)": "var h1: float = sim.sample_height(0.0, 6.0)",
    "var h2 := sim.sample_height(0.0, 6.0)": "var h2: float = sim.sample_height(0.0, 6.0)",
    "var water_before := sim.total_water()": "var water_before: float = sim.total_water()",
    "var water_after := sim.total_water()": "var water_after: float = sim.total_water()",
    "var state := sim.serialize_state()": "var state: Dictionary = sim.serialize_state()",
    "var sim2 := BeachSimulation.new(65, 49)": "var sim2: BeachSimulation = BeachSimulation.new(65, 49)",
}.items():
    replace(test, old, new)

print("Applied deterministic source fixes")
