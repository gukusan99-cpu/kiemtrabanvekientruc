"""Nap file DXF (ASCII, R2000+) vao CSDL Drawing cua lispsim de chay bo KT tren ban ve THAT.

    from lispsim.dxfload import load_dxf
    dwg = load_dxf("Template.dxf")               # -> Drawing (dung voi Session nhu ban ve dung tay)

Cach lam: doc TAG THO cua DXF (ma nhom, gia tri) theo dung thu tu trong file -> moi doi tuong giu
nguyen ma nhom goc (100 subclass, 102 {ACAD_REACTORS}, 330 owner, 5 handle, 340/350/360 tham chieu
-> ename, XDATA 1001 -> -3). entget tra ve gan giong AutoCAD:
  (-1 . ename) (0 . type) (330 . owner) (5 . handle) (100 . "AcDbEntity") (67 . 0) (410 . layout) (8 . ..)
  (neu co nhom 102 thi 5 dung truoc 102 nhu AutoCAD), them cac gia tri mac dinh ma DXF bo qua nhung
  entget luon tra (vd TEXT 50/41/51/7/71/72/11/73, INSERT 41/42/43/50, 210 ...).
Bang: VPORT LTYPE LAYER STYLE VIEW UCS APPID DIMSTYLE BLOCK_RECORD (tblsearch/tblnext/tblobjname).
Block: BLOCK ... ENDBLK (entnext trong block), INSERT + ATTRIB + SEQEND, POLYLINE + VERTEX + SEQEND.
Doi tuong: DICTIONARY (namedobjdict, ACAD_LAYOUT, ACAD_IMAGE_DICT ...), LAYOUT, XRECORD ...
Doi tuong cua layout khong active (block *Paper_SpaceN) duoc dua vao CSDL chinh voi 410 = ten layout.

CHUOI: DXF R2007+ la UTF-8. AutoLISP ban ANSI (AutoCAD <= 2020, VinaCAD) thay chuoi theo codepage
cua ban ve ($DWGCODEPAGE, vd ANSI_1252): ky tu thuoc codepage giu nguyen (luu trong lispsim duoi dang
byte codepage giai ma latin-1, de (ascii) / file ghi ra dung byte), ky tu NGOAI codepage -> "\\U+XXXX"
(vd "TRU+1EE4C": "TRỤC" -> "TR\\U+1EE4C"). Dat unicode=True de giu nguyen Unicode (AutoCAD 2021+).

GOC: DXF ghi do, entget tra radian -> moi ma 50..58 (ngoai XDATA) doi sang radian.

GIOI HAN da biet:
- Khong doc DXF nhi phan; khong doc CLASSES/THUMBNAIL. ACIS (3DSOLID/REGION) giu tag tho.
- Gia tri mac dinh entget chi bo sung cho LINE/CIRCLE/ARC/TEXT/ATTRIB/ATTDEF/INSERT/MTEXT/LWPOLYLINE/
  DIMENSION/POINT/ELLIPSE/HATCH; dinh LWPOLYLINE KHONG bo sung 40/41/42/91 cho tung dinh neu DXF bo qua.
- Thu tu ssget "_X" / entnext = thu tu trong file DXF (model truoc, paper space sau) - AutoCAD dung thu
  tu CSDL, thuong trung voi thu tu DXF nhung khong dam bao.
- Hop bao (vla-getboundingbox) cua HATCH/SPLINE/ELLIPSE/LEADER/WIPEOUT/IMAGE la xap xi tu diem dieu khien;
  chu (TEXT/MTEXT/textbox) van uoc luong 0.75*h*so ky tu (khong co font that).
- tblsearch "DIMSTYLE"/"STYLE"/... tra danh sach tag cua ban ghi (bo 5/105/330/100/102/360) - AutoCAD
  tra them vai ma suy ra (vd ten block mui ten DIMBLK dang chuoi o ma 5/6/7 kieu R12); khong mo phong.
- Header: chi nap cac bien $ thuong dung vao getvar (EXTMIN/EXTMAX/DIMSCALE/LTSCALE/INSUNITS/...).
"""
import math
import os
from collections import OrderedDict

from .drawing import Drawing, Ent, Block

