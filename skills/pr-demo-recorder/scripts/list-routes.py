#!/usr/bin/env python3
"""
list-routes.py — enumerate and RESOLVE DAP frontend routes for a given section.

Shows the actual URLs you can paste into a webreel.config.json, not raw
constant references. Works regardless of whether the section uses a central
constants file (Workflow) or defines paths inline in its Routes.tsx (Inventory,
AiOps, etc.).

Resolution walks three layers:
  1. Grep every `path:` line in the section's *.tsx files.
  2. For each constant reference (e.g. AI_OPS_PATHS.GRID_VIEW), find its
     definition block anywhere under apps/ or libs/ and parse the KEY→VALUE
     pairs — handles `const X = {...}`, `enum X {...}`, and template literals
     like `= `${BASE_PATH}/builder``.
  3. Compose full URLs using the section's ROOT segment as the mount.

Usage:
  list-routes.py                    # list available sections
  list-routes.py <Section>          # resolve routes for one section
  list-routes.py --all              # every section
  list-routes.py --base URL         # override base URL (default: http://localhost:4200)
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


# ──────────────────────────────────────────────────────────────────────────
# Locate the DAP workspace root
# ──────────────────────────────────────────────────────────────────────────

def find_repo_root() -> Path | None:
    """Find dap-workspace by walking up from script dir and CWD."""
    markers = ["apps/platform/dashboard-fe/src/routes"]
    for start in [Path(__file__).resolve(), Path.cwd().resolve()]:
        for p in [start] + list(start.parents):
            if all((p / m).is_dir() for m in markers):
                return p
    return None


# ──────────────────────────────────────────────────────────────────────────
# Parsing helpers
# ──────────────────────────────────────────────────────────────────────────

def _find_balanced_block(text: str, start_idx: int) -> str | None:
    """Given an index pointing at an opening `{`, return the contents between
    it and the matching `}`. Returns None if the braces don't balance."""
    if start_idx >= len(text) or text[start_idx] != "{":
        return None
    depth = 1
    i = start_idx + 1
    while i < len(text) and depth > 0:
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
        i += 1
    if depth != 0:
        return None
    return text[start_idx + 1 : i - 1]


def parse_constant_block(text: str, name: str) -> dict[str, str] | None:
    """Find `(export)? (const|enum) NAME (=|)\\s*{...}` in `text`, parse
    KEY→VALUE pairs inside, and return as a dict. Returns None if not found.

    Supports:
      - Object literals:   `ROOT: 'ai-ops',`
      - Enum string bodies: `ROOT = 'workflow',`
      - Template literals: `BUILDER = `${BASE_PATH}/builder`,`
    Template `${VAR}` placeholders are resolved against any
    `const VAR = '...'` definitions found elsewhere in the same text.
    """
    patterns = [
        rf"(?:export\s+)?const\s+{re.escape(name)}\s*=\s*\{{",
        rf"(?:export\s+)?enum\s+{re.escape(name)}\s*\{{",
    ]
    for pat in patterns:
        m = re.search(pat, text)
        if not m:
            continue
        brace_idx = m.end() - 1
        body = _find_balanced_block(text, brace_idx)
        if body is None:
            continue
        return _parse_entries(body, text)
    return None


def _parse_entries(body: str, full_text: str) -> dict[str, str]:
    """Extract KEY→VALUE pairs from an object/enum body."""
    pattern = re.compile(
        r"(\w+)\s*[:=]\s*"
        r"(?:"
        r"'([^']*)'|"  # 'single-quoted'
        r'"([^"]*)"|'  # "double-quoted"
        r"`([^`]*)`"   # `backtick template`
        r")"
    )
    entries: dict[str, str] = {}
    for m in pattern.finditer(body):
        key = m.group(1)
        value = m.group(2) or m.group(3)
        if value is None:
            # Template literal — resolve ${VAR} against full_text.
            value = _resolve_template(m.group(4), full_text)
        entries[key] = value
    return entries


def _resolve_template(template: str, full_text: str) -> str:
    """Replace ${VAR} with VAR's value from `const VAR = '...'` in full_text.
    Unresolved placeholders are left as-is."""
    def sub(m: re.Match) -> str:
        var = m.group(1)
        vm = re.search(
            rf"(?:const|let|var)\s+{re.escape(var)}\s*=\s*['\"]([^'\"]*)['\"]",
            full_text,
        )
        return vm.group(1) if vm else m.group(0)
    return re.sub(r"\$\{(\w+)\}", sub, template)


