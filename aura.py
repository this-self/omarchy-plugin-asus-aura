#!/usr/bin/env python3
"""Compatibility launcher; implementation lives in backend/aura_backend/."""
import sys

sys.dont_write_bytecode = True
from backend.aura_backend.cli import main

if __name__ == "__main__":
    raise SystemExit(main(legacy_state=True))
