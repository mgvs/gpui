#!/usr/bin/env python3
"""Prune the inherited Zed workspace manifest down to the crates this fork ships.

Upstream's root `Cargo.toml` lists ~250 workspace members; this fork carries only
the gpui crates (see `scripts/upstream-paths.txt`), so the manifest as it arrives
from upstream names directories that do not exist here and Cargo refuses to load
the workspace at all.

This script rewrites, in place:

  * `members`        — dropped down to the entries whose directory really exists,
                       in upstream's order;
  * `default-members`— pinned to `["crates/gpui"]`, so a bare `cargo build` in a
                       checkout of this fork builds gpui rather than the editor.

Everything else, `[workspace.dependencies]` included, is left exactly as upstream
wrote it: unused workspace dependencies are inert (Cargo resolves a workspace
dependency only where a member inherits it), and leaving them untouched keeps the
diff against upstream — and therefore the merge conflict on every sync — down to
this one array.

Run it after `scripts/sync-upstream.sh --merge` reports a conflict in
`Cargo.toml`: take upstream's side of the conflict, then run this.

    python3 scripts/prune-workspace.py [--check] [Cargo.toml]

`--check` exits 1 without writing if the file is not already pruned.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

DEFAULT_MEMBERS = ["crates/gpui"]

MEMBER_RE = re.compile(r'^\s*"([^"]+)"\s*,?\s*$')


def prune(text: str, root: pathlib.Path) -> str:
    lines = text.splitlines(keepends=True)
    out: list[str] = []
    i = 0
    seen_members = False
    seen_default = False

    while i < len(lines):
        line = lines[i]

        if not seen_members and re.match(r"^members\s*=\s*\[\s*$", line):
            seen_members = True
            out.append(line)
            i += 1
            kept = []
            while i < len(lines) and not re.match(r"^\]\s*$", lines[i]):
                m = MEMBER_RE.match(lines[i])
                # Comment and blank lines inside the array are upstream's section
                # headers ("# Extensions", "# Tooling"); they describe crates this
                # fork does not carry, so they go with them.
                if m and (root / m.group(1) / "Cargo.toml").is_file():
                    kept.append(f'    "{m.group(1)}",\n')
                i += 1
            out.extend(kept)
            out.append(lines[i])  # the closing ']'
            i += 1
            continue

        if not seen_default and re.match(r"^default-members\s*=", line):
            seen_default = True
            rendered = ", ".join(f'"{m}"' for m in DEFAULT_MEMBERS)
            out.append(f"default-members = [{rendered}]\n")
            # Upstream keeps this on one line; skip a multi-line form too.
            if "]" not in line:
                while i < len(lines) and "]" not in lines[i]:
                    i += 1
            i += 1
            continue

        out.append(line)
        i += 1

    if not seen_members:
        sys.exit("prune-workspace: no `members = [` array found — manifest shape changed")
    if not seen_default:
        sys.exit("prune-workspace: no `default-members =` key found — manifest shape changed")

    return "".join(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest", nargs="?", default=None)
    ap.add_argument("--check", action="store_true", help="exit 1 if pruning would change the file")
    args = ap.parse_args()

    manifest = pathlib.Path(args.manifest) if args.manifest else pathlib.Path(__file__).resolve().parent.parent / "Cargo.toml"
    root = manifest.resolve().parent
    before = manifest.read_text()
    after = prune(before, root)

    if before == after:
        print(f"{manifest}: already pruned")
        return 0
    if args.check:
        print(f"{manifest}: NOT pruned (members/default-members would change)", file=sys.stderr)
        return 1

    manifest.write_text(after)
    print(f"{manifest}: pruned")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
