"""Kiem thu pham vi kiem tra (vung) - kt:ask-scope / kt:region-* / KTALL / hop thoai KT.

    python3 -m unittest tests/test_region.py -v
"""
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
sys.path.insert(0, HERE)

from lispsim import Session, Ans, CANCEL                    # noqa: E402
from lispsim.dcl import attach_dcl                          # noqa: E402
from lispsim.fixtures import make_nhanvien                  # noqa: E402
from test_runtime import mau_cfg, internal_errors as _ie    # noqa: E402


def internal_errors(r):
    """ESC co chu dich (bi vl-catch-all-apply bat trong kt:ask-scope / kt:ask-window) khong tinh"""
    return [m for m in _ie(r) if m != "Function cancelled"]

# khung KT-01 (goc 0,0; A3 x 100 = 42000 x 29700); KT-02 o 50000, KT-02 trung o 80000
P1, P2 = (-100.0, -100.0), (42100.0, 29800.0)
WIN = [Ans("Vung", "Pham vi"), Ans(P1, "Goc thu nhat"), Ans(P2, "Goc doi dien")]


def cfg():
    c = mau_cfg()[3]
    if "DIMSTYLE|1-100" not in c:
        c += ("\nDIMSTYLE|1-100|100|1|2|1.5|KT-DIM|0|0\nDIMSTYLE|1-50|50|1|2|1.5|KT-DIM|0|0\n"
              "TEXTSTYLE|KT-DIM|romans.shx||0|0.8\n")
    return c


def session(mode="acad"):
    s = Session(make_nhanvien()[0], mode=mode, cfg_text=cfg())
    s.load_all()
    return s


def inside(i):
    p = i["pt"]
    return (i["space"] == "Model" and p and P1[0] <= p[0] <= P2[0] and P1[1] <= p[1] <= P2[1])


def region_marks(s):
    return [e for e in s.dwg.main if e.made and not e.deleted and e.layer == "KT_CHECK"
            and e.type == "LWPOLYLINE"]


class T1_Region(unittest.TestCase):
    def test_ktall_window_only_inside(self):
        for mode in ("acad", "vinacad"):
            with self.subTest(mode=mode):
                full = session(mode)
                full.command("KTALL")
                allis = full.issues()
                self.assertTrue([i for i in allis if not inside(i)], "can loi ngoai vung de kiem")
                self.assertTrue([i for i in allis if inside(i)])
                self.assertEqual(region_marks(full), [])

                s = session(mode)
                r = s.command("KTALL", WIN)
                self.assertEqual(internal_errors(r), [], r.describe_errors())
                iss = s.issues()
                self.assertTrue(iss)
                self.assertTrue(all(inside(i) for i in iss), [i for i in iss if not inside(i)])
                key = lambda i: (i["module"], i["code"], i["msg"])          # noqa: E731
                self.assertEqual(sorted(map(key, iss)), sorted(key(i) for i in allis if inside(i)))
                self.assertIn("muc ngoai vung da bo qua", r.out)
                self.assertIn("Pham vi: Vung (Model) -100,-100 - 42100,29800", r.out)
                self.assertIsNone(s.I.getv("*KT:REGION*"))           # vung chi cho lan chay nay
                rm = region_marks(s)
                self.assertEqual(len(rm), 1)
                self.assertEqual(rm[0].get(62), 3)
                # khong co loi cua khung thu 3 (KT-02 trung so, o x=80000)
                self.assertNotIn("KHUNG-TRUNGSO", {i["code"] for i in iss})
                self.assertEqual(s.dwg.violations, [])
                # chay lai toan ban ve: day du nhu ban dau
                r = s.command("KTALL")
                self.assertEqual(len(s.issues()), len(allis))

    def test_esc_nothing_runs(self):
        s = session()
        for inputs in ([Ans(CANCEL, "Pham vi")],
                       [Ans("Vung", "Pham vi"), Ans(CANCEL, "Goc thu nhat")],
                       [Ans("V", "Pham vi"), Ans(P1, "Goc thu nhat"), Ans(None, "Goc doi dien")]):
            r = s.command("KTALL", inputs)
            self.assertEqual(internal_errors(r), [], r.describe_errors())
            self.assertEqual(s.issues(), [])
            self.assertNotIn(">>>", r.out)
            self.assertIn("Khong chay", r.out)
            self.assertIsNone(s.I.getv("*KT:REGION*"))

    def test_keywords_and_kt_cmd(self):
        s = session()
        r = s.eval("(kt:cmd 'ktlay:run)", [Ans("W"), Ans(P1), Ans(P2)])
        self.assertEqual(internal_errors(r), [], r.describe_errors())
        iss = s.issues()
        self.assertTrue(iss)
        self.assertTrue(all(inside(i) and i["module"] == "LAYER" for i in iss))
        self.assertIsNone(s.I.getv("*KT:REGION*"))
        r = s.eval("(kt:cmd 'ktlay:run)", [Ans("Toan")])
        self.assertGreater(len(s.issues()), len(iss))
        r = s.eval("(kt:cmd 'ktlay:run)", [Ans(None)])        # Enter = toan ban ve
        self.assertGreater(len(s.issues()), len(iss))
        # loi cap ban ve (khong vi tri) bi bo khi co vung
        r = s.eval('(kt:region-set "Model" \'(0 0) \'(10 10))'
                   '(list (kt:region-p nil "Model") (kt:region-p \'(5 5) "Model") (kt:region-p \'(5 5) "A1")'
                   '      (kt:region-p \'(11 5) "Model") (progn (kt:region-clear) (kt:region-p nil "X")))')
        from lispsim.ltypes import tolist
        self.assertEqual([x is not None for x in tolist(r.value)], [False, True, False, False, True])

    def test_dialog_window_scope(self):
        s = session()
        dlg = attach_dcl(s)
        shots = []
        snap = lambda d: shots.append(dict(d.tiles))                 # noqa: E731
        dlg.script = [[snap, ("sc_win",), ("b_run",)], [snap, ("cancel",)],
                      [snap, ("b_run",)], [snap, ("cancel",)]]
        r = s.eval("(c:KT)", [Ans(P1, "Goc thu nhat"), Ans(P2, "Goc doi dien")])
        self.assertEqual(internal_errors(r), [], r.describe_errors())
        self.assertEqual(dlg.problems, [])
        self.assertEqual(shots[0]["sc_all"], "1")
        iss = s.issues()
        self.assertTrue(iss and all(inside(i) for i in iss))
        self.assertIn("Vung (Model)", shots[1]["i_scope"])
        self.assertIn("Pham vi: Vung", shots[1]["error"])
        self.assertIsNone(s.I.getv("*KT:REGION*"))
        # lan sau: nho lua chon Chon vung; ESC khi chon cua so -> khong chay, mo lai hop thoai
        s.command("KTX")
        r = s.eval("(c:KT)", [Ans(CANCEL, "Goc thu nhat")])
        self.assertEqual(internal_errors(r), [], r.describe_errors())
        self.assertEqual(shots[2]["sc_win"], "1")
        self.assertEqual(s.issues(), [])
        self.assertIn("Da huy chon vung", shots[3]["error"])
        self.assertNotIn(("getpoint",), dlg.problems)
        self.assertEqual(dlg.problems, [])


if __name__ == "__main__":
    unittest.main()
