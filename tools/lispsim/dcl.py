"""Gia lap DCL cho lispsim: parse file .dcl + load_dialog/new_dialog/start_dialog... chay theo
KICH BAN hanh dong nguoi dung.

    from lispsim import Session
    from lispsim.dcl import attach_dcl
    s = Session(dwg, cfg_text=cfg); s.load_all()
    dlg = attach_dcl(s)                         # cai ham DCL vao trinh thong dich
    dlg.script = [                              # moi phan tu = 1 lan start_dialog
        [("m_dim", "0"), ("b_run",)],           # (key gia-tri) / (key,) = bam nut
        [("f_sev", "1"), ("l_res", "1", 4)],    # (key gia-tri reason): 4 = double-click
        [lambda d: d.tiles["t_note"], ("cancel",)],   # ham python: soi trang thai giua chung
    ]
    r = s.command("KT")
    dlg.history, dlg.problems, dlg.lists["l_res"], dlg.tiles["i_st"]

Kiem tra:
  - cu phap .dcl: ngoac nhon can bang, ';' sau thuoc tinh, kieu tile thuoc tap CO BAN
    (khong image/slide/tab...), key khong trung;
  - action_tile / set_tile / get_tile / mode_tile / start_list voi key KHONG ton tai -> problems
    (AutoCAD im lang bo qua -> bug an);
  - set_tile gia tri khong phai chuoi -> loi "bad argument type" nhu AutoCAD;
  - goi command / getxxx / entmake / entdel / entmod / zoom / setvar CTAB khi hop thoai DANG MO
    -> problems (AutoCAD cam / treo).
che do: available=False -> khong co ham DCL (CAD khong ho tro); fail_load=True -> load_dialog -1.
"""
import os
import re

from .ltypes import LispError, mklist, to_str

# tile co ban duoc phep (AutoCAD + clone). Ten prototype co san trong base.dcl:
BASIC_TILES = {"dialog", "row", "column", "boxed_row", "boxed_column", "radio_row", "radio_column",
               "boxed_radio_row", "boxed_radio_column", "button", "toggle", "radio_button",
               "popup_list", "list_box", "text", "edit_box", "spacer", "concatenation",
               "paragraph", "text_part"}
PREDEF = {  # ten tham chieu khong ':' -> (kieu, [(key, kieu)...])
    "errtile": [("error", "text")],
    "ok_only": [("accept", "button")],
    "ok_cancel": [("accept", "button"), ("cancel", "button")],
    "ok_cancel_help": [("accept", "button"), ("cancel", "button"), ("help", "button")],
    "spacer": [], "spacer_0": [], "spacer_1": [],
}
FORBIDDEN = {"image", "image_button", "slider", "tab", "tabs", "tab_strip"}

_TOK = re.compile(r'\s+|//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|[{}:;=]|[A-Za-z_@$][\w.@$-]*|-?\d+(?:\.\d+)?',
                  re.S)


class DclSyntaxError(Exception):
    pass


def tokenize(text):
    out, i, line = [], 0, 1
    while i < len(text):
        m = _TOK.match(text, i)
        if not m:
            raise DclSyntaxError("dong %d: ky tu khong hop le %r" % (line, text[i]))
        t = m.group(0)
        if not (t.isspace() or t.startswith("//") or t.startswith("/*")):
            out.append((t, line))
        line += t.count("\n")
        i = m.end()
    return out


class Tile:
    def __init__(self, typ, line):
        self.type, self.line, self.attrs, self.children = typ, line, {}, []
        self.parent = None

    def walk(self):
        yield self
        for c in self.children:
            yield from c.walk()


