"""Trinh thong dich tap con AutoLISP (pham vi dong - dynamic scope).

Binding nong (shallow binding): moi Sym giu gia tri hien tai; goi ham defun luu gia tri
cu cua tham so + bien cuc bo, gan moi, chay than ham roi khoi phuc (ke ca khi loi).
Loi chua bi vl-catch-all-apply bat -> goi *error* NGAY TAI NOI LOI (truoc khi go
bien cuc bo) giong AutoCAD.
"""
import math
import re
import sys

from .ltypes import (Sym, Cons, LispError, Subr, USubr, Ename, PickSet, FileH, VlaObj,
                     SafeArray, Variant, CatchErr, mklist, iterlist, tolist, is_proper,
                     to_str, lisp_type)
from .reader import read_all

sys.setrecursionlimit(max(sys.getrecursionlimit(), 30000))


def wrap32(i):
    i &= 0xFFFFFFFF
    return i - 0x100000000 if i >= 0x80000000 else i


def isnum(x):
    return (isinstance(x, (int, float))) and not isinstance(x, bool)


class Interp:
    def __init__(self):
        self.symtab = {}
        self.T = self.intern("T")
        self.T.value = self.T
        self.special = {}
        self.stack = []             # ten ham defun dang chay
        self.catch_depth = 0
        self.out = []               # moi chuoi princ/prompt
        self.errors = []            # loi khong bi bat (da goi *error*)
        self.caught = []            # loi bi vl-catch-all-apply bat (de soi bug an)
        self.sim_bugs = []          # loi noi bo cua trinh gia lap (bug tool)
        self.warnings = []          # canh bao (tran so nguyen...)
        self.calls = {}             # dem so lan goi ham defun
        self._lambda_n = 0
        self.LAMBDA = self.intern("LAMBDA")
        self.QUOTE = self.intern("QUOTE")
        self.SLASH = self.intern("/")
        self._install_specials()
        self._install_builtins()

    # ------------------------------------------------------------ symbols
    def intern(self, name):
        s = self.symtab.get(name)
        if s is None:
            s = Sym(name)
            self.symtab[name] = s
        return s

    def sym(self, name):
        return self.intern(name.upper())

    def setv(self, name, val):
        self.sym(name).value = val

    def getv(self, name):
        return self.sym(name).value

    def defbi(self, name, fn, amin=0, amax=None):
        self.sym(name).value = Subr(name.upper(), fn, amin, amax)

    def undef(self, name):
        self.sym(name).value = None

    # ------------------------------------------------------------ output
    def emit(self, s):
        self.out.append(s)

    def output(self):
        return "".join(self.out)

    # ------------------------------------------------------------ eval
    def ev(self, x):
        if isinstance(x, Sym):
            return x.value
        if isinstance(x, Cons):
            head = x.car
            if isinstance(head, Sym):
                sf = self.special.get(head)
                if sf is not None:
                    return sf(x)
                f = head.value
                if f is None:
                    raise self._undef(head, x)
            elif isinstance(head, Cons) and head.car is self.LAMBDA:
                f = self._mk_lambda(head)
            else:
                f = self.ev(head)
            args = []
            a = x.cdr
            while isinstance(a, Cons):
                args.append(self.ev(a.car))
                a = a.cdr
            return self.call(f, args, x)
        return x

    unsupported_prefixes = ()

    def _undef(self, sym, form):
        n = sym.name
        if self.unsupported_prefixes and n.startswith(self.unsupported_prefixes):
            e = self._err("SIM-UNSUPPORTED: lispsim chua gia lap ham " + n, form, "sim")
            self.sim_bugs.append((e.msg, list(self.stack), self.where(form), ""))
            return e
        return self._err("no function definition: " + n, form)

    def _err(self, msg, form=None, kind="lisp"):
        e = LispError(msg, kind)
        e.form = form
        return e

    def resolve_fn(self, f):
        if isinstance(f, Sym):
            v = f.value
            if v is None:
                raise self._undef(f, None)
            return v
        if isinstance(f, Cons) and f.car is self.LAMBDA:
            return self._mk_lambda(f)
        return f

    def call(self, f, args, form=None):
        if isinstance(f, Subr):
            n = len(args)
            if n < f.amin:
                raise self._err("too few arguments", form)
            if f.amax is not None and n > f.amax:
                raise self._err("too many arguments", form)
            try:
                return f.fn(args)
            except LispError as e:
                if e.form is None:
                    e.form = form
                raise
            except RecursionError:
                raise self._err("stack overflow (lispsim: Python recursion)", form, "sim")
            except Exception as ex:  # bug cua trinh gia lap
                import traceback
                msg = "SIM-INTERNAL %s: %s: %s" % (f.name, type(ex).__name__, ex)
                self.sim_bugs.append((msg, list(self.stack), self.where(form),
                                      traceback.format_exc()))
                raise self._err(msg, form, "sim")
        if isinstance(f, USubr):
            return self.call_usubr(f, args, form)
        if isinstance(f, (Sym, Cons)):
            return self.call(self.resolve_fn(f), args, form)
        raise self._err("bad function: " + to_str(f, True), form)

    def call_usubr(self, f, args, form=None):
        np = len(f.params)
        if len(args) != np:
            raise self._err("too few arguments" if len(args) < np else "too many arguments", form)
        saved = [(s, s.value) for s in f.params]
        saved += [(s, s.value) for s in f.locals]
        for s, v in zip(f.params, args):
            s.value = v
        for s in f.locals:
            s.value = None
        self.stack.append(f.name)
        self.calls[f.name] = self.calls.get(f.name, 0) + 1
        try:
            r = None
            for b in f.body:
                r = self.ev(b)
            return r
        except LispError as e:
            if e.stack is None:
                e.stack = list(self.stack)
            if self.catch_depth == 0 and not e.handled:
                self.toplevel_error(e)
            raise
        finally:
            self.stack.pop()
            for s, v in reversed(saved):
                s.value = v

    def where(self, form):
        if isinstance(form, Cons) and form.pos:
            return "%s:%d" % form.pos
        return "?"

    def toplevel_error(self, e):
        """goi *error* (gia tri hien hanh, co the la bien cuc bo) truoc khi go stack"""
        e.handled = True
        if e.stack is None:
            e.stack = list(self.stack)
        self.errors.append(e)
        h = self.sym("*ERROR*").value
        if isinstance(h, (USubr, Subr)):
            self.catch_depth += 1
            try:
                self.call(h, [e.msg])
            except LispError as e2:
                self.emit("\n; error in *error*: " + e2.msg)
            finally:
                self.catch_depth -= 1
        else:
            self.emit("\n; error: " + e.msg)

    def apply(self, f, args):
        return self.call(self.resolve_fn(f), args)

    def truthy(self, x):
        return x is not None

    # ------------------------------------------------------------ load / run
    def load_text(self, text, fname="<string>"):
        forms = read_all(text, self.intern, fname)
        r = None
        for f in forms:
            r = self.ev(f)
        return r

    def eval_str(self, text):
        """chay chuoi lisp o muc top-level (loi -> *error*), tra ve (gia tri, loi)"""
        try:
            return self.load_text(text, "<cmd>"), None
        except LispError as e:
            if not e.handled:
                self.toplevel_error(e)
            return None, e

    # ------------------------------------------------------------ specials
    def _install_specials(self):
        sp = self.special
        I = self.intern
        sp[I("QUOTE")] = lambda x: x.cdr.car if x.cdr else None
        sp[I("FUNCTION")] = self._sf_function
        sp[I("SETQ")] = self._sf_setq
        sp[I("DEFUN")] = self._sf_defun
        sp[I("DEFUN-Q")] = self._sf_defun
        sp[I("LAMBDA")] = lambda x: self._mk_lambda(x)
        sp[I("IF")] = self._sf_if
        sp[I("COND")] = self._sf_cond
        sp[I("PROGN")] = self._sf_progn
        sp[I("AND")] = self._sf_and
        sp[I("OR")] = self._sf_or
        sp[I("WHILE")] = self._sf_while
        sp[I("REPEAT")] = self._sf_repeat
        sp[I("FOREACH")] = self._sf_foreach

    def _sf_function(self, x):
        a = x.cdr.car if x.cdr else None
        if isinstance(a, Cons) and a.car is self.LAMBDA:
            return self._mk_lambda(a)
        return a

    def _sf_setq(self, x):
        a = x.cdr
        r = None
        while isinstance(a, Cons):
            s = a.car
            if not isinstance(a.cdr, Cons):
                raise self._err("too few arguments", x)
            if not isinstance(s, Sym):
                raise self._err("bad argument type: symbolp " + to_str(s, True), x)
            if s is self.T or s.name == "NIL":
                raise self._err("attempt to set constant: " + s.name, x)
            r = self.ev(a.cdr.car)
            s.value = r
            a = a.cdr.cdr
        return r

    def _parse_params(self, plist, form):
        params, locs = [], []
        cur = params
        for p in iterlist(plist):
            if p is self.SLASH:
                cur = locs
                continue
            if not isinstance(p, Sym):
                raise self._err("bad argument list: " + to_str(plist, True), form)
            cur.append(p)
        return params, locs

    def _sf_defun(self, x):
        name = x.cdr.car
        if not isinstance(name, Sym):
            raise self._err("bad argument type: symbolp " + to_str(name, True), x)
        plist = x.cdr.cdr.car if x.cdr.cdr else None
        params, locs = self._parse_params(plist, x)
        body = tolist(x.cdr.cdr.cdr) if x.cdr.cdr else []
        name.value = USubr(name.name, params, locs, body, self.where(x))
        return name

    def _mk_lambda(self, x):
        plist = x.cdr.car if x.cdr else None
        params, locs = self._parse_params(plist, x)
        body = tolist(x.cdr.cdr) if x.cdr else []
        where = self.where(x)
        owner = self.stack[-1] if self.stack else "top"
        return USubr("lambda@%s(%s)" % (owner, where), params, locs, body, where)

    def _sf_if(self, x):
        args = tolist(x.cdr)
        if len(args) < 2:
            raise self._err("too few arguments", x)
        if len(args) > 3:
            raise self._err("too many arguments", x)
        if self.ev(args[0]) is not None:
            return self.ev(args[1])
        if len(args) == 3:
            return self.ev(args[2])
        return None

    def _sf_cond(self, x):
        for cl in iterlist(x.cdr):
            if not isinstance(cl, Cons):
                raise self._err("bad argument type: consp " + to_str(cl, True), x)
            v = self.ev(cl.car)
            if v is not None:
                b = cl.cdr
                while isinstance(b, Cons):
                    v = self.ev(b.car)
                    b = b.cdr
                return v
        return None

    def _sf_progn(self, x):
        r = None
        for b in iterlist(x.cdr):
            r = self.ev(b)
        return r

    def _sf_and(self, x):
        for b in iterlist(x.cdr):
            if self.ev(b) is None:
                return None
        return self.T

    def _sf_or(self, x):
        for b in iterlist(x.cdr):
            if self.ev(b) is not None:
                return self.T
        return None

    def _sf_while(self, x):
        test = x.cdr.car
        body = tolist(x.cdr.cdr)
        r = None
        guard = 0
        while self.ev(test) is not None:
            for b in body:
                r = self.ev(b)
            guard += 1
            if guard > 5000000:
                raise self._err("lispsim: vong lap while qua 5 trieu lan (treo?)", x, "sim")
        return r

    def _sf_repeat(self, x):
        n = self.ev(x.cdr.car)
        if not isinstance(n, int) or isinstance(n, bool):
            raise self._err("bad argument type: fixnump: " + to_str(n, True), x)
        r = None
        body = tolist(x.cdr.cdr)
        for _ in range(max(0, n)):
            for b in body:
                r = self.ev(b)
        return r

    def _sf_foreach(self, x):
        var = x.cdr.car
        if not isinstance(var, Sym):
            raise self._err("bad argument type: symbolp " + to_str(var, True), x)
        lst = self.ev(x.cdr.cdr.car)
        if lst is not None and not isinstance(lst, Cons):
            raise self._err("bad argument type: listp " + to_str(lst, True), x)
        body = tolist(x.cdr.cdr.cdr)
        old = var.value
        r = None
        try:
            while isinstance(lst, Cons):
                var.value = lst.car
                for b in body:
                    r = self.ev(b)
                lst = lst.cdr
            if lst is not None:
                raise self._err("bad list: " + to_str(lst, True), x)
        finally:
            var.value = old
        return r

    # ------------------------------------------------------------ type checks
    def num(self, x):
        if not isnum(x):
            raise LispError("bad argument type: numberp: " + to_str(x, True))
        return x

    def int_(self, x):
        if not isinstance(x, int) or isinstance(x, bool):
            raise LispError("bad argument type: fixnump: " + to_str(x, True))
        return x

    def str_(self, x):
        if not isinstance(x, str):
            raise LispError("bad argument type: stringp " + to_str(x, True))
        return x

    def lst(self, x):
        if x is not None and not isinstance(x, Cons):
            raise LispError("bad argument type: listp " + to_str(x, True))
        return x

    def plst(self, x):
        """danh sach dung (khong cham)"""
        self.lst(x)
        out = []
        while isinstance(x, Cons):
            out.append(x.car)
            x = x.cdr
        if x is not None:
            raise LispError("bad list: " + to_str(x, True))
        return out

    def symb(self, x):
        if not isinstance(x, Sym):
            raise LispError("bad argument type: symbolp " + to_str(x, True))
        return x

    def pt(self, x):
        if not isinstance(x, Cons):
            raise LispError("bad argument type: 2D/3D point: " + to_str(x, True))
        v = tolist(x)
        if len(v) < 2 or not all(isnum(a) for a in v[:3]):
            raise LispError("bad argument type: 2D/3D point: " + to_str(x, True))
        return [float(a) for a in v[:3]]

    def b(self, cond):
        return self.T if cond else None

    # ------------------------------------------------------------ equality
    def eq(self, a, b):
        if a is b:
            return True
        if isnum(a) and isnum(b):
            return type(a) == type(b) and a == b
        if isinstance(a, Ename) and isinstance(b, Ename):
            return a.ent is b.ent
        return False

    def equal(self, a, b, fuzz=0.0):
        if a is b:
            return True
        if isnum(a) and isnum(b):
            return abs(a - b) <= fuzz
        if isinstance(a, str) and isinstance(b, str):
            return a == b
        if isinstance(a, Cons) and isinstance(b, Cons):
            while isinstance(a, Cons) and isinstance(b, Cons):
                if not self.equal(a.car, b.car, fuzz):
                    return False
                a, b = a.cdr, b.cdr
            return self.equal(a, b, fuzz)
        if isinstance(a, Ename) and isinstance(b, Ename):
            return a.ent is b.ent
        if isinstance(a, VlaObj) and isinstance(b, VlaObj):
            return a.kind == b.kind and a.ent is b.ent
        return False

    # ------------------------------------------------------------ builtins
    def _install_builtins(self):
        d = self.defbi
        T = self.T
        B = self.b

        # --- so hoc ---
        def plus(a):
            a = [self.num(x) for x in a]
            if all(isinstance(x, int) for x in a):
                r = sum(a)
                w = wrap32(r)
                if w != r:
                    self.warnings.append("tran so nguyen (+): %d" % r)
                return w
            return float(sum(a))

        def minus(a):
            a = [self.num(x) for x in a]
            if not a:
                return 0
            if len(a) == 1:
                r = -a[0]
            else:
                r = a[0]
                for x in a[1:]:
                    r = r - x
            if all(isinstance(x, int) for x in a):
                return wrap32(r)
            return float(r)

        def times(a):
            a = [self.num(x) for x in a]
            r = 1
            for x in a:
                r = r * x
            if all(isinstance(x, int) for x in a):
                w = wrap32(r)
                if w != r:
                    self.warnings.append("tran so nguyen (*): %d" % r)
                return w
            return float(r)

        def idiv(x, y):
            if y == 0:
                raise LispError("divide by zero")
            q = abs(x) // abs(y)
            return q if (x >= 0) == (y >= 0) else -q

        def divide(a):
            a = [self.num(x) for x in a]
            if not a:
                return 0
            r = a[0]
            for y in a[1:]:
                if isinstance(r, int) and isinstance(y, int):
                    r = idiv(r, y)
                else:
                    if y == 0:
                        raise LispError("divide by zero")
                    r = float(r) / y
            return r

        d("+", plus)
        d("-", minus)
        d("*", times)
        d("/", divide)
        d("1+", lambda a: plus([a[0], 1]), 1, 1)
        d("1-", lambda a: minus([a[0], 1]), 1, 1)

        def rem_(a):
            a = [self.num(x) for x in a]
            if not a:
                return 0
            r = a[0]
            for y in a[1:]:
                if y == 0:
                    raise LispError("divide by zero")
                if isinstance(r, int) and isinstance(y, int):
                    r = r - y * idiv(r, y)
                else:
                    r = math.fmod(float(r), float(y))
            return r
        d("REM", rem_, 1)

        def mm(fn):
            def f(a):
                a = [self.num(x) for x in a]
                if not a:
                    return 0
                r = fn(a)
                if any(isinstance(x, float) for x in a):
                    return float(r)
                return r
            return f
        d("MIN", mm(min))
        d("MAX", mm(max))

        def abs_(a):
            x = self.num(a[0])
            return wrap32(abs(x)) if isinstance(x, int) else abs(x)
        d("ABS", abs_, 1, 1)

        def fix_(a):
            x = self.num(a[0])
            if isinstance(x, int):
                return x
            if x != x or abs(x) > 1e300:
                raise LispError("bad argument type: fixnump: " + to_str(x))
            r = int(x)
            w = wrap32(r)
            if w != r:
                self.warnings.append("tran so nguyen (fix %s)" % to_str(x))
            return w
        d("FIX", fix_, 1, 1)
        d("FLOAT", lambda a: float(self.num(a[0])), 1, 1)

        def sqrt_(a):
            x = self.num(a[0])
            if x < 0:
                raise LispError("function undefined for argument: " + to_str(x))
            return math.sqrt(x)
        d("SQRT", sqrt_, 1, 1)
        d("SIN", lambda a: math.sin(self.num(a[0])), 1, 1)
        d("COS", lambda a: math.cos(self.num(a[0])), 1, 1)

        def atan_(a):
            y = self.num(a[0])
            if len(a) > 1:
                return math.atan2(y, self.num(a[1]))
            return math.atan(y)
        d("ATAN", atan_, 1, 2)

        def log_(a):
            x = self.num(a[0])
            if x <= 0:
                raise LispError("function undefined for argument: " + to_str(x))
            return math.log(x)
        d("LOG", log_, 1, 1)
        d("EXP", lambda a: math.exp(self.num(a[0])), 1, 1)

        def expt_(a):
            x, y = self.num(a[0]), self.num(a[1])
            if isinstance(x, int) and isinstance(y, int) and y >= 0:
                return wrap32(x ** y)
            if x == 0 and y < 0:
                raise LispError("divide by zero")
            try:
                return float(x) ** float(y)
            except Exception:
                raise LispError("function undefined for argument: " + to_str(x))
        d("EXPT", expt_, 2, 2)

        def logand(a):
            r = -1
            for x in a:
                r &= self.int_(x)
            return r if a else 0

        def logior(a):
            r = 0
            for x in a:
                r |= self.int_(x)
            return r
        d("LOGAND", logand)
        d("LOGIOR", logior)
        d("~", lambda a: ~self.int_(a[0]), 1, 1)

        def lsh(a):
            x = self.int_(a[0])
            n = self.int_(a[1]) if len(a) > 1 else 0
            return wrap32(x << n) if n >= 0 else wrap32((x & 0xFFFFFFFF) >> (-n))
        d("LSH", lsh, 0, 2)

        def gcd_(a):
            return math.gcd(self.int_(a[0]), self.int_(a[1]))
        d("GCD", gcd_, 2, 2)
        d("MINUSP", lambda a: B(self.num(a[0]) < 0), 1, 1)
        d("ZEROP", lambda a: B(self.num(a[0]) == 0), 1, 1)
        d("NUMBERP", lambda a: B(isnum(a[0])), 1, 1)

        # --- so sanh ---
        def cmp_args(a, op, name):
            for x in a:
                if not (isnum(x) or isinstance(x, str)):
                    raise LispError("bad argument type: numberp: " + to_str(x, True))
            for x, y in zip(a, a[1:]):
                if isinstance(x, str) != isinstance(y, str):
                    raise LispError("bad argument type: " + ("stringp " if isinstance(x, str) else "numberp: ") + to_str(y, True))
                if not op(x, y):
                    return None
            return T

        def eqnum(x, y):
            if isnum(x) and isnum(y):
                return x == y
            if isinstance(x, str) and isinstance(y, str):
                return x == y
            return self.eq(x, y)

        def eq_(a):
            for x, y in zip(a, a[1:]):
                if not eqnum(x, y):
                    return None
            return T

        def neq_(a):
            for x, y in zip(a, a[1:]):
                if eqnum(x, y):
                    return None
            return T
        d("=", eq_, 1)
        d("/=", neq_, 1)
        d("<", lambda a: cmp_args(a, lambda x, y: x < y, "<"), 1)
        d(">", lambda a: cmp_args(a, lambda x, y: x > y, ">"), 1)
        d("<=", lambda a: cmp_args(a, lambda x, y: x <= y, "<="), 1)
        d(">=", lambda a: cmp_args(a, lambda x, y: x >= y, ">="), 1)
        d("EQ", lambda a: B(self.eq(a[0], a[1])), 2, 2)
        d("EQUAL", lambda a: B(self.equal(a[0], a[1], float(self.num(a[2])) if len(a) > 2 else 0.0)), 2, 3)

        # --- logic / kieu ---
        d("NOT", lambda a: B(a[0] is None), 1, 1)
        d("NULL", lambda a: B(a[0] is None), 1, 1)
        d("ATOM", lambda a: B(not isinstance(a[0], Cons)), 1, 1)
        d("LISTP", lambda a: B(a[0] is None or isinstance(a[0], Cons)), 1, 1)
        d("VL-CONSP", lambda a: B(isinstance(a[0], Cons)), 1, 1)
        d("BOUNDP", lambda a: B(self.symb(a[0]).value is not None), 1, 1)
        d("VL-SYMBOLP", lambda a: B(isinstance(a[0], Sym)), 1, 1)
        d("VL-SYMBOL-NAME", lambda a: self.symb(a[0]).name, 1, 1)
        d("VL-SYMBOL-VALUE", lambda a: self.symb(a[0]).value, 1, 1)

        def type_(a):
            t = lisp_type(a[0], T)
            if t is None:
                return None
            if t == "?":
                raise LispError("SIM-INTERNAL: type cua " + repr(a[0]), "sim")
            return self.intern(t)
        d("TYPE", type_, 1, 1)

        def set_(a):
            s = self.symb(a[0])
            s.value = a[1]
            return a[1]
        d("SET", set_, 2, 2)
        d("EVAL", lambda a: self.ev(a[0]), 1, 1)

        def apply_(a):
            return self.apply(a[0], self.plst(a[1]))
        d("APPLY", apply_, 2, 2)

        def read_(a):
            s = self.str_(a[0]) if a else ""
            forms = read_all(s, self.intern, "<read>")
            return forms[0] if forms else None
        d("READ", read_, 0, 1)

        # --- danh sach ---
        def car(x):
            if x is None:
                return None
            if isinstance(x, Cons):
                return x.car
            raise LispError("bad argument type: consp " + to_str(x, True))

        def cdr(x):
            if x is None:
                return None
            if isinstance(x, Cons):
                return x.cdr
            raise LispError("bad argument type: consp " + to_str(x, True))
        d("CAR", lambda a: car(a[0]), 1, 1)
        d("CDR", lambda a: cdr(a[0]), 1, 1)
        for nm in ["CAAR", "CADR", "CDAR", "CDDR", "CAAAR", "CAADR", "CADAR", "CADDR", "CDAAR",
                   "CDADR", "CDDAR", "CDDDR", "CADDDR", "CDDDDR", "CAADDR", "CADADR", "CDADDR"]:
            ops = nm[1:-1]

            def mk(ops):
                def f(a):
                    x = a[0]
                    for o in reversed(ops):
                        x = car(x) if o == "A" else cdr(x)
                    return x
                return f
            d(nm, mk(ops), 1, 1)
        d("CONS", lambda a: Cons(a[0], a[1]), 2, 2)
        d("LIST", lambda a: mklist(a))

        def append_(a):
            if not a:
                return None
            for x in a:
                self.lst(x)
            res = a[-1]
            for x in reversed(a[:-1]):
                res = mklist(self.plst(x), res)
            return res
        d("APPEND", append_)

        def length_(a):
            return len(self.plst(a[0]))
        d("LENGTH", length_, 1, 1)
        d("VL-LIST-LENGTH", lambda a: len(self.plst(a[0])) if is_proper(a[0]) else None, 1, 1)

        def nth_(a):
            n = self.int_(a[0])
            x = self.lst(a[1])
            if n < 0:
                return None
            while n > 0 and isinstance(x, Cons):
                x = x.cdr
                n -= 1
            return x.car if isinstance(x, Cons) else None
        d("NTH", nth_, 2, 2)

        def last_(a):
            x = self.lst(a[0])
            r = None
            while isinstance(x, Cons):
                r = x.car
                x = x.cdr
            return r
        d("LAST", last_, 1, 1)
        d("REVERSE", lambda a: mklist(list(reversed(self.plst(a[0])))), 1, 1)

        def member_(a):
            x = self.lst(a[1])
            while isinstance(x, Cons):
                if self.equal(a[0], x.car):
                    return x
                x = x.cdr
            return None
        d("MEMBER", member_, 2, 2)

        def assoc_(a):
            x = self.lst(a[1])
            while isinstance(x, Cons):
                it = x.car
                if isinstance(it, Cons) and self.equal(a[0], it.car):
                    return it
                if it is not None and not isinstance(it, Cons):
                    raise LispError("bad argument type: consp " + to_str(it, True))
                x = x.cdr
            return None
        d("ASSOC", assoc_, 2, 2)

        def subst_(a):
            new, old = a[0], a[1]
            items = self.plst(a[2])
            return mklist([new if self.equal(old, x) else x for x in items])
        d("SUBST", subst_, 3, 3)

        def mapcar_(a):
            f = self.resolve_fn(a[0])
            lists = [self.plst(x) for x in a[1:]]
            if not lists:
                raise LispError("too few arguments")
            n = min(len(l) for l in lists)
            return mklist([self.call(f, [l[i] for l in lists]) for i in range(n)])
        d("MAPCAR", mapcar_, 2)

        def vl_remove(a):
            return mklist([x for x in self.plst(a[1]) if not self.equal(a[0], x)])
        d("VL-REMOVE", vl_remove, 2, 2)

        def pred(a, want):
            f = self.resolve_fn(a[0])
            return mklist([x for x in self.plst(a[1]) if (self.call(f, [x]) is not None) == want])
        d("VL-REMOVE-IF", lambda a: pred(a, False), 2, 2)
        d("VL-REMOVE-IF-NOT", lambda a: pred(a, True), 2, 2)

        def member_if(a, want):
            f = self.resolve_fn(a[0])
            x = self.lst(a[1])
            while isinstance(x, Cons):
                if (self.call(f, [x.car]) is not None) == want:
                    return x
                x = x.cdr
            return None
        d("VL-MEMBER-IF", lambda a: member_if(a, True), 2, 2)
        d("VL-MEMBER-IF-NOT", lambda a: member_if(a, False), 2, 2)

        def some_(a):
            f = self.resolve_fn(a[0])
            lists = [self.plst(x) for x in a[1:]]
            n = min(len(l) for l in lists)
            for i in range(n):
                r = self.call(f, [l[i] for l in lists])
                if r is not None:
                    return r
            return None

        def every_(a):
            f = self.resolve_fn(a[0])
            lists = [self.plst(x) for x in a[1:]]
            n = min(len(l) for l in lists)
            for i in range(n):
                if self.call(f, [l[i] for l in lists]) is None:
                    return None
            return T
        d("VL-SOME", some_, 2)
        d("VL-EVERY", every_, 2)

        def position_(a):
            for i, x in enumerate(self.plst(a[1])):
                if self.equal(a[0], x):
                    return i
            return None
        d("VL-POSITION", position_, 2, 2)

        def sort_core(items, f):
            import functools

            def c(x, y):
                if self.call(f, [x, y]) is not None:
                    return -1
                if self.call(f, [y, x]) is not None:
                    return 1
                return 0
            return sorted(items, key=functools.cmp_to_key(c))

        def vl_sort(a):
            f = self.resolve_fn(a[1])
            items = sort_core(self.plst(a[0]), f)
            # AutoCAD: vl-sort xoa phan tu trung (eq) - vd so nguyen, so thuc, symbol
            out = []
            for x in items:
                if out and not isinstance(x, (Cons, str)) and self.eq(out[-1], x):
                    continue
                out.append(x)
            return mklist(out)
        d("VL-SORT", vl_sort, 2, 2)

        def vl_sort_i(a):
            f = self.resolve_fn(a[1])
            items = self.plst(a[0])
            idx = sort_core(list(range(len(items))), Subr("idx", lambda p: self.call(f, [items[p[0]], items[p[1]]]), 2, 2))
            return mklist(idx)
        d("VL-SORT-I", vl_sort_i, 2, 2)
        d("ACAD_STRLSORT", lambda a: mklist(sorted(self.plst(a[0]), key=lambda s: self.str_(s).upper())), 1, 1)

        def list_star(a):
            if len(a) == 1:
                return a[0]
            return mklist(a[:-1], a[-1])
        d("VL-LIST*", list_star, 1)

        # --- chuoi ---
        def strcat(a):
            return "".join(self.str_(x) for x in a)
        d("STRCAT", strcat)
        d("STRLEN", lambda a: sum(len(self.str_(x)) for x in a))

        def substr(a):
            s = self.str_(a[0])
            st = self.int_(a[1])
            if st < 1:
                raise LispError("bad argument value: positive " + to_str(st))
            if len(a) > 2 and a[2] is not None:
                n = self.int_(a[2])
                if n < 0:
                    raise LispError("bad argument value: non-negative " + to_str(n))
                return s[st - 1:st - 1 + n]
            return s[st - 1:]
        d("SUBSTR", substr, 2, 3)

        def strcase(a):
            s = self.str_(a[0])
            return s.lower() if len(a) > 1 and a[1] is not None else s.upper()
        d("STRCASE", strcase, 1, 2)
        d("ITOA", lambda a: str(self.int_(a[0])), 1, 1)

        def atoi(a):
            s = self.str_(a[0]).strip()
            m = re.match(r"[+-]?\d+", s)
            return wrap32(int(m.group(0))) if m else 0
        d("ATOI", atoi, 1, 1)

        def atof(a):
            s = self.str_(a[0]).strip()
            m = re.match(r"[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?", s)
            return float(m.group(0)) if m else 0.0
        d("ATOF", atof, 1, 1)

        def rtos(a):
            x = float(self.num(a[0]))
            mode = self.int_(a[1]) if len(a) > 1 and a[1] is not None else self.getvar_raw("LUNITS", 2)
            prec = self.int_(a[2]) if len(a) > 2 and a[2] is not None else self.getvar_raw("LUPREC", 4)
            return self.rtos(x, mode, prec)
        d("RTOS", rtos, 1, 3)

        def distof(a):
            s = self.str_(a[0]).strip()
            if re.match(r"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$", s):
                return float(s)
            return None
        d("DISTOF", distof, 1, 2)

        def wcmatch(a):
            return B(self.wcmatch(self.str_(a[0]), self.str_(a[1])))
        d("WCMATCH", wcmatch, 2, 2)

        def chr_(a):
            n = self.int_(a[0])
            return chr(n & 0xFFFF) if n else ""
        d("CHR", chr_, 1, 1)
        d("ASCII", lambda a: ord(self.str_(a[0])[0]) if self.str_(a[0]) else 0, 1, 1)

        def search(a):
            p, s = self.str_(a[0]), self.str_(a[1])
            st = self.int_(a[2]) if len(a) > 2 and a[2] is not None else 0
            if st < 0:
                st = 0
            i = s.find(p, st)
            return None if i < 0 else i
        d("VL-STRING-SEARCH", search, 2, 3)

        def vsubst(a):
            new, p, s = self.str_(a[0]), self.str_(a[1]), self.str_(a[2])
            st = self.int_(a[3]) if len(a) > 3 and a[3] is not None else 0
            i = s.find(p, st)
            if i < 0:
                return s
            return s[:i] + new + s[i + len(p):]
        d("VL-STRING-SUBST", vsubst, 3, 4)
        d("VL-STRING-TRIM", lambda a: self.str_(a[1]).strip(self.str_(a[0])), 2, 2)
        d("VL-STRING-LEFT-TRIM", lambda a: self.str_(a[1]).lstrip(self.str_(a[0])), 2, 2)
        d("VL-STRING-RIGHT-TRIM", lambda a: self.str_(a[1]).rstrip(self.str_(a[0])), 2, 2)

        def translate(a):
            src, dst, s = self.str_(a[0]), self.str_(a[1]), self.str_(a[2])
            m = {}
            for i, c in enumerate(src):
                if c not in m:
                    m[c] = dst[i] if i < len(dst) else (dst[-1] if dst else c)
            return "".join(m.get(c, c) for c in s)
        d("VL-STRING-TRANSLATE", translate, 3, 3)
        d("VL-STRING->LIST", lambda a: mklist([ord(c) for c in self.str_(a[0])]), 1, 1)
        d("VL-LIST->STRING", lambda a: "".join(chr(self.int_(c)) for c in self.plst(a[0])), 1, 1)

        def strpos(a):
            c = self.int_(a[0])
            s = self.str_(a[1])
            st = self.int_(a[2]) if len(a) > 2 and a[2] is not None else 0
            if len(a) > 3 and a[3] is not None:
                i = s.rfind(chr(c), 0, len(s))
            else:
                i = s.find(chr(c), st)
            return None if i < 0 else i
        d("VL-STRING-POSITION", strpos, 2, 4)
        d("VL-STRING-ELT", lambda a: ord(self.str_(a[0])[self.int_(a[1])]), 2, 2)
        d("VL-PRINC-TO-STRING", lambda a: to_str(a[0], False), 1, 1)
        d("VL-PRIN1-TO-STRING", lambda a: to_str(a[0], True), 1, 1)
        d("SNVALID", lambda a: T, 1, 2)

        # --- in ra ---
        def princ(a):
            if not a:
                return ""
            if len(a) > 1 and a[1] is not None:
                if not isinstance(a[1], FileH):
                    raise LispError("bad argument type: filep " + to_str(a[1], True))
                self.file_write(a[1], to_str(a[0], False))
                return a[0]
            self.emit(to_str(a[0], False))
            return a[0]

        def prin1(a):
            if not a:
                return ""
            s = to_str(a[0], True)
            if len(a) > 1 and a[1] is not None:
                self.file_write(a[1], s)
            else:
                self.emit(s)
            return a[0]

        def print_(a):
            if not a:
                return ""
            s = "\n" + to_str(a[0], True) + " "
            if len(a) > 1 and a[1] is not None:
                self.file_write(a[1], s)
            else:
                self.emit(s)
            return a[0]
        d("PRINC", princ, 0, 2)
        d("PRIN1", prin1, 0, 2)
        d("PRINT", print_, 0, 2)
        d("PROMPT", lambda a: self.emit(self.str_(a[0])), 1, 1)
        d("TERPRI", lambda a: self.emit("\n"), 0, 0)

        def alert(a):
            self.emit("\n[ALERT] " + self.str_(a[0]))
            return None
        d("ALERT", alert, 1, 1)

        # --- dieu khien / loi ---
        def exit_(a):
            raise LispError("quit / exit abort", "exit")
        d("EXIT", exit_, 0, 0)
        d("QUIT", exit_, 0, 0)

        def catch_apply(a):
            f = a[0]
            args = self.plst(a[1]) if len(a) > 1 else []
            self.catch_depth += 1
            try:
                return self.apply(f, args)
            except LispError as e:
                if e.stack is None:
                    e.stack = list(self.stack)
                self.caught.append(e)
                return CatchErr(e.msg, e)
            finally:
                self.catch_depth -= 1
        d("VL-CATCH-ALL-APPLY", catch_apply, 1, 2)
        d("VL-CATCH-ALL-ERROR-P", lambda a: B(isinstance(a[0], CatchErr)), 1, 1)

        def cmsg(a):
            if not isinstance(a[0], CatchErr):
                raise LispError("bad argument type: VL-CATCH-ALL-APPLY-ERROR: " + to_str(a[0], True))
            return a[0].msg
        d("VL-CATCH-ALL-ERROR-MESSAGE", cmsg, 1, 1)
        d("VL-EXIT-WITH-ERROR", lambda a: (_ for _ in ()).throw(LispError(self.str_(a[0]))), 1, 1)
        d("VL-LOAD-COM", lambda a: None, 0, 0)
        d("VL-LOAD-REACTORS", lambda a: None, 0, 0)
        d("GC", lambda a: None, 0, 0)
        d("VER", lambda a: "Visual LISP 2013 (en)", 0, 0)
        d("VL-BB-REF", lambda a: None, 1, 1)
        d("VL-BB-SET", lambda a: a[1], 2, 2)

    # ------------------------------------------------------------ helpers dung chung
    def getvar_raw(self, name, default=None):
        return default

    def file_write(self, fh, s):
        raise LispError("bad argument type: filep " + to_str(fh, True))

    def rtos(self, x, mode, prec):
        prec = max(0, min(prec, 8))
        if mode == 1:
            s = ("%." + str(prec) + "E") % x
            m, e = s.split("E")
            return "%sE%s%02d" % (m, e[0], abs(int(e)))
        s = ("%." + str(prec) + "f") % x
        dz = self.getvar_raw("DIMZIN", 8)
        if isinstance(dz, int) and (dz & 8) and "." in s:
            s = s.rstrip("0").rstrip(".")
        if isinstance(dz, int) and (dz & 4) and s.startswith("0.") and len(s) > 2:
            s = s[1:]
        elif isinstance(dz, int) and (dz & 4) and s.startswith("-0.") and len(s) > 3:
            s = "-" + s[2:]
        return s

    _wc_cache = {}

    def wcmatch(self, s, pat, nocase=False):
        key = (pat, nocase)
        rx = self._wc_cache.get(key)
        if rx is None:
            rx = compile_wc(pat, nocase)
            self._wc_cache[key] = rx
        return any(bool(r.match(s)) != neg for neg, r in rx)


