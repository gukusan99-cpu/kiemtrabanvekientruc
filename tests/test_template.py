"""Kiem thu hoi quy tren BAN VE MAU THAT cua cong ty (DXF) - xem docs/QA_TEMPLATE_RUN.md.

    KT_TEMPLATE_DXF=/duong/dan/Template.dxf python3 -m unittest tests/test_template.py -v

File DXF KHONG nam trong repo -> moi test bi bo qua (skip) neu khong tim thay file.
Mac dinh tim: bien moi truong KT_TEMPLATE_DXF, roi tests/data/Template.dxf.
Ca bo chay ~2-3 phut (nap DXF ~5 s, KTALL ~40 s / che do).

Quy uoc: bao nham DA SUA -> assert cung (hoi quy). Bao nham CON MO -> @expectedFailure
(khi Dev sua xong test bao "unexpected success" -> bo decorator).
"""
import csv
import io
import os
import re
import sys
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))

from lispsim import Session                       # noqa: E402
from lispsim.dxfload import load_dxf              # noqa: E402
from lispsim.ltypes import tolist, Cons, to_str   # noqa: E402

DXF = os.environ.get("KT_TEMPLATE_DXF") or os.path.join(HERE, "data", "Template.dxf")
HAVE = os.path.isfile(DXF)
SKIP = "khong co file DXF mau (dat KT_TEMPLATE_DXF)"
CFG_FILE = os.path.join(ROOT, "lisp", "KT_ChuanCongTy.txt")
MAX_KTALL_SEC = float(os.environ.get("KT_TEMPLATE_MAXSEC", "240"))   # ~40 s tren may QA

_C = {}


def dwg():
    """DXF nap moi lan (lenh co the them doi tuong KT_CHECK)"""
    return load_dxf(DXF)


def internal(r):
    return ([e.msg for e in r.errors] + [e.msg for e in r.real_caught()]
            + [b[0] for b in r.sim_bugs])


def ktmau(mode):
    key = ("ktmau", mode)
    if key not in _C:
        s = Session(dwg(), mode=mode)
        p = s.cfg_path()
        if os.path.exists(p):
            os.remove(p)
        s.load_all()
        r = s.command("KTMAU")          # Enter moi cau hoi = tu doan khung ten / tag
        _C[key] = (s, r, s.read_cfg() or "")
    return _C[key]


def std_cfg():
    if os.path.isfile(CFG_FILE):
        with open(CFG_FILE, encoding="latin-1") as f:
            return f.read()
    return ktmau("acad")[2]


def ktall(mode="acad"):
    key = ("ktall", mode)
    if key not in _C:
        s = Session(dwg(), mode=mode, cfg_text=std_cfg())
        s.load_all()
        t = time.time()
        r = s.command("KTALL")
        _C[key] = (s, r, time.time() - t, s.issues())
    return _C[key]


def by_ent(iss, code, handle):
    return [i for i in iss if i["code"] == code and handle in [e.handle for e in i["ents"]]]


