"""Kiem thu hop thoai KT (KT_Dialog.lsp) bang lispsim + gia lap DCL (tools/lispsim/dcl.py).

    python3 -m unittest tests/test_dialog.py -v

Kich ban mo phong nguoi dung: moi phan tu cua dlg.script = 1 lan start_dialog, gom cac buoc
(key gia-tri [reason]) / (key,) = bam nut / ham python (soi trang thai khi hop thoai dang mo).
"""
import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, HERE)

from lispsim import Session, Ans                                   # noqa: E402
from lispsim.dcl import attach_dcl, parse, validate, DclSyntaxError  # noqa: E402
from lispsim.fixtures import make_nhanvien, make_mau                # noqa: E402
from test_runtime import mau_cfg, internal_errors, MAU_INPUTS       # noqa: E402
import lisplint                                                     # noqa: E402

SEVS = ("LOI", "CANHBAO", "GOIY")


def session(mode="acad", cfg=True, dwg=None, **kw):
    d = dwg or make_nhanvien()[0]
    s = Session(d, mode=mode, cfg_text=(mau_cfg()[3] if cfg else None))
    s.load_all()
    dlg = attach_dcl(s, **kw)
    return s, dlg


def zooms(r):
    return [c for c in r.commands if c and (c[0] == "ZoomCenter" or c[0].strip('"').upper() == "_.ZOOM")]


class Snap:
    """ham kich ban: chup trang thai hop thoai dang mo"""

    def __init__(self):
        self.shots = []

    def __call__(self, d):
        self.shots.append(dict(tiles=dict(d.tiles), lists={k: list(v) for k, v in d.lists.items()},
                               modes=dict(d.modes)))


class T1_DclFile(unittest.TestCase):
    def test_generated_dcl_valid_and_matches_reference(self):
        s, dlg = session()
        r = s.command("KT")                    # kich ban rong -> ESC
        self.assertEqual(internal_errors(r), [], r.describe_errors())
        self.assertEqual(dlg.problems[:1], ["kich ban het: hop thoai lan 1 dong bang ESC"])
        self.assertEqual(len(dlg.sources), 1)
        src = list(dlg.sources.values())[0]
        keys = validate(parse(src))["kt_main"]
        for k in ("m_lay", "m_txt", "m_dim", "m_sh", "m_mat", "m_cl", "b_all", "b_none", "b_run",
                  "i_cfg", "i_st", "i_frm", "i_res", "l_sum", "f_sev", "f_mod", "f_sp", "l_res",
                  "b_view", "b_prev", "b_next", "b_csv", "b_clr", "b_mau", "b_cfg", "b_open",
                  "b_help", "cancel", "error", "o_pause"):
            self.assertIn(k, keys)
        self.assertEqual(keys["l_res"].attrs.get("fixed_width_font"), "true")
        ver = s.I.getv("*KT:VER*")
        self.assertIn('label = "KIEM TRA HO SO BAN VE - KT v%s";' % ver, src)
        self.assertTrue(all(ord(c) < 128 for c in src))
        # file tham khao lisp/KT_Dialog.dcl giong ban sinh (tru dong ghi chu dau + so phien ban)
        with open(os.path.join(ROOT, "lisp", "KT_Dialog.dcl"), encoding="latin-1") as fh:
            ref = fh.read().replace("\r\n", "\n").split("\n")
        gen = src.replace("\r\n", "\n").split("\n")
        ref = [re.sub(r"KT v[\d.]+", "KT v" + ver, x) for x in ref]
        self.assertEqual(ref[1:], gen[1:], "lisp/KT_Dialog.dcl lech voi ban sinh boi KT_Dialog.lsp")
        # file tam duoc xoa sau khi dong
        self.assertIn(("unload", 1), dlg.history)

    def test_parser_rejects_bad_dcl(self):
        good = 'd : dialog { label = "x"; : button { key = "a"; label = "A"; } errtile; }'
        validate(parse(good))
        for bad in ['d : dialog { label = "x"; : button { key = "a"; } ',          # thieu }
                    'd : dialog { label = "x"; : button { key = "a" } }',          # thieu ;
                    'd : dialog { label = "x"; : image { key = "a"; } }',          # tile cam
                    'd : dialog { label = "x"; : button { key = "a"; } : toggle { key = "a"; } }',
                    'd : dialog { label = "x"; : list_box { key = "l"; tabs = "4 8"; } }',
                    'd : dialog { label = "x"; : bogus { key = "a"; } }',
                    'd : dialog { : button { key = "a"; } }']:                     # thieu label
            with self.assertRaises(DclSyntaxError, msg=bad):
                validate(parse(bad))

    def test_lint_clean(self):
        p = os.path.join(ROOT, "lisp", "KT_Dialog.lsp")
        issues, _ = lisplint.lint_paths([os.path.join(ROOT, "lisp")], "WARN")
        mine = [i.fmt() for i in issues if i.file.endswith("KT_Dialog.lsp")]
        self.assertEqual(mine, [])
        with open(p, "rb") as fh:
            self.assertTrue(all(b < 128 for b in fh.read()), "KT_Dialog.lsp phai thuan ASCII")


