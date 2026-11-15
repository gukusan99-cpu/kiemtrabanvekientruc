"""CSDL ban ve gia lap + Python builder (layer, style, dimstyle, block, INSERT/ATTRIB,
LINE, LWPOLYLINE, CIRCLE, TEXT, MTEXT, DIMENSION + block an danh *D, VIEWPORT, layout, XDATA).

Du lieu doi tuong: list (ma, gia tri) theo thu tu DXF; diem = tuple float; tham chieu = Ent.
"""
import math
from collections import OrderedDict

POINT_CODES = set(range(10, 19)) | {110, 111, 112, 210, 211, 212, 213, 1010, 1011, 1012, 1013}


# doi tuong luu toa do OCS (210 = (0 0 -1) -> lat truc X); MTEXT/ELLIPSE/LINE/DIMENSION la WCS
OCS_TYPES = {"CIRCLE", "ARC", "LWPOLYLINE", "TEXT", "ATTRIB", "ATTDEF", "INSERT", "HATCH", "SOLID", "TRACE"}


class Ent:
    def __init__(self, dwg, etype, data, kind, owner):
        self.dwg = dwg
        self.handle = dwg.newh()
        self.type = etype
        self.data = list(data)
        self.kind = kind            # main | sub | block | blockbegin | blockend | table | object
        self.owner = owner          # ten layout (main/sub) | ten block (block) | ten bang
        self.xdata = OrderedDict()  # app -> [(ma, gia tri)]
        self.deleted = False
        self.made = False           # tao boi entmake (lisp)
        self.subs = []              # ATTRIB..., SEQEND cua INSERT
        self.parent = None
        self.tag = None             # nhan cho test (vd "LOI:LAYER-0")
        self.ename = None
        dwg.ents[self.handle] = self

    def get(self, code, default=None):
        for c, v in self.data:
            if c == code:
                return v
        return default

    def gets(self, code):
        return [v for c, v in self.data if c == code]

    def set(self, code, val):
        for i, (c, v) in enumerate(self.data):
            if c == code:
                self.data[i] = (code, val)
                return
        self.data.append((code, val))

    @property
    def layer(self):
        return self.get(8, "0")

    def __repr__(self):
        return "<Ent %s %s %s>" % (self.handle, self.type, self.layer)


class Block:
    def __init__(self, name, begin, end, record, flags=0, base=(0.0, 0.0, 0.0), xref=None):
        self.name, self.begin, self.end, self.record = name, begin, end, record
        self.flags, self.base, self.xref = flags, base, xref
        self.ents = []


def P(p):
    p = tuple(float(x) for x in p)
    return p if len(p) >= 3 else (p[0], p[1], 0.0)


def P2(p):
    return (float(p[0]), float(p[1]))


