"""Kiem thu RUNTIME bo KT bang trinh gia lap tools/lispsim (khong can AutoCAD).

    python3 -m unittest tests/test_runtime.py -v
    KT_VERBOSE=1 python3 -m unittest tests/test_runtime.py     # in danh sach loi de soi bao nham

Chay tren file lisp/*.lsp HIEN TAI (copy vao thu muc ao C:\\KT\\lisp moi lan).
"""
import csv
import io
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))

from lispsim import Session, Ans, Interp, Drawing          # noqa: E402
from lispsim.fixtures import make_mau, make_nhanvien         # noqa: E402

VERBOSE = bool(os.environ.get("KT_VERBOSE"))

MAU_INPUTS = [Ans(None, "Chi lay layer"), Ans(None, "KHUNG TEN"), Ans(None, "Dung block nay"),
              Ans("", "SO HIEU"), Ans("", "TEN ban"), Ans("", "TY LE"), Ans(None, "Ty le goc")]
SECTIONS = {"SETTING", "LAYER", "DIMSTYLE", "TEXTSTYLE", "KHUNG", "BLOCK", "LAYOUT", "DANHMUC"}

_CFG = {}


def mau_cfg(mode="acad"):
    """chay KTMAU tren ban ve mau (1 lan / che do) -> (session, ket qua, noi dung file)"""
    if mode not in _CFG:
        s = Session(make_mau(), mode=mode)
        lr = s.load_all()
        r = s.command("KTMAU", MAU_INPUTS)
        _CFG[mode] = (s, lr, r, s.read_cfg())
    return _CFG[mode]


def show(title, r, issues=None):
    if not VERBOSE:
        return
    print("\n----- %s -----" % title)
    print(r.describe_errors())
    for i in issues or []:
        print("  %-8s %-7s %-16s %s" % (i["sev"], i["module"], i["code"], i["msg"][:120]))


def internal_errors(r):
    """loi khong bi bat + loi bi bat (tru du phong ActiveX) + bug trinh gia lap"""
    return [e.msg for e in r.errors] + [e.msg for e in r.real_caught()] + [b[0] for b in r.sim_bugs]


# ======================================================================
class T0_Interpreter(unittest.TestCase):
    """ngu nghia AutoLISP co ban cua trinh gia lap"""

    def ev(self, s):
        i = Interp()
        v, e = i.eval_str(s)
        return v, e, i

    def test_int_division_and_types(self):
        v, e, _ = self.ev("(list (/ 7 2) (/ 7 2.0) (/ -7 2) (rem -7 2) (type 1) (type 1.0) (fix -2.7) (expt 2 3))")
        from lispsim.ltypes import tolist
        self.assertIsNone(e)
        self.assertEqual([x if not hasattr(x, "name") else x.name for x in tolist(v)],
                         [3, 3.5, -3, -1, "INT", "REAL", -2, 8])

    def test_dynamic_scope_and_locals(self):
        v, e, i = self.ev("(setq x 1)(defun g () x)(defun f (/ x) (setq x 2) (g))(list (f) x)")
        self.assertEqual(i.getv("X"), 1)
        from lispsim.ltypes import tolist
        self.assertEqual(tolist(v), [2, 1])

    def test_errors_like_autocad(self):
        for src, msg in [('(strcat "a" nil)', "bad argument type: stringp nil"),
                         ('(+ "a" 1)', 'bad argument type: numberp: "a"'),
                         ("(car 5)", "bad argument type: consp 5"),
                         ("(khong-co-ham 1)", "no function definition: KHONG-CO-HAM"),
                         ("(defun f (a) a)(f)", "too few arguments"),
                         ("(itoa 2.5)", "bad argument type: fixnump: 2.5")]:
            v, e, _ = self.ev(src)
            self.assertIsNotNone(e, src)
            self.assertEqual(e.msg, msg)

    def test_error_stack_and_star_error(self):
        v, e, i = self.ev('(defun *error* (m) (setq *M* m))(defun a () (b))(defun b () (strcat nil))(a)')
        self.assertEqual(e.stack, ["A", "B"])
        self.assertEqual(i.getv("*M*"), "bad argument type: stringp nil")

    def test_wcmatch(self):
        i = Interp()
        cases = [("KT-01", "KT-##", True), ("ab", "@@", True), ("A.B", "A.B", True), ("AXB", "A.B", False),
                 ("abc", "~a*", False), ("x", "a*,x", True), ("A,B", "A`,B", True), ("B", "[A-C]", True),
                 ("D", "[~A-C]", True), ("ABC", "*B?", True), ("a|b", "*|*", True), ("A", "a", False)]
        for s, p, want in cases:
            self.assertEqual(i.wcmatch(s, p), want, (s, p))

    def test_catch_all(self):
        v, e, i = self.ev("(setq r (vl-catch-all-apply '/ '(1 0)))(list (vl-catch-all-error-p r) (vl-catch-all-error-message r))")
        from lispsim.ltypes import tolist
        self.assertEqual(tolist(v)[1], "divide by zero")