class T2_Flow(unittest.TestCase):
    """mo -> chon module -> Kiem tra -> loc -> Xem (zoom, mo lai) -> Loi sau/truoc -> CSV -> Dong"""

    def test_full_flow(self):
        for mode in ("acad", "vinacad"):
            with self.subTest(mode=mode):
                self.run_flow(mode)

    def run_flow(self, mode):
        s, dlg = session(mode)
        snap = Snap()
        dlg.script = [
            [snap, ("b_none",), ("b_run",), snap,                         # 0: khong chon -> bao loi
             ("m_lay", "1"), ("m_txt", "1"), ("m_sh", "1"), ("m_mat", "1"), ("m_cl", "1"),
             ("b_run",)],
            [snap, ("f_sev", "1"), snap, ("l_res", "2", 4)],              # loc LOI, double-click dong 2
            [snap, ("b_next",)],
            [snap, ("b_prev",)],
            [snap, ("f_mod", "0"), ("b_csv",), snap, ("cancel",)],
        ]
        r = s.command("KT")
        self.assertEqual(internal_errors(r), [], r.describe_errors())
        self.assertEqual(dlg.problems, [])
        self.assertEqual([h[1] for h in dlg.history if h[0] == "done"], [2, 3, 3, 3, 0])
        self.assertEqual(len([h for h in dlg.history if h[0] == "open"]), 5)
        sh = snap.shots
        # lan mo dau: chua co ket qua, cac nut xem bi vo hieu
        self.assertIn("Chua co ket qua", sh[0]["tiles"]["t_note"])
        self.assertEqual(sh[0]["modes"]["b_view"], 1)
        self.assertIn("DA NAP", sh[0]["tiles"]["i_st"])
        self.assertRegex(sh[0]["tiles"]["i_frm"], r"Khung ten tim thay: [1-9]")
        self.assertIn("Chua chon module", sh[1]["tiles"]["error"])
        # sau khi kiem tra: DIM khong chay (da bo chon)
        iss = s.issues()
        self.assertGreater(len(iss), 5)
        mods = {i["module"] for i in iss}
        self.assertNotIn("DIM", mods)
        self.assertEqual(s.I.getv("*KT:DLG-MODS*").car, "1")
        res = sh[2]["lists"]["l_res"]
        self.assertTrue(res[0].lstrip().startswith("STT"))
        self.assertEqual(len(res), len(iss) + 1)
        summ = sh[2]["lists"]["l_sum"]
        tot = [x for x in summ if x.startswith("TONG")][0].split()
        self.assertEqual(int(tot[-1]), len(iss))
        self.assertEqual([int(x) for x in tot[1:4]], [sum(1 for i in iss if i["sev"] == v) for v in SEVS])
        # loc LOI: moi dong deu LOI
        loi = [k for k, i in enumerate(iss) if i["sev"] == "LOI"]
        self.assertGreaterEqual(len(loi), 3)
        rows = sh[3]["lists"]["l_res"][1:]
        self.assertEqual(len(rows), len(loi))
        self.assertTrue(all(row.split()[1] == "LOI" for row in rows))
        self.assertEqual([int(row.split()[0]) - 1 for row in rows], loi)     # STT = chi so goc + 1
        # double-click dong 2 (= LOI thu 2) -> zoom toi dung muc goc
        self.assertEqual(sh[4]["tiles"]["f_sev"], "1")                        # bo loc giu nguyen
        self.assertEqual(sh[4]["tiles"]["l_res"], "2")                        # dong chon giu nguyen
        self.assertIn("Loi %d/%d" % (loi[1] + 1, len(iss)), sh[4]["tiles"]["error"])
        self.assertIn("Loi %d/%d" % (loi[1] + 1, len(iss)), r.out)
        # Loi sau -> LOI thu 3, Loi truoc -> LOI thu 2
        self.assertEqual(sh[5]["tiles"]["l_res"], "3")
        self.assertIn("Loi %d/%d" % (loi[2] + 1, len(iss)), sh[5]["tiles"]["error"])
        self.assertEqual(sh[6]["tiles"]["l_res"], "2")
        self.assertEqual(s.I.getv("*KT:IDX*"), loi[1])
        self.assertGreaterEqual(len(zooms(r)), 3, r.commands)
        self.assertEqual(r.prompts.count("\n[KT] Da zoom toi loi. Nhan Enter de quay lai hop thoai KT..."),
                         sum(1 for k in (loi[1], loi[2], loi[1]) if iss[k]["pt"]))
        # vi tri hop thoai giu lai
        opens = [h for h in dlg.history if h[0] == "open"]
        self.assertIsNone(opens[0][2])
        self.assertEqual(opens[1][2], "(100 120)")
        # CSV
        self.assertIn("Da xuat CSV", sh[7]["tiles"]["error"])
        self.assertTrue(os.path.exists(s.path("C:\\DuAn\\NHANVIEN_KiemTra.csv")))
        self.assertEqual(s.dwg.violations, [])

    def test_filter_module_space_and_selection_persist(self):
        s, dlg = session()
        snap = Snap()
        dlg.script = [[("b_run",)], [snap, ("cancel",)]]
        s.command("KT")
        iss = s.issues()
        labels = snap.shots[0]["lists"]["f_mod"]
        self.assertEqual(labels[0], "Tat ca")
        k = [n for n, x in enumerate(labels) if x.startswith("KHUNG")][0]
        want = [n for n, i in enumerate(iss) if i["module"] == "KHUNG"]
        self.assertEqual(labels[k], "KHUNG (%d)" % len(want))
        sp = snap.shots[0]["lists"]["f_sp"]
        self.assertEqual(sp[0], "Tat ca")
        # lan goi KT moi: bo loc module giu trong phien
        snap2 = Snap()
        dlg.script = [[("f_mod", str(k)), ("l_res", "1"), snap2, ("cancel",)], [snap2, ("cancel",)]]
        r = s.command("KT")
        self.assertEqual(internal_errors(r), [], r.describe_errors())
        rows = snap2.shots[0]["lists"]["l_res"][1:]
        self.assertEqual([int(x.split()[0]) - 1 for x in rows], want)
        self.assertIn("#%d [" % (want[0] + 1), snap2.shots[0]["tiles"]["t_note"])
        r = s.command("KT")
        self.assertEqual(snap2.shots[1]["tiles"]["f_mod"], str(k))
        self.assertEqual(s.I.getv("*KT:DLG-FMOD*"), "KHUNG")
        self.assertEqual(s.I.getv("*KT:DLG-SEL*"), want[0])
        self.assertEqual(snap2.shots[1]["tiles"]["l_res"], "1")

    def test_row_limit_note(self):
        s, dlg = session()
        s.eval("(setq *KT:DLG-MAXROW* 3)")
        snap = Snap()
        dlg.script = [[("b_run",)], [snap, ("l_res", "4"), snap, ("b_none",), ("b_run",)]]
        r = s.command("KT")
        self.assertEqual(internal_errors(r), [])
        self.assertEqual(dlg.problems, [])
        n = len(s.issues())
        rows = snap.shots[0]["lists"]["l_res"]
        self.assertEqual(len(rows), 5)                       # tieu de + 3 + ghi chu
        self.assertIn("con %d muc nua" % (n - 3), rows[4])
        self.assertEqual(snap.shots[1]["tiles"]["t_note"], snap.shots[0]["tiles"]["t_note"])
        s.eval("(setq *KT:DLG-SEL* nil)")
        dlg.script = [[snap, ("cancel",)]]
        s.command("KT")
        self.assertRegex(snap.shots[2]["tiles"]["t_note"], r"Hien 3/%d muc dau" % n)

    def test_clear_reload_open_help(self):
        s, dlg = session()
        snap = Snap()
        dlg.script = [[("b_run",)], [("b_open",), snap, ("b_help",), ("b_clr",)],
                      [snap, ("b_cfg",)], [snap, ("cancel",)]]
        r = s.command("KT")
        self.assertEqual(internal_errors(r), [], r.describe_errors())
        self.assertEqual(dlg.problems, [])
        self.assertEqual(dlg.apps[0][0], "notepad")
        self.assertIn("KT_ChuanCongTy.txt", dlg.apps[0][1])
        self.assertIn("Notepad", snap.shots[0]["tiles"]["error"])
        self.assertEqual(len(dlg.alerts), 1)
        self.assertIn("KTMAU", dlg.alerts[0])
        self.assertEqual(s.issues(), [])
        self.assertIn("Da xoa danh dau", snap.shots[1]["tiles"]["error"])
        self.assertEqual(snap.shots[1]["modes"]["b_view"], 1)
        self.assertIn("Da nap lai", snap.shots[2]["tiles"]["error"])


