"""Phien chay: ban ve + VFS tam + nap cac file lisp + chay lenh voi kich ban nhap lieu.

    from lispsim import Session, Ans
    s = Session(drawing, mode="acad", lispdir="lisp")      # mode "vinacad" = khong ActiveX
    s.load_all()                                             # nap KT_Load.lsp
    r = s.command("KTALL")                                   # -> RunResult
"""
import os
import shutil
import tempfile

from .interp import Interp
from .cad import install, VFS, Ans
from .ltypes import to_str, tolist, LispError

KT_HOME = "C:\\KT\\lisp"
DWG_DIR = "C:\\DuAn"


class RunResult:
    def __init__(self, cmd, value, error, out, errors, caught, sim_bugs, prompts, commands):
        self.cmd, self.value, self.error, self.out = cmd, value, error, out
        self.errors, self.caught, self.sim_bugs = errors, caught, sim_bugs
        self.prompts, self.commands = prompts, commands

    def real_caught(self):
        """loi bi vl-catch-all-apply bat, tru loi 'no function definition: VLA-*' (du phong VinaCAD)"""
        return [e for e in self.caught if not is_vla_noise(e)]

    @property
    def ok(self):
        return self.error is None and not self.errors

    def describe_errors(self, include_caught=True):
        lines = []
        for e in self.errors:
            lines.append("LOI-KHONG-BAT [%s] %s  @%s  stack=%s" % (e.kind, e.msg, _where(e), " > ".join(e.stack or [])))
        if include_caught:
            vla = [e for e in self.caught if is_vla_noise(e)]
            if vla:
                lines.append("(%d loi ActiveX bi bat - duong du phong, bo qua)" % len(vla))
            for e in self.real_caught():
                lines.append("loi-bi-bat [%s] %s  @%s  stack=%s" % (e.kind, e.msg, _where(e), " > ".join(e.stack or [])))
        for b in self.sim_bugs:
            lines.append("SIM-BUG %s @%s stack=%s" % (b[0], b[2], " > ".join(b[1])))
        return "\n".join(lines)


def is_vla_noise(e):
    m = e.msg.upper()
    return m.startswith("NO FUNCTION DEFINITION: VLA") or "ACTIVEX SERVER RETURNED" in m


def _where(e):
    f = e.form
    if f is not None and getattr(f, "pos", None):
        return "%s:%d %s" % (f.pos[0], f.pos[1], to_str(f, True)[:90])
    return "?"


class Session:
    def __init__(self, dwg, mode="acad", lispdir=None, root=None, cfg_text=None):
        here = os.path.dirname(os.path.abspath(__file__))
        self.lispdir = lispdir or os.environ.get("LISPSIM_LISPDIR") or os.path.normpath(os.path.join(here, "..", "..", "lisp"))
        self.root = root or tempfile.mkdtemp(prefix="lispsim_")
        self.dwg = dwg
        self.mode = mode
        self.vfs = VFS(self.root, cwd=DWG_DIR, support=[KT_HOME, "C:\\KT\\Fonts"])
        for wp in (KT_HOME, DWG_DIR, "C:\\KT\\Fonts"):
            self.vfs.mkdirs(wp)
        for f in os.listdir(self.lispdir):
            src = os.path.join(self.lispdir, f)
            # KT_ChuanCongTy.txt (chuan THAT cua cong ty trong lisp/) khong chep: moi phien tu
            # quyet dinh file chuan (cfg_text / KTMAU); kich ban "chua co file chuan" van dung
            if f.lower() == "kt_chuancongty.txt":
                continue
            if os.path.isfile(src) and f.lower().endswith((".lsp", ".txt")):
                shutil.copy(src, self.vfs.host(KT_HOME + "\\" + f))
        leg = os.path.join(self.lispdir, "legacy", "CheckDimOverlap.lsp")
        if os.path.isfile(leg):
            os.makedirs(self.vfs.host(KT_HOME + "\\legacy"), exist_ok=True)
            shutil.copy(leg, self.vfs.host(KT_HOME + "\\legacy\\CheckDimOverlap.lsp"))
        for font in ("romans.shx", "vntime.shx", "hztxt.shx", "txt.shx", "simplex.shx"):
            open(self.vfs.host("C:\\KT\\Fonts\\" + font), "w").close()
        if cfg_text is not None:
            self.write_cfg(cfg_text)
        self.I = Interp()
        install(self.I, dwg, self.vfs, mode)
        self.loaded = []

    # ---------------------------------------------------------------- file
    def path(self, winpath):
        return self.vfs.host(winpath)

    def cfg_path(self):
        return self.vfs.host(KT_HOME + "\\KT_ChuanCongTy.txt")

    def write_cfg(self, text):
        with open(self.cfg_path(), "w", encoding="latin-1") as f:
            f.write(text)

    def read_cfg(self):
        p = self.cfg_path()
        if not os.path.exists(p):
            return None
        with open(p, encoding="latin-1") as f:
            return f.read()

    # ---------------------------------------------------------------- chay
    def _reset(self):
        I = self.I
        I.out, I.errors, I.caught, I.sim_bugs = [], [], [], []
        I.prompts, I.commands = [], []

    def eval(self, text, inputs=None):
        self._reset()
        self.I.inputs = list(inputs or [])
        v, err = self.I.eval_str(text)
        return RunResult(text, v, err, self.I.output(), list(self.I.errors), list(self.I.caught),
                         list(self.I.sim_bugs), list(self.I.prompts), list(self.I.commands))

    def load(self, fname):
        return self.eval('(load "%s\\\\%s")' % (KT_HOME.replace("\\", "\\\\"), fname))

    def load_all(self):
        r = self.load("KT_Load.lsp")
        self.loaded.append(r)
        return r

    def command(self, name, inputs=None):
        return self.eval("(c:%s)" % name, inputs)

    def issues(self):
        """*KT:ISSUES* -> list dict"""
        out = []
        for x in tolist(self.I.getv("*KT:ISSUES*")):
            it = tolist(x)
            ens = tolist(it[4]) if it[4] is not None else []
            out.append(dict(module=it[0], code=it[1], sev=it[2], msg=it[3],
                            ents=[e.ent for e in ens if hasattr(e, "ent")],
                            pt=tolist(it[5]), r=it[6], space=it[7]))
        return out
