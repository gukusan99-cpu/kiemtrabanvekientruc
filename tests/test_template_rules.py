"""Quy cach ban ve mau cong ty (Template.dxf - xem docs/TEMPLATE_ANALYSIS.md) tren ban ve gia lap nho:

- dimstyle DIMSCALE = 0, DIMTXT theo don vi ban ve ("DG 1-100 (200)" = 150, "DG 1-30 (60) x4" DIMLFAC 0.25)
  + override DSTYLE DIMSCALE=1 tren moi dim -> khong bao DIM-TYLE / DIM-OVR / DIM-LFAC
- ma 42 cua dim = Measurement DA nhan DIMLFAC (AutoCAD): dim x4 do 400 -> 42 = 100, khong bao DIM-GHIDE
- dim style 1/30 dat trong khung 1/100 (chu 0.6mm giay) -> DIM-TYLE LOI; dim x4 noi chuoi dim thuong
  -> DIM-LFAC CANHBAO
- khung ten nhieu block (KHUNG chinh co attribute + to bia khong attribute), ten 2 dong "A+B"
- ky hieu cao do co diem goc (dinh tam giac) KHAC diem chen, chen mirror/xoay 180 -> khong bao nham
  KHOP-CAODO-VITRI; 1 ky hieu dat lech 50mm -> LOI
- ten block co dau ("TR\\U+1EE4C" = TRUC) khop file chuan; bo nhieu to cung ten lien tiep khong bao.

Chay: python3 -m unittest tests/test_template_rules.py
"""
import math
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))

from lispsim import Session, Drawing  # noqa: E402
from lispsim.ltypes import tolist  # noqa: E402

TRUC = "TR\\U+1EE4C"          # "TRỤC" nhu AutoLISP ANSI nhin thay

CFG = r"""SETTING|CAO_CHU_GIAY|2,2.5,4
SETTING|CAO_CHU_DIM|1.5,2
SETTING|TY_LE_CHO_PHEP|20,30,50,100
SETTING|LAYER_BO_QUA|DEFPOINTS,KT_CHECK,*|*
LAYER|0|7|Continuous|-3|1
LAYER|1 DIM|251|Continuous|5|1
LAYER|1 TEXT|7|Continuous|20|1
LAYER|1 KI HIEU|3|Continuous|5|1
LAYER|1 TRUC|15|Continuous|5|1
DIMSTYLE|DG 1-100 (200)|0|1|150|60|DIMTXT|0|0
DIMSTYLE|DG 1-30 (60)|0|1|60|20|DIMTXT|0|0
DIMSTYLE|DG 1-30 (60) x4|0|0.25|60|20|DIMTXT|0|0
TEXTSTYLE|DIMTXT|arial.ttf||0|1
TEXTSTYLE|Standard|arial.ttf||0|1
TEXTSTYLE|0 ARIAL 2|arial.ttf||200|1
KHUNG|KHUNGA|SO_HIEU_BV|TEN_BAN_VE+TEN_CONG_TRINH|TY_LE|100
KHUNG|BIA||||54
BLOCK|%s|TRUC|A
BLOCK|COTCAODO|CAODO|COTE||-88.25,-49.03
""" % TRUC

FW, FH = 42000.0, 29700.0          # khung A3 ve san o 1/100


