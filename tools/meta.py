"""String-aware scanning of the (meta ...) s-expression block in source
pages.  Naive paren counting ends the block early when a quoted string
contains parens (e.g. (description "x (see y)")); the finders here track
in-string state with escapes instead."""
import re

META_START_RE = re.compile(r"\(meta\b")


def find_group(text, start_re):
    """Return (start, end) of the balanced group beginning at
    start_re.search(text), skipping parens inside "..." strings
    (with backslash escapes), or None when absent/unbalanced."""
    m = start_re.search(text)
    if not m:
        return None
    depth = 0
    in_str = False
    esc = False
    for i in range(m.start(), len(text)):
        c = text[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return (m.start(), i + 1)
    return None


def meta_block(text):
    """Return (start, end) of the first (meta ...) block, else None."""
    return find_group(text, META_START_RE)