def parse(text):
    """-> {ten dialog: Tile}. Loi cu phap -> DclSyntaxError"""
    toks = tokenize(text)
    if text.count("{") != text.count("}"):
        # dem tho (ke ca trong chuoi) chi de bao som; parse ben duoi moi chinh xac
        pass
    pos = [0]

    def peek(k=0):
        return toks[pos[0] + k] if pos[0] + k < len(toks) else (None, toks[-1][1] if toks else 0)

    def take(expect=None):
        t = peek()
        if t[0] is None:
            raise DclSyntaxError("het file, thieu %s" % (expect or "token"))
        if expect is not None and t[0] != expect:
            raise DclSyntaxError("dong %d: can '%s' nhung gap '%s'" % (t[1], expect, t[0]))
        pos[0] += 1
        return t

    def value(tok):
        v, ln = tok
        if v.startswith('"'):
            return bytes(v[1:-1], "latin-1").decode("unicode_escape")
        if re.match(r"^-?\d+(\.\d+)?$", v):
            return float(v) if "." in v else int(v)
        return v

    def body(tile):
        take("{")
        while True:
            t, ln = peek()
            if t is None:
                raise DclSyntaxError("dong %d: tile '%s' thieu '}'" % (tile.line, tile.type))
            if t == "}":
                take()
                return
            if t == ":":
                take()
                typ, ln2 = take()
                child = Tile(typ, ln2)
                child.parent = tile
                body(child)
                tile.children.append(child)
                continue
            # ten ; (tham chieu prototype) | ten = gia tri ;
            name, ln = take()
            nxt = peek()[0]
            if nxt == ";":
                take()
                tile.children.append(Tile(name, ln))
            elif nxt == "=":
                take()
                v = take()
                if v[0] in ("{", "}", ";", ":", "="):
                    raise DclSyntaxError("dong %d: thuoc tinh '%s' thieu gia tri" % (ln, name))
                take(";")
                if name in tile.attrs:
                    raise DclSyntaxError("dong %d: thuoc tinh '%s' lap lai" % (ln, name))
                tile.attrs[name] = value(v)
            elif nxt == "{":
                child = Tile(name, ln)
                body(child)
                tile.children.append(child)
            else:
                raise DclSyntaxError("dong %d: sau '%s' can ';' hoac '=' (gap %r)" % (ln, name, nxt))

    dialogs = {}
    while pos[0] < len(toks):
        t, ln = take()
        if t == "@include":
            take()
            continue
        take(":")
        typ, ln2 = take()
        tl = Tile(typ, ln2)
        body(tl)
        if typ != "dialog":
            raise DclSyntaxError("dong %d: '%s' khong phai dialog (prototype rieng khong ho tro)" % (ln, t))
        if t in dialogs:
            raise DclSyntaxError("dong %d: dialog '%s' trung" % (ln, t))
        dialogs[t] = tl
    return dialogs


def validate(dialogs):
    """-> {dialog: {key: Tile}}; loi -> DclSyntaxError"""
    out = {}
    for name, dl in dialogs.items():
        keys = {}
        for t in dl.walk():
            if t is dl:
                if "label" not in t.attrs:
                    raise DclSyntaxError("dialog %s thieu label" % name)
                continue
            if t.type in FORBIDDEN:
                raise DclSyntaxError("dong %d: tile '%s' khong dung (VinaCAD)" % (t.line, t.type))
            if t.type in PREDEF:
                for k, typ in PREDEF[t.type]:
                    if k in keys:
                        raise DclSyntaxError("key '%s' trung (%s)" % (k, t.type))
                    nt = Tile(typ, t.line)
                    nt.attrs["key"] = k
                    keys[k] = nt
                continue
            if t.type not in BASIC_TILES:
                raise DclSyntaxError("dong %d: kieu tile la '%s'" % (t.line, t.type))
            if t.type == "list_box" and "tabs" in t.attrs:
                raise DclSyntaxError("dong %d: khong dung tabs (tu pad chuoi + fixed_width_font)" % t.line)
            k = t.attrs.get("key")
            if k is not None:
                if not isinstance(k, str):
                    raise DclSyntaxError("dong %d: key phai la chuoi" % t.line)
                if k in keys:
                    raise DclSyntaxError("dong %d: key '%s' trung" % (t.line, k))
                keys[k] = t
            elif t.type in ("button", "toggle", "popup_list", "list_box", "radio_button", "edit_box"):
                raise DclSyntaxError("dong %d: %s khong co key" % (t.line, t.type))
        out[name] = keys
    return out