# ======================================================================
class T1_KTMAU(unittest.TestCase):
    """Kich ban 1: KTMAU tren ban ve MAU -> KT_ChuanCongTy.txt hop le"""

    def test_load_suite(self):
        s, lr, r, cfg = mau_cfg()
        self.assertEqual(internal_errors(lr), [], lr.describe_errors())
        self.assertIn("Da nap 10 file", lr.out)   # 9 + KT_Dialog.lsp
        self.assertNotIn("file LOI", lr.out)

    def test_ktmau_runs_clean(self):
        s, lr, r, cfg = mau_cfg()
        show("KTMAU", r)
        self.assertIsNotNone(cfg, "KTMAU khong ghi file")
        self.assertIn("KTMAU: hoan tat", r.out)
        self.assertEqual(internal_errors(r), [], r.describe_errors())

    def test_cfg_valid_and_complete(self):
        s, lr, r, cfg = mau_cfg()
        rows = {}
        for ln in cfg.splitlines():
            ln = ln.strip()
            if not ln or ln.startswith(";"):
                continue
            f = ln.split("|")
            self.assertIn(f[0], SECTIONS, ln)
            self.assertTrue(all(ord(c) < 128 for c in ln), "ky tu ngoai ASCII: " + ln)
            rows.setdefault(f[0], []).append(f[1:])
        for sec in SECTIONS:
            self.assertIn(sec, rows, "thieu muc " + sec)
        names = lambda sec: {r[0].upper() for r in rows[sec]}
        self.assertTrue({"KT-TUONG", "KT-DIM", "KT-TRUC", "KT-TEXT"} <= names("LAYER"))
        self.assertTrue({"1-100", "1-50"} <= names("DIMSTYLE"), rows.get("DIMSTYLE"))
        self.assertTrue({"KT-TEXT", "KT-DIM"} <= names("TEXTSTYLE"), rows.get("TEXTSTYLE"))
        self.assertEqual(rows["KHUNG"][0][:5], ["KHUNG_A3", "SOHIEU", "TENBANVE", "TYLE", "1"])
        blk = {r[0]: r[1:] for r in rows["BLOCK"]}
        self.assertEqual(blk.get("KH_TRUC"), ["TRUC", "TENTRUC"])
        self.assertEqual(blk.get("KH_CAODO"), ["CAODO", "CAODO"])
        self.assertEqual(blk.get("KH_MATCAT", [None])[0], "MATCAT")
        self.assertIn(["KT-03"], rows["LAYOUT"])
        self.assertIn(["KT-01", "MAT BANG TANG 1"], rows["DANHMUC"])
        self.assertIn(["KT-02", "MAT CAT 1-1"], rows["DANHMUC"])
        st = {r[0]: r[1:] for r in rows["SETTING"]}
        hs = [float(x) for x in st["CAO_CHU_GIAY"][0].split(",")]
        self.assertTrue({2.5, 3.5, 5.0} <= set(hs), hs)
        self.assertIn("100", st["TY_LE_CHO_PHEP"][0].split(","))
        for r_ in rows["DIMSTYLE"]:
            self.assertEqual(len(r_), 8, r_)
        for r_ in rows["LAYER"]:
            self.assertEqual(len(r_), 5, r_)

    def test_ktmau_rerun_makes_backup(self):
        s, lr, r, cfg = mau_cfg()
        r2 = s.command("KTMAU", MAU_INPUTS)
        self.assertEqual(internal_errors(r2), [], r2.describe_errors())
        self.assertTrue(os.path.exists(s.path("C:\\KT\\lisp\\KT_ChuanCongTy.bak")))


# ======================================================================
class T2_KTALL_Mau(unittest.TestCase):
    """Kich ban 2: KTALL tren chinh ban ve mau -> gan nhu khong co LOI"""

    def test_ktall_on_sample(self):
        _, _, _, cfg = mau_cfg()
        s = Session(make_mau(), cfg_text=cfg)
        s.load_all()
        r = s.command("KTALL")
        iss = s.issues()
        show("KTALL ban ve MAU", r, iss)
        self.assertEqual(internal_errors(r), [], r.describe_errors())
        self.assertIn("Da chay 6 module", r.out)
        loi = [(i["code"], i["msg"]) for i in iss if i["sev"] == "LOI"]
        self.assertEqual(loi, [], "bao nham LOI tren ban ve mau")
        warn = [(i["code"], i["msg"]) for i in iss if i["sev"] == "CANHBAO"]
        self.assertLessEqual(len(warn), 2, warn)
        self.assertEqual(s.dwg.violations, [])


