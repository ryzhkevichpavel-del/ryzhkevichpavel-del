#!/usr/bin/env python3
"""Apply release-critical fixes after bootstrapping the Godot source tree.

The bootstrap archive is immutable historical input. This script makes the
materialized tree use Godot 4's user-argument API, keeps the automated capture
fast, and repairs reset-time camera binding before CI commits the readable
sources back to the project branch.
"""
from pathlib import Path

root = Path(__file__).resolve().parent / "tihiy-bereg"
main = root / "scripts" / "main.gd"
text = main.read_text(encoding="utf-8")

text = text.replace("OS.get_cmdline_args()", "OS.get_cmdline_user_args()")
text = text.replace("for _i in range(150):", "for _i in range(48):")
text = text.replace("await get_tree().create_timer(2.2).timeout", "await get_tree().create_timer(1.2).timeout")
text = text.replace(
    "func _run_capture_mode() -> void:\n\tawait get_tree().create_timer(0.45).timeout",
    "func _run_capture_mode() -> void:\n\tprint(\"CAPTURE_MODE_STARTED\")\n\tawait get_tree().create_timer(0.45).timeout",
)
needle = "func _reset_world() -> void:\n\t_push_undo()\n\tsim = BeachSimulation.new(161, 121)\n"
replacement = needle + "\tcamera_rig.terrain_sampler = Callable(sim, \"sample_height\")\n"
if needle in text and "camera_rig.terrain_sampler = Callable(sim, \"sample_height\")" not in text[text.index(needle):text.index(needle) + 260]:
    text = text.replace(needle, replacement, 1)

main.write_text(text, encoding="utf-8")
print("Applied release fixes to", main)
