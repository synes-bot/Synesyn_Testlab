#!/usr/bin/env python3
"""
First-party version consistency check.

Policy
------
The repository root `VERSION` file is the single source of truth for the
Synesyn platform release version. Every first-party declaration that states
the project or component version must match it.

Checked surfaces
----------------
- `VERSION` (canonical)
- `CITATION.cff` `version:`
- `synesyn_client/project.godot` `application/config/version`
- first-party `synesyn_client/addons/*/plugin.cfg` `version=`
  (excludes vendored third-party addons such as limboai)
- `services/synesyn_hub/app/config.py` default hub version string
- `METAPUNKT_VERSION` in Metapunkt's SLOP EndpointHandler
- `CHANGELOG.md` must contain a `## [<version>]` release heading

Not checked (intentionally)
---------------------------
- Document / PRD / schema / pack / artifact schema versions
- Third-party vendored addon versions (e.g. limboai)
- Python / Godot runtime versions in CI

Exit 0 on success, 1 on drift or a missing declaration.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# Vendored upstream addons keep their own release numbers.
THIRD_PARTY_ADDONS = frozenset({"limboai"})

VERSION_PATH = REPO_ROOT / "VERSION"
CITATION_PATH = REPO_ROOT / "CITATION.cff"
PROJECT_GODOT = REPO_ROOT / "synesyn_client" / "project.godot"
ADDONS_DIR = REPO_ROOT / "synesyn_client" / "addons"
HUB_CONFIG = REPO_ROOT / "services" / "synesyn_hub" / "app" / "config.py"
METAPUNKT_HANDLER = (
	REPO_ROOT
	/ "synesyn_client"
	/ "addons"
	/ "metapunkt"
	/ "Networking"
	/ "SLOPServer"
	/ "EndpointHandler.gd"
)
CHANGELOG_PATH = REPO_ROOT / "CHANGELOG.md"

_PLUGIN_VERSION = re.compile(r'(?m)^version="([^"]*)"\s*$')
_CITATION_VERSION = re.compile(r"(?m)^version:\s*(.+?)\s*$")
_PROJECT_VERSION = re.compile(r'(?m)^config/version="([^"]*)"\s*$')
_HUB_DEFAULT = re.compile(
	r"""raw\.get\(\s*["']version["']\s*,\s*["']([^"']+)["']\s*\)"""
)
_METAPUNKT_VERSION = re.compile(
	r'(?m)^const\s+METAPUNKT_VERSION\s*:=\s*"([^"]+)"\s*$'
)
_CHANGELOG_HEADING = re.compile(r"(?m)^## \[([^\]]+)\]\s*$")


def _read_canonical() -> str:
	if not VERSION_PATH.is_file():
		raise FileNotFoundError(f"missing canonical version file: {VERSION_PATH}")
	text = VERSION_PATH.read_text(encoding="utf-8").strip()
	if not text:
		raise ValueError(f"{VERSION_PATH} is empty")
	# One version token; ignore trailing comments if ever added.
	return text.split()[0]


def _expect(label: str, actual: str | None, expected: str, errors: list[str]) -> None:
	if actual is None:
		errors.append(f"{label}: missing version declaration (expected {expected})")
	elif actual != expected:
		errors.append(f"{label}: found {actual!r}, expected {expected!r}")


def main() -> int:
	errors: list[str] = []
	try:
		expected = _read_canonical()
	except (OSError, ValueError) as exc:
		print(f"FAIL: {exc}", file=sys.stderr)
		return 1

	# CITATION.cff
	if CITATION_PATH.is_file():
		match = _CITATION_VERSION.search(CITATION_PATH.read_text(encoding="utf-8"))
		_expect("CITATION.cff", match.group(1).strip() if match else None, expected, errors)
	else:
		errors.append("CITATION.cff: file missing")

	# project.godot
	if PROJECT_GODOT.is_file():
		match = _PROJECT_VERSION.search(PROJECT_GODOT.read_text(encoding="utf-8"))
		_expect(
			"synesyn_client/project.godot application/config/version",
			match.group(1) if match else None,
			expected,
			errors,
		)
	else:
		errors.append("synesyn_client/project.godot: file missing")

	# First-party plugin.cfg
	if not ADDONS_DIR.is_dir():
		errors.append(f"{ADDONS_DIR}: directory missing")
	else:
		plugin_cfgs = sorted(ADDONS_DIR.glob("*/plugin.cfg"))
		if not plugin_cfgs:
			errors.append("no addon plugin.cfg files found under synesyn_client/addons/")
		for cfg_path in plugin_cfgs:
			addon_name = cfg_path.parent.name
			if addon_name in THIRD_PARTY_ADDONS:
				continue
			rel = cfg_path.relative_to(REPO_ROOT).as_posix()
			match = _PLUGIN_VERSION.search(cfg_path.read_text(encoding="utf-8"))
			_expect(rel, match.group(1) if match else None, expected, errors)

	# Hub default
	if HUB_CONFIG.is_file():
		match = _HUB_DEFAULT.search(HUB_CONFIG.read_text(encoding="utf-8"))
		_expect(
			"services/synesyn_hub/app/config.py default version",
			match.group(1) if match else None,
			expected,
			errors,
		)
	else:
		errors.append("services/synesyn_hub/app/config.py: file missing")

	# Metapunkt runtime constant
	if METAPUNKT_HANDLER.is_file():
		match = _METAPUNKT_VERSION.search(METAPUNKT_HANDLER.read_text(encoding="utf-8"))
		_expect(
			"METAPUNKT_VERSION",
			match.group(1) if match else None,
			expected,
			errors,
		)
	else:
		errors.append(f"{METAPUNKT_HANDLER.relative_to(REPO_ROOT).as_posix()}: file missing")

	# CHANGELOG release heading
	if CHANGELOG_PATH.is_file():
		headings = _CHANGELOG_HEADING.findall(CHANGELOG_PATH.read_text(encoding="utf-8"))
		if expected not in headings:
			errors.append(
				f"CHANGELOG.md: missing '## [{expected}]' release heading "
				f"(found: {', '.join(headings) or 'none'})"
			)
	else:
		errors.append("CHANGELOG.md: file missing")

	if errors:
		print(f"Version consistency check failed (canonical={expected}):", file=sys.stderr)
		for err in errors:
			print(f"  - {err}", file=sys.stderr)
		return 1

	print(f"OK: first-party versions match {expected}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
