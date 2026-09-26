"""Process-adapter fixture. Deliberately cannot access D-Bus or hardware."""
import json
from pathlib import Path
import sys

if sys.argv[1:] == ["state"]:
    print((Path(__file__).parent / "pre2021-global.json").read_text())
elif len(sys.argv) == 4 and sys.argv[1] == "apply":
    request = json.loads(sys.argv[3])
    if request.get("value") == "fail":
        print("intentional test failure", file=sys.stderr)
        raise SystemExit(1)
else:
    raise SystemExit("Unexpected fake backend arguments")