# ======================================================================
@unittest.skipUnless(HAVE, SKIP)
class T0_Loader(unittest.TestCase):
    """dxfload: entget giong AutoCAD"""

    @classmethod
    def setUpClass(cls):
        cls.s = Session(dwg())

    def ev(self, src):
        r = self.s.eval(src)
        self.assertIsNone(r.error, (src, r.error and r.error.msg))
        return r.value

    def test_counts(self):
        d = self.s.dwg
        self.assertEqual(sum(1 for e in d.main if e.kind == "main"), 7674)
        self.assertGreater(len(d.blocks), 3000)
        self.assertEqual(list(d.layouts)[0], "Model")

    def test_entget_header_and_angle(self):
        v = self.ev('(entget (handent "113B99"))')        # INSERT 1444, goc 359.99999 do
        lst = tolist(v)
        self.assertEqual([c.car for c in lst[:6]], [-1, 0, 330, 5, 100, 67])
        d = {c.car: c.cdr for c in lst}
        self.assertEqual(d[410], "Model")
        self.assertAlmostEqual(d[50], 6.283185307, 5)                # radian
        self.assertEqual(d[41], -1.0)

    def test_ansi_unicode_names(self):
        # "1 TRỤC" -> \U+1EE4 ; "1 GHI CHÚ" -> Ú thuoc cp1252 giu nguyen (byte 0xDA)
        self.assertIsNotNone(self.ev('(tblsearch "LAYER" "1 TR\\\\U+1EE4C")'))
        self.assertIsNotNone(self.ev('(tblsearch "LAYER" "1 GHI CH\xda")'))
        self.assertEqual(self.ev('(ascii (substr "\xda" 1 1))'), 0xDA)

    def test_attrib_seqend_and_block_chain(self):
        v = self.ev('(list (cdr (assoc 0 (entget (entnext (handent "22A05"))))) '
                    '(cdr (assoc 0 (entget (entnext (entnext (handent "22A05")))))))')
        self.assertEqual(tolist(v), ["ATTRIB", "SEQEND"])
        n = self.ev('(progn (setq e (tblobjname "BLOCK" "KHUNGTEENA") n 0)'
                    '(while (and (setq e (entnext e)) (/= (cdr (assoc 0 (entget e))) "ENDBLK")) (setq n (1+ n))) n)')
        self.assertEqual(n, 70)

    def test_dimension_xdata_dimstyle_dict(self):
        v = self.ev('(cdr (assoc -3 (entget (handent "C86DC") (list "ACAD"))))')
        self.assertIn("DSTYLE", to_str(v, True))
        v = self.ev('(cdr (assoc 340 (entget (tblobjname "DIMSTYLE" "DG 1-100 (200)"))))')
        self.assertEqual(self.ev('(cdr (assoc 0 (entget (cdr (assoc 340 (entget (tblobjname "DIMSTYLE" "DG 1-100 (200)")))))))'),
                         "STYLE")
        self.assertIsNotNone(self.ev('(dictsearch (namedobjdict) "ACAD_LAYOUT")'))
        self.assertIsNotNone(self.ev('(dictsearch (namedobjdict) "ACAD_IMAGE_DICT")'))
        # MTEXT trong block *D co 42/43 (entget AutoCAD luon co)
        v = self.ev('(progn (setq e (entnext (tblobjname "BLOCK" "*D2812")))'
                    '(while (/= (cdr (assoc 0 (entget e))) "MTEXT") (setq e (entnext e)))'
                    '(list (cdr (assoc 42 (entget e))) (cdr (assoc 43 (entget e)))))')
        self.assertTrue(all(x and x > 0 for x in tolist(v)))


# ======================================================================
@unittest.skipUnless(HAVE, SKIP)
class T1_KTMAU(unittest.TestCase):
    def test_acad_guess_frame(self):
        s, r, cfg = ktmau("acad")
        self.assertEqual(internal(r), [], r.describe_errors())
        self.assertIn("KTMAU: hoan tat", r.out)
        self.assertRegex(cfg, r"(?m)^KHUNG\|KHUNGTEENA\|SO_HIEU_BV\|[^|]*TEN_BAN_VE[^|]*\|TY_LE\|100")
        self.assertGreaterEqual(len(re.findall(r"(?m)^DANHMUC\|", cfg)), 55)
        self.assertRegex(cfg, r"(?m)^BLOCK\|COTCAODO\|CAODO\|")

    def test_layout_names_not_empty(self):
        """B-T1: ktmau:layouts lay (assoc 1) dau tien = ten page setup (AcDbPlotSettings) -> 'LAYOUT|'"""
        cfg = ktmau("acad")[2]
        self.assertNotRegex(cfg, r"(?m)^LAYOUT\|\s*$")

    def test_vinacad_guess_frame(self):
        """B-T3: kt:ent-pts (du phong khong ActiveX) coi vector 11/12 cua WIPEOUT la diem -> doan sai khung"""
        s, r, cfg = ktmau("vinacad")
        self.assertEqual(internal(r), [], r.describe_errors())
        self.assertRegex(cfg, r"(?m)^KHUNG\|KHUNGTEENA\|")


