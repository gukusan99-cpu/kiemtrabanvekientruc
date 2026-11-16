"""Ham CAD cho lispsim: entget/ssget/tbl*/entmake..., getvar/setvar, file (VFS), nhap lieu
theo kich ban, va ActiveX toi thieu (che do "acad") hoac khong co ActiveX (che do "vinacad").
"""
import math
import os
import re

from .ltypes import (Sym, Cons, LispError, Ename, PickSet, FileH, VlaObj, SafeArray, Variant,
                     mklist, tolist, to_str)
from .interp import compile_wc, isnum
from .drawing import Ent, POINT_CODES, P, text_size

TBL_SKIP = {5, 105, 330, 100, 102, 360}
TABLES = {"LAYER": "LAYER", "LTYPE": "LTYPE", "STYLE": "STYLE", "DIMSTYLE": "DIMSTYLE",
          "BLOCK": "BLOCK", "VIEW": "VIEW", "UCS": "UCS", "APPID": "APPID", "VPORT": "VPORT"}


class Ans:
    """1 cau tra loi trong hang doi nhap lieu. value None = Enter. match = chuoi con cua prompt"""

    def __init__(self, value=None, match=None):
        self.value, self.match = value, match

    def __repr__(self):
        return "Ans(%r, %r)" % (self.value, self.match)


CANCEL = object()   # Ans(CANCEL) = nguoi dung nhan ESC


class VFS:
    """He thong file ao: duong dan Windows "C:\\a\\b" -> <root>/C/a/b (khong phan biet hoa thuong)"""

    def __init__(self, root, cwd="C:\\DuAn", support=()):
        self.root = root
        self.cwd = cwd
        self.support = list(support)

    @staticmethod
    def norm(p):
        p = p.replace("/", "\\")
        while "\\\\" in p[1:]:
            i = p.index("\\\\", 1)
            p = p[:i] + p[i + 1:]
        return p

    def isabs(self, p):
        return bool(re.match(r"^[A-Za-z]:\\", self.norm(p))) or p.startswith("\\")

    def absw(self, p):
        p = self.norm(p)
        if not self.isabs(p):
            p = self.cwd.rstrip("\\") + "\\" + p
        if p.startswith("\\"):
            p = "C:" + p
        return p

    def host(self, wp, create=False):
        wp = self.absw(wp)
        parts = [wp[0].upper()] + [x for x in wp[3:].split("\\") if x not in ("", ".")]
        cur = self.root
        for i, comp in enumerate(parts):
            nxt = os.path.join(cur, comp)
            if not os.path.exists(nxt) and os.path.isdir(cur):
                for f in os.listdir(cur):
                    if f.lower() == comp.lower():
                        nxt = os.path.join(cur, f)
                        break
            cur = nxt
        return cur

    def exists(self, wp):
        return os.path.exists(self.host(wp))

    def findfile(self, name):
        name = self.norm(name)
        if self.isabs(name):
            return self.absw(name) if os.path.isfile(self.host(name)) else None
        for d in [self.cwd] + self.support:
            wp = d.rstrip("\\") + "\\" + name
            if os.path.isfile(self.host(wp)):
                return wp
        return None

    def mkdirs(self, wp):
        os.makedirs(self.host(wp), exist_ok=True)