# ---------------------------------------------------------------- kieu gia tri theo ma nhom
POINT_X = set(range(10, 19)) | {110, 111, 112, 210, 1010, 1011, 1012, 1013}
HANDLE_STR = {5, 105, 1005} | set(range(320, 330))
HANDLE_REF = set(range(330, 370)) | set(range(390, 400)) | {480, 481}


def vtype(c):
    if c < 0:
        return "s"
    if c <= 9:
        return "s"
    if c <= 59:
        return "f"
    if c <= 99:
        return "i"
    if c in (100, 101, 102):
        return "s"
    if c in HANDLE_STR:
        return "h"
    if 110 <= c <= 149:
        return "f"
    if 160 <= c <= 169:
        return "i"
    if 170 <= c <= 179:
        return "i"
    if 210 <= c <= 239:
        return "f"
    if 270 <= c <= 299:
        return "i"
    if 300 <= c <= 319:
        return "s"
    if c in HANDLE_REF:
        return "r"
    if 370 <= c <= 389:
        return "i"
    if 400 <= c <= 409:
        return "i"
    if 410 <= c <= 419:
        return "s"
    if 420 <= c <= 429:
        return "i"
    if 430 <= c <= 439:
        return "s"
    if 440 <= c <= 459:
        return "i"
    if 460 <= c <= 469:
        return "f"
    if 470 <= c <= 479:
        return "s"
    if c == 999:
        return "s"
    if 1000 <= c <= 1009:
        return "s"
    if 1010 <= c <= 1059:
        return "f"
    if 1060 <= c <= 1071:
        return "i"
    return "s"


_VT = {}


def _vt(c):
    t = _VT.get(c)
    if t is None:
        t = _VT[c] = vtype(c)
    return t


class Ref:
    """tham chieu handle chua giai (thay bang Ent sau khi nap het)"""
    __slots__ = ("h",)

    def __init__(self, h):
        self.h = h


def make_ansi(codepage="cp1252", unicode=False):
    cache = {}

    def conv(s):
        if unicode or s.isascii():
            return s
        r = cache.get(s)
        if r is not None:
            return r
        out = []
        for ch in s:
            if ord(ch) < 128:
                out.append(ch)
                continue
            try:
                out.append(ch.encode(codepage).decode("latin-1"))
            except UnicodeEncodeError:
                o = ord(ch)
                out.append("\\U+%04X" % o if o <= 0xFFFF else "\\U+%04X\\U+%04X" % (
                    0xD800 + ((o - 0x10000) >> 10), 0xDC00 + ((o - 0x10000) & 0x3FF)))
        r = cache[s] = "".join(out)
        return r
    return conv


def _codepage(name):
    n = (name or "ANSI_1252").upper()
    if n.startswith("ANSI_"):
        return "cp" + n[5:]
    return "cp1252"


def _num(s, t):
    s = s.strip()
    if t == "f":
        try:
            return float(s)
        except ValueError:
            return 0.0
    try:
        return int(s)
    except ValueError:
        try:
            return int(float(s))
        except ValueError:
            return 0


# ---------------------------------------------------------------- doc tag
def read_raw(path):
    with open(path, "rb") as f:
        b = f.read()
    if b[:22] == b"AutoCAD Binary DXF\r\n\x1a\x00":
        raise ValueError("DXF nhi phan chua ho tro")
    try:
        text = b.decode("utf-8")
        utf8 = True
    except UnicodeDecodeError:
        text = None
        utf8 = False
    if text is None:
        # DXF < R2007: dung codepage trong header
        head = b[:20000].decode("latin-1")
        cp = "cp1252"
        i = head.find("$DWGCODEPAGE")
        if i >= 0:
            cp = _codepage(head[i:].split("\n")[2].strip())
        text = b.decode(cp, errors="replace")
    lines = text.split("\n")
    n = len(lines) - 1
    out = []
    i = 0
    while i < n:
        try:
            c = int(lines[i])
        except ValueError:
            i += 1
            continue
        v = lines[i + 1]
        if v.endswith("\r"):
            v = v[:-1]
        out.append((c, v))
        i += 2
    return out, utf8