class T3_NoCfg_KTMAU(unittest.TestCase):
    def test_no_cfg_then_ktmau(self):
        s, dlg = session(cfg=False, dwg=make_mau())
        snap = Snap()
        dlg.script = [[snap, ("b_open",), snap, ("b_mau",)], [snap, ("cancel",)]]
        r = s.eval("(c:KT)", MAU_INPUTS)
        self.assertEqual(internal_errors(r), [], r.describe_errors())
        self.assertEqual(dlg.problems, [])
        self.assertIn("CHUA CO CHUAN", snap.shots[0]["tiles"]["i_st"])
        self.assertIn("KTMAU", snap.shots[1]["tiles"]["error"])
        self.assertEqual(dlg.apps, [])
        self.assertIsNotNone(s.read_cfg())
        self.assertIn("DA NAP", snap.shots[2]["tiles"]["i_st"])


class T4_Fallback(unittest.TestCase):
    def check(self, **kw):
        s, dlg = session(**kw)
        r = s.command("KT")
        self.assertEqual(internal_errors(r), [], r.describe_errors())
        self.assertIn("che do DONG LENH", r.out)
        self.assertIn("KTALL", r.out)
        self.assertIn("KTN", r.out)
        self.assertGreater(len(s.issues()), 5)          # Enter = Co -> KTALL da chay
        return s, dlg, r

    def test_no_dcl_functions(self):
        s, dlg, r = self.check(available=False)
        self.assertIn("load_dialog", r.out)

    def test_load_dialog_fails(self):
        s, dlg, r = self.check(fail_load=True)
        self.assertTrue(all(h[0] == "load" for h in dlg.history))

    def test_new_dialog_fails(self):
        s, dlg, r = self.check(fail_new=True)
        self.assertIn("new_dialog that bai", r.out)
        self.assertIn(("unload", 1), dlg.history)

    def test_fallback_answer_no(self):
        s, dlg = session(available=False)
        r = s.eval("(c:KT)", [Ans("Khong", "KTALL")])
        self.assertEqual(internal_errors(r), [])
        self.assertEqual(s.issues(), [])

    def test_alias_and_help(self):
        s, dlg = session()
        r = s.command("KTDLG")
        self.assertEqual(internal_errors(r), [])
        self.assertIn(("open", "kt_main", None), dlg.history)
        r = s.command("KTHELP")
        self.assertIn("KT      : MO HOP THOAI", r.out)
        self.assertNotIn("KT      : MO HOP THOAI tong hop (chon module, kiem tra, loc, xem loi)   (chua nap)",
                         r.out)


if __name__ == "__main__":
    unittest.main()
