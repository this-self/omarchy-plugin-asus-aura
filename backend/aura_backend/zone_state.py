"""Read only asusd's top-level multizone flag; never interpret saved colours."""
from pathlib import Path
import re

from .models import PATH_RE, validate_path


def multizone_flag(text):
    """Tokenize comments/strings so nested or commented flags cannot masquerade
    as the root flag. Unknown/malformed layouts fail closed.
    """
    tokens = re.findall(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|'
                        r'[A-Za-z_][A-Za-z0-9_]*|[^\s]', text)
    tokens = [t for t in tokens if not t.startswith(('//', '/*'))]
    stack, values = [], []
    pairs = {')': '(', ']': '[', '}': '{'}
    for i, token in enumerate(tokens):
        if token == 'multizone_on' and stack == ['(']:
            if tokens[i + 1:i + 3] not in [[':', 'true'], [':', 'false']]:
                return None
            if tokens[i + 3:i + 4] not in [[','], [')']]:
                return None
            values.append(tokens[i + 2] == 'true')
        if token in ('(', '[', '{'):
            stack.append(token)
        elif token in pairs:
            if not stack or stack.pop() != pairs[token]:
                return None
    return values[0] if not stack and len(values) == 1 else None


def read_zone_state(path, zones):
    validate_path(path)
    if not zones:
        return "global"
    product = re.fullmatch(PATH_RE, path)[1]
    try:
        flag = multizone_flag(Path(f"/etc/asusd/aura_{product}.ron").read_text())
    except (OSError, UnicodeError):
        flag = None
    return "unknown" if flag is None else ("zoned" if flag else "global")
