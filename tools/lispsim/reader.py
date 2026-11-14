"""Bo doc ma nguon AutoLISP -> Cons/Sym/so/chuoi (ghi kem (file, dong) cho moi list)."""
import re

from .ltypes import Cons, LispError

_INT = re.compile(r"^[+-]?\d+$")
_REAL = re.compile(r"^[+-]?(\d+\.\d*|\.\d+|\d+)([eE][+-]?\d+)?$")
_DELIM = set(" \t\r\n\f()'\";")


class Reader:
    def __init__(self, text, intern, fname="<string>"):
        self.s = text
        self.i = 0
        self.n = len(text)
        self.intern = intern
        self.fname = fname
        self.line = 1

    def _skip(self):
        s, n = self.s, self.n
        while self.i < n:
            c = s[self.i]
            if c == "\n":
                self.line += 1
                self.i += 1
            elif c in " \t\r\f":
                self.i += 1
            elif c == ";":
                if self.i + 1 < n and s[self.i + 1] == "|":
                    j = s.find("|;", self.i + 2)
                    if j < 0:
                        raise LispError("malformed comment (;| khong dong) %s:%d" % (self.fname, self.line))
                    self.line += s.count("\n", self.i, j)
                    self.i = j + 2
                else:
                    j = s.find("\n", self.i)
                    self.i = n if j < 0 else j
            else:
                break

    def at_end(self):
        self._skip()
        return self.i >= self.n

    def read(self):
        self._skip()
        if self.i >= self.n:
            raise EOFError
        s = self.s
        c = s[self.i]
        if c == "(":
            line = self.line
            self.i += 1
            items = []
            tail = None
            while True:
                self._skip()
                if self.i >= self.n:
                    raise LispError("malformed list on input (%s:%d)" % (self.fname, line))
                c = s[self.i]
                if c == ")":
                    self.i += 1
                    break
                if c == "." and self.i + 1 < self.n and s[self.i + 1] in _DELIM and items:
                    self.i += 1
                    tail = self.read()
                    self._skip()
                    if self.i < self.n and s[self.i] == ")":
                        self.i += 1
                    else:
                        raise LispError("malformed dotted pair (%s:%d)" % (self.fname, line))
                    break
                items.append(self.read())
            r = tail
            for x in reversed(items):
                r = Cons(x, r)
            if r is not None and isinstance(r, Cons):
                r.pos = (self.fname, line)
            return r
        if c == ")":
            self.i += 1
            raise LispError("extra right paren on input (%s:%d)" % (self.fname, self.line))
        if c == "'":
            self.i += 1
            line = self.line
            x = self.read()
            return Cons(self.intern("QUOTE"), Cons(x), (self.fname, line))
        if c == '"':
            return self._string()
        j = self.i
        while j < self.n and s[j] not in _DELIM:
            j += 1
        tok = s[self.i:j]
        self.i = j
        if _INT.match(tok):
            v = int(tok)
            if -2147483648 <= v <= 2147483647:
                return v
            return float(v)
        if _REAL.match(tok):
            return float(tok)
        return self.intern(tok.upper())

    def _string(self):
        s = self.s
        self.i += 1
        out = []
        start = self.line
        while True:
            if self.i >= self.n:
                raise LispError("chuoi khong dong (%s:%d)" % (self.fname, start))
            c = s[self.i]
            if c == '"':
                self.i += 1
                break
            if c == "\n":
                self.line += 1
            if c == "\\" and self.i + 1 < self.n:
                d = s[self.i + 1]
                self.i += 2
                if d == "n":
                    out.append("\n")
                elif d == "t":
                    out.append("\t")
                elif d == "r":
                    out.append("\r")
                elif d == "e":
                    out.append("\x1b")
                elif d in "01234567":
                    k = self.i - 1
                    m = k
                    while m < self.n and m < k + 3 and s[m] in "01234567":
                        m += 1
                    out.append(chr(int(s[k:m], 8)))
                    self.i = m
                else:
                    out.append(d)
                continue
            out.append(c)
            self.i += 1
        return "".join(out)


def read_all(text, intern, fname="<string>"):
    r = Reader(text, intern, fname)
    forms = []
    while not r.at_end():
        forms.append(r.read())
    return forms
