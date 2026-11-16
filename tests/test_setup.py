"""Kiem thu cai dat / khoi dong bo KT (bao cao VinaCAD cua leader 11/2026).

Tinh huong that: giai nen vao C:\\KT_Tool_v1.1.1 (KHONG nam trong Support path), them MOI file .lsp
vao Startup Suite. Ban cu hoi "Nhap duong dan..." luc nap -> Startup Suite nuot cau hoi (40 dong
lap lai) -> "Chua nap bo KT". Yeu cau: luc nap KHONG BAO GIO hoi; tu do thu muc; nho cho lan sau;
lenh KTSETUP chon file 1 lan.
"""
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))

from lispsim import Session                 # noqa: E402
from lispsim.fixtures import make_mau       # noqa: E402

JUNK = ["C:\\KT_Tool_v1.1.1\\KT_Clean.lsp has been added to Startup Suite."] * 5


def loaded(s):
    v = s.I.getv("*KT:LOADED*")
    return v is not None


class T_Setup(unittest.TestCase):

    def startup(self, s):
        """nap nhu Startup Suite: co san cac dong 'rac' trong hang doi nhap lieu"""
        r = s.eval('(load "%s\\\\KT_Load.lsp")' % s.home.replace("\\", "\\\\"), JUNK)
        return r

    def test_no_prompt_and_guess_kt_tool_folder(self):
        for mode in ("lms", "acad", "vinacad"):
            env = {}
            s = Session(make_mau(), mode=mode, kt_home="C:\\KT_Tool_v1.1.1", support=False, env=env)
            r = self.startup(s)
            self.assertEqual(r.prompts, [], "%s: luc nap khong duoc hoi: %r" % (mode, r.prompts))
            self.assertEqual(len(s.I.inputs), len(JUNK), "%s: da nuot dong nhap" % mode)
            self.assertTrue(loaded(s), "%s: khong nap duoc\n%s" % (mode, r.out))
            self.assertIn("KT_Tool_v1.1.1", r.out)
            self.assertEqual(env.get("KT_HOME"), "C:\\KT_Tool_v1.1.1")
            if mode != "vinacad":          # co ActiveX -> tu them vao Support path
                self.assertIn("C:\\KT_Tool_v1.1.1", s.I.support_path)
            # lenh chinh chay duoc sau khi nap
            r2 = s.command("KTHELP")
            self.assertNotIn("Chua nap", r2.out)

    def test_unknown_folder_then_ktsetup(self):
        env = {}
        s = Session(make_mau(), mode="lms", kt_home="E:\\CongTy\\CongCu\\KiemTra", support=False, env=env)
        r = self.startup(s)
        self.assertEqual(r.prompts, [])
        self.assertEqual(len(s.I.inputs), len(JUNK))
        self.assertFalse(loaded(s))
        self.assertIn("KTSETUP", r.out)
        r = s.command("KTSETUP", ["E:\\CongTy\\CongCu\\KiemTra\\KT_Load.lsp"])
        self.assertTrue(loaded(s), r.out)
        self.assertEqual(env.get("KT_HOME"), "E:\\CongTy\\CongCu\\KiemTra")
        # khoi dong lai CAD (Session moi, cung registry) -> tu nap qua KT_HOME, khong hoi
        s2 = Session(make_mau(), mode="lms", kt_home="E:\\CongTy\\CongCu\\KiemTra", support=False, env=env)
        r = self.startup(s2)
        self.assertEqual(r.prompts, [])
        self.assertTrue(loaded(s2), r.out)
        self.assertEqual(s2.I.getv("*KT:HOME-SRC*"), "KT_HOME")

    def test_ktsetup_cancel(self):
        s = Session(make_mau(), mode="lms", kt_home="E:\\X\\Y", support=False, env={})
        self.startup(s)
        r = s.command("KTSETUP", [None, ""])
        self.assertIn("Huy", r.out)
        self.assertFalse(loaded(s))

    def test_reload_twice_quiet(self):
        """moi file trong Startup Suite: KT_Load chay lai -> 1 dong tong ket, khong loi"""
        s = Session(make_mau(), mode="lms", env={})
        s.load_all()
        r = s.load_all()
        self.assertIn("Da nap lai", r.out)
        self.assertEqual([e for e in r.errors], [])


if __name__ == "__main__":
    unittest.main()
