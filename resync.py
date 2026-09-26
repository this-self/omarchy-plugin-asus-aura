#!/usr/bin/env python3
"""Compatibility launcher for recovery without a running widget."""
import sys

sys.dont_write_bytecode = True
from backend.aura_backend.cli import main

if __name__ == "__main__":
    raise SystemExit(main(["resync", *sys.argv[1:]]))