def install(I, dwg, vfs, mode="acad"):
    """cai ham CAD vao Interp I"""
    d = I.defbi
    T = I.T
    B = I.b
    I.dwg = dwg
    I.vfs = vfs
    I.mode = mode
    I.inputs = []
    I.prompts = []
    I.commands = []
    I.ss_inputs = []
    I.ig = (0, None)
    I.files_written = []
    sv = {"DWGPREFIX": vfs.cwd.rstrip("\\") + "\\", "DWGNAME": dwg.name, "TILEMODE": 1, "CTAB": "Model",
          "CVPORT": 2, "DIMSCALE": 1.0, "CLAYER": "0", "CDATE": 20261114.153012, "DATE": 2461359.5,
          "ACADVER": "24.1s (LMS Tech)" if mode == "acad" else "VinaCAD 2024",
          "LUNITS": 2, "LUPREC": 4, "DIMZIN": 8, "AUNITS": 0, "AUPREC": 0, "CMDECHO": 1, "OSMODE": 0,
          "PICKFIRST": 1, "INSUNITS": 4, "MEASUREMENT": 1, "TEXTSIZE": 2.5, "DIMASSOC": 2, "ERRNO": 0,
          "VIEWSIZE": 30000.0, "VIEWCTR": (0.0, 0.0, 0.0), "EXTMIN": (0.0, 0.0, 0.0),
          "EXTMAX": (100000.0, 50000.0, 0.0), "LTSCALE": 1.0, "TEXTSTYLE": "Standard",
          "DIMSTYLE": "Standard", "PSTYLEMODE": 1, "UNITMODE": 0, "SECURELOAD": 1, "FILEDIA": 1}
    for k, v in (getattr(dwg, "header", None) or {}).items():
        if k in sv or k in ("LIMMIN", "LIMMAX", "PDMODE", "CELTYPE", "CECOLOR", "DIMTXT", "DIMASZ", "DIMLFAC", "DIMDEC"):
            if k == "TILEMODE":
                continue
            sv[k] = v
    I.sysvars = sv
    I.getvar_raw = lambda n, default=None: sv.get(n.upper(), default)

    # ------------------------------------------------------------ chuyen doi
    def ename(e):
        if e.ename is None:
            e.ename = Ename(e)
        return e.ename

    def tolisp(v):
        if isinstance(v, Ent):
            return ename(v)
        if isinstance(v, tuple):
            return mklist([float(x) for x in v])
        return v

    def pair(c, v):
        if isinstance(v, tuple):
            return Cons(c, tolisp(v))
        return Cons(c, tolisp(v))

    def frompy(c, v):
        """gia tri lisp -> python (luu vao data)"""
        if isinstance(v, Cons):
            return tuple(float(x) for x in tolist(v))
        if isinstance(v, Ename):
            return v.ent
        return v

    def ent_of(x, fn="lentityp"):
        if not isinstance(x, Ename):
            raise LispError("bad argument type: lentityp " + to_str(x, True))
        return x.ent

    def owner_rec(e):
        if e.kind in ("main", "sub"):
            nm = "*Model_Space" if e.owner == "Model" else "*Paper_Space"
            return dwg.tables["BLOCK_RECORD"][nm.upper()]
        if e.kind in ("block", "blockbegin", "blockend"):
            return dwg.tables["BLOCK_RECORD"][e.owner.upper()]
        return dwg.rootdict

    def xdata_part(e, apps):
        if apps is None:
            return []
        want = [a.upper() for a in apps]
        grp = []
        for app, items in e.xdata.items():
            if "*" in want or app.upper() in want:
                grp.append(mklist([app] + [pair(c, v) for c, v in items]))
        if not grp:
            return []
        return [Cons(-3, mklist(grp))]

    def entget_list(e, apps=None):
        if getattr(e, "raw", False):
            out = [Cons(-1, ename(e)), Cons(0, e.type)] + [pair(c, v) for c, v in e.data]
            return mklist(out + xdata_part(e, apps))
        out = [Cons(-1, ename(e)), Cons(0, e.type), Cons(330, ename(owner_rec(e))), Cons(5, e.handle)]
        if e.kind == "table":
            out += [Cons(100, "AcDbSymbolTableRecord")]
            out += [pair(c, v) for c, v in e.data]
        elif e.kind == "object":
            out += [pair(c, v) for c, v in e.data]
        else:
            out.append(Cons(100, "AcDbEntity"))
            if e.kind in ("main", "sub"):
                if e.owner != "Model":
                    out.append(Cons(67, 1))
                out.append(Cons(410, e.owner))
            out += [pair(c, v) for c, v in e.data]
        return mklist(out + xdata_part(e, apps))

    def alive(e):
        return e is not None and not e.deleted

    # ------------------------------------------------------------ entget & co
    def entget_(a):
        e = ent_of(a[0])
        if e.deleted:
            return None
        apps = None
        if len(a) > 1 and a[1] is not None:
            apps = [I.str_(x) for x in I.plst(a[1])]
        return entget_list(e, apps)
    d("ENTGET", entget_, 1, 2)

    def entnext_(a):
        if not a or a[0] is None:
            for e in dwg.main:
                if alive(e) and e.kind == "main":
                    return ename(e)
            return None
        e = ent_of(a[0])
        if e.kind in ("main", "sub"):
            main = dwg.main
            i = getattr(e, "_mi", None)
            if i is None or i >= len(main) or main[i] is not e:
                i = main.index(e)
            for k in range(i + 1, len(main)):
                if alive(main[k]):
                    return ename(main[k])
            return None
        if e.kind in ("block", "blockbegin"):
            b = dwg.blocks[e.owner.upper()]
            ch = getattr(b, "_chain", None)
            if ch is None or ch[0] != len(b.ents):
                chain = [b.begin]
                for x in b.ents:
                    chain.append(x)
                    chain.extend(x.subs)
                chain.append(b.end)
                ch = b._chain = (len(b.ents), chain, {id(x): k for k, x in enumerate(chain)})
            chain = ch[1]
            i = ch[2].get(id(e))
            if i is None:
                return None
            for x in chain[i + 1:]:
                if alive(x):
                    return ename(x)
            return None
        return None
    d("ENTNEXT", entnext_, 0, 1)

    def entlast_(a):
        for e in reversed(dwg.main):
            if alive(e) and e.kind == "main":
                return ename(e)
        return None
    d("ENTLAST", entlast_, 0, 0)

    def entdel_(a):
        e = ent_of(a[0])
        if not e.made:
            dwg.violations.append(("entdel", e.handle, e.type, e.layer))
        e.deleted = not e.deleted
        return a[0]
    d("ENTDEL", entdel_, 1, 1)

    def handent_(a):
        h = I.str_(a[0]).upper()
        e = dwg.ents.get(h)
        return ename(e) if alive(e) else None
    d("HANDENT", handent_, 1, 1)

    HDR = (-1, 0, 5, 330, 100, 410, 67, -3)

    def entmod_(a):
        lst = I.plst(a[0])
        en = [x for x in lst if isinstance(x, Cons) and x.car == -1]
        if not en:
            raise LispError("bad entmod list")
        e = ent_of(en[0].cdr)
        if not e.made:
            dwg.violations.append(("entmod", e.handle, e.type, e.layer))
        e.data = [(x.car, frompy(x.car, x.cdr)) for x in lst if isinstance(x, Cons) and x.car not in HDR]
        return a[0]
    d("ENTMOD", entmod_, 1, 1)
    d("ENTUPD", lambda a: a[0], 1, 1)

    REQ = {"CIRCLE": (10, 40), "TEXT": (10, 40, 1), "LINE": (10, 11), "MTEXT": (10,), "POINT": (10,),
           "LWPOLYLINE": (10,), "ARC": (10, 40, 50, 51), "INSERT": (2, 10)}

    def entmake_(a):
        lst = I.plst(a[0]) if a and a[0] is not None else []
        pairs = []
        for x in lst:
            if not isinstance(x, Cons):
                raise LispError("bad argument type: consp " + to_str(x, True))
            pairs.append((x.car, x.cdr))
        typ = dict(pairs).get(0)
        if not isinstance(typ, str):
            return None
        typ = typ.upper()
        if typ in ("LAYER", "STYLE", "LTYPE", "DIMSTYLE", "APPID"):
            nm = dict(pairs).get(2)
            if not isinstance(nm, str) or nm.upper() in dwg.tables[typ if typ != "STYLE" else "STYLE"]:
                return None
            data = [(c, frompy(c, v)) for c, v in pairs if c not in HDR and c != 2]
            rec = dwg._rec(typ, nm, data)
            rec.made = True
            return a[0]
        if typ not in REQ:
            I.warnings.append("entmake loai %s chua ho tro" % typ)
            return None
        have = dict(pairs)
        for c in REQ[typ]:
            if c not in have:
                return None
        sp = have.get(410, I.sysvars["CTAB"] if I.sysvars["TILEMODE"] == 0 else "Model")
        if not isinstance(sp, str):
            return None
        sp_real = None
        for lo in dwg.layouts:
            if lo.upper() == sp.upper():
                sp_real = lo
        if sp_real is None:
            return None
        data = [(c, frompy(c, v)) for c, v in pairs if c not in HDR]
        for c, v in data:
            if c in POINT_CODES and not (isinstance(v, tuple) and all(isinstance(t, float) for t in v)):
                return None
            if c == 40 and not isnum(v):
                return None
            if c == 1 and not isinstance(v, str):
                return None
        e = dwg.add(typ, data, sp_real)
        e.made = True
        return a[0]
    d("ENTMAKE", entmake_, 0, 1)

    # ------------------------------------------------------------ bang ky hieu
    def tname(x):
        t = I.str_(x).upper()
        if t not in TABLES:
            raise LispError("bad argument value: table name " + to_str(x, True))
        return t

    _tcache = {}

    def tbl_items(t):
        # cache theo so ban ghi (entmake them ban ghi -> doi kich thuoc -> lam moi)
        src = dwg.blocks if t == "BLOCK" else dwg.tables[t]
        c = _tcache.get(t)
        if c is not None and c[0] == len(src) and c[1] is src:
            return c[2]
        if t == "BLOCK":
            items = [b for b in src.values() if not getattr(b, "system", False)]
        else:
            items = list(src.values())
        _tcache[t] = (len(src), src, items)
        return items

    def tbl_short(t, it):
        if t == "BLOCK":
            b = it
            first = next((x for x in b.ents if not x.deleted), b.end)
            out = [Cons(0, "BLOCK"), Cons(2, b.name), Cons(70, b.flags), Cons(10, tolisp(b.base)),
                   Cons(-2, ename(first))]
            if b.xref:
                out.append(Cons(1, b.xref))
            return mklist(out)
        e = it
        if getattr(e, "raw", False) and t != "LAYER":
            return mklist([Cons(0, t)] + [pair(c, v) for c, v in e.data if c not in TBL_SKIP])
        if t == "LAYER":
            return mklist([Cons(0, "LAYER"), Cons(2, e.get(2)), Cons(70, e.get(70, 0)),
                           Cons(62, e.get(62, 7)), Cons(6, e.get(6, "Continuous"))])
        return mklist([Cons(0, t)] + [pair(c, v) for c, v in e.data])

    def tblsearch_(a):
        t = tname(a[0])
        nm = I.str_(a[1]).upper()
        if not (len(a) > 2 and a[2] is not None):
            if t == "BLOCK":
                b = dwg.blocks.get(nm)
                return tbl_short(t, b) if b is not None and not getattr(b, "system", False) else None
            e = dwg.tables[t].get(nm)
            return tbl_short(t, e) if e is not None else None
        for it in tbl_items(t):
            if (it.name if t == "BLOCK" else it.get(2)).upper() == nm:
                if len(a) > 2 and a[2] is not None:
                    I._tblpos[t] = tbl_items(t).index(it) + 1
                return tbl_short(t, it)
        return None
    I._tblpos = {}
    d("TBLSEARCH", tblsearch_, 2, 3)

    def tblnext_(a):
        t = tname(a[0])
        if len(a) > 1 and a[1] is not None:
            I._tblpos[t] = 0
        i = I._tblpos.get(t, 0)
        items = tbl_items(t)
        if i >= len(items):
            return None
        I._tblpos[t] = i + 1
        return tbl_short(t, items[i])
    d("TBLNEXT", tblnext_, 1, 2)

    def tblobjname_(a):
        t = tname(a[0])
        nm = I.str_(a[1]).upper()
        if t == "BLOCK":
            b = dwg.blocks.get(nm)
            return ename(b.begin) if b and not getattr(b, "system", False) else None
        e = dwg.tables[t].get(nm)
        return ename(e) if e else None
    d("TBLOBJNAME", tblobjname_, 2, 2)

    def namedobjdict_(a):
        return ename(dwg.rootdict)
    d("NAMEDOBJDICT", namedobjdict_, 0, 0)

    def dictsearch_(a):
        e = ent_of(a[0])
        key = I.str_(a[1]).upper()
        items = e.data
        for i, (c, v) in enumerate(items):
            if c == 3 and v.upper() == key and i + 1 < len(items):
                target = items[i + 1][1]
                return entget_list(target)
        return None
    d("DICTSEARCH", dictsearch_, 2, 3)

    def layoutlist_(a):
        los = sorted([(getattr(lo, "_tab", None) if getattr(lo, "_tab", None) is not None else lo.get(71, 0), nm) for nm, lo in dwg.layouts.items() if nm != "Model"])
        return mklist([nm for _, nm in los])
    d("LAYOUTLIST", layoutlist_, 0, 0)

    # ------------------------------------------------------------ ssget
    def ent_vals(e, code):
        if code == 0:
            return [e.type]
        if code == 410:
            return [e.owner] if e.kind in ("main", "sub") else []
        if code == 67:
            return [0 if e.owner == "Model" else 1]
        vals = e.gets(code)
        if not vals:
            if code == 8:
                return ["0"]
            if code == 62:
                return [256]
            if code == 6:
                return ["BYLAYER"]
        return vals

    def relop(op, a, b):
        if op in ("=", "*"):
            return a == b or op == "*"
        if op in ("!=", "/=", "<>"):
            return a != b
        if op == "<":
            return a < b
        if op == "<=":
            return a <= b
        if op == ">":
            return a > b
        if op == ">=":
            return a >= b
        if op == "&":
            return bool(a & b)
        if op == "&=":
            return (a & b) == b
        return a == b

    def test_one(e, code, val, op=None):
        if code == -3:
            apps = [x.upper() for x in tolist(val) if isinstance(x, str)] if isinstance(val, Cons) else []
            have = [x.upper() for x in e.xdata]
            return all(any(I.wcmatch(h, ap, True) for h in have) for ap in apps)
        vals = ent_vals(e, code)
        for v in vals:
            if isinstance(val, str):
                if isinstance(v, str) and I.wcmatch(v, val, True):
                    return True
            elif isinstance(val, Cons):
                pv = tuple(float(x) for x in tolist(val))
                if isinstance(v, tuple):
                    ops = (op or "=,=,=").split(",") if op and "," in (op or "") else [op or "="] * 3
                    if all(relop(ops[i] if i < len(ops) else "=", v[i], pv[i]) for i in range(min(len(v), len(pv)))):
                        return True
            elif isnum(val):
                if isnum(v):
                    if op:
                        if op in ("&", "&=") and not (isinstance(v, int) and isinstance(val, int)):
                            continue
                        if relop(op, v, val):
                            return True
                    elif v == val:
                        return True
            elif isinstance(val, Ename):
                if v is val.ent:
                    return True
        return False

    def parse_filter(items):
        """-> cay (op, [con]) / ('t', code, val, rel)"""
        pos = [0]

        def parse_seq(stop):
            res = []
            while pos[0] < len(items):
                c, v = items[pos[0]]
                if c == -4 and isinstance(v, str):
                    u = v.upper()
                    if stop and u == stop:
                        pos[0] += 1
                        return res
                    if u in ("<AND", "<OR", "<NOT", "<XOR"):
                        pos[0] += 1
                        sub = parse_seq(u[1:] + ">")
                        res.append((u[1:], sub))
                        continue
                    if u in ("AND>", "OR>", "NOT>", "XOR>"):
                        raise LispError("bad ssget list: unbalanced " + v)
                    pos[0] += 1
                    if pos[0] >= len(items):
                        raise LispError("bad ssget list")
                    c2, v2 = items[pos[0]]
                    pos[0] += 1
                    res.append(("t", c2, v2, u))
                    continue
                pos[0] += 1
                res.append(("t", c, v, None))
            if stop:
                raise LispError("bad ssget list: thieu " + stop)
            return res
        return ("AND", parse_seq(None))

    def ev_filter(node, e):
        k = node[0]
        if k == "t":
            return test_one(e, node[1], node[2], node[3])
        subs = node[1]
        if k == "AND":
            return all(ev_filter(s, e) for s in subs)
        if k == "OR":
            return any(ev_filter(s, e) for s in subs)
        if k == "NOT":
            return not all(ev_filter(s, e) for s in subs)
        if k == "XOR":
            return sum(1 for s in subs if ev_filter(s, e)) == 1
        return False

    def mk_ss(ents):
        return PickSet([ename(e) for e in ents]) if ents else None

    def ssget_(a):
        mode = None
        filt = None
        rest = list(a)
        if rest and isinstance(rest[0], str):
            mode = rest.pop(0).upper().lstrip("_").lstrip(".").lstrip("_")
        if rest and isinstance(rest[-1], Cons) and isinstance(rest[-1].car, Cons):
            filt = rest.pop()
        items = []
        if filt is not None:
            for x in tolist(filt):
                if not isinstance(x, Cons):
                    raise LispError("bad ssget list")
                items.append((x.car, x.cdr))
        tree = parse_filter(items)
        if mode == "X" or mode == "A":
            res = [e for e in dwg.main if alive(e) and e.kind == "main" and ev_filter(tree, e)]
            return mk_ss(res)
        if mode in (None, ":S", ":E", "+.:S", "W", "C", "WP", "CP", "F", "I", "P"):
            I.prompts.append("<ssget %s>" % (mode or ""))
            if mode is None and I.ss_inputs:
                hs = I.ss_inputs.pop(0)
                if hs is None:
                    return None
                res = [dwg.ents[h] if isinstance(h, str) else h for h in hs]
                return mk_ss([e for e in res if alive(e) and ev_filter(tree, e)])
            return None
        if mode == "L":
            l = entlast_([])
            return PickSet([l]) if l else None
        return None
    d("SSGET", ssget_, 0, 5)

    def ss_of(x):
        if not isinstance(x, PickSet):
            raise LispError("bad argument type: lselsetp " + to_str(x, True))
        return x

    d("SSLENGTH", lambda a: len(ss_of(a[0]).items), 1, 1)

    def ssname_(a):
        s = ss_of(a[0])
        i = a[1]
        if isinstance(i, float):
            i = int(i)
        I.int_(i)
        return s.items[i] if 0 <= i < len(s.items) else None
    d("SSNAME", ssname_, 2, 2)

    def ssadd_(a):
        if not a:
            return PickSet()
        e = ent_of(a[0])
        if len(a) > 1 and a[1] is not None:
            s = ss_of(a[1])
        else:
            s = PickSet()
        if e.deleted:
            raise LispError("bad argument type: lentityp " + to_str(a[0], True))
        if not any(x.ent is e for x in s.items):
            s.items.append(a[0])
        return s
    d("SSADD", ssadd_, 0, 2)

    def ssdel_(a):
        e = ent_of(a[0])
        s = ss_of(a[1])
        n = len(s.items)
        s.items = [x for x in s.items if x.ent is not e]
        return s if len(s.items) != n else None
    d("SSDEL", ssdel_, 2, 2)
    d("SSMEMB", lambda a: a[0] if any(x.ent is ent_of(a[0]) for x in ss_of(a[1]).items) else None, 2, 2)

    def sssetfirst_(a):
        s = a[1] if len(a) > 1 else None
        if s is not None:
            ss_of(s)
            for x in s.items:
                if x.ent.deleted:
                    raise LispError("bad argument type: lentityp " + to_str(x, True))
        dwg.selected = s
        return mklist([a[0], s])
    d("SSSETFIRST", sssetfirst_, 1, 2)
    d("SSGETFIRST", lambda a: mklist([None, dwg.selected]), 0, 0)

    # ------------------------------------------------------------ sysvar / lenh
    def getvar_(a):
        n = I.str_(a[0]).upper()
        v = sv.get(n)
        if isinstance(v, tuple):
            return tolisp(v)
        return v
    d("GETVAR", getvar_, 1, 1)

    def setvar_(a):
        n = I.str_(a[0]).upper()
        v = a[1]
        if n not in sv:
            raise LispError("setvar rejected: " + n)
        if n == "CTAB":
            I.str_(v)
            match = [lo for lo in dwg.layouts if lo.upper() == v.upper()]
            if not match:
                raise LispError("bad argument value: AutoCAD variable setting rejected: \"CTAB\" " + to_str(v, True))
            sv["CTAB"] = match[0]
            sv["TILEMODE"] = 1 if match[0] == "Model" else 0
            return v
        if n == "TILEMODE":
            I.int_(v)
            sv["TILEMODE"] = v
            if v == 1:
                sv["CTAB"] = "Model"
            elif sv["CTAB"] == "Model":
                sv["CTAB"] = layoutlist_([]).car if layoutlist_([]) else "Model"
            return v
        if n in ("DWGNAME", "DWGPREFIX", "ACADVER", "CDATE", "DATE"):
            raise LispError("setvar rejected: read-only " + n)
        sv[n] = frompy(0, v)
        return v
    d("SETVAR", setvar_, 2, 2)

    def command_(a):
        I.commands.append([to_str(x, True) for x in a])
        return None
    d("COMMAND", command_)
    d("VL-CMDF", lambda a: (command_(a), T)[1])
    d("REDRAW", lambda a: None, 0, 2)
    d("GRDRAW", lambda a: None, 3, 5)
    d("GRTEXT", lambda a: None, 0, 3)
    d("TRANS", lambda a: a[0], 3, 4)
    # bien moi truong luu registry (getenv/setenv) - dict I.env, Session co the gieo san
    if not hasattr(I, "env"):
        I.env = {}
    d("GETENV", lambda a: I.env.get(I.str_(a[0]).upper()), 1, 1)

    def setenv_(a):
        I.env[I.str_(a[0]).upper()] = I.str_(a[1])
        return a[1]
    d("SETENV", setenv_, 2, 2)

    def getfiled_(a):
        v = next_input(I.str_(a[0]), "str")
        return str(v) if v else None
    d("GETFILED", getfiled_, 4, 4)

    def textbox_(a):
        lst = I.plst(a[0])
        dd = {x.car: x.cdr for x in lst if isinstance(x, Cons)}
        s = dd.get(1, "")
        h = dd.get(40, sv["TEXTSIZE"])
        wf = dd.get(41, 1.0)
        if not isinstance(s, str) or not isnum(h):
            return None
        w, hh = text_size(s, h, wf if isnum(wf) else 1.0)
        return mklist([mklist([0.0, 0.0, 0.0]), mklist([float(w), float(hh), 0.0])])
    d("TEXTBOX", textbox_, 1, 1)

    # ------------------------------------------------------------ hinh hoc
    def distance_(a):
        p, q = I.pt(a[0]), I.pt(a[1])
        n = min(len(p), len(q))
        return math.sqrt(sum((p[i] - q[i]) ** 2 for i in range(n)))
    d("DISTANCE", distance_, 2, 2)

    def angle_(a):
        p, q = I.pt(a[0]), I.pt(a[1])
        r = math.atan2(q[1] - p[1], q[0] - p[0])
        return r + 2 * math.pi if r < 0 else r
    d("ANGLE", angle_, 2, 2)

    def polar_(a):
        p = I.pt(a[0])
        ang, dist = float(I.num(a[1])), float(I.num(a[2]))
        r = [p[0] + dist * math.cos(ang), p[1] + dist * math.sin(ang)] + p[2:]
        return mklist(r)
    d("POLAR", polar_, 3, 3)

    def inters_(a):
        p1, p2, p3, p4 = [I.pt(x) for x in a[:4]]
        onseg = len(a) < 5 or a[4] is not None
        d1 = (p2[0] - p1[0], p2[1] - p1[1])
        d2 = (p4[0] - p3[0], p4[1] - p3[1])
        den = d1[0] * d2[1] - d1[1] * d2[0]
        if abs(den) < 1e-12:
            return None
        t = ((p3[0] - p1[0]) * d2[1] - (p3[1] - p1[1]) * d2[0]) / den
        s = ((p3[0] - p1[0]) * d1[1] - (p3[1] - p1[1]) * d1[0]) / den
        if onseg and not (-1e-10 <= t <= 1 + 1e-10 and -1e-10 <= s <= 1 + 1e-10):
            return None
        r = [p1[0] + t * d1[0], p1[1] + t * d1[1]]
        if len(p1) > 2:
            r.append(0.0)
        return mklist(r)
    d("INTERS", inters_, 4, 5)

    # ------------------------------------------------------------ file
    def fname_parts(p):
        p = VFS.norm(I.str_(p))
        i = p.rfind("\\")
        return (p[:i] if i >= 0 else ""), (p[i + 1:] if i >= 0 else p)

    def fn_dir(a):
        dr, _ = fname_parts(a[0])
        return dr
    d("VL-FILENAME-DIRECTORY", fn_dir, 1, 1)

    def fn_base(a):
        _, f = fname_parts(a[0])
        return f.rsplit(".", 1)[0] if "." in f else f
    d("VL-FILENAME-BASE", fn_base, 1, 1)

    def fn_ext(a):
        _, f = fname_parts(a[0])
        return "." + f.rsplit(".", 1)[1] if "." in f else None
    d("VL-FILENAME-EXTENSION", fn_ext, 1, 1)
    d("VL-FILENAME-MKTEMP", lambda a: "C:\\Temp\\$VL~~001", 0, 3)

    def findfile_(a):
        return vfs.findfile(I.str_(a[0]))
    d("FINDFILE", findfile_, 1, 1)

    def open_(a):
        p = I.str_(a[0])
        m = I.str_(a[1]).lower()
        if m not in ("r", "w", "a"):
            raise LispError("bad argument value: file mode " + to_str(a[1], True))
        hp = vfs.host(p)
        try:
            if m == "r":
                if not os.path.isfile(hp):
                    return None
                fh = open(hp, "r", encoding="latin-1", newline="")
            else:
                if not os.path.isdir(os.path.dirname(hp)):
                    return None
                fh = open(hp, m, encoding="latin-1", newline="")
                I.files_written.append(vfs.absw(p))
        except OSError:
            return None
        return FileH(vfs.absw(p), m, fh)
    d("OPEN", open_, 2, 3)

    def fh_of(x, want=None):
        if not isinstance(x, FileH):
            raise LispError("bad argument type: filep " + to_str(x, True))
        if x.closed:
            raise LispError("bad argument type: file closed " + to_str(x, True))
        return x

    def close_(a):
        f = fh_of(a[0])
        f.fh.close()
        f.closed = True
        if getattr(I, "lms_quirks", False):
            # VinaCAD that (nen LMS): close bao loi du file da dong xong
            raise LispError("C operation (write) signaled an error.\nC library explanation: Bad file descriptor.")
        return None
    d("CLOSE", close_, 1, 1)

    def read_line_(a):
        if not a:
            return None
        f = fh_of(a[0])
        if f.mode != "r":
            raise LispError("bad argument type: file not open for read")
        ln = f.fh.readline()
        if ln == "":
            return None
        return ln.rstrip("\n").rstrip("\r")
    d("READ-LINE", read_line_, 0, 1)

    def write_line_(a):
        s = I.str_(a[0])
        if len(a) > 1 and a[1] is not None:
            f = fh_of(a[1])
            if f.mode == "r":
                raise LispError("bad argument type: file not open for write")
            f.fh.write(s + "\r\n")
        else:
            I.emit(s + "\n")
        return s
    d("WRITE-LINE", write_line_, 1, 2)

    def file_write(f, s):
        fh_of(f).fh.write(s)
    I.file_write = file_write

    def load_(a):
        p = I.str_(a[0])
        f = vfs.findfile(p)
        if f is None and "." not in p.rsplit("\\", 1)[-1]:
            f = vfs.findfile(p + ".lsp")
        if f is None:
            if len(a) > 1:
                return a[1]
            raise LispError("LOAD failed: " + to_str(p, True))
        with open(vfs.host(f), "r", encoding="latin-1") as fh:
            text = fh.read()
        base = os.path.basename(vfs.host(f))
        return I.load_text(text, base)
    d("LOAD", load_, 1, 2)

    def dirfiles_(a):
        dr = I.str_(a[0]) if a and a[0] is not None else vfs.cwd
        pat = I.str_(a[1]) if len(a) > 1 and a[1] is not None else "*.*"
        mode = a[2] if len(a) > 2 else 0
        hp = vfs.host(dr)
        if not os.path.isdir(hp):
            return None
        out = []
        for f in sorted(os.listdir(hp)):
            full = os.path.join(hp, f)
            isd = os.path.isdir(full)
            if (mode == 1 and isd) or (mode == -1 and not isd):
                continue
            if I.wcmatch(f, pat.replace("*.*", "*"), True):
                out.append(f)
        return mklist(out)
    d("VL-DIRECTORY-FILES", dirfiles_, 0, 3)
    d("VL-FILE-DIRECTORY-P", lambda a: B(os.path.isdir(vfs.host(I.str_(a[0])))), 1, 1)

    def fdel(a):
        hp = vfs.host(I.str_(a[0]))
        if os.path.isfile(hp):
            os.remove(hp)
            return T
        return None
    d("VL-FILE-DELETE", fdel, 1, 1)

    def fcopy(a):
        s, t = vfs.host(I.str_(a[0])), vfs.host(I.str_(a[1]))
        if not os.path.isfile(s) or os.path.exists(t):
            return None
        import shutil
        shutil.copyfile(s, t)
        return os.path.getsize(t)
    d("VL-FILE-COPY", fcopy, 2, 3)

    # ------------------------------------------------------------ nhap lieu theo kich ban
    def initget_(a):
        bits = 0
        kw = None
        for x in a:
            if isinstance(x, int):
                bits = x
            elif isinstance(x, str):
                kw = x.split()
        I.ig = (bits, kw)
        return None
    d("INITGET", initget_, 0, 2)

    def next_input(prompt, kind):
        I.prompts.append(prompt or "")
        I.emit(prompt or "")
        while True:
            if not I.inputs:
                return None
            ans = I.inputs.pop(0)
            if not isinstance(ans, Ans):
                ans = Ans(ans)
            if ans.match and ans.match.lower() not in (prompt or "").lower():
                raise LispError("lispsim: kich ban nhap lieu lech: cho prompt chua '%s' nhung gap '%s'"
                                % (ans.match, (prompt or "").strip()), "sim")
            if ans.value is CANCEL:
                I.emit("*Cancel*")
                raise LispError("Function cancelled")
            I.emit("[" + to_str(ans.value, True) + "]")
            return ans.value

    def kw_match(s, kws):
        u = s.strip().upper()
        if not u:
            return None
        for k in kws:
            req = "".join(c for c in k if c.isupper())
            if k.upper().startswith(u) and len(u) >= max(1, len(req)):
                return k
        return None

    def get_generic(prompt, conv, kind):
        bits, kws = I.ig
        I.ig = (0, None)
        for _ in range(20):
            v = next_input(prompt, kind)
            if v is None:
                if bits & 1:
                    raise LispError("lispsim: het kich ban nhap lieu ma initget cam Enter (%s)" % prompt, "sim")
                return None
            if isinstance(v, str) and kws:
                k = kw_match(v, kws)
                if k:
                    return k
            r = conv(v)
            if r is None:
                I.emit("\nlispsim: gia tri khong hop le, hoi lai")
                continue
            if isnum(r):
                if (bits & 2) and r == 0:
                    continue
                if (bits & 4) and r < 0:
                    continue
            return r
        raise LispError("lispsim: nhap sai qua nhieu lan", "sim")

    def prm(a, i=0):
        return I.str_(a[i]) if len(a) > i and a[i] is not None else ""

    def getstring_(a):
        if a and not isinstance(a[0], str):
            pr = prm(a, 1)
        else:
            pr = prm(a, 0)
        I.ig = (0, None)
        v = next_input(pr, "str")
        if v is None:
            return ""
        return str(v)
    d("GETSTRING", getstring_, 0, 2)

    def to_real(v):
        if isnum(v):
            return float(v)
        try:
            return float(v)
        except Exception:
            return None

    def to_int(v):
        if isinstance(v, int):
            return v
        try:
            return int(v)
        except Exception:
            return None
    d("GETREAL", lambda a: get_generic(prm(a), to_real, "real"), 0, 1)
    d("GETINT", lambda a: get_generic(prm(a), to_int, "int"), 0, 1)
    d("GETDIST", lambda a: get_generic(prm(a, 1 if a and not isinstance(a[0], str) else 0), to_real, "real"), 0, 2)

    def getkword_(a):
        bits, kws = I.ig
        r = get_generic(prm(a), lambda v: None if kws else (str(v) if isinstance(v, str) else None), "kw")
        return r
    def getkword_lms(a):
        # VinaCAD that: tu khoa dung van bi "Invalid option keyword", Enter hoi lai
        while True:
            v = next_input(prm(a, 0), "str")
            if v is None:
                raise LispError("Function cancelled")
            I.emit("Invalid option keyword.")

    d("GETKWORD", lambda a: (getkword_lms(a) if getattr(I, "lms_quirks", False) else getkword_(a)), 0, 1)

    def to_pt(v):
        if isinstance(v, (tuple, list)):
            return mklist([float(x) for x in v])
        return None
    d("GETPOINT", lambda a: get_generic(prm(a, 1 if a and not isinstance(a[0], str) else 0), to_pt, "pt"), 0, 2)
    d("GETCORNER", lambda a: get_generic(prm(a, 1), to_pt, "pt"), 1, 2)

    def entsel_(a):
        I.ig = (0, None)
        v = next_input(prm(a) or "\nSelect object: ", "ent")
        if v is None:
            return None
        e = dwg.ents[v] if isinstance(v, str) else v
        bb = dwg.bbox(e)
        p = bb[0] if bb else (0.0, 0.0, 0.0)
        return mklist([ename(e), tolisp(tuple(p))])
    d("ENTSEL", entsel_, 0, 1)
    d("NENTSEL", entsel_, 0, 1)

    # ------------------------------------------------------------ ActiveX
    if mode == "acad":
        I.unsupported_prefixes = ("VLA-", "VLAX-", "VLR-")
        APP = VlaObj("Application")
        DOC = VlaObj("Document")

        def vobj(x):
            if not isinstance(x, VlaObj):
                raise LispError("bad argument type: VLA-OBJECT " + to_str(x, True))
            return x
        d("VLAX-GET-ACAD-OBJECT", lambda a: APP, 0, 0)
        PREFS = VlaObj("Preferences")
        FILES = VlaObj("PreferencesFiles")
        if not hasattr(I, "support_path"):
            I.support_path = ""

        def getprop(a):
            o, nm = vobj(a[0]), I.symb(a[1]).name.upper() if not isinstance(a[1], str) else a[1].upper()
            if o is APP and nm == "PREFERENCES":
                return PREFS
            if o is PREFS and nm == "FILES":
                return FILES
            if o is FILES and nm == "SUPPORTPATH":
                return I.support_path
            if o is APP and nm == "ACTIVEDOCUMENT":
                return DOC
            raise LispError("ActiveX Server returned the error: unknown name: " + nm)
        d("VLAX-GET-PROPERTY", getprop, 2, 2)

        def putprop(a):
            o, nm = vobj(a[0]), I.symb(a[1]).name.upper() if not isinstance(a[1], str) else a[1].upper()
            if o is FILES and nm == "SUPPORTPATH":
                I.support_path = I.str_(a[2])
                return None
            raise LispError("ActiveX Server returned the error: unknown name: " + nm)
        d("VLAX-PUT-PROPERTY", putprop, 3, 3)
        d("VLA-GET-ACTIVEDOCUMENT", lambda a: (vobj(a[0]), DOC)[1], 1, 1)
        d("VLA-STARTUNDOMARK", lambda a: (vobj(a[0]), None)[1], 1, 1)
        d("VLA-ENDUNDOMARK", lambda a: (vobj(a[0]), None)[1], 1, 1)

        def zoomc(a):
            vobj(a[0])
            I.commands.append(["ZoomCenter", to_str(a[1]), to_str(a[2])])
            return None
        d("VLA-ZOOMCENTER", zoomc, 3, 3)
        d("VLAX-3D-POINT", lambda a: Variant(I.pt(a[0]) if len(a) == 1 else [float(I.num(x)) for x in a]), 1, 3)

        def e2o(a):
            e = ent_of(a[0])
            if e.deleted:
                raise LispError("Automation Error. Object was erased")
            return VlaObj(e.type, e)
        d("VLAX-ENAME->VLA-OBJECT", e2o, 1, 1)
        d("VLAX-VLA-OBJECT->ENAME", lambda a: ename(vobj(a[0]).ent), 1, 1)

        def gbb(a):
            o = vobj(a[0])
            if o.ent is None:
                raise LispError("ActiveX Server returned the error: unknown name: GetBoundingBox")
            bb = dwg.bbox(o.ent)
            if bb is None:
                raise LispError("Automation Error. Null extents")
            I.symb(a[1]).value = SafeArray(bb[0])
            I.symb(a[2]).value = SafeArray(bb[1])
            return None
        d("VLA-GETBOUNDINGBOX", gbb, 3, 3)

        def sa2l(a):
            x = a[0]
            if isinstance(x, Variant):
                x = x.val
            if not isinstance(x, SafeArray):
                raise LispError("bad argument type: safearrayp " + to_str(x, True))
            return mklist([float(v) for v in x.vals])
        d("VLAX-SAFEARRAY->LIST", sa2l, 1, 1)

        def vval(a):
            x = a[0]
            return x.val if isinstance(x, Variant) else x
        d("VLAX-VARIANT-VALUE", vval, 1, 1)

        def effname(a):
            o = vobj(a[0])
            if o.ent is None or o.ent.type != "INSERT":
                raise LispError("ActiveX Server returned the error: unknown name: EffectiveName")
            nm = o.ent.get(2)
            b = dwg.blocks.get(nm.upper())
            return getattr(b, "dyn_source", None) or nm
        d("VLA-GET-EFFECTIVENAME", effname, 1, 1)
        d("VLA-GET-OBJECTNAME", lambda a: "AcDb" + (vobj(a[0]).ent.type.title() if vobj(a[0]).ent else "Object"), 1, 1)

        def notable(a):
            o = vobj(a[0])
            if o.ent is None or o.ent.type != "ACAD_TABLE":
                raise LispError("ActiveX Server returned the error: unknown name: Rows")
            return 0
        d("VLA-GET-ROWS", notable, 1, 1)
        d("VLA-GET-COLUMNS", notable, 1, 1)
        d("VLA-GETTEXT", lambda a: notable(a[:1]), 3, 3)