def build():
    d = Drawing("TEMPLATE_RULES.dwg")
    for nm, col in [("1 DIM", 251), ("1 TEXT", 7), ("1 KI HIEU", 3), ("1 TRUC", 15)]:
        d.layer(nm, col, "Continuous", 5)
    d.style("DIMTXT", "arial.ttf", "", 0.0, 1.0)
    d.style("0 ARIAL 2", "arial.ttf", "", 200.0, 1.0)
    d.dimstyle("DG 1-100 (200)", dimscale=0, dimtxt=150, dimasz=60, txsty="DIMTXT")
    d.dimstyle("DG 1-30 (60)", dimscale=0, dimtxt=60, dimasz=20, txsty="DIMTXT")
    d.dimstyle("DG 1-30 (60) x4", dimscale=0, dimlfac=0.25, dimtxt=60, dimasz=20, txsty="DIMTXT")
    # khung chinh: vien 42000 x 29700, diem goc tren-trai; attribute TEN tran ra ngoai vien
    k = d.block("KHUNGA")
    d.rect((0, -FH), (FW, 0), "1 TEXT", k)
    for tag, p in [("SO_HIEU_BV", (39000, -27500)), ("TEN_BAN_VE", (38000, -24400)),
                   ("TEN_CONG_TRINH", (38000, -24900)), ("TY_LE", (37500, -27200))]:
        d.attdef(k, tag, p, 250, style="Standard", layer="1 TEXT")
    b = d.block("BIA")
    d.rect((0, -16038), (22680, 0), "1 TEXT", b)
    # ky hieu truc: diem chen = duoi duoi, vong tron phia tren
    t = d.block(TRUC)
    d.circle((0, -400), 266.7, "1 TRUC", t)
    d.pline([(0, -166.7), (0, 0)], "1 TRUC", t)
    d.attdef(t, "A", (-112, -516), 250, style="Standard", layer="1 TEXT")
    # cao do: dinh tam giac (-88.25,-49.03) nam tren vach y = -49.03; diem chen (0,0) KHONG tren vach
    c = d.block("COTCAODO")
    d.add("SOLID", [(8, "1 KI HIEU"), (10, (-178.49, 46.58, 0)), (11, (-88.25, 46.58, 0)),
                    (12, (-88.25, -49.03, 0)), (13, (-88.25, -49.03, 0))], c)
    d.add("SOLID", [(8, "1 KI HIEU"), (10, (1.98, 46.58, 0)), (11, (-88.25, 46.58, 0)),
                    (12, (-88.25, -49.03, 0)), (13, (-88.25, -49.03, 0))], c)
    d.line((-179.0, -49.03), (1121.2, -49.03), "1 KI HIEU", c)
    d.attdef(c, "COTE", (470, 250), 200, style="Standard", layer="1 TEXT")
    return d


def frame(d, x, y, sc, so, ten, ten2="", tl=None):
    return d.insert("KHUNGA", (x, y), sc / 100.0, layer="1 TEXT",
                    attribs={"SO_HIEU_BV": so, "TEN_BAN_VE": ten, "TEN_CONG_TRINH": ten2,
                             "TY_LE": tl or "1:%d" % sc})


def dim(d, p1, p2, y, style, measure=None, ovr=True):
    e = d.dim_linear(p1, p2, (0, y), 0.0, style, layer="1 DIM", measure=measure)
    if ovr:  # template: moi dim co override DSTYLE day du, DIMSCALE = 1 (style = 0)
        meta = d.dimstyle_meta[style.upper()]
        d.dim_override(e, {40: 1.0, 140: meta["dimtxt"], 144: meta["dimlfac"]})
    return e


def make():
    d = build()
    seed = {}
    # --- 1/100: mat dung truc 1-3 (ten 2 dong) ---
    frame(d, 0, FH, 100, "MD/01", "MAT DUNG", "TRUC 1-3")
    for nm, x in (("1", 5000.0), ("2", 8600.0), ("3", 12800.0)):
        d.line((x, 2000), (x, 12000), "1 TRUC")
        d.insert(TRUC, (x, 12000), sx=-0.76, sy=0.76, rot=math.pi, layer="1 TEXT", attribs={"A": nm})
    y0 = 3000.0
    lv = [(-0.45, "-0.450"), (0.0, "+0.000"), (3.6, "+3.600"), (7.2, "+7.200")]
    for v, s in lv:
        # diem goc dinh tam giac phai nam tren cao do: diem chen = cao do - (dinh doi qua scale/xoay)
        yv = y0 + 1000 * v
        if v < 0:   # ky hieu cot am lat nguoc (mirror X, xoay 180): dinh -> (+88.25*0.955, +49.03*0.955)
            d.insert("COTCAODO", (14000 - 88.25 * 0.955, yv - 49.03 * 0.955), sx=-0.955, sy=0.955,
                     rot=math.pi, layer="1 KI HIEU", attribs={"COTE": s})
        else:
            d.insert("COTCAODO", (14000 + 88.25 * 0.955, yv + 49.03 * 0.955), 0.955,
                     layer="1 KI HIEU", attribs={"COTE": s})
    bad = d.insert("COTCAODO", (16000 + 88.25 * 0.955, y0 + 10800 + 50 + 49.03 * 0.955), 0.955,
                   layer="1 KI HIEU", attribs={"COTE": "+10.800"})
    seed["KHOP-CAODO-VITRI"] = [bad]
    # dim truc dung chuan (override DIMSCALE=1)
    dim(d, (5000, 12000), (8600, 12000), 13000, "DG 1-100 (200)")
    dim(d, (8600, 12000), (12800, 12000), 13000, "DG 1-100 (200)")
    # dim style 1/30 trong khung 1/100 -> chu 0.6mm giay
    seed["DIM-TYLE"] = [dim(d, (5000, 1000), (6000, 1000), 500, "DG 1-30 (60)")]
    # --- to bia (khung phu khong attribute) 1/100 ---
    d.insert("BIA", (-50000, FH), 100 / 54.0, layer="1 TEXT")
    # --- 3 to chi tiet 1/30 cung ten (bo nhieu to) ---
    for i in range(3):
        frame(d, 50000 + i * 12600, FH, 30, "C/0%d" % (i + 1), "CHI TIET CUA")
    # chi tiet ve phong to x4 trong khung 1/30: dim x4 do 400 -> hien 100 (ma 42 = 100)
    dim(d, (52000, 25000), (52400, 25000), 25500, "DG 1-30 (60) x4", measure=100.0)
    dim(d, (52400, 25000), (53200, 25000), 25500, "DG 1-30 (60) x4", measure=200.0)
    # dim thuong 1/30 noi chuoi voi dim x4 (chung diem 53200) -> DIM-LFAC CANHBAO
    mix = dim(d, (53200, 25000), (54000, 25000), 25500, "DG 1-30 (60)")
    seed["DIM-LFAC"] = [mix]
    return d, seed