# ======================================================================
@unittest.skipUnless(HAVE, SKIP)
class T2_KTALL(unittest.TestCase):
    def test_no_crash_and_time(self):
        s, r, sec, iss = ktall("acad")
        self.assertEqual(internal(r), [], r.describe_errors())
        self.assertIn("Da chay 6 module", r.out)
        self.assertLess(sec, MAX_KTALL_SEC)
        self.assertEqual(s.dwg.violations, [])
        self.assertGreater(len(iss), 100)          # template co loi that (MAU-BYOBJ, LAYER-0, ...)

    def test_vinacad_no_crash(self):
        s, r, sec, iss = ktall("vinacad")
        self.assertEqual(internal(r), [], r.describe_errors())
        self.assertLess(sec, MAX_KTALL_SEC)

    def test_real_errors_found(self):
        iss = ktall("acad")[3]
        codes = {i["code"] for i in iss}
        for c in ("LAYER-0", "LINE-TRUNG", "KHUNG-TRUNGSO", "PLINE-0", "DIM-GHIDE"):
            self.assertIn(c, codes)
        self.assertTrue(by_ent(iss, "KHUNG-TRUNGSO", "EC5DC"))       # C/04 trung
        self.assertTrue(by_ent(iss, "DIM-GHIDE", "152183"))          # ghi 141, do 71.5

    # ---- bao nham da sua (hoi quy) ----
    def test_no_level_false_positive(self):
        """COTCAODO lat 180 do: vach cao do khong nam o diem chen (KHOP-CAODO-VITRI 'lech 93.6mm')"""
        iss = ktall("acad")[3]
        self.assertEqual([i["msg"] for i in iss if i["code"] == "KHOP-CAODO-VITRI"], [])

    def test_no_chain_dim_overlap(self):
        """dim lien tiep chung 1 diem (lech 0.002) khong phai DIM-DUONG"""
        iss = ktall("acad")[3]
        self.assertEqual(by_ent(iss, "DIM-DUONG", "147C04"), [])

    def test_dimscale0_style_not_tyle_1_1(self):
        """style DIMSCALE 0 + override DIMSCALE 1, ty le 'nuong' trong DIMTXT: khong bao 'Dim TL 1/1'"""
        iss = ktall("acad")[3]
        self.assertEqual([i for i in iss if i["code"] == "DIM-TYLE" and "Dim TL 1/1 " in i["msg"]], [])

    # ---- bao nham con mo ----
    @unittest.expectedFailure
    def test_z_noise(self):
        """B-T4: Z-KHAC0 nguong 1e-6 -> bao 'Z = 0' / 'Z = -0' (|z| < 0.001)"""
        iss = ktall("acad")[3]
        bad = [i["msg"] for i in iss if i["code"] == "Z-KHAC0" and re.search(r"Z = -?0 \(", i["msg"])]
        self.assertEqual(bad, [])


# ======================================================================
@unittest.skipUnless(HAVE, SKIP)
class T3_Nav(unittest.TestCase):
    def test_ktn_ktbc(self):
        s, r, sec, iss = ktall("acad")
        n = len(iss)
        r1 = s.command("KTN")
        self.assertIn("Loi 1/%d" % n, r1.out)
        r2 = s.command("KTN")
        self.assertIn("Loi 2/%d" % n, r2.out)
        rb = s.command("KTBC")
        self.assertEqual(internal(rb), [], rb.describe_errors())
        name = os.path.splitext(s.dwg.name)[0]
        p = s.path("C:\\DuAn\\%s_KiemTra.csv" % name)
        self.assertTrue(os.path.exists(p), rb.out)
        with open(p, encoding="latin-1", newline="") as f:
            rows = [x for x in csv.reader(io.StringIO(f.read()))]
        data = [x for x in rows[2:] if x and x[0].strip().isdigit()]
        self.assertEqual(len(data), n)
        self.assertTrue(all(len(x) == len(rows[1]) for x in data))


if __name__ == "__main__":
    unittest.main()