class Drawing:
    def __init__(self, name="Drawing1.dwg"):
        self.name = name
        self._h = 0x100
        self.ents = {}
        self.main = []              # doi tuong chinh + ATTRIB/SEQEND theo thu tu CSDL
        self.tables = OrderedDict((t, OrderedDict()) for t in
                                  ["VPORT", "LTYPE", "LAYER", "STYLE", "VIEW", "UCS", "APPID",
                                   "DIMSTYLE", "BLOCK_RECORD"])
        self.blocks = OrderedDict()
        self.layouts = OrderedDict()  # ten -> Ent LAYOUT
        self.violations = []        # sua/xoa doi tuong goc cua ban ve
        self.selected = None        # sssetfirst
        self.vp_id = 1
        self.dimstyle_meta = {}
        self.style_ents = {}
        self.anon = 0
        # mac dinh
        self.rootdict = Ent(self, "DICTIONARY", [], "object", None)
        self.layoutdict = Ent(self, "DICTIONARY", [], "object", None)
        self.rootdict.data = [(3, "ACAD_LAYOUT"), (350, self.layoutdict)]
        for lt in ["ByBlock", "ByLayer", "Continuous"]:
            self.ltype(lt)
        self.layer("0")
        self.style("Standard", "arial.ttf")
        self.appid("ACAD")
        self._mkblock("*Model_Space", system=True)
        self._mkblock("*Paper_Space", system=True)
        self.dimstyle("Standard", dimscale=1.0, dimtxt=2.5, dimasz=2.5)
        self.layout("Model", _model=True)

    def newh(self):
        self._h += 1
        return "%X" % self._h

    # ------------------------------------------------------------ bang ky hieu
    def _rec(self, table, name, data):
        e = Ent(self, table if table != "BLOCK_RECORD" else "BLOCK_RECORD", [(2, name)] + data, "table", table)
        self.tables[table][name.upper()] = e
        return e

    def ltype(self, name, desc=""):
        if name.upper() in self.tables["LTYPE"]:
            return self.tables["LTYPE"][name.upper()]
        return self._rec("LTYPE", name, [(70, 0), (3, desc), (72, 65), (73, 0), (40, 0.0)])

    def appid(self, name):
        if name.upper() not in self.tables["APPID"]:
            self._rec("APPID", name, [(70, 0)])

    def layer(self, name, color=7, ltype="Continuous", lw=-3, plot=1, off=False, frozen=False):
        if ltype.upper() not in self.tables["LTYPE"]:
            self.ltype(ltype)
        data = [(70, 1 if frozen else 0), (62, -abs(color) if off else color), (6, ltype),
                (290, plot), (370, lw)]
        ex = self.tables["LAYER"].get(name.upper())
        if ex:
            ex.data = [(2, name)] + data
            return ex
        return self._rec("LAYER", name, data)

    def style(self, name, font, bigfont="", height=0.0, width=1.0, family=None):
        e = self._rec("STYLE", name, [(70, 0), (40, float(height)), (41, float(width)), (50, 0.0),
                                       (71, 0), (42, 2.5), (3, font), (4, bigfont)])
        if family:
            self.appid("ACAD")
            e.xdata["ACAD"] = [(1000, family), (1071, 34)]
        self.style_ents[name.upper()] = e
        return e

    def dimstyle(self, name, dimscale=1.0, dimlfac=1.0, dimtxt=2.5, dimasz=2.5, txsty="Standard",
                 dimdec=0, annotative=False, post=""):
        st = self.style_ents.get(txsty.upper()) or self.style_ents["STANDARD"]
        e = self._rec("DIMSTYLE", name, [(70, 0), (3, post), (40, float(dimscale)), (41, float(dimasz)),
                                          (42, 0.625), (44, 1.25), (140, float(dimtxt)), (141, 0.09),
                                          (144, float(dimlfac)), (147, 0.625), (77, 1), (271, int(dimdec)),
                                          (340, st)])
        if annotative:
            self.appid("AcadAnnotative")
            e.xdata["AcadAnnotative"] = [(1000, "AnnotativeData"), (1002, "{"), (1070, 1), (1070, 1),
                                         (1002, "}")]
        self.dimstyle_meta[name.upper()] = dict(dimscale=float(dimscale), dimtxt=float(dimtxt),
                                                dimdec=int(dimdec), dimlfac=float(dimlfac), txsty=txsty)
        return e

    # ------------------------------------------------------------ block / layout
    def _mkblock(self, name, flags=0, base=(0, 0, 0), xref=None, system=False):
        rec = self._rec("BLOCK_RECORD", name, [(70, 0)])
        bdata = [(8, "0"), (2, name), (70, flags), (10, P(base)), (3, name), (1, xref or "")]
        begin = Ent(self, "BLOCK", bdata, "blockbegin", name)
        end = Ent(self, "ENDBLK", [(8, "0")], "blockend", name)
        b = Block(name, begin, end, rec, flags, P(base), xref)
        b.system = system
        self.blocks[name.upper()] = b
        return b

    def block(self, name, base=(0, 0, 0), flags=0, xref=None):
        return self._mkblock(name, flags, base, xref)

    def layout(self, name, _model=False):
        tab = len(self.layouts)
        lo = Ent(self, "LAYOUT", [(1, name), (70, 1), (71, tab)], "object", None)
        self.layouts[name] = lo
        self.layoutdict.data += [(3, name), (350, lo)]
        if not _model:
            # viewport tong cua layout (69 = 1)
            self.add("VIEWPORT", [(8, "0"), (10, (148.5, 105.0, 0.0)), (40, 400.0), (41, 280.0),
                                  (68, 1), (69, 1), (12, (148.5, 105.0, 0.0)), (45, 280.0)], name)
        return lo

    # ------------------------------------------------------------ them doi tuong
    def add(self, etype, data, space="Model", subs=None):
        """space = ten layout hoac Block"""
        nd = []
        for c, v in data:
            if c in POINT_CODES and isinstance(v, (tuple, list)):
                v = P2(v) if (etype == "LWPOLYLINE" and c == 10) else P(v)
            nd.append((c, v))
        data = nd
        if not any(c == 8 for c, _ in data):
            data = [(8, "0")] + data
        lay = dict(data)[8]
        if lay.upper() not in self.tables["LAYER"]:
            self.layer(lay)
        if isinstance(space, Block):
            e = Ent(self, etype, data, "block", space.name)
            space.ents.append(e)
            return e
        if space not in self.layouts:
            raise ValueError("chua co layout " + space)
        e = Ent(self, etype, data, "main", space)
        e._mi = len(self.main)
        self.main.append(e)
        for s in subs or []:
            se = Ent(self, s[0], s[1], "sub", space)
            se.parent = e
            e.subs.append(se)
            se._mi = len(self.main)
            self.main.append(se)
        return e

    def line(self, p1, p2, layer="0", space="Model", **kw):
        d = [(8, layer)] + self._common(kw) + [(10, P(p1)), (11, P(p2))]
        return self.add("LINE", d, space)

    def _common(self, kw):
        d = []
        if "color" in kw:
            d.append((62, kw["color"]))
        if "ltype" in kw:
            d.append((6, kw["ltype"]))
        if "lw" in kw:
            d.append((370, kw["lw"]))
        return d

    def pline(self, pts, layer="0", space="Model", closed=False, elev=0.0, **kw):
        d = [(8, layer)] + self._common(kw) + [(90, len(pts)), (70, 1 if closed else 0), (43, 0.0),
                                                (38, float(elev))]
        for p in pts:
            d.append((10, P2(p)))
        return self.add("LWPOLYLINE", d, space)

    def rect(self, p1, p2, layer="0", space="Model", **kw):
        (x1, y1), (x2, y2) = p1[:2], p2[:2]
        return self.pline([(x1, y1), (x2, y1), (x2, y2), (x1, y2)], layer, space, closed=True, **kw)

    def circle(self, c, r, layer="0", space="Model", **kw):
        return self.add("CIRCLE", [(8, layer)] + self._common(kw) + [(10, P(c)), (40, float(r))], space)

    def text(self, p, s, h, layer="0", space="Model", style="Standard", width=1.0, rot=0.0, **kw):
        d = [(8, layer)] + self._common(kw) + [(10, P(p)), (40, float(h)), (1, s), (50, float(rot)),
                                                (41, float(width)), (7, style), (72, 0), (11, (0.0, 0.0, 0.0)),
                                                (73, 0)]
        return self.add("TEXT", d, space)

    def mtext(self, p, s, h, layer="0", space="Model", style="Standard", width=0.0, attach=1, **kw):
        d = [(8, layer)] + self._common(kw) + [(10, P(p)), (40, float(h)), (41, float(width)),
                                                (71, attach), (72, 5)]
        while len(s) > 250:
            d.append((3, s[:250]))
            s = s[250:]
        d += [(1, s), (7, style), (11, (1.0, 0.0, 0.0)), (42, 0.75 * h * max(1, len(s))), (43, float(h))]
        return self.add("MTEXT", d, space)

    def attdef(self, blk, tag, p, h, default="", prompt=None, style="Standard", layer="0"):
        d = [(8, layer), (10, P(p)), (40, float(h)), (1, default), (50, 0.0), (41, 1.0), (7, style),
             (72, 0), (11, (0.0, 0.0, 0.0)), (3, prompt or tag), (2, tag), (70, 0), (74, 0)]
        return self.add("ATTDEF", d, blk)

    def insert(self, name, p, scale=1.0, rot=0.0, attribs=None, layer="0", space="Model",
               sx=None, sy=None, **kw):
        b = self.blocks[name.upper()]
        sx = float(scale if sx is None else sx)
        sy = float(scale if sy is None else sy)
        p = P(p)
        subs = []
        attribs = dict(attribs or {})
        if attribs is not None:
            c, s = math.cos(rot), math.sin(rot)
            for ad in [e for e in b.ents if e.type == "ATTDEF"]:
                tag = ad.get(2)
                if tag not in attribs and tag.upper() not in attribs:
                    continue
                val = attribs.get(tag, attribs.get(tag.upper()))
                ap = ad.get(10)
                lx, ly = (ap[0] - b.base[0]) * sx, (ap[1] - b.base[1]) * sy
                wp = (p[0] + lx * c - ly * s, p[1] + lx * s + ly * c, p[2])
                subs.append(("ATTRIB", [(8, layer), (10, wp), (40, ad.get(40) * abs(sy)), (1, val),
                                        (50, float(rot)), (41, 1.0), (7, ad.get(7, "Standard")),
                                        (72, 0), (11, (0.0, 0.0, 0.0)), (2, tag), (70, 0), (74, 0)]))
        d = [(8, layer)] + self._common(kw)
        if subs:
            d.append((66, 1))
        d += [(2, b.name), (10, p), (41, sx), (42, sy), (43, float(scale)), (50, float(rot))]
        if subs:
            subs.append(("SEQEND", [(8, layer)]))
        return self.add("INSERT", d, space, subs)

    def viewport(self, layout, center, w, h, view_center, scale, layer="KT-VIEWPORT"):
        self.vp_id += 1
        d = [(8, layer), (10, P(center)), (40, float(w)), (41, float(h)), (68, 1), (69, self.vp_id),
             (12, P(view_center)), (13, (0.0, 0.0, 0.0)), (17, (0.0, 0.0, 0.0)), (45, float(h * scale)),
             (51, 0.0), (90, 32864)]
        return self.add("VIEWPORT", d, layout)

    def dim_linear(self, p1, p2, dpt, rot=0.0, style="Standard", override="", layer="0", space="Model",
                   measure=None, aligned=False):
        """dim thang (rotated); dpt = 1 diem tren duong dim. Tao block an danh *Dn (LINE + MTEXT)."""
        m = self.dimstyle_meta[style.upper()]
        u = (math.cos(rot), math.sin(rot))
        v = (-u[1], u[0])
        p1, p2, dpt = P(p1), P(p2), P(dpt)

        def proj(p):
            t = (p[0] - dpt[0]) * u[0] + (p[1] - dpt[1]) * u[1]
            return (dpt[0] + u[0] * t, dpt[1] + u[1] * t, 0.0)
        e1, e2 = proj(p1), proj(p2)
        meas = abs((p2[0] - p1[0]) * u[0] + (p2[1] - p1[1]) * u[1]) if measure is None else measure
        h = m["dimtxt"] * m["dimscale"]
        gap = 0.625 * m["dimscale"]
        mid = ((e1[0] + e2[0]) / 2, (e1[1] + e2[1]) / 2)
        tp = (mid[0] + v[0] * (gap + h / 2), mid[1] + v[1] * (gap + h / 2), 0.0)
        val = meas * m["dimlfac"]
        disp = ("%." + str(m["dimdec"]) + "f") % val
        if override and "<>" not in override:
            disp = override
        elif override:
            disp = override.replace("<>", disp)
        self.anon += 1
        bn = "*D%d" % self.anon
        b = self._mkblock(bn, flags=1)
        self.add("LINE", [(8, "0"), (10, e1), (11, e2)], b)
        self.add("LINE", [(8, "0"), (10, p1), (11, e1)], b)
        self.add("LINE", [(8, "0"), (10, p2), (11, e2)], b)
        w = 0.75 * h * max(1, len(disp))
        self.add("MTEXT", [(8, "0"), (10, tp), (40, h), (41, 0.0), (71, 5), (72, 1), (1, disp),
                           (7, m["txsty"]), (11, (u[0], u[1], 0.0)), (42, w), (43, h)], b)
        d = [(8, layer), (2, bn), (10, e2), (11, tp), (12, (0.0, 0.0, 0.0)), (70, 33 if aligned else 32),
             (1, override), (71, 5), (42, float(meas)), (3, m.get("name", style)), (13, p1), (14, p2),
             (50, float(rot))]
        d[9] = (3, self.tables["DIMSTYLE"][style.upper()].get(2))
        return self.add("DIMENSION", d, space)

    def set_xdata(self, ent, app, items):
        self.appid(app)
        ent.xdata[app] = list(items)

    def dim_override(self, dim, codes):
        items = [(1000, "DSTYLE"), (1002, "{")]
        for k, val in codes.items():
            items.append((1070, k))
            items.append((1040 if isinstance(val, float) else 1070, val))
        items.append((1002, "}"))
        self.set_xdata(dim, "ACAD", items)

    # ------------------------------------------------------------ hinh hoc
    def bbox(self, e, depth=0):
        """(xmin ymin zmin) (xmax ymax zmax) hoac None"""
        t = e.type
        pts = []
        if t == "LINE":
            pts = [e.get(10), e.get(11)]
        elif t == "LWPOLYLINE":
            z = e.get(38, 0.0)
            pts = [(p[0], p[1], z) for p in e.gets(10)]
        elif t == "CIRCLE":
            c, r = e.get(10), e.get(40, 0.0)
            pts = [(c[0] - r, c[1] - r, c[2]), (c[0] + r, c[1] + r, c[2])]
        elif t == "ARC":
            pts = arc_points(e.get(10), e.get(40, 0.0), e.get(50, 0.0), e.get(51, 2 * math.pi))
        elif t == "ELLIPSE":
            c, m = e.get(10), e.get(11, (0.0, 0.0, 0.0))
            ratio = e.get(40, 1.0)
            t0, t1 = e.get(41, 0.0), e.get(42, 2 * math.pi)
            nz = (e.get(210) or (0.0, 0.0, 1.0))[2]
            mn = (-m[1] * ratio, m[0] * ratio) if nz >= 0 else (m[1] * ratio, -m[0] * ratio)
            while t1 <= t0:
                t1 += 2 * math.pi
            n = 64
            pts = [(c[0] + math.cos(t) * m[0] + math.sin(t) * mn[0], c[1] + math.cos(t) * m[1] + math.sin(t) * mn[1],
                    c[2]) for t in [t0 + (t1 - t0) * k / n for k in range(n + 1)]]
        elif t == "HATCH":
            pts = hatch_points(e)
        elif t in ("IMAGE", "WIPEOUT"):
            o, u, v, sz = e.get(10), e.get(11), e.get(12), e.get(13)
            if o and u and v and sz:
                bnd = [q for c_, q in e.data if c_ == 14]
                if len(bnd) == 2:
                    (x1, y1), (x2, y2) = bnd[0][:2], bnd[1][:2]
                    bnd = [(x1, y1), (x2, y1), (x2, y2), (x1, y2)]
                if not bnd:
                    bnd = [(-0.5, -0.5), (sz[0] - 0.5, -0.5), (sz[0] - 0.5, sz[1] - 0.5), (-0.5, sz[1] - 0.5)]
                ox = o[0] + u[0] * 0.5 - v[0] * 0.5
                oy = o[1] + u[1] * 0.5 - v[1] * 0.5
                hh = sz[1]
                pts = [(ox + u[0] * q[0] + v[0] * (hh - q[1]), oy + u[1] * q[0] + v[1] * (hh - q[1]), 0.0)
                       for q in bnd]
        elif t == "POLYLINE":
            pts = [se.get(10) for se in e.subs if se.type == "VERTEX" and se.get(10)]
        elif t in ("SPLINE", "LEADER", "SOLID", "3DFACE", "TRACE", "MLINE", "POINT", "XLINE", "RAY",
                   "MULTILEADER"):
            pts = [v for c_, v in e.data if c_ in (10, 11, 12, 13) and isinstance(v, tuple)]
            if t in ("XLINE", "RAY"):
                pts = pts[:1]
        elif t in ("TEXT", "ATTRIB", "ATTDEF"):
            pts = text_corners(e)
        elif t == "MTEXT":
            pts = mtext_corners(e)
        elif t == "VIEWPORT":
            c, w, h = e.get(10), e.get(40, 0.0), e.get(41, 0.0)
            pts = [(c[0] - w / 2, c[1] - h / 2, 0.0), (c[0] + w / 2, c[1] + h / 2, 0.0)]
        elif t in ("INSERT", "DIMENSION"):
            b = self.blocks.get((e.get(2) or "").upper())
            if b and depth < 10:
                if t == "INSERT":
                    ins = e.get(10)
                    sx, sy, rot = e.get(41, 1.0), e.get(42, 1.0), e.get(50, 0.0)
                    base = b.base
                else:
                    ins, sx, sy, rot, base = (0.0, 0.0, 0.0), 1.0, 1.0, 0.0, (0.0, 0.0, 0.0)
                c, s = math.cos(rot), math.sin(rot)
                for be in b.ents:
                    if be.type == "ATTDEF" or be.deleted:
                        continue
                    bb = self.bbox(be, depth + 1)
                    if not bb:
                        continue
                    for x in (bb[0][0], bb[1][0]):
                        for y in (bb[0][1], bb[1][1]):
                            lx, ly = (x - base[0]) * sx, (y - base[1]) * sy
                            pts.append((ins[0] + lx * c - ly * s, ins[1] + lx * s + ly * c, ins[2]))
                for se in e.subs:
                    if se.type == "ATTRIB" and not se.deleted:
                        pts += text_corners(se)
            if not pts:
                for code in (10, 11, 13, 14):
                    if e.get(code):
                        pts.append(e.get(code))
        else:
            if e.get(10):
                pts = [e.get(10)]
        pts = [P(p) for p in pts if p]
        if not pts:
            return None
        if t in OCS_TYPES:
            nz = e.get(210)
            if nz and nz[2] < 0 and abs(nz[0]) < 1e-9 and abs(nz[1]) < 1e-9:
                pts = [(-p[0], p[1], -p[2]) for p in pts]      # OCS (0 0 -1) -> WCS: x -> -x
        return (tuple(min(p[i] for p in pts) for i in range(3)),
                tuple(max(p[i] for p in pts) for i in range(3)))