def split_ents(tags):
    """-> list (section_name, [entity_tags...]) ; entity_tags bat dau bang (0, TYPE)"""
    secs = []
    i, n = 0, len(tags)
    cur = None
    while i < n:
        c, v = tags[i]
        if c == 0 and v == "SECTION":
            name = tags[i + 1][1] if i + 1 < n else ""
            cur = (name, [])
            secs.append(cur)
            i += 2
            if name == "HEADER":
                start = i
                while i < n and not (tags[i][0] == 0 and tags[i][1] == "ENDSEC"):
                    i += 1
                cur[1].append(tags[start:i])
            continue
        if c == 0 and v in ("ENDSEC", "EOF"):
            cur = None
            i += 1
            continue
        if c == 0 and cur is not None:
            j = i + 1
            while j < n and tags[j][0] != 0:
                j += 1
            cur[1].append(tags[i:j])
            i = j
            continue
        i += 1
    return secs


# ---------------------------------------------------------------- chuyen tag -> (ma, gia tri)
def conv_tags(raw, conv):
    """raw = [(code, str)] (khong gom (0 TYPE)) -> (data, xdata OrderedDict)"""
    data = []
    xdata = OrderedDict()
    tgt = data
    i, n = 0, len(raw)
    while i < n:
        c, s = raw[i]
        if c == 1001:
            tgt = xdata.setdefault(conv(s), [])
            i += 1
            continue
        if c in POINT_X:
            x = _num(s, "f")
            pt = [x]
            if i + 1 < n and raw[i + 1][0] == c + 10:
                pt.append(_num(raw[i + 1][1], "f"))
                i += 1
                if i + 1 < n and raw[i + 1][0] == c + 20:
                    pt.append(_num(raw[i + 1][1], "f"))
                    i += 1
            tgt.append((c, tuple(pt)))
            i += 1
            continue
        t = _vt(c)
        if t == "s":
            v = conv(s)
        elif t == "h":
            v = s.strip()
        elif t == "r":
            h = s.strip().upper()
            v = Ref(h) if h and h != "0" else None
        else:
            v = _num(s, t)
            if 50 <= c <= 58 and tgt is data:
                v = math.radians(v)      # DXF: do ; entget: radian
        if v is not None:
            tgt.append((c, v))
        i += 1
    return data, xdata


# mac dinh entget luon co nhung DXF co the bo qua
Z3 = (0.0, 0.0, 0.0)
EXT = (0.0, 0.0, 1.0)
TEXT_DEF = [(39, None), (50, 0.0), (41, 1.0), (51, 0.0), (7, "Standard"), (71, 0), (72, 0), (11, Z3),
            (210, EXT), (73, 0)]
DEFAULTS = {
    "LINE": [(210, EXT)],
    "POINT": [(210, EXT), (50, 0.0)],
    "CIRCLE": [(210, EXT)],
    "ARC": [(210, EXT)],
    "ELLIPSE": [(210, EXT)],
    "TEXT": TEXT_DEF,
    "ATTRIB": TEXT_DEF + [(70, 0), (74, 0)],
    "ATTDEF": TEXT_DEF + [(70, 0), (74, 0)],
    "INSERT": [(41, 1.0), (42, 1.0), (43, 1.0), (50, 0.0), (70, 0), (71, 0), (44, 0.0), (45, 0.0),
               (210, EXT)],
    "MTEXT": [(41, 0.0), (46, 0.0), (71, 1), (72, 1), (7, "Standard"), (210, EXT), (11, (1.0, 0.0, 0.0)),
              (50, 0.0), (73, 1), (44, 1.0)],
    "LWPOLYLINE": [(70, 0), (43, 0.0), (38, 0.0), (39, 0.0), (210, EXT)],
    "DIMENSION": [(1, ""), (51, 0.0), (210, EXT), (71, 5), (72, 1), (41, 1.0)],
    "HATCH": [(210, EXT)],
}
GRAPHIC_SKIP = {"BLOCK", "ENDBLK"}