def find_constant_definition(repo_root: Path, name: str) -> tuple[Path, dict[str, str]] | tuple[None, None]:
    """Search apps/ and libs/ for a const/enum block named `name`."""
    search_dirs = [repo_root / "apps", repo_root / "libs"]
    decl_pat = re.compile(rf"(?:const|enum)\s+{re.escape(name)}\b")
    for d in search_dirs:
        if not d.is_dir():
            continue
        for path in d.rglob("*.ts*"):
            try:
                text = path.read_text()
            except (OSError, UnicodeDecodeError):
                continue
            if not decl_pat.search(text):
                continue
            entries = parse_constant_block(text, name)
            if entries:
                return path, entries
    return None, None


# ──────────────────────────────────────────────────────────────────────────
# Section enumeration
# ──────────────────────────────────────────────────────────────────────────

def available_sections(routes_dir: Path) -> list[str]:
    return sorted(p.name for p in routes_dir.iterdir() if p.is_dir())


def extract_path_references(section_dir: Path) -> list[tuple[Path, int, str]]:
    """Return a list of (file, line_no, raw_path_expression) for every `path:`
    line in the section's TSX files."""
    refs: list[tuple[Path, int, str]] = []
    path_pat = re.compile(r"path:\s*(.+?),?\s*$")
    for tsx in section_dir.rglob("*.tsx"):
        try:
            for lineno, line in enumerate(tsx.read_text().splitlines(), start=1):
                m = path_pat.search(line)
                if m:
                    refs.append((tsx, lineno, m.group(1).strip().rstrip(",")))
        except (OSError, UnicodeDecodeError):
            continue
    return refs


def resolve_path_expression(
    expr: str,
    constants_cache: dict[str, dict[str, str]],
    repo_root: Path,
) -> tuple[str | None, str]:
    """Resolve a `path:` expression to a final segment value.

    Returns (resolved_value, source_note). `resolved_value` is None when the
    expression can't be resolved (e.g. a complex expression, or a constant we
    can't find)."""
    # String literal: 'value' / "value" / `value`
    m = re.match(r"^['\"`]([^'\"`]*)['\"`]$", expr)
    if m:
        return m.group(1), "literal"

    # Constant reference: IDENT or IDENT.FIELD
    m = re.match(r"^([A-Z_][A-Z0-9_]*)(?:\.([A-Z_][A-Z0-9_]*))?$", expr)
    if m:
        enum_name, field = m.group(1), m.group(2)
        # Fetch enum definition (cached).
        if enum_name not in constants_cache:
            _, entries = find_constant_definition(repo_root, enum_name)
            constants_cache[enum_name] = entries or {}
        entries = constants_cache[enum_name]
        if not entries:
            return None, f"(could not find definition of {enum_name})"
        if field is None:
            # Bare reference — unusual, but return the whole dict if we can't pick
            return None, f"(bare {enum_name} reference — look up field manually)"
        if field not in entries:
            return None, f"({enum_name}.{field} not found in definition)"
        return entries[field], f"{enum_name}.{field}"

    # Fallback: unknown expression shape.
    return None, f"(unresolved expression: {expr})"


# ──────────────────────────────────────────────────────────────────────────
# Section renderer
# ──────────────────────────────────────────────────────────────────────────