def hatch_points(e):
    """dinh / diem dac trung cua duong bien HATCH (dung truoc seed 98)"""
    pts = []
    data = e.data
    i, n = 0, len(data)
    while i < n and data[i][0] != 91:
        i += 1
    poly = False
    et = 0
    center = None
    while i < n:
        c, v = data[i]
        if c == 98:
            break
        if c == 92:
            poly = bool(v & 2)
            et = 0
        elif c == 72 and not poly:
            et = v
            center = None
        elif c == 10 and isinstance(v, tuple):
            if poly or et in (1, 4, 0):
                pts.append(v)
            else:
                center = v
        elif c == 11 and isinstance(v, tuple):
            if not poly and et == 1:
                pts.append(v)
            elif et == 3 and center is not None:
                r = math.hypot(v[0], v[1])
                pts += [(center[0] - r, center[1] - r), (center[0] + r, center[1] + r)]
            elif et == 4:
                pts.append(v)
        elif c == 40 and et == 2 and center is not None:
            pts += [(center[0] - v, center[1] - v), (center[0] + v, center[1] + v)]
            center = None
        i += 1
    z = (e.get(10) or (0.0, 0.0, 0.0))
    z = z[2] if len(z) > 2 else 0.0
    return [(p[0], p[1], z) for p in pts]