def finish_data(etype, data, layout, kind):
    """sap lai header giong entget AutoCAD + them mac dinh"""
    hdr, rest = [], list(data)
    # 5 / 102 groups / 330 owner o dau
    h5 = [x for x in rest[:1] if x[0] in (5, 105)]
    if h5:
        rest = rest[1:]
    groups = []
    while rest and rest[0][0] == 102:
        k = 1
        while k < len(rest) and rest[k][0] != 102:
            k += 1
        groups += rest[:k + 1]
        rest = rest[k + 1:]
    own = []
    if rest and rest[0][0] == 330:
        own = [rest[0]]
        rest = rest[1:]
    if groups:
        hdr = h5 + groups + own
    else:
        hdr = own + h5
    if kind in ("main", "sub", "block"):
        # (100 . "AcDbEntity") (67 . 0) (410 . "Model") (8 ...)
        out = []
        k = 0
        if rest and rest[0] == (100, "AcDbEntity"):
            out.append(rest[0])
            k = 1
        body = rest[k:]
        if kind in ("main", "sub"):
            if not any(c == 67 for c, _ in body[:3]):
                out.append((67, 0 if layout == "Model" else 1))
            else:
                out.append(next(x for x in body[:3] if x[0] == 67))
                body = [x for x in body if not (x[0] == 67)]
            out.append((410, layout))
        if not any(c == 8 for c, _ in body):
            out.append((8, "0"))
        rest = out + body
        have = {c for c, _ in rest}
        for c, v in DEFAULTS.get(etype, ()):
            if c not in have and v is not None:
                rest.append((c, v))
    return hdr + rest


def _new_ent(dwg, etype, handle, data, kind, owner):
    e = Ent.__new__(Ent)
    e.dwg = dwg
    e.handle = handle
    e.type = etype
    e.data = data
    e.kind = kind
    e.owner = owner
    e.xdata = OrderedDict()
    e.deleted = False
    e.made = False
    e.subs = []
    e.parent = None
    e.tag = None
    e.ename = None
    e.raw = True
    if handle:
        dwg.ents[handle] = e
    return e


HEADER_VARS = {"$EXTMIN": "EXTMIN", "$EXTMAX": "EXTMAX", "$DIMSCALE": "DIMSCALE", "$LTSCALE": "LTSCALE",
               "$INSUNITS": "INSUNITS", "$MEASUREMENT": "MEASUREMENT", "$TEXTSIZE": "TEXTSIZE",
               "$TEXTSTYLE": "TEXTSTYLE", "$DIMSTYLE": "DIMSTYLE", "$CLAYER": "CLAYER", "$LUNITS": "LUNITS",
               "$LUPREC": "LUPREC", "$DIMZIN": "DIMZIN", "$DIMASSOC": "DIMASSOC", "$TILEMODE": "TILEMODE",
               "$PSTYLEMODE": "PSTYLEMODE", "$AUNITS": "AUNITS", "$AUPREC": "AUPREC", "$UNITMODE": "UNITMODE",
               "$DWGCODEPAGE": "DWGCODEPAGE", "$ACADVER": "_DXFVER", "$PDMODE": "PDMODE",
               "$LIMMIN": "LIMMIN", "$LIMMAX": "LIMMAX", "$CELTYPE": "CELTYPE", "$CECOLOR": "CECOLOR",
               "$DIMTXT": "DIMTXT", "$DIMASZ": "DIMASZ", "$DIMLFAC": "DIMLFAC", "$DIMDEC": "DIMDEC"}


def parse_header(tags, conv):
    hv = {}
    i, n = 0, len(tags)
    while i < n:
        c, v = tags[i]
        if c == 9:
            name = v.strip()
            j = i + 1
            vals = []
            while j < n and tags[j][0] != 9:
                vals.append(tags[j])
                j += 1
            if name in HEADER_VARS and vals:
                d, _ = conv_tags(vals, conv)
                if d:
                    val = d[0][1]
                    if isinstance(val, tuple) and len(val) == 2:
                        val = (val[0], val[1], 0.0)
                    hv[HEADER_VARS[name]] = val
            i = j
            continue
        i += 1
    return hv