class DclSim:
    BLOCK_WHILE_OPEN = ["COMMAND", "VL-CMDF", "GETSTRING", "GETKWORD", "GETPOINT", "GETREAL", "GETINT",
                        "GETDIST", "GETCORNER", "ENTSEL", "NENTSEL", "ENTMAKE", "ENTDEL", "ENTMOD",
                        "VLA-ZOOMCENTER"]

    def __init__(self, I, vfs, available=True, fail_load=False, fail_new=False):
        self.I, self.vfs = I, vfs
        self.script = []
        self.history = []          # ("load", path) ("open", dlg) ("action", key, val) ("done", st) ...
        self.problems = []
        self.files = {}            # id -> {dialog: {key: Tile}}
        self.sources = {}          # id -> text dcl
        self.next_id = 1
        self.active = None         # dict trang thai hop thoai dang mo
        self.last = None           # trang thai hop thoai vua dong (de soi)
        self.started = 0
        self.fail_load, self.fail_new = fail_load, fail_new
        self.apps = []             # startapp
        self.alerts = []
        if available:
            self._install()
        self._guard()

    # -------------------------------------------------------------- tien ich
    @property
    def tiles(self):
        st = self.active or self.last
        return st["values"] if st else {}

    @property
    def lists(self):
        st = self.active or self.last
        return st["lists"] if st else {}

    @property
    def modes(self):
        st = self.active or self.last
        return st["modes"] if st else {}

    def _need_active(self, fn):
        if self.active is None:
            raise LispError("lispsim-dcl: %s khi khong co hop thoai dang mo" % fn)
        return self.active

    def _key(self, fn, key):
        st = self._need_active(fn)
        k = self.I.str_(key)
        if k not in st["keys"]:
            self.problems.append("%s: key '%s' khong co trong dialog %s" % (fn, k, st["name"]))
            return None
        return k

    def _guard(self):
        I = self.I
        for nm in self.BLOCK_WHILE_OPEN + ["SETVAR"]:
            f = I.sym(nm).value
            if f is None:
                continue

            def mk(orig, nm=nm):
                def g(a):
                    if self.active is not None:
                        if nm != "SETVAR" or (a and isinstance(a[0], str) and a[0].upper() in ("CTAB", "TILEMODE")):
                            self.problems.append("%s goi khi hop thoai dang mo" % nm)
                    return orig.fn(a)
                return g
            I.defbi(nm, mk(f), f.amin, f.amax)
        alert = I.sym("ALERT").value

        def al(a):
            self.alerts.append(to_str(a[0]) if a else "")
            return alert.fn(a)
        I.defbi("ALERT", al, alert.amin, alert.amax)

    # -------------------------------------------------------------- ham DCL
    def _install(self):
        I = self.I
        d = I.defbi
        T = I.T

        def load_dialog(a):
            p = I.str_(a[0])
            self.history.append(("load", p))
            if self.fail_load:
                return -1
            cands = [p] if "." in p.rsplit("\\", 1)[-1] else [p + ".dcl", p]
            for c in cands:
                f = self.vfs.findfile(c)
                if f:
                    break
            else:
                return -1
            with open(self.vfs.host(f), encoding="latin-1") as fh:
                text = fh.read()
            try:
                keys = validate(parse(text))
            except DclSyntaxError as e:
                self.problems.append("DCL loi cu phap (%s): %s" % (p, e))
                return -1
            i = self.next_id
            self.next_id += 1
            self.files[i], self.sources[i] = keys, text
            return i
        d("LOAD_DIALOG", load_dialog, 1, 1)

        def unload_dialog(a):
            self.history.append(("unload", a[0]))
            self.files.pop(a[0], None)
            return None
        d("UNLOAD_DIALOG", unload_dialog, 1, 1)

        def new_dialog(a):
            name = I.str_(a[0])
            i = a[1]
            if self.active is not None:
                self.problems.append("new_dialog khi hop thoai khac dang mo")
            if i not in self.files:
                raise LispError("bad argument value: dialog id %s" % to_str(i, True))
            if self.fail_new or name not in self.files[i]:
                return None
            if len(a) > 2 and a[2] is not None:
                I.str_(a[2])
            pos = to_str(a[3]) if len(a) > 3 else None
            self.active = dict(name=name, keys=self.files[i][name], values={}, lists={}, modes={},
                               actions={}, listing=None, done=None, pos=pos)
            for k, t in self.active["keys"].items():
                v = t.attrs.get("value")
                if v is not None:
                    self.active["values"][k] = str(v)
            self.history.append(("open", name, pos))
            return T
        d("NEW_DIALOG", new_dialog, 2, 4)

        def start_dialog(a):
            st = self._need_active("start_dialog")
            self.started += 1
            steps = self.script.pop(0) if self.script else []
            if not steps:
                self.problems.append("kich ban het: hop thoai lan %d dong bang ESC" % self.started)
            try:
                for stp in steps:
                    if st["done"] is not None:
                        self.problems.append("kich ban con buoc sau khi hop thoai da dong: %r" % (stp,))
                        break
                    if callable(stp):
                        stp(self)
                        continue
                    self.user(*stp)
                if st["done"] is None:
                    self._fire("cancel", None, 1, esc=True)
                    if st["done"] is None:
                        st["done"] = 0
            finally:
                self.last, self.active = st, None
            self.history.append(("done", st["done"]))
            return st["done"]
        d("START_DIALOG", start_dialog, 0, 0)

        def done_dialog(a):
            st = self._need_active("done_dialog")
            st["done"] = a[0] if a and a[0] is not None else 1
            return mklist([100, 120])
        d("DONE_DIALOG", done_dialog, 0, 1)

        def term_dialog(a):
            if self.active is not None:
                self.active["done"] = 0
            return None
        d("TERM_DIALOG", term_dialog, 0, 0)

        def action_tile(a):
            k = self._key("action_tile", a[0])
            code = I.str_(a[1])
            if k is not None:
                self.active["actions"][k] = code
            return T
        d("ACTION_TILE", action_tile, 2, 2)

        def set_tile(a):
            k = self._key("set_tile", a[0])
            if not isinstance(a[1], str):
                raise LispError("bad argument type: stringp " + to_str(a[1], True))
            if k is not None:
                t = self.active["keys"][k]
                if t.type == "list_box" and a[1] != "":
                    n = len(self.active["lists"].get(k, []))
                    if int(a[1]) >= n:
                        self.problems.append("set_tile %s = %s vuot so dong (%d)" % (k, a[1], n))
                self.active["values"][k] = a[1]
            return a[1]
        d("SET_TILE", set_tile, 2, 2)

        def get_tile(a):
            k = self._key("get_tile", a[0])
            return self.active["values"].get(k, "") if k else ""
        d("GET_TILE", get_tile, 1, 1)

        def mode_tile(a):
            k = self._key("mode_tile", a[0])
            if k is not None:
                self.active["modes"][k] = I.int_(a[1])
            return None
        d("MODE_TILE", mode_tile, 2, 2)

        def get_attr(a):
            k = self._key("get_attr", a[0])
            v = self.active["keys"][k].attrs.get(I.str_(a[1])) if k else None
            return "" if v is None else str(v)
        d("GET_ATTR", get_attr, 2, 2)
        d("CLIENT_DATA_TILE", lambda a: (self._key("client_data_tile", a[0]), None)[1], 2, 2)

        def start_list(a):
            k = self._key("start_list", a[0])
            op = a[1] if len(a) > 1 and a[1] is not None else 3
            if k is not None and self.active["keys"][k].type not in ("list_box", "popup_list"):
                self.problems.append("start_list tren tile %s kieu %s" % (k, self.active["keys"][k].type))
            if self.active["listing"] is not None:
                self.problems.append("start_list khi chua end_list")
            if k is not None:
                if op == 3:
                    self.active["lists"][k] = []
                    self.active["values"][k] = "" if self.active["keys"][k].type == "list_box" else "0"
                self.active["lists"].setdefault(k, [])
            self.active["listing"] = k if k is not None else "?"
            return k
        d("START_LIST", start_list, 1, 3)

        def add_list(a):
            st = self._need_active("add_list")
            s = I.str_(a[0])
            if st["listing"] is None:
                self.problems.append("add_list ngoai start_list")
            elif st["listing"] != "?":
                st["lists"][st["listing"]].append(s)
            return s
        d("ADD_LIST", add_list, 1, 1)

        def end_list(a):
            st = self._need_active("end_list")
            if st["listing"] is None:
                self.problems.append("end_list khong co start_list")
            st["listing"] = None
            return None
        d("END_LIST", end_list, 0, 0)

        def startapp(a):
            self.apps.append([to_str(x) for x in a])
            return 33
        d("STARTAPP", startapp, 1, 2)

    # -------------------------------------------------------------- nguoi dung
    def user(self, key, value=None, reason=1):
        """mo phong thao tac: dat gia tri tile (neu co) roi chay action cua no"""
        st = self._need_active("user")
        if key not in st["keys"]:
            raise LispError("lispsim-dcl: kich ban bam key '%s' khong co trong dialog" % key, "sim")
        if st["modes"].get(key) == 1:
            raise LispError("lispsim-dcl: kich ban bam tile '%s' dang bi vo hieu (mode_tile 1)" % key, "sim")
        t = st["keys"][key]
        if value is not None:
            value = str(value)
            if t.type in ("list_box", "popup_list"):
                n = len(st["lists"].get(key, []))
                if not (0 <= int(value) < n):
                    raise LispError("lispsim-dcl: chon dong %s ngoai danh sach %s (%d dong)" % (value, key, n), "sim")
            st["values"][key] = value
        elif t.type == "toggle":
            st["values"][key] = "0" if st["values"].get(key, "0") == "1" else "1"
        if t.type == "radio_button":
            value = "1" if value is None else value
            st["values"][key] = value
            if value == "1" and t.parent is not None:
                for sib in t.parent.children:
                    k2 = sib.attrs.get("key")
                    if sib.type == "radio_button" and k2 and k2 != key:
                        st["values"][k2] = "0"
                if t.parent.attrs.get("key"):
                    st["values"][t.parent.attrs["key"]] = key
        self._fire(key, st["values"].get(key, ""), reason)

    def _fire(self, key, value, reason, esc=False):
        st = self.active
        self.history.append(("action", key, value) if not esc else ("esc",))
        code = st["actions"].get(key)
        if code is None:
            t = st["keys"].get(key)
            if t is not None and (t.attrs.get("is_cancel") == "true" or key == "cancel"):
                st["done"] = 0
            elif t is not None and (t.attrs.get("is_default") == "true" or key == "accept"):
                st["done"] = 1
            return
        I = self.I
        I.setv("$KEY", key)
        I.setv("$VALUE", value if value is not None else "")
        I.setv("$REASON", reason)
        I.setv("$DATA", None)
        I.load_text(code, "<action_tile %s>" % key)


def attach_dcl(session, **kw):
    """cai DclSim vao Session (sau Session(...), truoc/sau load_all deu duoc)"""
    sim = DclSim(session.I, session.vfs, **kw)
    session.dcl = sim
    # thu muc TEMP cho vl-filename-mktemp gia lap (C:\\Temp\\...)
    session.vfs.mkdirs("C:\\Temp")
    return sim
