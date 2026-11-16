#!/usr/bin/env python3
"""Phan tich ban ve MAU cong ty (DXF) -> so lieu cho docs/TEMPLATE_ANALYSIS.md va file chuan KT.

    python3 -I tools/template_analysis.py Template.dxf              # bao cao (markdown) ra stdout
    python3 -I tools/template_analysis.py Template.dxf --json a.json # them so lieu tho dang JSON
    python3 -I tools/template_analysis.py Template.dxf --cfg lisp/KT_ChuanCongTy.txt
                                                                     # sinh file chuan DA CHON LOC

Can ezdxf (pip install ezdxf). Chay voi python3 -I (file DXF la du lieu ngoai, khong tin cay).

Quy uoc phan tich (xem docs/TEMPLATE_ANALYSIS.md):
- Khung ten CHINH = block co attribute lon nhat trong Model (vd KHUNGTEENA); khung PHU = block cung ti
  le canh (A-series) va cung kich thuoc giay khi chen (vd KHUNGT43 - to bia hang muc, khong attribute).
  Ty le goc = (kich thuoc block) / (kich thuoc giay). Ty le thuc = |scale X| x ty le goc.
- Chieu cao chu quy ra giay = chieu cao chu (model) / ty le khung chua diem chen.
- Chieu cao chu dim quy ra giay = DIMTXT hieu dung x (DIMSCALE neu > 0, khong thi 1) / ty le khung;
  DIMTXT hieu dung = chieu cao co dinh cua textstyle dim (neu > 0) > override (XData DSTYLE) > dimstyle.
- "Ho cong ty" (chon loc): layer "0", "Defpoints" va "1 <TEN>" (co dau cach); dimstyle "DG 1-.." va
  "TL 1-.."; textstyle "0 *", "0_T_*", "Arial", "Standard", textstyle cua dimstyle cong ty, textstyle
  cua block khung. Con lai = rac (copy tu file khac, xref bind "$0$", ban ve hang khac JFP/VTD/YLD...).
- Ten trong file chuan ghi DUNG NHU AutoLISP ANSI (codepage ban ve, vd ANSI_1252) nhin thay: ky tu thuoc
  codepage -> 1 byte, ky tu ngoai -> "\\U+XXXX" (vd "TRỤC" -> "TR\\U+1EE4C"); file ghi bang codepage do.
"""
import argparse
import collections
import json
import math
import re
import sys

try:
    import ezdxf
    from ezdxf import bbox as ezbbox
except ImportError:  # pragma: no cover
    sys.exit("Can ezdxf: pip install ezdxf")


# ---------------------------------------------------------------- tien ich
def lisp_name(s, cp="cp1252"):
    """chuoi Unicode -> chuoi nhu AutoLISP ANSI nhin thay (byte codepage / \\U+XXXX)"""
    out = []
    for ch in s:
        if ord(ch) < 128:
            out.append(ch)
            continue
        try:
            out.append(ch.encode(cp).decode("latin-1"))
        except UnicodeEncodeError:
            out.append("\\U+%04X" % ord(ch))
    return "".join(out)


def unaccent(s):
    import unicodedata
    s = s.replace("đ", "d").replace("Đ", "D")
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")


def norm(s):
    return re.sub(r"[^A-Z0-9]", "", unaccent(s).upper())


def fmt(x, nd=3):
    if x is None:
        return ""
    if isinstance(x, float):
        if abs(x - round(x)) < 1e-6:
            return str(int(round(x)))
        return (("%." + str(nd) + "f") % x).rstrip("0").rstrip(".")
    return str(x)


def parse_scale(s):
    m = re.search(r"(?<![0-9.])1\s*[:/]\s*([0-9]+(?:\.[0-9]+)?)", s or "")
    return float(m.group(1)) if m else None


def name_scale(s):
    """ty le trong ten dimstyle: 'DG 1-30 (60)' -> 30, 'JFP_DG 1- 20' -> 20, 'D60' -> None"""
    m = re.search(r"(?<![0-9.])1\s*[-/:]\s*([0-9]+(?:\.[0-9]+)?)", s or "")
    return float(m.group(1)) if m else None


def level_val(s):
    """'+3.900' '%%P0.000' '-0.450' -> met; None neu khong phai cao do"""
    u = (s or "").upper().replace("%%P", "").replace("±", "").replace(",", ".").strip()
    m = re.fullmatch(r"([+-]?)\s*([0-9]+)\.([0-9]{3})", u)
    if not m:
        return None
    v = int(m.group(2)) + int(m.group(3)) / 1000.0
    return -v if m.group(1) == "-" else v


def dstyle_ovr(e):
    """XData ACAD DSTYLE -> {ma: gia tri}"""
    if not e.has_xdata("ACAD"):
        return {}
    x = list(e.get_xdata("ACAD"))
    on, i, res = False, 0, {}
    while i < len(x):
        t = x[i]
        if t.code == 1000 and t.value == "DSTYLE":
            on = True
        elif on and t.code == 1002 and t.value == "}":
            break
        elif on and t.code == 1070 and i + 1 < len(x):
            res[t.value] = x[i + 1].value
            i += 1
        i += 1
    return res


def xform(p, ins, sx, sy, rot_deg):
    a = math.radians(rot_deg)
    x, y = p[0] * sx, p[1] * sy
    return (ins[0] + x * math.cos(a) - y * math.sin(a), ins[1] + x * math.sin(a) + y * math.cos(a))


def ent_text(e):
    if e.dxftype() == "MTEXT":
        return e.plain_text()
    return e.dxf.text


def ent_h(e):
    return e.dxf.height if e.dxftype() in ("TEXT", "ATTDEF", "ATTRIB") else e.dxf.char_height