# ======================================================================
class T3_NhanVien(unittest.TestCase):
    """Kich ban 3: ban ve NHAN VIEN co cai loi -> moi loi duoc phat hien dung ma"""

    def run_nv(self, mode="acad", cfg=None):
        if cfg is None:
            cfg = mau_cfg()[3]
        d, seed = make_nhanvien()
        s = Session(d, mode=mode, cfg_text=cfg)
        s.load_all()
        r = s.command("KTALL")
        return s, r, s.issues(), seed

    def check_seeds(self, iss, seed, skip=()):
        miss = []
        for code, ents in seed.items():
            if code in skip:
                continue
            if not [i for i in iss if i["code"] == code and any(e in i["ents"] for e in ents)]:
                miss.append(code)
        return miss

    def test_seeded_errors_detected(self):
        s, r, iss, seed = self.run_nv()
        show("KTALL ban ve NHAN VIEN", r, iss)
        self.assertEqual(internal_errors(r), [], r.describe_errors())
        self.assertEqual(self.check_seeds(iss, seed), [])
        self.assertEqual(s.dwg.violations, [], "lenh kiem tra da sua/xoa doi tuong goc")

    def test_seeded_with_complete_cfg(self):
        """doc lap voi KTMAU: them tay muc DIMSTYLE/TEXTSTYLE neu file sinh ra bi thieu"""
        cfg = mau_cfg()[3]
        if "DIMSTYLE|1-100" not in cfg:
            cfg += ("\nDIMSTYLE|1-100|100|1|2|1.5|KT-DIM|0|0\nDIMSTYLE|1-50|50|1|2|1.5|KT-DIM|0|0\n"
                    "TEXTSTYLE|KT-DIM|romans.shx||0|0.8\n")
        s, r, iss, seed = self.run_nv(cfg=cfg)
        self.assertEqual(self.check_seeds(iss, seed), [])
        codes = {i["code"] for i in iss}
        self.assertIn("DIM-STYLE", codes)


# ======================================================================
class T4_VinaCAD(unittest.TestCase):
    """Kich ban 4: che do VinaCAD (moi vla-*/vlax-* -> no function definition): khong lenh nao crash"""

    CMDS = ["KTLAYER", "KTTEXT", "KTDIM", "KTKHUNG", "KTKHOP", "KTSACH", "KTALL", "KTN", "KTP",
            "KTBC", "KTX", "KTCFG", "KTHELP", "KTPROBE"]

    def test_ktmau_vinacad(self):
        s, lr, r, cfg = mau_cfg("vinacad")
        show("KTMAU VinaCAD", r)
        self.assertIsNotNone(cfg)
        self.assertEqual([m for m in internal_errors(lr)], [])
        self.assertEqual(internal_errors(r), [], r.describe_errors())

    def test_all_commands_vinacad(self):
        cfg = mau_cfg("vinacad")[3]
        d, seed = make_nhanvien()
        s = Session(d, mode="vinacad", cfg_text=cfg)
        s.load_all()
        bad = {}
        for c in self.CMDS:
            r = s.command(c)
            if internal_errors(r):
                bad[c] = r.describe_errors()
        self.assertEqual(bad, {})

    def test_detection_same_as_autocad(self):
        cfg = mau_cfg()[3]
        res = {}
        for mode in ("acad", "vinacad"):
            d, seed = make_nhanvien()
            s = Session(d, mode=mode, cfg_text=cfg)
            s.load_all()
            s.command("KTALL")
            res[mode] = sorted((i["code"], i["sev"]) for i in s.issues())
        self.assertEqual(res["acad"], res["vinacad"])


