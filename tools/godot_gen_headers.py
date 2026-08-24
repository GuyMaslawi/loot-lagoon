#!/usr/bin/env python3
"""Generate the handful of Godot .gen.h headers an iOS plugin needs to compile.

An iOS plugin is built against the engine's own headers -- local_notifications.h
includes core/object/class_db.h -- and several of those headers are produced by
SCons at build time rather than committed. Building the whole engine just to
obtain four generated files costs the better part of an hour, so this drives the
generators the engine itself uses, directly, in a couple of seconds.

Run from inside a Godot source checkout, or point --src at one.

Why this file exists at all: the two xcframeworks in ios/plugins were compiled
on 2026-08-22 by a toolchain that left no trace in the repo -- no build script,
no engine checkout, nothing. The binaries could not be rebuilt, which means they
could not be patched either. That is the actual bug this closes; the SIWA plugin
is just the first thing that needed it.
"""

import argparse
import importlib.util
import os
import sys
from pathlib import Path


class Val:
    """Stands in for SCons' env.Value(): the builders call source[0].read()."""

    def __init__(self, payload):
        self._payload = payload

    def read(self):
        return self._payload


def _load(src: Path, module: str, path: Path):
    """Import a generator by path, with `src` on sys.path so its own
    `import methods` resolves to the checkout's methods.py."""
    spec = importlib.util.spec_from_file_location(module, src / path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[module] = mod
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=".", help="Godot source checkout")
    args = ap.parse_args()

    src = Path(args.src).resolve()
    if not (src / "core" / "object" / "class_db.h").is_file():
        print(f"error: {src} is not a Godot checkout (no core/object/class_db.h)", file=sys.stderr)
        return 1

    # The generators import each other and `methods` by bare name, and
    # methods.get_version_info() reads version.py relative to the cwd.
    sys.path.insert(0, str(src))
    os.chdir(src)

    import methods  # noqa: E402  -- only importable once sys.path is set up

    made = []

    # --- core/extension/gdextension_interface.gen.h --------------------------
    # Not hand-writable: it is a thousand-odd lines generated from
    # gdextension_interface.json, and object.h includes it unconditionally.
    mih = _load(src, "make_interface_header", Path("core/extension/make_interface_header.py"))
    out = src / "core/extension/gdextension_interface.gen.h"
    mih.run([str(out)], [str(src / "core/extension/gdextension_interface.json")], None)
    made.append(out)

    # --- core/extension/ext_wrappers.gen.h ----------------------------------
    mw = _load(src, "make_wrappers", Path("core/extension/make_wrappers.py"))
    out = src / "core/extension/ext_wrappers.gen.h"
    mw.run([str(out)], [], None)
    made.append(out)

    # --- core/version_generated.gen.h ---------------------------------------
    cb = _load(src, "core_builders", Path("core/core_builders.py"))
    out = src / "core/version_generated.gen.h"
    cb.version_info_builder([str(out)], [Val(methods.get_version_info(""))], None)
    made.append(out)

    # --- core/disabled_classes.gen.h ----------------------------------------
    # Empty, because a plugin build disables nothing. The header still has to
    # exist: object.h includes it.
    out = src / "core/disabled_classes.gen.h"
    cb.disabled_class_builder([str(out)], [Val([])], None)
    made.append(out)

    for p in made:
        print(f"  {p.relative_to(src)}  ({p.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