def ent_pt(e):
    t = e.dxftype()
    try:
        if t == "LINE":
            return e.dxf.start
        if t == "LWPOLYLINE":
            p = e.get_points()[0]
            return (p[0], p[1])
        if t == "HATCH":
            return ezbbox.extents([e], fast=True).center
        if t == "DIMENSION":
            return e.dxf.defpoint
        if t == "LEADER":
            return e.vertices[0]
        if e.dxf.hasattr("insert"):
            return e.dxf.insert
        if e.dxf.hasattr("center"):
            return e.dxf.center
    except Exception:
        return None
    return None


# ---------------------------------------------------------------- phan tich
class Template:
    def __init__(self, path):
        self.doc = ezdxf.readfile(path)
        self.msp = self.doc.modelspace()
        self.cp = "cp" + (self.doc.header.get("$DWGCODEPAGE", "ANSI_1252").upper().replace("ANSI_", "") or "1252")
        self.path = path
        self.blkext = {}
        self.find_frames()

    # ---------------- block
    def bext(self, name):
        if name not in self.blkext:
            b = self.doc.blocks.get(name)
            ext = ezbbox.extents(b, fast=True) if b is not None else None
            self.blkext[name] = ((ext.extmin.x, ext.extmin.y), (ext.extmax.x, ext.extmax.y)) if ext and ext.has_data else None
        return self.blkext[name]

    def ins_box(self, e):
        ext = self.bext(e.dxf.name)
        if not ext:
            return None
        pts = [xform(p, (e.dxf.insert.x, e.dxf.insert.y), e.dxf.xscale, e.dxf.yscale, e.dxf.rotation)
               for p in (ext[0], ext[1], (ext[0][0], ext[1][1]), (ext[1][0], ext[0][1]))]
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        return (min(xs), min(ys), max(xs), max(ys))

    # ---------------- khung ten
    def find_frames(self):
        cnt = collections.Counter()
        size = {}
        for e in self.msp.query("INSERT"):
            if not e.attribs:
                continue
            ext = self.bext(e.dxf.name)
            if ext:
                w = (ext[1][0] - ext[0][0]) * abs(e.dxf.xscale)
                cnt[e.dxf.name] += 1
                size[e.dxf.name] = max(size.get(e.dxf.name, 0), w)
        big = max(size.values())
        cands = [n for n in cnt if size[n] >= 0.5 * big and len(self.doc.blocks[n].query("ATTDEF")) >= 3]
        self.main = max(cands, key=lambda n: (cnt[n], size[n]))
        ext = self.bext(self.main)
        mw, mh = ext[1][0] - ext[0][0], ext[1][1] - ext[0][1]
        # ty le goc: ty le ghi / scale X (lay trung vi)
        facs = []
        tag_tl = self.tag_guess()["TL"]
        for e in self.msp.query('INSERT[name=="%s"]' % self.main):
            sc = parse_scale(self.att(e, tag_tl))
            if sc:
                facs.append(sc / abs(e.dxf.xscale))
        facs.sort()
        self.main_fac = round(facs[len(facs) // 2], 3) if facs else 1.0
        self.paper = (mw / self.main_fac, mh / self.main_fac)
        # khung phu: cung ti le canh, cung kich thuoc giay khi chen
        self.extra = {}
        for name in set(e.dxf.name for e in self.msp.query("INSERT")):
            if name == self.main or name.startswith("*"):
                continue
            ext = self.bext(name)
            if not ext:
                continue
            w, h = ext[1][0] - ext[0][0], ext[1][1] - ext[0][1]
            if w <= 0 or h <= 0 or abs((w / h) / (mw / mh) - 1) > 0.01:
                continue
            fac = w / self.paper[0]
            ins = list(self.msp.query('INSERT[name=="%s"]' % name))
            # scale thuc cua moi lan chen phai la ty le "tron" (>= 1)
            scs = [abs(e.dxf.xscale) * fac for e in ins]
            if scs and all(s >= 1 and abs(s - round(s)) < 0.01 for s in scs):
                self.extra[name] = round(fac) if abs(fac - round(fac)) < 0.01 else round(fac, 4)
        self.frames = []
        tg = self.tag_guess()
        for e in self.msp.query("INSERT"):
            n = e.dxf.name
            if n != self.main and n not in self.extra:
                continue
            fac = self.main_fac if n == self.main else self.extra[n]
            box = self.ins_box(e)
            f = dict(ent=e, block=n, box=box, scale=round(abs(e.dxf.xscale) * fac, 3),
                     sx=e.dxf.xscale, rot=e.dxf.rotation, layer=e.dxf.layer,
                     so=self.att(e, tg["SO"]), ten=self.att(e, tg["TEN"]),
                     ten2=self.att(e, tg["TEN2"]), tl=self.att(e, tg["TL"]),
                     ins=(e.dxf.insert.x, e.dxf.insert.y))
            f["tl_val"] = parse_scale(f["tl"])
            f["title"] = (f["ten"] + " " + f["ten2"]).strip()
            f["kind"] = self.kind(f["title"]) if n == self.main else "BIA"
            self.frames.append(f)
        self.frames.sort(key=lambda f: (-round(f["box"][3], -2), f["box"][0]))

    @staticmethod
    def att(e, tag):
        if not tag:
            return ""
        for a in e.attribs:
            if a.dxf.tag.upper() == tag:
                return a.dxf.text.strip()
        return ""

    def tag_guess(self):
        tags = [a.dxf.tag.upper() for a in self.doc.blocks[self.main].query("ATTDEF")] if hasattr(self, "main") else []
        def pick(pats, excl=()):
            for p in pats:
                for t in tags:
                    if t not in excl and re.search(p, t):
                        return t
            return ""
        tl = pick([r"TY_?LE", r"SCALE"])
        ten = pick([r"TEN_?BAN_?VE", r"TITLE"], (tl,))
        so = pick([r"SO_?HIEU", r"SHEET", r"SO_?BV"], (tl, ten))
        ten2 = pick([r"TEN"], (tl, ten, so))
        return dict(TL=tl, TEN=ten, SO=so, TEN2=ten2)

    @staticmethod
    def kind(title):
        n = norm(title)
        k = []
        if "MATBANG" in n:
            k.append("MB")
        if any(x in n for x in ("MATDUNG", "MATTIEN", "MATBEN", "MATSAU")):
            k.append("MD")
        if "MATCAT" in n:
            k.append("MC")
        if n.startswith("CHITIET"):
            k.append("CT")
        return "+".join(k) or "-"

    def frame_at(self, p):
        if p is None:
            return None
        for f in self.frames:
            b = f["box"]
            if b[0] <= p[0] <= b[2] and b[1] <= p[1] <= b[3]:
                return f
        return None

    # ---------------- bang ky hieu
    def usage(self):
        top = collections.Counter()
        alll = collections.Counter()
        styles_top = collections.Counter()
        styles_all = collections.Counter()
        dims = collections.Counter()
        seen = set()

        def walk(ents, is_top):
            for e in ents:
                alll[e.dxf.layer] += 1
                if is_top:
                    top[e.dxf.layer] += 1
                t = e.dxftype()
                if t in ("TEXT", "MTEXT", "ATTDEF"):
                    styles_all[e.dxf.style] += 1
                    if is_top:
                        styles_top[e.dxf.style] += 1
                if t in ("DIMENSION", "LEADER"):
                    dims[e.dxf.dimstyle] += 1
                if t == "INSERT":
                    for a in e.attribs:
                        styles_all[a.dxf.style] += 1
                        alll[a.dxf.layer] += 1
                    if e.dxf.name not in seen:
                        seen.add(e.dxf.name)
                        b = self.doc.blocks.get(e.dxf.name)
                        if b is not None:
                            walk(b, False)
        walk(self.msp, True)
        return top, alll, styles_top, styles_all, dims

    def style_font(self, s):
        f = s.dxf.font or ""
        fam = ""
        try:
            if s.has_xdata("ACAD"):
                x = list(s.get_xdata("ACAD"))
                if x and x[0].code == 1000:
                    fam = x[0].value
        except Exception:
            pass
        return f, (s.dxf.get("bigfont", "") or ""), fam

    # ---------------- dim
    def dim_rows(self):
        rows = []
        for e in self.msp.query("DIMENSION"):
            st = self.doc.dimstyles.get(e.dxf.dimstyle)
            o = dstyle_ovr(e)
            ds = o.get(40, st.dxf.get("dimscale", 1.0) if st else 1.0)
            txt = o.get(140, st.dxf.get("dimtxt", 2.5) if st else 2.5)
            lf = o.get(144, st.dxf.get("dimlfac", 1.0) if st else 1.0)
            tsn = st.dxf.get("dimtxsty", "Standard") if st else "Standard"
            ts = self.doc.styles.get(tsn)
            fixed = ts.dxf.get("height", 0.0) if ts else 0.0
            heff = fixed if fixed and fixed > 0 else txt
            f = self.frame_at(e.dxf.defpoint)
            geo = None
            if e.dimtype in (0, 1):
                p1, p2 = e.dxf.defpoint2, e.dxf.defpoint3
                a = math.radians(e.dxf.get("angle", 0.0)) if e.dimtype == 0 else math.atan2(p2.y - p1.y, p2.x - p1.x)
                geo = abs((p2.x - p1.x) * math.cos(a) + (p2.y - p1.y) * math.sin(a))
            m42 = e.dxf.get("actual_measurement", None)
            hp = heff * (ds if ds and ds > 0 else 1.0) / f["scale"] if f else None
            rows.append(dict(e=e, style=e.dxf.dimstyle, ds=ds, txt=txt, heff=heff, lf=lf, frame=f, hp=hp,
                             geo=geo, m42=m42, ovr=o, text=e.dxf.get("text", "")))
        return rows

    # ---------------- ky hieu
    def blocks_with_atts(self):
        res = collections.OrderedDict()
        for e in self.msp.query("INSERT"):
            if e.attribs or e.dxf.name in ("vet cat",):
                d = res.setdefault(e.dxf.name, dict(n=0, tags=[a.dxf.tag for a in e.attribs], vals=collections.Counter(),
                                                    scales=collections.Counter(), layers=collections.Counter(),
                                                    frames=collections.Counter()))
                d["n"] += 1
                for a in e.attribs:
                    d["vals"][a.dxf.text] += 1
                d["scales"][(round(e.dxf.xscale, 3), round(e.dxf.yscale, 3), round(e.dxf.rotation) % 360)] += 1
                d["layers"][e.dxf.layer] += 1
                f = self.frame_at(e.dxf.insert)
                d["frames"][f["so"] if f else "(ngoai khung)"] += 1
        return res

    def level_refpt(self, name):
        """diem goc cao do trong block: y cua LINE ngang dai nhat; x = dinh SOLID nam tren vach (neu co)"""
        b = self.doc.blocks[name]
        best = None
        for e in b:
            segs = []
            if e.dxftype() == "LINE":
                segs = [((e.dxf.start.x, e.dxf.start.y), (e.dxf.end.x, e.dxf.end.y))]
            elif e.dxftype() == "LWPOLYLINE":
                pts = [(p[0], p[1]) for p in e.get_points()]
                segs = list(zip(pts, pts[1:]))
            for a, c in segs:
                if abs(a[1] - c[1]) < 1e-6 and (best is None or abs(c[0] - a[0]) > best[0]):
                    best = (abs(c[0] - a[0]), a[1])
        if not best:
            return (0.0, 0.0)
        y = best[1]
        x = 0.0
        for e in b.query("SOLID"):
            for v in ("vtx0", "vtx1", "vtx2", "vtx3"):
                p = e.dxf.get(v)
                if p is not None and abs(p[1] - y) < 0.01 * best[0]:
                    x = p[0]
        return (round(x, 2), round(y, 2))


# ---------------------------------------------------------------- chon loc chuan cong ty
def is_company_layer(n):
    return n in ("0", "Defpoints") or (n.startswith("1 ") and "$" not in n)


def is_company_dimstyle(n):
    return bool(re.match(r"^(DG|TL) 1-\d", n))


def company_textstyles(T, dimstyles):
    keep = set()
    for s in T.doc.styles:
        n = s.dxf.name
        if n.startswith("0 ") or n.startswith("0_T_") or n in ("Arial", "Standard"):
            keep.add(n)
    for dn in dimstyles:
        st = T.doc.dimstyles.get(dn)
        if st is not None:
            keep.add(st.dxf.get("dimtxsty", "Standard"))
    for bn in [T.main] + list(T.extra):
        for e in T.doc.blocks[bn]:
            if e.dxftype() in ("TEXT", "MTEXT", "ATTDEF"):
                keep.add(e.dxf.style)
    return keep


# ---------------------------------------------------------------- bao cao
def report(T, out):
    W = out.write
    doc = T.doc
    W("# So lieu phan tich %s\n\n" % T.path)
    W("DXF %s, codepage %s, $INSUNITS=%s, $DIMSCALE=%s, $LTSCALE=%s\n\n" % (
        doc.dxfversion, doc.header.get("$DWGCODEPAGE"), doc.header.get("$INSUNITS"),
        doc.header.get("$DIMSCALE"), doc.header.get("$LTSCALE")))
    W("Doi tuong Model: %s\n\n" % dict(collections.Counter(e.dxftype() for e in T.msp).most_common()))
    W("Layout: %s\n\n" % ", ".join("%s (%d)" % (l.name, len(l)) for l in doc.layouts if l.name != "Model"))

    # khung
    tg = T.tag_guess()
    W("## Khung ten\n\nKhung chinh: %s (ty le goc %s, giay %sx%s mm); khung phu: %s\n\n" % (
        T.main, fmt(T.main_fac), fmt(T.paper[0], 0), fmt(T.paper[1], 0),
        ", ".join("%s (ty le goc %s)" % (k, v) for k, v in T.extra.items()) or "-"))
    W("Tag: %s\n\n" % tg)
    W("| ATTDEF | gia tri mac dinh | cao | style | layer |\n|---|---|---|---|---|\n")
    for a in doc.blocks[T.main].query("ATTDEF"):
        W("| %s | %s | %s | %s | %s |\n" % (a.dxf.tag, a.dxf.text, fmt(a.dxf.height), a.dxf.style, a.dxf.layer))
    W("\n| # | block | so hieu | ten ban ve | dong 2 | TL ghi | scale X | TL thuc | loai | goc (x,y) |\n"
      "|---|---|---|---|---|---|---|---|---|---|\n")
    for i, f in enumerate(T.frames, 1):
        W("| %d | %s | %s | %s | %s | %s | %s | %s | %s | %d,%d |\n" % (
            i, f["block"], f["so"], f["ten"], f["ten2"], f["tl"], fmt(f["sx"], 4), fmt(f["scale"]), f["kind"],
            f["ins"][0], f["ins"][1]))
    sos = collections.Counter(norm(f["so"]) for f in T.frames if f["so"])
    W("\nSo hieu trung: %s\n" % [k for k, v in sos.items() if v > 1])
    bad = [f["so"] for f in T.frames if f["tl_val"] and abs(f["tl_val"] - f["scale"]) > 0.005 * f["scale"]]
    W("TL ghi khac TL thuc: %s\n" % bad)
    W("Ty le dung: %s\n\n" % dict(collections.Counter(fmt(f["scale"]) for f in T.frames)))

    # dimstyle
    top, alll, sty_top, sty_all, dimuse = T.usage()
    rows = T.dim_rows()
    W("## Dimstyle\n\n| ten | dimscale | dimlfac | dimtxt | dimasz | textstyle | dec | mui ten | so dim+leader |\n"
      "|---|---|---|---|---|---|---|---|---|\n")
    for s in doc.dimstyles:
        g = s.dxf.get
        W("| %s | %s | %s | %s | %s | %s | %s | %s | %d |\n" % (
            s.dxf.name, fmt(g("dimscale")), fmt(g("dimlfac")), fmt(g("dimtxt")), fmt(g("dimasz")),
            g("dimtxsty"), g("dimdec"), g("dimblk") or "", dimuse.get(s.dxf.name, 0)))
    W("\nDim theo ty le khung (style -> so dim, chieu cao chu giay):\n\n| TL khung | dimstyle | so dim | chu dim giay (mm) | DIMLFAC |\n|---|---|---|---|---|\n")
    agg = collections.defaultdict(collections.Counter)
    for r in rows:
        k = (fmt(r["frame"]["scale"]) if r["frame"] else "ngoai", r["style"])
        agg[k][(fmt(r["hp"], 2) if r["hp"] else "-", fmt(r["lf"], 3))] += 1
    for k in sorted(agg, key=lambda k: (k[0], k[1])):
        for (hp, lf), n in agg[k].most_common():
            W("| %s | %s | %d | %s | %s |\n" % (k[0], k[1], n, hp, lf))
    ov = collections.Counter()
    for r in rows:
        o = r["ovr"]
        ov[(r["style"],) + tuple("%d=%s" % (c, fmt(o[c], 3)) for c in (40, 140, 144) if c in o)] += 1
    W("\nOverride DSTYLE (40=DIMSCALE 140=DIMTXT 144=DIMLFAC):\n\n")
    for k, n in ov.most_common():
        W("- %d x %s\n" % (n, " ".join(k)))
    r42 = collections.Counter()
    for r in rows:
        if r["geo"] and r["m42"]:
            r42[(r["style"], fmt(r["m42"] / r["geo"], 3), fmt(r["lf"], 3))] += 1
    W("\nMa 42 / do hinh hoc (kiem tra 42 da nhan DIMLFAC):\n\n")
    for k, n in r42.most_common():
        W("- %d x %s: 42/hinh = %s, DIMLFAC = %s\n" % (n, k[0], k[1], k[2]))
    txt = collections.Counter((r["style"], r["text"]) for r in rows if r["text"] not in ("", "<>"))
    W("\nChu ghi de: %s\n\n" % dict(txt))

    # leader
    W("## Leader\n\n")
    W("Dimstyle: %s; layer: %s\n\n" % (dict(collections.Counter(e.dxf.dimstyle for e in T.msp.query("LEADER"))),
                                       dict(collections.Counter(e.dxf.layer for e in T.msp.query("LEADER")))))

    # textstyle
    W("## Textstyle\n\n| ten | font | bigfont | ho TTF | cao co dinh | width | dung (ngoai block / tong) |\n|---|---|---|---|---|---|---|\n")
    for s in doc.styles:
        f, bf, fam = T.style_font(s)
        W("| %s | %s | %s | %s | %s | %s | %d / %d |\n" % (s.dxf.name, f, bf, fam, fmt(s.dxf.get("height", 0.0)),
                                                       fmt(s.dxf.get("width", 1.0)), sty_top.get(s.dxf.name, 0),
                                                       sty_all.get(s.dxf.name, 0)))
    W("\nChieu cao chu quy ra giay (TEXT/MTEXT trong Model, bo MTEXT co \\H):\n\n| TL khung | style | cao giay (mm) | so chu | vi du |\n|---|---|---|---|---|\n")
    th = collections.defaultdict(list)
    for e in T.msp.query("TEXT MTEXT"):
        if e.dxftype() == "MTEXT" and "\\H" in e.text:
            continue
        f = T.frame_at(e.dxf.insert)
        if not f:
            continue
        th[(fmt(f["scale"]), e.dxf.style, round(ent_h(e) / f["scale"], 2))].append(ent_text(e)[:25])
    for k in sorted(th, key=lambda k: (float(k[0]), k[1], k[2])):
        W("| %s | %s | %s | %d | %s |\n" % (k[0], k[1], fmt(k[2], 2), len(th[k]), th[k][0].replace("|", "/").replace("\n", " ")))

    # layer
    W("\n## Layer\n\n| layer | mau | linetype | lw | plot | ngoai block | tong | ho cong ty |\n|---|---|---|---|---|---|---|---|\n")
    for l in doc.layers:
        n = l.dxf.name
        W("| %s | %s | %s | %s | %s | %d | %d | %s |\n" % (n, l.dxf.color, l.dxf.linetype, l.dxf.get("lineweight", -3),
                                                       l.dxf.get("plot", 1), top.get(n, 0), alll.get(n, 0),
                                                       "x" if is_company_layer(n) else ""))
    where = collections.defaultdict(collections.Counter)
    for e in T.msp:
        f = T.frame_at(ent_pt(e))
        where[e.dxf.layer][f["so"] if f else "(ngoai khung)"] += 1
    W("\nLayer rac dang co doi tuong ngoai block (vi tri):\n\n")
    for n in sorted(where):
        if not is_company_layer(n):
            W("- %s: %s\n" % (n, dict(where[n].most_common(6))))
    lay0 = collections.Counter((e.dxftype(), e.dxf.name if e.dxftype() == "INSERT" else "") for e in T.msp if e.dxf.layer == "0")
    W("\nDoi tuong tren layer 0 (Model): %s\n" % dict(lay0))

    # ky hieu
    W("\n## Block co attribute / ky hieu\n\n")
    for n, d in T.blocks_with_atts().items():
        W("- **%s** x%d tag=%s layer=%s scale(x,y,rot)=%s\n  gia tri: %s\n  khung: %s\n" % (
            n, d["n"], d["tags"], dict(d["layers"]), dict(d["scales"].most_common(6)),
            dict(d["vals"].most_common(12)), dict(d["frames"].most_common(8))))
    # truc
    if "TRỤC" in doc.blocks:
        b = doc.blocks["TRỤC"]
        W("\nTRUC: %s\n" % [(e.dxftype(), tuple(round(v, 1) for v in e.dxf.center)[:2], round(e.dxf.radius, 1))
                             for e in b if e.dxftype() == "CIRCLE"])
    # cao do
    for bn in ("COTCAODO", "KI HIEU CODE MB"):
        if bn in doc.blocks:
            W("Diem goc cao do %s (trong block): %s\n" % (bn, T.level_refpt(bn)))
    W("\nKiem tra moc cao do (Y diem goc - 1000 x gia tri) theo ban ve:\n\n")
    ref = T.level_refpt("COTCAODO") if "COTCAODO" in doc.blocks else (0, 0)
    grp = collections.defaultdict(list)
    for e in T.msp.query('INSERT[name=="COTCAODO"]'):
        v = level_val(e.attribs[0].dxf.text if e.attribs else "")
        if v is None:
            continue
        f = T.frame_at(e.dxf.insert)
        p = xform(ref, (e.dxf.insert.x, e.dxf.insert.y), e.dxf.xscale, e.dxf.yscale, e.dxf.rotation)
        grp[f["so"] if f else "-"].append((v, round(p[1] - 1000 * v, 1), round(e.dxf.insert.y - 1000 * v, 1), e))
    for so, lst in grp.items():
        datums = collections.Counter(x[1] for x in lst)
        main = datums.most_common(1)[0][0]
        odd = [(x[0], round(x[1] - main, 1)) for x in lst if abs(x[1] - main) > 5]
        raw = collections.Counter(x[2] for x in lst)
        W("- %s: %d ky hieu, moc %s, lech > 5mm: %s; (neu dung diem chen: %d moc khac nhau)\n" % (
            so, len(lst), main, odd or "-", len(raw)))

    # ngoai khung
    nout = collections.Counter(e.dxftype() for e in T.msp if T.frame_at(ent_pt(e)) is None)
    W("\n## Ngoai khung\n\n%s\n" % dict(nout))


# ---------------------------------------------------------------- sinh file chuan
def emit_cfg(T, path):
    doc, cp = T.doc, T.cp
    top, alll, sty_top, sty_all, dimuse = T.usage()
    L = lambda s: lisp_name(s, cp)
    rows = T.dim_rows()
    lines = []
    A = lines.append
    A(";;; ============================================================")
    A(";;; KT_ChuanCongTy.txt - CHUAN CONG TY (Kien truc & Noi that Dong Giao) cho bo kiem tra ban ve KT")
    A(";;; Sinh boi tools/template_analysis.py tu ban ve mau Template.dxf (61 khung KHUNGTEENA + 11 bia")
    A(";;; KHUNGT43), DA CHON LOC: chi giu ho layer/dimstyle/textstyle cua cong ty, bo rac (xem")
    A(";;; docs/TEMPLATE_ANALYSIS.md muc 'Rac trong template').")
    A(";;; MA HOA: file ghi codepage %s. Ten giu DUNG nhu AutoLISP ANSI nhin thay: ky tu thuoc codepage" % cp)
    A(";;;   = 1 byte (vd 'E sac' trong '1 NET THAY'), ky tu ngoai codepage = \\U+XXXX (vd TRUC = TR\\U+1EE4C).")
    A(";;;   KHONG mo/luu lai file nay bang trinh soan thao doi sang UTF-8 (ten layer co dau se khong khop).")
    A(";;; ------------------------------------------------------------")
    A(";;; Dinh dang: moi dong  MUC|truong1|truong2|...   ; dong bat dau ';' la ghi chu")
    A(";;;   LAYER|ten|mau(1-255)|linetype|lineweight(1/100mm, -3=mac dinh)|plot(1/0)")
    A(";;;   DIMSTYLE|ten|dimscale|dimlfac|dimtxt|dimasz|textstyle|dimdec|annotative(1/0)")
    A(";;;   TEXTSTYLE|ten|font (file hoac ho TrueType)|bigfont|chieu cao co dinh(0=khong)|width factor")
    A(";;;   KHUNG|ten block|tag so hieu|tag ten ban ve(+tag dong 2...)|tag ty le|ty le goc|tag khac...")
    A(";;;   BLOCK|ten block|vai tro (TRUC/CAODO/MATCAT/CHITIET/CUA/KHAC)|tag chinh|tag phu|diem goc x,y")
    A(";;;   DANHMUC|so hieu|ten ban ve      SETTING|KHOA|gia tri")
    A(";;; ============================================================")
    A("")
    # ---------------- SETTING
    scales = sorted(set(int(round(f["scale"])) for f in T.frames))
    th = collections.Counter()
    keep_ts = company_textstyles(T, [s.dxf.name for s in doc.dimstyles if is_company_dimstyle(s.dxf.name)])
    for e in T.msp.query("TEXT MTEXT"):
        if e.dxftype() == "MTEXT" and "\\H" in e.text:
            continue
        f = T.frame_at(e.dxf.insert)
        if f and e.dxf.style in keep_ts and f["kind"] != "BIA" and abs(f["scale"] - 35) > 0.5:
            th[round(ent_h(e) / f["scale"] * 20) / 20.0] += 1
    hs = sorted(h for h, n in th.items() if n >= 10)
    dh = collections.Counter(round(r["hp"], 2) for r in rows if r["hp"] and is_company_dimstyle(r["style"])
                             and abs(r["frame"]["scale"] - 35) > 0.5)
    dhs = sorted(h for h, n in dh.items() if n >= 20)
    A("; ---------- SETTING ----------")
    A("; CAO_CHU_GIAY: chieu cao chu IN TREN GIAY (mm) = chieu cao that / ty le khung (dung sai 3%).")
    A(";   Thong ke tu template (chu ngoai block, style cong ty, gia tri >= 10 lan; bo to bia va khung 1/35):")
    A(";   0.75 ten do noi that, 1.25 dien tich phong, 1.8 ten phong, 2.0/2.2/2.5 ghi chu, 3.3 bang thong ke")
    A(";   cua, 4.0/5.0 ten hinh ve. Them 10 = tieu de to bia.")
    A("SETTING|CAO_CHU_GIAY|%s" % ",".join(fmt(h, 2) for h in sorted(set(hs + [10.0]))))
    A("; CAO_CHU_DIM: chieu cao chu DIM tren giay (mm) = DIMTXT hieu dung x (DIMSCALE neu >0, khong thi 1)")
    A(";   / ty le khung. Cong ty de DIMSCALE=0 va DIMTXT theo don vi ban ve: DG 1-100 (200) 150 -> 1.5mm,")
    A(";   DG 1-30 (60) 60 -> 2.0mm o 1/30, TL 1-60 (120) 120 -> 2.0mm o 1/60. Lech <= 25% -> CANHBAO, hon -> LOI.")
    A("SETTING|CAO_CHU_DIM|%s" % ",".join(fmt(h, 2) for h in dhs))
    A("; TY_LE_CHO_PHEP: mau so ty le duoc phep. Template dung: %s." % ", ".join("1/%d" % s for s in scales))
    allowed = sorted(set(scales + [1, 2, 5, 10, 15, 25, 50, 75, 150, 200, 250, 500]))
    A("SETTING|TY_LE_CHO_PHEP|%s" % ",".join(str(s) for s in allowed))
    A("; LAYER_MAU_BYLAYER: 1 = doi tuong bat buoc mau/linetype ByLayer.")
    A("SETTING|LAYER_MAU_BYLAYER|1")
    A("; MAU_BYOBJ_BO_QUA: HATCH mau 8 (xam) gan rieng la thoi quen cua template (157 hatch).")
    A("SETTING|MAU_BYOBJ_BO_QUA|HATCH")
    A("SETTING|MAX_LOI_MOI_MA|300")
    A("SETTING|DUNG_SAI_KICH_THUOC|1")
    A("; LAYER_BO_QUA: *|* = layer xref. KT_CHECK / CHECK_DIM_OVERLAP = layer danh dau.")
    A("SETTING|LAYER_BO_QUA|DEFPOINTS,KT_CHECK,CHECK_DIM_OVERLAP,*|*")
    A("; KHUNG_TRUNGTEN_LIENTIEP: 0 = khong bao trung ten khi cac to cung ten co so hieu LIEN TIEP cung")
    A(";   tien to (bo nhieu to 'CHI TIET CUA' C/01..C/07 - quy cach cong ty), 1 = bao GOIY.")
    A("SETTING|KHUNG_TRUNGTEN_LIENTIEP|0")
    fonts = set()
    for s in doc.styles:
        if s.dxf.name in keep_ts:
            f, bf, fam = T.style_font(s)
            for x in (f, bf):
                if x:
                    fonts.add(x.lower())
    A("; FONT_CHO_PHEP: file font cua textstyle cong ty (TrueType theo ho -> khong co file).")
    A("SETTING|FONT_CHO_PHEP|%s" % ",".join(sorted(fonts)))
    A("")
    # ---------------- LAYER
    A("; ---------- LAYER: ten|mau|linetype|lineweight|plot ----------")
    A("; Ho cong ty: '0', 'Defpoints', '1 <TEN>' (co dau cach). Layer '1-xxx' (khong cach) la cua chi tiet")
    A("; chong tham copy tu file khac (CTH/01) -> rac, khong dua vao chuan.")
    for l in sorted(doc.layers, key=lambda l: l.dxf.name.upper()):
        n = l.dxf.name
        if not is_company_layer(n):
            continue
        if alll.get(n, 0) == 0 and n not in ("0", "Defpoints"):
            continue
        A("LAYER|%s|%d|%s|%d|%d" % (L(n), abs(l.dxf.color), L(l.dxf.linetype), l.dxf.get("lineweight", -3),
                                    1 if l.dxf.get("plot", 1) else 0))
    A("")
    # ---------------- DIMSTYLE
    A("; ---------- DIMSTYLE: ten|dimscale|dimlfac|dimtxt|dimasz|textstyle|dimdec|annotative ----------")
    A("; Quy cach: DIMSCALE = 0, DIMTXT/DIMASZ theo don vi ban ve (mm model). 'DG 1-<TL> (<chu>)' cho khung")
    A("; 1/<TL>; ban 'x2'/'x4' (DIMLFAC 0.5/0.25) chi dung cho chi tiet VE PHONG TO 2/4 lan trong khung 1/30.")
    A("; Luu y: 'DG 1-100 (200)' ten ghi (200) nhung DIMTXT = 150 (chu 1.5mm).")
    for s in sorted(doc.dimstyles, key=lambda s: s.dxf.name):
        n = s.dxf.name
        if not is_company_dimstyle(n):
            continue
        g = s.dxf.get
        A("DIMSTYLE|%s|%s|%s|%s|%s|%s|%s|0" % (L(n), fmt(g("dimscale", 1.0)), fmt(g("dimlfac", 1.0)), fmt(g("dimtxt", 2.5)),
                                              fmt(g("dimasz", 2.5)), L(g("dimtxsty", "Standard")), g("dimdec", 4)))
    A("")
    # ---------------- TEXTSTYLE
    A("; ---------- TEXTSTYLE: ten|font|bigfont|cao co dinh|width ----------")
    A("; '0 ARIAL 2'/'0 ARIAL 2.5'/'0 ARIAL TEN' cao co dinh 200/250/400 (= 2/2.5/4mm o 1/100);")
    A("; '0_T_*' dung trong khung ten/COTCAODO; 'mb tret$0$DIMENSION' la textstyle cua dimstyle DG/TL")
    A("; (font VNI-Helve-Condense); 'VHAVANT'/'bold' cua to bia KHUNGT43 (font TCVN3 .VnAvantH).")
    for s in sorted(doc.styles, key=lambda s: s.dxf.name.upper()):
        n = s.dxf.name
        if n not in keep_ts:
            continue
        f, bf, fam = T.style_font(s)
        A("TEXTSTYLE|%s|%s|%s|%s|%s" % (L(n), L(f or fam), L(bf), fmt(s.dxf.get("height", 0.0), 3),
                                       fmt(s.dxf.get("width", 1.0), 3)))
    A("")
    # ---------------- KHUNG
    tg = T.tag_guess()
    others = [a.dxf.tag.upper() for a in doc.blocks[T.main].query("ATTDEF")
              if a.dxf.tag.upper() not in (tg["SO"], tg["TEN"], tg["TL"], tg["TEN2"])]
    A("; ---------- KHUNG: block|tag so hieu|tag ten(+dong 2)|tag ty le|ty le goc|tag khac ----------")
    A("; %s: khung A3 ve san o 1/100 (block %sx%s) -> ty le goc %s; scale X 0.6 = 1/60, 0.3 = 1/30 ..."
      % (T.main, fmt(T.paper[0] * T.main_fac, 0), fmt(T.paper[1] * T.main_fac, 0), fmt(T.main_fac)))
    A(";   Ten ban ve = %s + %s (vd 'MAT BANG CONG NANG' + 'TANG 1 & TANG 2')." % (tg["TEN"], tg["TEN2"]))
    A("KHUNG|%s|%s|%s+%s|%s|%s%s" % (L(T.main), tg["SO"], tg["TEN"], tg["TEN2"], tg["TL"], fmt(T.main_fac),
                                    "".join("|" + o for o in others)))
    for n, fac in T.extra.items():
        etags = [a.dxf.tag.upper() for a in doc.blocks[n].query("ATTDEF")]
        if tg["SO"] in etags and tg["TEN"] in etags:
            A("; %s: khung cung mau (them NGAY/NGUOI THIET KE/HO SO), dung cho to PHOI CANH PC/01." % n)
            A("KHUNG|%s|%s|%s+%s|%s|%s%s" % (L(n), tg["SO"], tg["TEN"], tg["TEN2"], tg["TL"], fmt(fac),
                                            "".join("|" + o for o in etags if o not in (tg["SO"], tg["TEN"], tg["TL"], tg["TEN2"]))))
        else:
            A("; %s: to bia hang muc (khong attribute) cung kho A3; scale X 1.852 x %s = 1/100." % (n, fmt(fac, 2)))
            A("KHUNG|%s||||%s" % (L(n), fmt(fac, 4)))
    A("")
    # ---------------- BLOCK
    A("; ---------- BLOCK: ten|vai tro|tag chinh|tag phu (so ban ve tham chieu)|diem goc x,y ----------")
    A("; TRUC: diem chen = DUOI duoi cua ky hieu (nam tren duong truc), vong tron o phia tren 400 x scale.")
    A("; CAODO: diem goc = dinh tam giac tren vach cao do = (x,y) trong block o truong cuoi; diem chen KHONG nam")
    A(";   tren vach (lech 49 x scale) -> KTKHOP doi diem goc qua scale/mirror/xoay cua tung lan chen.")
    ref = T.level_refpt("COTCAODO")
    A("BLOCK|%s|TRUC|A" % L("TRỤC"))
    A("BLOCK|COTCAODO|CAODO|COTE||%s,%s" % (fmt(ref[0], 2), fmt(ref[1], 2)))
    ref2 = T.level_refpt("KI HIEU CODE MB")
    A("; KI HIEU CODE MB: ky hieu cao do tren MAT BANG (tag ten '+0.000', gia tri '+7.450', '%%P0.000').")
    A("BLOCK|KI HIEU CODE MB|CAODO|+0.000||%s,%s" % (fmt(ref2[0], 2), fmt(ref2[1], 2)))
    A("; GHICHUCHITIET: ky hieu goi chi tiet, TENCT = ten chi tiet (CT-01), VITRIBANVE = so hieu to chi tiet.")
    A("BLOCK|GHICHUCHITIET|CHITIET|TENCT|VITRIBANVE")
    A("; 41244 / 1444: ky hieu mat cat tren mat bang - tag 'B' = ten mat cat (A, B), tag 'KT-00' = so hieu to mat cat.")
    A("BLOCK|41244|MATCAT|B|KT-00")
    A("BLOCK|1444|MATCAT|B|KT-00")
    A("; vet cat mat cat (khong attribute, ten mat cat ghi bang TEXT).")
    A("BLOCK|vet cat|MATCAT|")
    A("; GHICHUCUA: dong bang thong ke cua; 1111111111111: ky hieu cua tren MB dinh vi cua (ma cua/kich thuoc/cao do bau).")
    A("BLOCK|GHICHUCUA|CUA|TENCUA")
    A("BLOCK|1111111111111|CUA|S1")
    A("; BLOCK DO DOC 2: ky hieu do doc (i=..%)")
    A("BLOCK|%s|KHAC|BLOCK" % L("BLOCK ĐỘ DỐC 2"))
    A("")
    # ---------------- DANHMUC
    A("; ---------- DANHMUC: so hieu|ten ban ve  (lay tu khung ten, template KHONG co bang danh muc) ----------")
    seen = set()
    def natkey(s):
        return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", norm(s.split("/")[0]) + "/" + s.split("/")[-1])]
    for f in sorted([f for f in T.frames if f["so"]], key=lambda f: natkey(f["so"])):
        k = (f["so"], f["title"])
        if k in seen:
            continue
        seen.add(k)
        A("DANHMUC|%s|%s" % (L(f["so"]), L(f["title"]).replace("|", "/")))
    data = "\n".join(lines) + "\n"
    with open(path, "w", encoding=cp, newline="\r\n") as fh:
        fh.write(data)
    return len(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("dxf")
    ap.add_argument("--cfg", help="ghi file chuan da chon loc")
    ap.add_argument("--json", help="ghi so lieu khung ten dang JSON")
    a = ap.parse_args(argv)
    T = Template(a.dxf)
    report(T, sys.stdout)
    if a.cfg:
        n = emit_cfg(T, a.cfg)
        print("\n[da ghi %s: %d dong]" % (a.cfg, n))
    if a.json:
        with open(a.json, "w", encoding="utf-8") as fh:
            json.dump([{k: v for k, v in f.items() if k != "ent"} for f in T.frames], fh, ensure_ascii=False, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