def compile_wc(pat, nocase=False):
    """Mau wildcard AutoCAD -> danh sach (phu_dinh, regex). Phan cach ',' (khong co `)"""
    alts = []
    cur = []
    i = 0
    n = len(pat)
    while i < n:
        c = pat[i]
        if c == "`" and i + 1 < n:
            cur.append(pat[i:i + 2])
            i += 2
            continue
        if c == "[":
            j = i + 1
            while j < n and pat[j] != "]":
                if pat[j] == "`":
                    j += 1
                j += 1
            cur.append(pat[i:j + 1])
            i = j + 1
            continue
        if c == ",":
            alts.append("".join(cur))
            cur = []
            i += 1
            continue
        cur.append(c)
        i += 1
    alts.append("".join(cur))
    out = []
    flags = re.DOTALL | (re.IGNORECASE if nocase else 0)
    for a in alts:
        neg = False
        if a.startswith("~"):
            neg = True
            a = a[1:]
        rx = []
        i = 0
        n = len(a)
        while i < n:
            c = a[i]
            if c == "`" and i + 1 < n:
                rx.append(re.escape(a[i + 1]))
                i += 2
            elif c == "#":
                rx.append("[0-9]")
                i += 1
            elif c == "@":
                rx.append("[A-Za-z]")
                i += 1
            elif c == ".":
                rx.append("[^A-Za-z0-9]")
                i += 1
            elif c == "*":
                rx.append(".*")
                i += 1
            elif c == "?":
                rx.append(".")
                i += 1
            elif c == "[":
                j = i + 1
                negc = False
                if j < n and a[j] == "~":
                    negc = True
                    j += 1
                items = []
                while j < n and a[j] != "]":
                    if a[j] == "`" and j + 1 < n:
                        items.append(re.escape(a[j + 1]))
                        j += 2
                    elif a[j] == "-" and items and j + 1 < n and a[j + 1] != "]":
                        items.append("-")
                        j += 1
                    else:
                        items.append(re.escape(a[j]) if a[j] not in "-" else "\\-")
                        j += 1
                body = "".join(items)
                rx.append("[" + ("^" if negc else "") + body + "]" if body else ("[^\\s\\S]" if not negc else "."))
                i = j + 1
            else:
                rx.append(re.escape(c))
                i += 1
        out.append((neg, re.compile("".join(rx) + r"\Z", flags)))
    return out