def render_section(section: str, routes_dir: Path, repo_root: Path, base_url: str) -> None:
    section_dir = routes_dir / section
    if not section_dir.is_dir():
        print(f"Error: unknown section '{section}'", file=sys.stderr)
        print("Available sections:", file=sys.stderr)
        for s in available_sections(routes_dir):
            print(f"  {s}", file=sys.stderr)
        sys.exit(2)

    refs = extract_path_references(section_dir)
    if not refs:
        print(f"{section}: no `path:` entries found under {section_dir.relative_to(repo_root)}")
        return

    # Resolve every path expression. Cache constant lookups across refs.
    cache: dict[str, dict[str, str]] = {}
    resolved: list[tuple[Path, int, str, str | None, str]] = []
    for fpath, lineno, expr in refs:
        value, note = resolve_path_expression(expr, cache, repo_root)
        resolved.append((fpath, lineno, expr, value, note))

    # Identify the mount: first entry whose constant field is ROOT, or the
    # first successfully-resolved non-empty segment.
    mount = None
    for _, _, _, value, note in resolved:
        if note.endswith(".ROOT") and value:
            mount = value
            break
    if mount is None:
        # Fall back to the first non-'/' resolved value.
        for _, _, _, value, _ in resolved:
            if value and value != "/":
                mount = value
                break

    # Render header.
    print("═" * 64)
    if mount:
        print(f"  {section}  ({base_url}/{mount})")
    else:
        print(f"  {section}")
    print("═" * 64)
    print()

    # Render resolved routes.
    print("Resolved URLs:")
    for fpath, lineno, expr, value, note in resolved:
        if value is None:
            print(f"  ?  path: {expr}  {note}")
            continue
        if value == "/" or value == "":
            # Index route — re-uses the parent mount.
            url = f"{base_url}/{mount}" if mount else f"{base_url}/"
            print(f"     {url}  (index route — same as parent)")
        elif value == mount:
            # This is the mount itself.
            print(f"     {base_url}/{value}  (section mount)")
        elif value.startswith("$") or value.startswith(":"):
            # Dynamic param route (TanStack `$foo` or React Router `:foo`).
            # NOTE: this route is almost certainly nested under some *other*
            # parent route (e.g. /inventory/devices/$deviceId), not directly
            # under the section mount. We don't parse `getParentRoute:` so we
            # can't know which. Flag it explicitly.
            url = f"{base_url}/{mount}/…/{value}" if mount else f"{base_url}/…/{value}"
            print(f"     {url}  (dynamic param — actual parent route unknown; check {fpath.name} for `getParentRoute`)")
        else:
            url = f"{base_url}/{mount}/{value}" if mount else f"{base_url}/{value}"
            print(f"     {url}")
    print()

    # Render the source notes so the agent can audit the resolution.
    print("Source notes:")
    for fpath, lineno, expr, value, note in resolved:
        rel = fpath.relative_to(repo_root)
        if value is None:
            print(f"  {rel}:{lineno}: path: {expr}  →  {note}")
        else:
            print(f"  {rel}:{lineno}: path: {expr}  →  '{value}'  ({note})")
    print()

    # Surface useSearch / useSearchParams — tells the agent about query-param routes.
    search_hits: list[tuple[Path, int, str]] = []
    for tsx in section_dir.rglob("*.tsx"):
        try:
            for lineno, line in enumerate(tsx.read_text().splitlines(), start=1):
                if re.search(r"\buseSearch\b|\buseSearchParams\b|new URLSearchParams", line):
                    search_hits.append((tsx, lineno, line.strip()))
        except (OSError, UnicodeDecodeError):
            continue

    print("Query-param hints (useSearch / useSearchParams in section):")
    if not search_hits:
        print("  (none detected — routes use path segments only)")
        print("  If a URL you need has `?param=...`, grep the page component for `useSearch`")
        print("  or inspect the running app's address bar after navigating to it.")
    else:
        for fpath, lineno, line in search_hits[:10]:
            rel = fpath.relative_to(repo_root)
            print(f"  {rel}:{lineno}: {line[:100]}")
    print()


# ──────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("section", nargs="?", help="Section name (e.g. Workflow). Omit to list sections.")
    parser.add_argument("--all", action="store_true", help="Render every section")
    parser.add_argument("--base", default="http://localhost:4200",
                        help="Base URL prefix (default: http://localhost:4200)")
    args = parser.parse_args()

    repo_root = find_repo_root()
    if repo_root is None:
        print("Error: could not find dap-workspace root (looked for apps/platform/dashboard-fe/src/routes).",
              file=sys.stderr)
        return 1

    routes_dir = repo_root / "apps" / "platform" / "dashboard-fe" / "src" / "routes"

    if args.all:
        for section in available_sections(routes_dir):
            render_section(section, routes_dir, repo_root, args.base)
        return 0

    if args.section is None:
        print("Available sections:")
        for s in available_sections(routes_dir):
            print(f"  {s}")
        print()
        print("Usage:")
        print("  list-routes.py <Section>           # resolved routes for one section")
        print("  list-routes.py --all               # every section")
        print("  list-routes.py <Section> --base <url>")
        return 0

    # Normalize section name (case-insensitive match against available sections).
    sections = available_sections(routes_dir)
    match = next((s for s in sections if s.lower() == args.section.lower()), None)
    if match is None:
        print(f"Error: unknown section '{args.section}'", file=sys.stderr)
        print("Available sections:", file=sys.stderr)
        for s in sections:
            print(f"  {s}", file=sys.stderr)
        return 2

    render_section(match, routes_dir, repo_root, args.base)
    return 0


if __name__ == "__main__":
    sys.exit(main())
