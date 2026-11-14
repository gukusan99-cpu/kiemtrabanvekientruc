"""Ban ve mau gia lap cho kiem thu runtime.

make_mau()      : ban ve MAU cong ty (chuan): KT-01 MAT BANG TANG 1 (1/100), KT-02 MAT CAT 1-1
                  (1/50), layout KT-03 (khung + viewport 1/100). Truc 1-2-3 / A-B-C, cao do, dim dung chuan.
make_nhanvien() : ban ve nhan vien co cai loi; tra ve (dwg, seeded) voi seeded = {ma_loi: [Ent...]}
"""
import math

from .drawing import Drawing

AX_NUM = [("1", 5000.0), ("2", 8600.0), ("3", 12800.0)]      # truc so (X) tren mat bang
AX_LET = [("A", 5000.0), ("B", 9500.0), ("C", 12800.0)]      # truc chu (Y) tren mat bang
SEC_X0 = 53000.0                                              # mat cat: truc A tai X nay
LEVELS = [(0.0, "%%p0.000"), (3.6, "+3.600"), (7.2, "+7.200")]


def _std_tables(d):
    for nm, col, lt, lw in [("KT-TUONG", 7, "Continuous", 50), ("KT-CUA", 4, "Continuous", 18),
                            ("KT-DIM", 1, "Continuous", 13), ("KT-TEXT", 2, "Continuous", 18),
                            ("KT-TRUC", 1, "CENTER", 13), ("KT-CAODO", 3, "Continuous", 13),
                            ("KT-KYHIEU", 3, "Continuous", 13), ("KT-KHUNG", 7, "Continuous", 35),
                            ("KT-VIEWPORT", 8, "Continuous", -3)]:
        d.layer(nm, col, lt, lw, plot=0 if nm == "KT-VIEWPORT" else 1)
    d.layer("Defpoints", 7, "Continuous", -3, plot=0)
    d.style("KT-TEXT", "vntime.shx", "hztxt.shx", 0.0, 0.8)
    d.style("KT-DIM", "romans.shx", "", 0.0, 0.8)
    d.dimstyle("1-100", dimscale=100, dimtxt=2, dimasz=1.5, txsty="KT-DIM", dimdec=0)
    d.dimstyle("1-50", dimscale=50, dimtxt=2, dimasz=1.5, txsty="KT-DIM", dimdec=0)


def _blocks(d):
    k = d.block("KHUNG_A3")
    d.rect((0, 0), (420, 297), "KT-KHUNG", k)
    d.rect((25, 5), (415, 292), "KT-KHUNG", k)
    d.rect((235, 5), (415, 45), "KT-KHUNG", k)
    for tag, p, h in [("CONGTRINH", (240, 37), 3.5), ("TENBANVE", (240, 25), 5.0),
                      ("SOHIEU", (380, 25), 5.0), ("TYLE", (380, 12), 3.5),
                      ("NGAY", (240, 12), 2.5), ("THIETKE", (300, 12), 2.5)]:
        d.attdef(k, tag, p, h, style="KT-TEXT", layer="KT-KHUNG")
    t = d.block("KH_TRUC")
    d.circle((0, 0), 4.0, "KT-TRUC", t)
    d.attdef(t, "TENTRUC", (-1.5, -2.0), 4.0, style="KT-TEXT", layer="KT-TRUC")
    c = d.block("KH_CAODO")
    d.line((0, 0), (-1.5, 2.5), "KT-CAODO", c)
    d.line((-1.5, 2.5), (1.5, 2.5), "KT-CAODO", c)
    d.line((1.5, 2.5), (0, 0), "KT-CAODO", c)
    d.line((0, 2.5), (18, 2.5), "KT-CAODO", c)
    d.attdef(c, "CAODO", (2, 3.2), 2.5, style="KT-TEXT", layer="KT-CAODO")
    m = d.block("KH_MATCAT")
    d.circle((0, 0), 5.0, "KT-KYHIEU", m)
    d.line((-5, 0), (5, 0), "KT-KYHIEU", m)
    d.attdef(m, "KYHIEU", (-1.5, 1.0), 3.5, style="KT-TEXT", layer="KT-KYHIEU")
    d.attdef(m, "SOBV", (-3, -3.5), 2.0, style="KT-TEXT", layer="KT-KYHIEU")
    # block khong duoc chen (GOIY BLOCK-THUA binh thuong)
    w = d.block("CUA_DI_900")
    d.line((0, 0), (900, 0), "KT-CUA", w)


def _frame(d, p, scale, so, ten, tyle, ngay="01/11/2026", space="Model"):
    return d.insert("KHUNG_A3", p, scale, layer="KT-KHUNG", space=space,
                    attribs={"CONGTRINH": "NHA PHO 3 TANG", "TENBANVE": ten, "SOHIEU": so,
                             "TYLE": tyle, "NGAY": ngay, "THIETKE": "NGUYEN VAN A"})


