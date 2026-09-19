#!/usr/bin/env python3
"""Re-send ASUS Aura power/effect settings, preserving actual current brightness."""

import json
import re
import subprocess
import sys

SERVICE = "xyz.ljones.Asusd"
INTERFACE = "xyz.ljones.Aura"


def busctl(*args):
    result = subprocess.run(
        ["busctl", "--system", "--timeout=5s", "--json=short", *args],
        capture_output=True, text=True, timeout=7, check=False,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "ASUS service request failed")
    return result.stdout


def get(path, prop):
    return json.loads(busctl("get-property", SERVICE, path, INTERFACE, prop))["data"]


def set_property(path, prop, signature, *values):
    busctl("set-property", SERVICE, path, INTERFACE, prop, signature,
           *(str(value).lower() if isinstance(value, bool) else str(value)
             for value in values))


def resync(path):
    if not re.fullmatch(r"/xyz/ljones/aura/[A-Za-z0-9_]+", path):
        raise ValueError("Invalid ASUS Aura device path")

    # Snapshot the daemon, not the widget's possibly stale or optimistic UI.
    # Read everything before making any changes. Keep all power zones intact.
    brightness = get(path, "Brightness")
    mode = get(path, "LedMode")
    rows = get(path, "LedPower")[0]
    if type(brightness) is not int or not 0 <= brightness <= 3:
        raise ValueError("Unexpected keyboard brightness")
    if type(mode) is not int or not rows or any(len(row) != 5 for row in rows):
        raise ValueError("Unexpected ASUS lighting settings")

    set_property(path, "LedPower", "(a(ubbbb))", len(rows),
                 *(value for row in rows for value in row))

    # LedMode loads the current effect's saved colours/speed/zones. It can
    # also reset brightness from asusd's config (or turn an Off level on),
    # so always restore the snapshot, even if the mode request fails.
    mode_error = None
    try:
        set_property(path, "LedMode", "u", mode)
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        mode_error = error
    try:
        set_property(path, "Brightness", "u", brightness)
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        detail = f"{mode_error}; " if mode_error else ""
        raise RuntimeError(f"{detail}Could not restore brightness: {error}") from error
    if mode_error:
        raise mode_error


def main():
    try:
        if len(sys.argv) != 2:
            raise ValueError("Expected an ASUS Aura device path")
        resync(sys.argv[1])
    except (RuntimeError, OSError, ValueError, KeyError, IndexError, TypeError,
            subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
