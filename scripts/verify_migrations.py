#!/usr/bin/env python3
"""Fail closed when the imported middleware migration graph is incomplete."""

from __future__ import annotations

import ast
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERSIONS = ROOT / "middleware" / "versions"
EXPECTED_HEAD = "0059_klyrow_usage_events"


def assignments(path: Path) -> dict[str, object]:
    values: dict[str, object] = {}
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    for node in tree.body:
        if isinstance(node, ast.Assign):
            targets = node.targets
        elif isinstance(node, ast.AnnAssign):
            targets = [node.target]
        else:
            continue
        for target in targets:
            if isinstance(target, ast.Name) and target.id in {"revision", "down_revision"}:
                values[target.id] = ast.literal_eval(node.value)
    return values


def main() -> None:
    source = json.loads((ROOT / "middleware" / "SOURCE.json").read_text(encoding="utf-8"))
    sha = source.get("source_sha", "")
    if len(sha) != 40 or any(char not in "0123456789abcdef" for char in sha):
        raise SystemExit("SOURCE.json source_sha must be an exact lowercase commit SHA")
    if source.get("production_applied") is not False:
        raise SystemExit("import candidates must remain explicitly unapplied")

    revisions: dict[str, tuple[Path, object]] = {}
    for path in sorted(VERSIONS.glob("*.py")):
        values = assignments(path)
        revision = values.get("revision")
        if not isinstance(revision, str) or not revision:
            raise SystemExit(f"{path}: missing string revision")
        if revision in revisions:
            raise SystemExit(f"duplicate revision {revision}: {revisions[revision][0]} and {path}")
        revisions[revision] = (path, values.get("down_revision"))

    parents: set[str] = set()
    edges: dict[str, tuple[str, ...]] = {}
    for revision, (path, raw_parent) in revisions.items():
        if raw_parent is None:
            resolved: tuple[str, ...] = ()
        elif isinstance(raw_parent, str):
            resolved = (raw_parent,)
        elif isinstance(raw_parent, (tuple, list)) and all(isinstance(item, str) for item in raw_parent):
            resolved = tuple(raw_parent)
        else:
            raise SystemExit(f"{path}: invalid down_revision")
        missing = [parent for parent in resolved if parent not in revisions]
        if missing:
            raise SystemExit(f"{path}: missing parent(s) {', '.join(missing)}")
        parents.update(resolved)
        edges[revision] = resolved

    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(revision: str) -> None:
        if revision in visiting:
            raise SystemExit(f"migration cycle detected at {revision}")
        if revision in visited:
            return
        visiting.add(revision)
        for parent in edges[revision]:
            visit(parent)
        visiting.remove(revision)
        visited.add(revision)

    for revision in revisions:
        visit(revision)

    heads = sorted(set(revisions) - parents)
    if heads != [EXPECTED_HEAD]:
        raise SystemExit(f"expected sole head {EXPECTED_HEAD}; found {heads}")
    if len(revisions) != 72:
        raise SystemExit(f"expected 72 Alembic revisions; found {len(revisions)}")

    tracked = list((ROOT / "middleware").rglob("*"))
    for path in tracked:
        if path.is_file() and path.suffix in {".py", ".sql", ".json"}:
            text = path.read_text(encoding="utf-8")
            if any(marker in text for marker in ("<<<<<<<", "=======", ">>>>>>>")):
                raise SystemExit(f"merge marker found in {path}")

    print(f"verified {len(revisions)} revisions; sole head={EXPECTED_HEAD}; source={sha}")


if __name__ == "__main__":
    main()
