#!/usr/bin/env python3
"""Run directly from any working directory; no package installation needed."""
import sys

sys.dont_write_bytecode = True
from aura_backend.cli import main

if __name__ == "__main__":
    raise SystemExit(main())
