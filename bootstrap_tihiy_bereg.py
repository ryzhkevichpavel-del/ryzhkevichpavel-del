#!/usr/bin/env python3
from pathlib import Path
import base64
import io
import tarfile
import traceback
import zlib

root = Path(__file__).resolve().parent
source = root / "tihiy-bereg"
project = source / "project.godot"
report = source / "BOOTSTRAP-REPORT.txt"
messages = []


def note(message: str) -> None:
    messages.append(message)
    print(message)


def replace(path: Path, old: str, new: str) -> None:
    if not path.exists():
        note(f"missing:{path.relative_to(root)}")
        return
    text = path.read_text(encoding="utf-8")
    if old in text:
        path.write_text(text.replace(old, new), encoding="utf-8")
        note(f"patched:{path.relative_to(root)}")


try:
    if not project.exists():
        parts = root / "bootstrap_parts"
        data = "".join(p.read_text().strip() for p in sorted(parts.glob("part*.b64")))
        with tarfile.open(fileobj=io.BytesIO(base64.b64decode(data)), mode="r:gz") as tf:
            tf.extractall(root)
        note("materialized:tihiy-bereg")
    else:
        note("source:already-materialized")

    sim = source / "scripts" / "simulation.gd"
    sim_override = root / "source_overrides" / "simulation.z.b64"
    if sim_override.exists():
        compressed = base64.b64decode(sim_override.read_text(encoding="ascii").strip())
        clean_simulation = zlib.decompress(compressed)
        clean_simulation.decode("utf-8")
        sim.parent.mkdir(parents=True, exist_ok=True)
        sim.write_bytes(clean_simulation)
        note("restored:tihiy-bereg/scripts/simulation.gd")

    if project.exists():
        project.write_text(project.read_text(encoding="utf-8").replace(
            "anti_aliasing/quality/screen_space_aa=1\n", ""
        ), encoding="utf-8")

    bus = source / "default_bus_layout.tres"
    bus.write_text('[gd_resource type="AudioBusLayout" format=3]\n\n[resource]\n', encoding="utf-8")

    replace(sim, "var blend := clampf(rate * falloff * 2.4, 0.0, 0.88)", "var smooth_blend: float = clampf(rate * falloff * 2.4, 0.0, 0.88)")
    replace(sim, "smooth_values[smooth_index], blend)", "smooth_values[smooth_index], smooth_blend)")
    replace(sim, "compaction[i] + blend * 0.025", "compaction[i] + smooth_blend * 0.025")
    replace(sim, "var blend := clampf(rate * falloff * 2.0, 0.0, 0.94)", "var flatten_blend: float = clampf(rate * falloff * 2.0, 0.0, 0.94)")
    replace(sim, "flatten_height, blend)", "flatten_height, flatten_blend)")
    replace(sim, "compaction[i] + blend * 0.04", "compaction[i] + flatten_blend * 0.04")

    main = source / "scripts" / "main.gd"
    if main.exists():
        main_lines = main.read_text(encoding="utf-8").splitlines()
        filtered_lines = [line for line in main_lines if "viewport.screen_space_aa" not in line]
        if len(filtered_lines) != len(main_lines):
            main.write_text("\n".join(filtered_lines) + "\n", encoding="utf-8")
            note("patched:tihiy-bereg/scripts/main.gd:remove-screen-space-aa")
    fixes = [
        ("var y := sim.sample_height(x, z)", "var y: float = sim.sample_height(x, z)"),
        ("var height := sim.sample_height(point.x, point.z)", "var height: float = sim.sample_height(point.x, point.z)"),
        ("var ground := sim.sample_height(point.x, point.z)", "var ground: float = sim.sample_height(point.x, point.z)"),
        ("var ground := sim.sample_height(node.position.x, node.position.z)", "var ground: float = sim.sample_height(node.position.x, node.position.z)"),
        ("var depth := sim.sample_water_depth(node.position.x, node.position.z)", "var depth: float = sim.sample_water_depth(node.position.x, node.position.z)"),
        ("var surface := sim.sample_water_surface(node.position.x, node.position.z)", "var surface: float = sim.sample_water_surface(node.position.x, node.position.z)"),
        ("var flow := sim.sample_flow(node.position.x, node.position.z)", "var flow: Vector2 = sim.sample_flow(node.position.x, node.position.z)"),
        ("var normal := sim.terrain_normal(node.position.x, node.position.z)", "var normal: Vector3 = sim.terrain_normal(node.position.x, node.position.z)"),
        ("var ground := sim.sample_height(p.x, p.z)", "var ground: float = sim.sample_height(p.x, p.z)"),
        ("var flow := sim.sample_flow(p.x, p.z)", "var flow: Vector2 = sim.sample_flow(p.x, p.z)"),
    ]
    for old, new in fixes:
        replace(main, old, new)

    test = source / "tests" / "test_simulation.gd"
    test_fixes = [
        ("var sim := BeachSimulation.new(65, 49)", "var sim: BeachSimulation = BeachSimulation.new(65, 49)"),
        ("var h0 := sim.sample_height(0.0, 6.0)", "var h0: float = sim.sample_height(0.0, 6.0)"),
        ("var h1 := sim.sample_height(0.0, 6.0)", "var h1: float = sim.sample_height(0.0, 6.0)"),
        ("var h2 := sim.sample_height(0.0, 6.0)", "var h2: float = sim.sample_height(0.0, 6.0)"),
        ("var water_before := sim.total_water()", "var water_before: float = sim.total_water()"),
        ("var water_after := sim.total_water()", "var water_after: float = sim.total_water()"),
        ("var state := sim.serialize_state()", "var state: Dictionary = sim.serialize_state()"),
        ("var sim2 := BeachSimulation.new(65, 49)", "var sim2: BeachSimulation = BeachSimulation.new(65, 49)"),
    ]
    for old, new in test_fixes:
        replace(test, old, new)

    note("bootstrap:success")
except Exception:
    note("bootstrap:exception")
    messages.append(traceback.format_exc())

source.mkdir(parents=True, exist_ok=True)
report.write_text("\n".join(messages) + "\n", encoding="utf-8")