def _plan(d, ox=0.0, bshift=0.0):
    """mat bang trong khung KT-01 (goc khung (0,0), 1/100)"""
    ents = {}
    x1, x3 = AX_NUM[0][1], AX_NUM[-1][1]
    y1, y3 = AX_LET[0][1], AX_LET[-1][1]
    for nm, x in AX_NUM:
        d.line((x, 3000), (x, 15500), "KT-TRUC")
        for y in (2500.0, 16000.0):
            d.insert("KH_TRUC", (x, y), 100, layer="KT-TRUC", attribs={"TENTRUC": nm})
    for nm, y in AX_LET:
        d.line((3000, y), (14800, y), "KT-TRUC")
        for x in (2500.0, 15300.0):
            d.insert("KH_TRUC", (x, y), 100, layer="KT-TRUC", attribs={"TENTRUC": nm})
    d.rect((x1 - 100, y1 - 100), (x3 + 100, y3 + 100), "KT-TUONG")
    d.rect((x1 + 100, y1 + 100), (x3 - 100, y3 - 100), "KT-TUONG")
    # dim chuoi + dim tong theo truc so (ngang) va truc chu (doc)
    for (a, xa), (b, xb) in zip(AX_NUM, AX_NUM[1:]):
        d.dim_linear((xa, 15500), (xb, 15500), (0, 18000), 0.0, "1-100", layer="KT-DIM")
    d.dim_linear((x1, 15500), (x3, 15500), (0, 19000), 0.0, "1-100", layer="KT-DIM")
    for (a, ya), (b, yb) in zip(AX_LET, AX_LET[1:]):
        d.dim_linear((3000, ya), (3000, yb), (1200, 0), math.pi / 2, "1-100", layer="KT-DIM")
    d.dim_linear((3000, y1), (3000, y3), (400, 0), math.pi / 2, "1-100", layer="KT-DIM")
    # chu
    d.text((6000, 1200), "MAT BANG TANG 1", 500, "KT-TEXT", style="KT-TEXT", width=0.8)
    d.text((6000, 600), "TL 1/100", 350, "KT-TEXT", style="KT-TEXT", width=0.8)
    d.text((6000, 7000), "PHONG KHACH", 250, "KT-TEXT", style="KT-TEXT", width=0.8)
    d.text((9800, 7000), "BEP", 250, "KT-TEXT", style="KT-TEXT", width=0.8)
    d.text((6000, 6400), "+0.000", 250, "KT-CAODO", style="KT-TEXT", width=0.8)
    # ky hieu mat cat 1-1 tro toi KT-02
    d.insert("KH_MATCAT", (7000, 3500), 100, layer="KT-KYHIEU", attribs={"KYHIEU": "1", "SOBV": "KT-02"})
    # danh muc ban ve (TEXT trong khung KT-01)
    d.text((28000, 22000), "DANH MUC BAN VE", 350, "KT-TEXT", style="KT-TEXT", width=0.8)
    for i, (so, ten) in enumerate([("KT-01", "MAT BANG TANG 1"), ("KT-02", "MAT CAT 1-1"),
                                   ("KT-03", "MAT BANG TANG 1 BAN IN")]):
        y = 21000 - 600 * i
        d.text((28000, y), so, 250, "KT-TEXT", style="KT-TEXT", width=0.8)
        d.text((30000, y), ten, 250, "KT-TEXT", style="KT-TEXT", width=0.8)
    return ents


def _section(d, bshift=0.0):
    """mat cat 1-1 trong khung KT-02 (goc (50000,0), 1/50): truc A-B-C theo X, cao do theo Y"""
    xs = [SEC_X0, SEC_X0 + 4500 + bshift, SEC_X0 + 7800]
    y0 = 3000.0
    out = {}
    for (nm, _), x in zip(AX_LET, xs):
        d.line((x, 2000), (x, y0 + 7800), "KT-TRUC")
        out[nm] = d.insert("KH_TRUC", (x, 1600), 50, layer="KT-TRUC", attribs={"TENTRUC": nm})
    for lv, s in LEVELS:
        y = y0 + lv * 1000
        d.line((SEC_X0 - 300, y), (SEC_X0 + 8100, y), "KT-TUONG")
        d.insert("KH_CAODO", (SEC_X0 + 9000, y), 50, layer="KT-CAODO", attribs={"CAODO": s})
    d.dim_linear((SEC_X0, y0), (SEC_X0 + 4500, y0), (0, 2400), 0.0, "1-50", layer="KT-DIM")
    d.dim_linear((SEC_X0 + 4500, y0), (SEC_X0 + 7800, y0), (0, 2400), 0.0, "1-50", layer="KT-DIM")
    d.dim_linear((SEC_X0 + 8100, y0), (SEC_X0 + 8100, y0 + 3600), (SEC_X0 + 8600, 0), math.pi / 2,
                 "1-50", layer="KT-DIM")
    d.dim_linear((SEC_X0 + 8100, y0 + 3600), (SEC_X0 + 8100, y0 + 7200), (SEC_X0 + 8600, 0), math.pi / 2,
                 "1-50", layer="KT-DIM")
    d.text((55000, 700), "MAT CAT 1-1", 250, "KT-TEXT", style="KT-TEXT", width=0.8)
    d.text((55000, 300), "TL 1/50", 175, "KT-TEXT", style="KT-TEXT", width=0.8)
    return out