class T_TemplateRules(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.d, cls.seed = make()
        s = Session(cls.d, cfg_text=CFG)
        s.load_all()
        cls.r = {c: s.command(c) for c in ("KTDIM", "KTKHUNG", "KTKHOP", "KTTEXT")}
        cls.s = s
        cls.iss = s.issues()

    def by(self, code, sev=None):
        return [i for i in self.iss if i["code"] == code and (sev is None or i["sev"] == sev)]

    def test_no_internal_errors(self):
        for c, r in self.r.items():
            self.assertEqual(r.errors, [], c + ": " + r.describe_errors())

    def test_frames_multi_block_and_title(self):
        fr = self.s.eval('(mapcar (function (lambda (f) (list (nth 5 f) (nth 6 f) (nth 4 f)))) (kt:frames))').value
        rows = [tolist(x) for x in tolist(fr)]
        titles = {r[0]: r[1] for r in rows if r[0]}
        self.assertEqual(titles.get("MD/01"), "MAT DUNG TRUC 1-3")
        self.assertEqual(len(rows), 5)                                  # 4 KHUNGA + 1 BIA
        bia = [r for r in rows if not r[0]]
        self.assertAlmostEqual(bia[0][2], 100.0, places=3)

    def test_dim_conventions(self):
        tyle = self.by("DIM-TYLE")
        self.assertEqual([i["ents"] for i in tyle], [self.seed["DIM-TYLE"]], tyle)
        self.assertEqual(tyle[0]["sev"], "LOI")
        self.assertEqual(self.by("DIM-OVR"), [])
        self.assertEqual(self.by("DIM-GHIDE"), [])
        lf = self.by("DIM-LFAC")
        self.assertEqual(len(lf), 1, lf)
        self.assertEqual(lf[0]["sev"], "CANHBAO")
        self.assertIn(self.seed["DIM-LFAC"][0], lf[0]["ents"])

    def test_level_refpoint(self):
        v = self.by("KHOP-CAODO-VITRI")
        self.assertEqual([i["ents"] for i in v], [self.seed["KHOP-CAODO-VITRI"]], v)

    def test_sheet(self):
        self.assertEqual(self.by("KHUNG-TRUNGTEN"), [])
        self.assertEqual(self.by("KHUNG-THIEU"), [])                  # TEN_CONG_TRINH trong: tuy chon
        self.assertEqual(self.by("KHUNG-TYLE", "LOI"), [])

    def test_no_false_loi(self):
        loi = [(i["code"], i["msg"]) for i in self.iss if i["sev"] == "LOI"
               and i["code"] not in ("DIM-TYLE", "KHOP-CAODO-VITRI")]
        self.assertEqual(loi, [])

    def test_ukey(self):
        v = self.s.eval('(list (kt:ukey "tr\\\\U+1ee5c") (kt:ukey "1 n\xe9t") (kt:cfg-row "BLOCK" "tr\\\\U+1ee5c"))').value
        v = tolist(v)
        self.assertEqual(v[0], TRUC)
        self.assertEqual(v[1], "1 N\xc9T")
        self.assertEqual(tolist(v[2])[:2], [TRUC, "TRUC"])


if __name__ == "__main__":
    unittest.main()