def arc_points(c, r, a1, a2):
    """goc radian (nhu entget)"""
    while a2 <= a1:
        a2 += 2 * math.pi
    angs = [a1, a2] + [k * math.pi / 2 for k in range(-4, 9) if a1 < k * math.pi / 2 < a2]
    z = c[2] if len(c) > 2 else 0.0
    return [(c[0] + r * math.cos(a), c[1] + r * math.sin(a), z) for a in angs]


def text_size(s, h, wf=1.0):
    return 0.75 * h * wf * max(1, len(s)), h


def text_corners(e):
    p = e.get(10)
    if not p:
        return []
    w, h = text_size(e.get(1, ""), e.get(40, 2.5), e.get(41, 1.0))
    r = e.get(50, 0.0)
    c, s = math.cos(r), math.sin(r)
    return [(p[0] + x * c - y * s, p[1] + x * s + y * c, p[2]) for x, y in ((0, 0), (w, 0), (w, h), (0, h))]


def mtext_corners(e):
    p = e.get(10)
    if not p:
        return []
    h = e.get(43) or e.get(40, 2.5)
    w = e.get(42) or e.get(41) or 0.75 * e.get(40, 2.5) * len(e.get(1, ""))
    a = e.get(71, 1)
    col, row = (a - 1) % 3, (a - 1) // 3
    x0 = -col * w / 2
    ytop = row * h / 2
    d = e.get(11)
    ang = math.atan2(d[1], d[0]) if d else e.get(50, 0.0)
    c, s = math.cos(ang), math.sin(ang)
    return [(p[0] + x * c - y * s, p[1] + x * s + y * c, p[2])
            for x, y in ((x0, ytop - h), (x0 + w, ytop - h), (x0 + w, ytop), (x0, ytop))]
