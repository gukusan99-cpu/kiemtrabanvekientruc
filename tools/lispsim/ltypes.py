"""Kieu du lieu AutoLISP cho trinh gia lap lispsim (chi thu vien chuan).

nil = None (Python), T = Sym "T". Danh sach = chuoi o Cons (car/cdr) -> cap cham
(dotted pair) tu nhien. INT = int (32 bit, tran so quay vong), REAL = float.
"""


class Sym:
    __slots__ = ("name", "value")

    def __init__(self, name):
        self.name = name
        self.value = None

    def __repr__(self):
        return self.name


class Cons:
    __slots__ = ("car", "cdr", "pos")

    def __init__(self, car, cdr=None, pos=None):
        self.car = car
        self.cdr = cdr
        self.pos = pos          # (file, line) cua form trong ma nguon

    def __repr__(self):
        return to_str(self, True)


class LispError(Exception):
    """Loi AutoLISP (giong thong bao AutoCAD). kind='lisp' | 'exit' | 'sim'."""

    def __init__(self, msg, kind="lisp"):
        Exception.__init__(self, msg)
        self.msg = msg
        self.kind = kind
        self.stack = None       # ngan xep ten ham defun luc phat sinh
        self.form = None        # form (Cons) noi phat sinh
        self.handled = False    # da goi *error*


class Subr:
    __slots__ = ("name", "fn", "amin", "amax")

    def __init__(self, name, fn, amin=0, amax=None):
        self.name, self.fn, self.amin, self.amax = name, fn, amin, amax

    def __repr__(self):
        return "<Subr: #%s>" % self.name


class USubr:
    __slots__ = ("name", "params", "locals", "body", "src")

    def __init__(self, name, params, locs, body, src=None):
        self.name, self.params, self.locals, self.body, self.src = name, params, locs, body, src

    def __repr__(self):
        return "<USUBR @%x: %s>" % (id(self) & 0xFFFFFF, self.name)


class Ename:
    __slots__ = ("ent",)

    def __init__(self, ent):
        self.ent = ent

    def __repr__(self):
        return "<Entity name: %x>" % (0x7FF700000000 + int(self.ent.handle, 16) * 16)


class PickSet:
    __slots__ = ("items",)

    def __init__(self, items=None):
        self.items = list(items or [])

    def __repr__(self):
        return "<Selection set: %x>" % (id(self) & 0xFFFF)


class FileH:
    __slots__ = ("path", "mode", "fh", "closed")

    def __init__(self, path, mode, fh):
        self.path, self.mode, self.fh, self.closed = path, mode, fh, False

    def __repr__(self):
        return '<File: "%s">' % self.path


class VlaObj:
    __slots__ = ("kind", "ent")

    def __init__(self, kind, ent=None):
        self.kind, self.ent = kind, ent

    def __repr__(self):
        return "#<VLA-OBJECT IAcad%s %x>" % (self.kind, id(self) & 0xFFFFFF)


class SafeArray:
    __slots__ = ("vals",)

    def __init__(self, vals):
        self.vals = list(vals)

    def __repr__(self):
        return "#<safearray...>"


class Variant:
    __slots__ = ("val",)

    def __init__(self, val):
        self.val = val

    def __repr__(self):
        return "#<variant 8197 ...>"


class CatchErr:
    __slots__ = ("msg", "err")

    def __init__(self, msg, err=None):
        self.msg, self.err = msg, err

    def __repr__(self):
        return "#<%%catch-all-apply-error%%>"


# ---------------- tien ich danh sach ----------------
def mklist(items, tail=None):
    r = tail
    for x in reversed(list(items)):
        r = Cons(x, r)
    return r


def iterlist(x):
    while isinstance(x, Cons):
        yield x.car
        x = x.cdr


def tolist(x):
    out = []
    while isinstance(x, Cons):
        out.append(x.car)
        x = x.cdr
    return out


def is_proper(x):
    while isinstance(x, Cons):
        x = x.cdr
    return x is None


# ---------------- in ra (princ / prin1) ----------------
def fmt_real(x):
    if x != x:
        return "-1.#IND"
    if x in (float("inf"), float("-inf")):
        return "1.#INF" if x > 0 else "-1.#INF"
    s = "%.6g" % x
    if "e" in s:
        m, e = s.split("e")
        if "." not in m:
            m += ".0"
        sign = "-" if e.startswith("-") else "+"
        e = e.lstrip("+-").lstrip("0") or "0"
        return "%se%s%03d" % (m, sign, int(e))
    if "." not in s and "inf" not in s:
        s += ".0"
    return s


def _esc(s):
    out = []
    for c in s:
        if c == "\\":
            out.append("\\\\")
        elif c == '"':
            out.append('\\"')
        elif c == "\n":
            out.append("\\n")
        elif c == "\t":
            out.append("\\t")
        elif c == "\r":
            out.append("\\r")
        elif c == "\x1b":
            out.append("\\e")
        else:
            out.append(c)
    return '"' + "".join(out) + '"'


def to_str(x, quote=False, depth=0):
    if depth > 60:
        return "..."
    if x is None:
        return "nil"
    if isinstance(x, bool):
        return "T" if x else "nil"
    if isinstance(x, int):
        return str(x)
    if isinstance(x, float):
        return fmt_real(x)
    if isinstance(x, str):
        return _esc(x) if quote else x
    if isinstance(x, Sym):
        return x.name
    if isinstance(x, Cons):
        parts = []
        n = 0
        while isinstance(x, Cons):
            parts.append(to_str(x.car, quote, depth + 1))
            x = x.cdr
            n += 1
            if n > 2000:
                parts.append("...")
                x = None
                break
        s = "(" + " ".join(parts)
        if x is not None:
            s += " . " + to_str(x, quote, depth + 1)
        return s + ")"
    return repr(x)


def lisp_type(x, T):
    """ten kieu theo (type x)"""
    if x is None:
        return None
    if isinstance(x, int):
        return "INT"
    if isinstance(x, float):
        return "REAL"
    if isinstance(x, str):
        return "STR"
    if isinstance(x, Sym):
        return "SYM"
    if isinstance(x, Cons):
        return "LIST"
    if isinstance(x, Subr):
        return "SUBR"
    if isinstance(x, USubr):
        return "USUBR"
    if isinstance(x, Ename):
        return "ENAME"
    if isinstance(x, PickSet):
        return "PICKSET"
    if isinstance(x, FileH):
        return "FILE"
    if isinstance(x, VlaObj):
        return "VLA-OBJECT"
    if isinstance(x, SafeArray):
        return "SAFEARRAY"
    if isinstance(x, Variant):
        return "VARIANT"
    if isinstance(x, CatchErr):
        return "VL-CATCH-ALL-APPLY-ERROR"
    return "?"