def _elevation(d, ox):
    """mat dung truc 1-3 (goc (ox,0), 1/100): truc 1-2-3 theo X, cao do"""
    y0 = 3000.0
    for nm, x in AX_NUM:
        d.line((ox + x, 2500), (ox + x, y0 + 7600), "KT-TRUC")
        d.insert("KH_TRUC", (ox + x, 2000), 100, layer="KT-TRUC", attribs={"TENTRUC": nm})
    for lv, s in LEVELS:
        y = y0 + lv * 1000
        d.line((ox + 4700, y), (ox + 13100, y), "KT-TUONG")
        d.insert("KH_CAODO", (ox + 14000, y), 100, layer="KT-CAODO", attribs={"CAODO": s})
    d.text((ox + 6000, 1000), "MAT DUNG TRUC 1-3", 500, "KT-TEXT", style="KT-TEXT", width=0.8)


def _layout(d, sohieu="KT-03"):
    d.layout("KT-03")
    _frame(d, (0, 0), 1, sohieu, "MAT BANG TANG 1 BAN IN", "1/100", space="KT-03")
    d.viewport("KT-03", (150, 160), 250, 200, (8900, 9000), 100)


def make_mau():
    d = Drawing("MAU_CONGTY.dwg")
    _std_tables(d)
    _blocks(d)
    _frame(d, (0, 0), 100, "KT-01", "MAT BANG TANG 1", "1/100")
    _frame(d, (50000, 0), 50, "KT-02", "MAT CAT 1-1", "1/50")
    _plan(d)
    _section(d)
    _layout(d)
    return d


def make_nhanvien():
    """ban ve nhan vien: cung cau truc + 12 loi cai san. Tra ve (dwg, seeded)"""
    d = Drawing("NHANVIEN.dwg")
    _std_tables(d)
    _blocks(d)
    seeded = {}
    _frame(d, (0, 0), 100, "KT-01", "MAT BANG TANG 1", "1/100")
    _frame(d, (50000, 0), 50, "KT-02", "MAT CAT 1-1", "1/50")
    # (9) so hieu khung trung KT-02 + (10) attribute NGAY rong
    f3 = _frame(d, (80000, 0), 100, "KT-02", "MAT DUNG TRUC 1-3", "1/100", ngay="")
    seeded["KHUNG-TRUNGSO"] = [f3]
    seeded["KHUNG-THIEU"] = [f3]
    _plan(d)
    # (8) truc B mat cat lech 100
    sec = _section(d, bshift=100.0)
    seeded["KHOP-TRUC"] = [sec["B"]]
    _elevation(d, 80000.0)
    _layout(d)
    # (1) layer la
    d.layer("ABC-LA", 5)
    seeded["LAYER-LA"] = [d.line((20000, 5000), (24000, 5000), "ABC-LA")]
    # (2) doi tuong layer 0
    seeded["LAYER-0"] = [d.circle((21000, 9000), 300, "0")]
    # (3) dim style la
    d.dimstyle("ISO-25", dimscale=1, dimtxt=2.5, dimasz=2.5, txsty="Standard", dimdec=0)
    seeded["DIM-STYLE"] = [d.dim_linear((20000, 11000), (22000, 11000), (0, 11500), 0.0, "ISO-25",
                                        layer="KT-DIM")]
    # (4) dim TL 1/50 trong khung 1/100
    seeded["DIM-TYLE"] = [d.dim_linear((20000, 13000), (23000, 13000), (0, 13500), 0.0, "1-50",
                                       layer="KT-DIM")]
    # (5) dim ghi de 3300, do 3250
    seeded["DIM-GHIDE"] = [d.dim_linear((25000, 5000), (28250, 5000), (0, 4300), 0.0, "1-100",
                                        override="3300", layer="KT-DIM")]
    # (6) chu cao sai (4mm giay)
    seeded["TEXT-CAO"] = [d.text((20000, 15000), "GHI CHU SAI CO CHU", 400, "KT-TEXT", style="KT-TEXT",
                                 width=0.8)]
    # (7) 2 dim trung nhau
    d1 = d.dim_linear((25000, 8000), (27400, 8000), (0, 8800), 0.0, "1-100", layer="KT-DIM")
    d2 = d.dim_linear((25000, 8000), (27400, 8000), (0, 8800), 0.0, "1-100", layer="KT-DIM")
    seeded["DIM-TRUNG"] = [d1, d2]
    # (11) line trung
    l1 = d.line((25000, 12000), (28000, 12000), "KT-TUONG")
    l2 = d.line((28000, 12000), (25000, 12000), "KT-TUONG")
    seeded["LINE-TRUNG"] = [l1, l2]
    # (12) Z khac 0
    seeded["Z-KHAC0"] = [d.line((25000, 14000, 150.0), (28000, 14000, 150.0), "KT-TUONG")]
    return d, seeded