# ======================================================================
class T5_Navigation_Report(unittest.TestCase):
    """Kich ban 5: KTN/KTP/KTX/KTBC + file CSV hop le"""

    def test_nav_and_csv(self):
        cfg = mau_cfg()[3]
        d, seed = make_nhanvien()
        s = Session(d, cfg_text=cfg)
        s.load_all()
        s.command("KTALL")
        n = len(s.issues())
        self.assertGreater(n, 5)
        marks = [e for e in d.main if e.made and not e.deleted and e.layer == "KT_CHECK"]
        self.assertGreaterEqual(len(marks), n)
        for c in ["KTN", "KTN", "KTP", "KTP", "KTP"]:
            r = s.command(c)
            self.assertEqual(internal_errors(r), [], c + ": " + r.describe_errors())
            self.assertRegex(r.out, r"Loi \d+/%d" % n)
        r = s.command("KTBC")
        self.assertEqual(internal_errors(r), [], r.describe_errors())
        p = s.path("C:\\DuAn\\NHANVIEN_KiemTra.csv")
        self.assertTrue(os.path.exists(p), r.out)
        with open(p, encoding="latin-1", newline="") as f:
            rows = list(csv.reader(f))
        if rows and rows[0] and rows[0][0].startswith("sep="):
            rows = rows[1:]                    # dong goi y dau phan cach cho Excel
        self.assertEqual(rows[0][:5], ["STT", "Module", "Ma loi", "Muc do", "Noi dung"])
        ncol = len(rows[0])
        self.assertEqual(len(rows) - 1, n)
        for i, row in enumerate(rows[1:], 1):
            self.assertEqual(len(row), ncol, row)
            self.assertEqual(row[0], str(i))
            self.assertIn(row[3], ("LOI", "CANHBAO", "GOIY"))
            for col in ("X", "Y"):              # "" = muc tong ket khong co vi tri
                v = row[rows[0].index(col)]
                if v != "":
                    float(v)
        r = s.command("KTX")
        self.assertEqual(internal_errors(r), [], r.describe_errors())
        self.assertEqual(s.issues(), [])
        marks = [e for e in d.main if e.made and not e.deleted and e.layer == "KT_CHECK"]
        self.assertEqual(marks, [])
        r = s.command("KTN")
        self.assertIn("Chua co ket qua", r.out)
        r = s.command("KTBC")
        self.assertEqual(internal_errors(r), [])
        self.assertEqual(d.violations, [])

    def test_single_commands(self):
        cfg = mau_cfg()[3]
        d, seed = make_nhanvien()
        s = Session(d, cfg_text=cfg)
        s.load_all()
        for c in ["KTLAYER", "KTTEXT", "KTDIM", "KTKHUNG", "KTKHOP", "KTSACH", "KTCFG", "KTHELP", "KTPROBE"]:
            r = s.command(c)
            self.assertEqual(internal_errors(r), [], c + ": " + r.describe_errors())
        r = s.command("KTDIMSET", [None] * 7)
        self.assertEqual(internal_errors(r), [], r.describe_errors())

    def test_no_cfg_file(self):
        """chua co KT_ChuanCongTy.txt: cac lenh bao va bo qua, khong crash"""
        d, seed = make_nhanvien()
        s = Session(d)
        s.load_all()
        for c in ["KTALL", "KTLAYER", "KTDIM", "KTKHUNG", "KTN", "KTBC", "KTX"]:
            r = s.command(c)
            self.assertEqual(internal_errors(r), [], c + ": " + r.describe_errors())


# ======================================================================
class T6_Legacy_CDO(unittest.TestCase):
    """Hieu chuan: lisp CDO goc (da chay tot thuc te) phai chay khong loi tren trinh gia lap"""

    def test_cdo(self):
        d, seed = make_nhanvien()
        s = Session(d)
        r = s.eval('(load "C:\\\\KT\\\\lisp\\\\legacy\\\\CheckDimOverlap.lsp")')
        self.assertEqual(internal_errors(r), [], r.describe_errors())
        r = s.command("CDO")
        self.assertEqual(internal_errors(r), [], r.describe_errors())
        self.assertIn("TRUNG: 1", r.out)
        for c in ("CDON", "CDOX"):
            r = s.command(c)
            self.assertEqual(internal_errors(r), [], r.describe_errors())


if __name__ == "__main__":
    unittest.main()


# ======================================================================
class T7_VinaCAD_LMS(unittest.TestCase):
    """VinaCAD that (nen LMS Tech, bao cao cua leader 11/2026): ActiveX co, nhung (type car)
    khong tra 'SUBR -> code KHONG duoc phu thuoc ten kieu ham. Truoc khi sua: KTPROBE bao
    0/28 ham, KT/KTALL bao 'Chua nap KT_Core'."""

    def test_lms_commands(self):
        cfg = mau_cfg()[3]
        d, seed = make_nhanvien()
        s = Session(d, mode="lms", cfg_text=cfg)
        s.load_all()
        r = s.command("KTPROBE")
        self.assertIn("co 28/28 ham", r.out)
        r = s.command("KTALL")
        self.assertEqual(internal_errors(r), [], r.describe_errors())
        out = r.out
        self.assertNotIn("Chua nap KT_Core", out)
        self.assertTrue(len(s.issues()) > 0)