# ---------------------------------------------------------------- nap
def load_dxf(path, unicode=False, name=None):
    tags, utf8 = read_raw(path)
    secs = split_ents(tags)
    del tags
    # codepage tu header
    cp = "cp1252"
    for sname, items in secs:
        if sname == "HEADER" and items:
            for k, (c, v) in enumerate(items[0]):
                if c == 9 and v.strip() == "$DWGCODEPAGE" and k + 1 < len(items[0]):
                    cp = _codepage(items[0][k + 1][1].strip())
    conv = make_ansi(cp, unicode)

    dwg = Drawing.__new__(Drawing)
    dwg.name = name or (os.path.splitext(os.path.basename(path))[0] + ".dwg")
    dwg._h = 0x100
    dwg.ents = {}
    dwg.main = []
    dwg.tables = OrderedDict((t, OrderedDict()) for t in
                             ["VPORT", "LTYPE", "LAYER", "STYLE", "VIEW", "UCS", "APPID", "DIMSTYLE",
                              "BLOCK_RECORD"])
    dwg.blocks = OrderedDict()
    dwg.layouts = OrderedDict()
    dwg.violations = []
    dwg.selected = None
    dwg.vp_id = 1
    dwg.dimstyle_meta = {}
    dwg.style_ents = {}
    dwg.anon = 0
    dwg.header = {}
    dwg.source = path
    dwg.table_heads = {}

    entities = []      # (Ent) tu ENTITIES
    block_list = []
    objects = []

    def mk(raw, kind, owner):
        etype = raw[0][1].strip()
        data, xd = conv_tags(raw[1:], conv)
        h = None
        for c, v in data[:2]:
            if c in (5, 105):
                h = v.upper()
                break
        e = _new_ent(dwg, etype, h, data, kind, owner)
        e.xdata = xd
        return e

    for sname, items in secs:
        if sname == "HEADER":
            dwg.header = parse_header(items[0], conv) if items else {}
        elif sname == "TABLES":
            tbl = None
            for raw in items:
                t = raw[0][1]
                if t == "TABLE":
                    tbl = next((v for c, v in raw if c == 2), "").strip()
                    e = mk(raw, "object", None)
                    e.type = "TABLE"
                    dwg.table_heads[tbl] = e
                    continue
                if t == "ENDTAB":
                    tbl = None
                    continue
                e = mk(raw, "table", tbl)
                nm = e.get(2, "")
                dwg.tables.setdefault(tbl, OrderedDict())[nm.upper()] = e
        elif sname == "BLOCKS":
            cur = None
            last = None
            for raw in items:
                t = raw[0][1]
                if t == "BLOCK":
                    e = mk(raw, "blockbegin", None)
                    nm = e.get(2, "")
                    e.owner = nm
                    cur = Block(nm, e, None, None, e.get(70, 0), _p3(e.get(10, Z3)), e.get(1) or None)
                    cur.system = nm.upper() == "*MODEL_SPACE" or nm.upper().startswith("*PAPER_SPACE")
                    block_list.append(cur)
                    last = None
                    continue
                if t == "ENDBLK":
                    if cur is not None:
                        cur.end = mk(raw, "blockend", cur.name)
                    cur = None
                    continue
                if cur is None:
                    continue
                if t in ("ATTRIB", "VERTEX", "SEQEND") and last is not None and (last.subs or t != "SEQEND" or True) \
                        and last.type in ("INSERT", "POLYLINE") and not getattr(last, "_closed", False):
                    se = mk(raw, "block", cur.name)
                    se.parent = last
                    last.subs.append(se)
                    if t == "SEQEND":
                        last._closed = True
                    continue
                e = mk(raw, "block", cur.name)
                cur.ents.append(e)
                last = e if (e.type == "INSERT" and e.get(66) == 1) or e.type == "POLYLINE" else None
        elif sname == "ENTITIES":
            last = None
            for raw in items:
                t = raw[0][1]
                if t in ("ATTRIB", "VERTEX", "SEQEND") and last is not None and not getattr(last, "_closed", False):
                    se = mk(raw, "sub", None)
                    se.parent = last
                    last.subs.append(se)
                    if t == "SEQEND":
                        last._closed = True
                    continue
                e = mk(raw, "main", None)
                entities.append(e)
                last = e if (e.type == "INSERT" and e.get(66) == 1) or e.type == "POLYLINE" else None
        elif sname == "OBJECTS":
            for raw in items:
                objects.append(mk(raw, "object", None))

    # ---- giai tham chieu handle
    ents = dwg.ents

    def resolve(lst):
        out = []
        for c, v in lst:
            if isinstance(v, Ref):
                v = ents.get(v.h)
                if v is None:
                    continue
            out.append((c, v))
        return out
    for e in list(ents.values()):
        e.data = resolve(e.data)
        for s in e.subs:
            pass
    # subs chua co trong ents neu khong co handle -> khong xay ra (DXF luon co 5)

    # ---- layout
    rec_layout = {}
    los = []
    for o in objects:
        if o.type == "LAYOUT":
            nm = None
            tab = 0
            sub = False
            br = None
            for c, v in o.data:
                if c == 100 and v == "AcDbLayout":
                    sub = True
                elif sub and c == 1 and nm is None:
                    nm = v
                elif sub and c == 71:
                    tab = v
                elif sub and c == 330 and isinstance(v, Ent):
                    br = v
            if nm is None:
                nm = o.get(1, "")
            o._tab = tab
            o.layout_name = nm
            los.append((tab, nm, o))
            if br is not None:
                rec_layout[br.handle] = nm
    los.sort(key=lambda x: (x[1] != "Model", x[0]))
    for tab, nm, o in los:
        dwg.layouts[nm] = o
    if "Model" not in dwg.layouts:
        lo = _new_ent(dwg, "LAYOUT", None, [(1, "Model"), (70, 1), (71, 0)], "object", None)
        dwg.layouts["Model"] = lo
        dwg.layouts.move_to_end("Model", last=False)

    # ---- block
    for b in block_list:
        b.record = dwg.tables["BLOCK_RECORD"].get(b.name.upper())
        if b.end is None:
            b.end = _new_ent(dwg, "ENDBLK", None, [(8, "0")], "blockend", b.name)
        dwg.blocks[b.name.upper()] = b

    def owner_layout(e):
        own = e.get(330)
        if isinstance(own, Ent) and own.handle in rec_layout:
            return rec_layout[own.handle]
        return "Model" if e.get(67, 0) == 0 else next((n for n in dwg.layouts if n != "Model"), "Model")

    def put_main(e, layout):
        e.kind = "main"
        e.owner = layout
        e.data = finish_data(e.type, e.data, layout, "main")
        e._mi = len(dwg.main)
        dwg.main.append(e)
        for s in e.subs:
            s.kind = "sub"
            s.owner = layout
            s.data = finish_data(s.type, s.data, layout, "sub")
            s._mi = len(dwg.main)
            dwg.main.append(s)

    for e in entities:
        put_main(e, owner_layout(e))
    # doi tuong cua layout khong active nam trong block *Paper_SpaceN
    for b in block_list:
        if b.system and b.ents:
            lay = rec_layout.get(b.record.handle if b.record else "", None)
            if lay is None:
                lay = "Model" if b.name.upper() == "*MODEL_SPACE" else None
            if lay is None:
                continue
            for e in b.ents:
                put_main(e, lay)
            b.ents = []
    for b in block_list:
        for e in b.ents:
            e.data = finish_data(e.type, e.data, None, "block")
            for s in e.subs:
                s.data = finish_data(s.type, s.data, None, "block")
    for e in list(ents.values()):
        if e.kind in ("table", "object", "blockbegin", "blockend"):
            e.data = finish_data(e.type, e.data, None, e.kind)

    # ---- dynamic block: ten goc qua XDATA AcDbBlockRepBTag cua BLOCK_RECORD
    for b in block_list:
        rec = b.record
        if rec is None:
            continue
        x = rec.xdata.get("AcDbBlockRepBTag")
        if x:
            src = next((v for c, v in x if c == 1005), None)
            se = ents.get((src or "").upper())
            if se is not None and se.get(2):
                b.dyn_source = se.get(2)

    # ---- dictionary goc
    dwg.rootdict = objects[0] if objects else _new_ent(dwg, "DICTIONARY", None, [], "object", None)
    lod = None
    items = dwg.rootdict.data
    for k, (c, v) in enumerate(items):
        if c == 3 and v.upper() == "ACAD_LAYOUT" and k + 1 < len(items):
            lod = items[k + 1][1]
    dwg.layoutdict = lod if isinstance(lod, Ent) else _new_ent(dwg, "DICTIONARY", None, [], "object", None)

    # ---- handle moi cho entmake khong trung
    mx = 0
    for h in ents:
        try:
            mx = max(mx, int(h, 16))
        except ValueError:
            pass
    dwg._h = max(mx + 0x10, 0x100)
    for app in dwg.tables["APPID"]:
        pass
    return dwg


def _p3(p):
    p = tuple(float(x) for x in p)
    return p if len(p) >= 3 else (p[0], p[1], 0.0)


def stats(dwg):
    from collections import Counter
    c = Counter((e.owner, e.type) for e in dwg.main if e.kind == "main")
    return c
