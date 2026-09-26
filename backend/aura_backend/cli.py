"""Internal JSON command boundary; stdout is reserved for state responses."""
import json
import sys

from .service import AuraService
from .legacy import state as legacy_snapshot


def main(argv=None, service=None, legacy_state=False):
    args = sys.argv[1:] if argv is None else argv
    service = service if service is not None else AuraService()
    try:
        if args == ["state"]:
            print(json.dumps(legacy_snapshot(service) if legacy_state else service.state()))
        elif len(args) == 3 and args[0] == "apply":
            service.apply(args[1], json.loads(args[2]))
        elif len(args) == 2 and args[0] == "resync":
            service.resync(args[1])
        else:
            raise ValueError("Expected state, apply PATH JSON, or resync PATH")
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0
