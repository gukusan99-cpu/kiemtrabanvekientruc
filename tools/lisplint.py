#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""lisplint - kiem tra tinh (static check) cho ma AutoLISP / Visual LISP.

Dung:  python3 tools/lisplint.py <file.lsp|thu_muc> [...] [--json] [--min-level LEVEL]

Exit code: 0 = khong co ERROR, 1 = co ERROR, 2 = loi su dung (khong tim thay file...).
Dinh dang dau ra:  file:dong: MUC: thong diep [MA]

Chi dung thu vien chuan Python 3.
Chi thi trong comment cua file .lsp:
    ; lisplint: extern TEN1 TEN2   -> khai bao ham ngoai (nap tu thu vien khac)
    ; lisplint: ignore             -> bo qua moi canh bao tren dong nay
    ; lisplint: ignore=LEAK,RISKY  -> bo qua cac ma loi chi dinh tren dong nay
"""

# =====================================================================
# DANH SACH HAM RUI RO KHI CHAY TREN VINACAD / INTELLICAD  (de sua)
# (mau fnmatch, chu thuong) -> ghi chu.  Ham khop mau duoc coi la "ton tai"
# (khong bao loi chua dinh nghia) nhung bi canh bao WARN.
# =====================================================================
RISKY_FUNCTIONS = [
    ("acet-*", "Express Tools (acet-*) thuong KHONG co tren VinaCAD/IntelliCAD; can viet ham thay the"),
    ("dos_*", "DOSLib (dos_*) phai cai rieng, co the khong co tren may nguoi dung"),
    ("getpropertyvalue", "co the khong ho tro tren VinaCAD/IntelliCAD/AutoCAD cu (<2012); nen dung entget/vla- co fallback"),
    ("setpropertyvalue", "co the khong ho tro tren VinaCAD/IntelliCAD/AutoCAD cu (<2012); nen dung entmod/vla- co fallback"),
    ("ispropertyreadonly", "co the khong ho tro tren VinaCAD/IntelliCAD"),
    ("dumpallproperties", "co the khong ho tro tren VinaCAD/IntelliCAD"),
    ("vlax-curve-*", "vlax-curve-* co the khong ho tro day du tren VinaCAD/IntelliCAD; can kiem thu hoac co fallback hinh hoc"),
    ("vl-registry-*", "truy cap registry co the khac/khong ho tro tren VinaCAD/IntelliCAD"),
    ("vlr-*", "reactor (vlr-*) thuong khong ho tro hoac hanh vi khac tren VinaCAD/IntelliCAD"),
    ("command-s", "command-s chi co tu AutoCAD 2015, co the khong co tren VinaCAD/IntelliCAD; dung (command ...) hoac vl-cmdf"),
    ("vla-get-*", "thuoc tinh ActiveX co the khac ten/khong co tren VinaCAD; nen co fallback (entget / vl-catch-all-apply)"),
    ("vla-put-*", "thuoc tinh ActiveX co the khac ten/khong co tren VinaCAD; nen co fallback (entmod / vl-catch-all-apply)"),
]

import argparse
import fnmatch
import json
import os
import re
import sys

LEVELS = {"INFO": 0, "WARN": 1, "ERROR": 2}

# =====================================================================
# DANH SACH BUILT-IN AutoLISP / Visual LISP
# =====================================================================
_CORE = """
+ - * / = /= < <= > >= ~ 1+ 1-
abs acad_colordlg acad_helpdlg acad_strlsort acad_truecolorcli acad_truecolordlg
acad-pop-dbmod acad-push-dbmod acdimenableupdate action_tile add_list alert alloc and
angle angtof angtos append apply arx arxload arxunload ascii assoc atan atof atoi atom
atoms-family autoarxload autoload boole boundp
car cdr caar cadr cdar cddr caaar caadr cadar caddr cdaar cdadr cddar cdddr
caaaar caaadr caadar caaddr cadaar cadadr caddar cadddr
cdaaar cdaadr cdadar cdaddr cddaar cddadr cdddar cddddr
chr client_data_tile close command command-s cond cons cos cvunit
defun defun-q defun-q-list-ref defun-q-list-set dictadd dictnext dictremove dictrename
dictsearch dimx_tile dimy_tile distance distof done_dialog dumpallproperties
end_image end_list entdel entget entlast entmake entmakex entmod entnext entsel entupd
eq equal *error* eval exit exp expand expt
fill_image findfile findtrustedfile fix float foreach function
gc gcd get_attr get_tile getangle getcfg getcname getcorner getdist getenv getfiled
getint getkword getorient getpoint getpropertyvalue getreal getstring getvar graphscr
grclear grdraw grread grtext grvecs
handent help if initcommandversion initdia initget inters ispropertyreadonly itoa
lambda last layoutlist layerstate-addlayers layerstate-compare layerstate-delete
layerstate-export layerstate-getlastrestored layerstate-getlayers layerstate-getnames
layerstate-has layerstate-import layerstate-importfromdb layerstate-removelayers
layerstate-rename layerstate-restore layerstate-save length list listp load
load_dialog log logand logior lsh
mapcar max mem member menucmd menugroup min minusp mode_tile
namedobjdict nentsel nentselp new_dialog not nth null numberp
open or osnap polar prin1 princ print progn prompt quit quote
read read-char read-line redraw regapp rem repeat reverse rtos
set set_tile setcfg setenv setfunhelp setpropertyvalue setq setvar setview sin
slide_image snvalid sqrt ssadd ssdel ssget ssgetfirst sslength ssmemb ssname ssnamex
sssetfirst startapp start_dialog start_image start_list strcase strcat strlen subst
substr tablet tblnext tblobjname tblsearch term_dialog terpri textbox textpage textscr
trace trans type unload_dialog untrace vector_image ver vports
wcmatch while write-char write-line xdroom xdsize zerop
vlisp-compile vlisp-export-symbol vlisp-import-symbol
"""

_VL = """
vl-acad-defun vl-acad-undefun vl-arx-import vl-bb-ref vl-bb-set vl-bt
vl-catch-all-apply vl-catch-all-error-message vl-catch-all-error-p vl-cmdf vl-consp
vl-directory-files vl-doc-export vl-doc-import vl-doc-ref vl-doc-set vl-every
vl-exit-with-error vl-exit-with-value vl-file-copy vl-file-delete vl-file-directory-p
vl-file-rename vl-file-size vl-file-systime vl-filename-base vl-filename-directory
vl-filename-extension vl-filename-mktemp vl-get-resource vl-infp vl-list*
vl-list->string vl-list-exported-functions vl-list-length vl-list-loaded-vlx
vl-load-all vl-load-com vl-load-reactors vl-mkdir vl-member-if vl-member-if-not vl-nanp
vl-position vl-prin1-to-string vl-princ-to-string vl-propagate vl-registry-delete
vl-registry-descendents vl-registry-read vl-registry-write vl-remove vl-remove-if
vl-remove-if-not vl-some vl-sort vl-sort-i vl-string->list vl-string-elt
vl-string-left-trim vl-string-mismatch vl-string-position vl-string-right-trim
vl-string-search vl-string-subst vl-string-translate vl-string-trim vl-symbol-name
vl-symbol-value vl-symbolp vl-unload-vlx vl-vbaload vl-vbarun vl-vlx-loaded-p
vl-annotative-get vl-annotative-set vl-annotative-get-scales vl-annotative-add-scale
vl-annotative-remove-scale
"""

_VLAX = """
vlax-3d-point vlax-add-cmd vlax-create-object
vlax-curve-getarea vlax-curve-getclosestpointto vlax-curve-getclosestpointtoprojection
vlax-curve-getdistatparam vlax-curve-getdistatpoint vlax-curve-getendparam
vlax-curve-getendpoint vlax-curve-getfirstderiv vlax-curve-getparamatdist
vlax-curve-getparamatpoint vlax-curve-getpointatdist vlax-curve-getpointatparam
vlax-curve-getsecondderiv vlax-curve-getstartparam vlax-curve-getstartpoint
vlax-curve-isclosed vlax-curve-isperiodic vlax-curve-isplanar
vlax-dump-object vlax-ename->vla-object vlax-erased-p vlax-for vlax-get
vlax-get-acad-object vlax-get-object vlax-get-or-create-object vlax-get-property
vlax-import-type-library vlax-invoke vlax-invoke-method vlax-ldata-delete
vlax-ldata-get vlax-ldata-list vlax-ldata-put vlax-ldata-test vlax-machine-product-key
vlax-make-safearray vlax-make-variant vlax-map-collection vlax-method-applicable-p
vlax-object-released-p vlax-product-key vlax-property-available-p vlax-put
vlax-put-property vlax-read-enabled-p vlax-release-object vlax-remove-cmd
vlax-safearray->list vlax-safearray-fill vlax-safearray-get-dim
vlax-safearray-get-element vlax-safearray-get-l-bound vlax-safearray-get-u-bound
vlax-safearray-put-element vlax-safearray-type vlax-tmatrix vlax-typeinfo-available-p
vlax-user-product-key vlax-variant-change-type vlax-variant-type vlax-variant-value
vlax-vla-object->ename vlax-write-enabled-p
"""

BUILTINS = set(_CORE.split()) | set(_VL.split()) | set(_VLAX.split())

# Ham nhan ham lam doi so: ten -> vi tri (0-based trong danh sach doi so) cua doi so ham
FUNARG_POS = {
    "mapcar": 0, "apply": 0, "vl-catch-all-apply": 0, "vl-member-if": 0,
    "vl-member-if-not": 0, "vl-remove-if": 0, "vl-remove-if-not": 0, "vl-some": 0,
    "vl-every": 0, "vl-sort": 1, "vl-sort-i": 1,
}

# So tham so (min, max) cua mot so built-in thong dung (max=None: khong gioi han).
BUILTIN_ARITY = {
    "if": (2, 3), "car": (1, 1), "cdr": (1, 1), "cadr": (1, 1), "caddr": (1, 1),
    "cddr": (1, 1), "caar": (1, 1), "cdar": (1, 1), "cadddr": (1, 1),
    "cons": (2, 2), "assoc": (2, 2), "nth": (2, 2), "member": (2, 2), "subst": (3, 3),
    "distance": (2, 2), "angle": (2, 2), "polar": (3, 3), "inters": (4, 5),
    "entget": (1, 2), "entnext": (0, 1), "entdel": (1, 1), "entmod": (1, 1),
    "entupd": (1, 1), "entmake": (0, 1), "entmakex": (0, 1), "entlast": (0, 0),
    "sslength": (1, 1), "ssname": (2, 2), "ssadd": (0, 2), "ssdel": (2, 2),
    "ssmemb": (2, 2), "sssetfirst": (1, 2), "ssget": (0, 5),
    "itoa": (1, 1), "atoi": (1, 1), "atof": (1, 1), "rtos": (1, 3), "angtos": (1, 3),
    "substr": (2, 3), "strcase": (1, 2), "abs": (1, 1), "not": (1, 1), "null": (1, 1),
    "length": (1, 1), "reverse": (1, 1), "last": (1, 1), "float": (1, 1), "fix": (1, 1),
    "sqrt": (1, 1), "sin": (1, 1), "cos": (1, 1), "atan": (1, 2), "exp": (1, 1),
    "log": (1, 1), "expt": (2, 2), "1+": (1, 1), "1-": (1, 1), "zerop": (1, 1),
    "minusp": (1, 1), "numberp": (1, 1), "listp": (1, 1), "atom": (1, 1), "type": (1, 1),
    "getvar": (1, 1), "setvar": (2, 2), "tblsearch": (2, 3), "tblobjname": (2, 2),
    "tblnext": (1, 2), "textbox": (1, 1), "trans": (3, 4), "wcmatch": (2, 2),
    "eq": (2, 2), "equal": (2, 3), "chr": (1, 1), "ascii": (1, 1), "read": (0, 1),
    "eval": (1, 1), "boundp": (1, 1), "quote": (1, 1), "function": (1, 1),
    "apply": (2, 2), "mapcar": (2, None), "vl-sort": (2, 2), "vl-sort-i": (2, 2),
    "vl-position": (2, 2), "vl-remove": (2, 2), "vl-remove-if": (2, 2),
    "vl-remove-if-not": (2, 2), "vl-member-if": (2, 2), "vl-member-if-not": (2, 2),
    "vl-catch-all-apply": (2, 2), "vl-catch-all-error-p": (1, 1),
    "vl-catch-all-error-message": (1, 1), "vl-string-search": (2, 3),
    "vl-string-subst": (3, 4), "vl-string-trim": (2, 2), "vl-load-com": (0, 0),
    "vlax-get-acad-object": (0, 0), "vlax-ename->vla-object": (1, 1),
    "vlax-vla-object->ename": (1, 1), "vlax-3d-point": (1, 3), "findfile": (1, 1),
    "open": (2, 3), "close": (1, 1), "read-line": (0, 1), "write-line": (1, 2),
    "repeat": (1, None), "while": (1, None), "foreach": (2, None), "setq": (0, None),
    "princ": (0, 2), "prin1": (0, 2), "print": (0, 2), "alert": (1, 1),
    "getreal": (0, 1), "getint": (0, 1), "getstring": (0, 2), "getpoint": (0, 2),
    "getdist": (0, 2), "getangle": (0, 2), "getkword": (0, 1), "initget": (0, 2),
    "entsel": (0, 1), "nentsel": (0, 1), "handent": (1, 1), "rem": (1, None),
    # DCL
    "load_dialog": (1, 1), "unload_dialog": (1, 1), "new_dialog": (2, 4), "start_dialog": (0, 0),
    "done_dialog": (0, 1), "term_dialog": (0, 0), "action_tile": (2, 2), "set_tile": (2, 2),
    "get_tile": (1, 1), "mode_tile": (2, 2), "get_attr": (2, 2), "client_data_tile": (2, 2),
    "start_list": (1, 3), "add_list": (1, 1), "end_list": (0, 0), "startapp": (1, 2),
}

# Bien do DCL dat khi chay bieu thuc action_tile (chi hop le BEN TRONG chuoi action)
DCL_ACTION_VARS = {"$key", "$value", "$reason", "$data", "$x", "$y"}
# ham ma doi so thu k (0-based) la CHUOI MA LISP se duoc eval (DCL callback)
CODE_STRING_ARG = {"action_tile": 1, "new_dialog": 2}

ACTIVEX_PREFIXES = ("vla-", "vlax-")


class Issue:
    __slots__ = ("file", "line", "level", "code", "msg")

    def __init__(self, file, line, level, code, msg):
        self.file, self.line, self.level, self.code, self.msg = file, line, level, code, msg

    def fmt(self):
        return "%s:%d: %s: %s [%s]" % (self.file, self.line, self.level, self.msg, self.code)

    def as_dict(self):
        return {"file": self.file, "line": self.line, "level": self.level,
                "code": self.code, "message": self.msg}


# =====================================================================
# TOKENIZER
# =====================================================================
class Tok:
    __slots__ = ("kind", "val", "line", "col")

    def __init__(self, kind, val, line, col):
        self.kind, self.val, self.line, self.col = kind, val, line, col

    def __repr__(self):
        return "Tok(%s,%r,%d)" % (self.kind, self.val, self.line)


_DELIMS = set(" \t\r\n\f\v()'\";")
_NUM_RE = re.compile(r"^[+-]?(\d+\.?\d*([eE][+-]?\d+)?|\.\d+([eE][+-]?\d+)?)$")
_DIRECTIVE_RE = re.compile(r"lisplint\s*:\s*(extern|ignore)(?:\s*=\s*([\w,\- ]+)|\s+([^\r\n]*))?",
                           re.IGNORECASE)


def tokenize(text, fname, issues, directives):
    """Tra ve danh sach Tok: LP RP QUOTE STR SYM NUM DOT.
    directives: dict {'extern': set(), 'ignore': {line: set(codes)|None}} duoc cap nhat."""
    toks = []
    i, n, line, col0 = 0, len(text), 1, 0  # col0 = vi tri dau dong hien tai

    def handle_comment(body, cline):
        for m in _DIRECTIVE_RE.finditer(body):
            kind = m.group(1).lower()
            if kind == "extern":
                rest = (m.group(3) or m.group(2) or "")
                for name in rest.replace(",", " ").split():
                    directives["extern"].add(name.lower())
            else:
                codes = m.group(2)
                if codes:
                    s = set(c.strip().upper() for c in codes.split(",") if c.strip())
                    prev = directives["ignore"].get(cline, set())
                    if prev is not None:
                        directives["ignore"][cline] = prev | s
                else:
                    directives["ignore"][cline] = None  # None = bo qua tat ca

    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
            col0 = i
            continue
        if c in " \t\r\f\v":
            i += 1
            continue
        if c == ";":
            if i + 1 < n and text[i + 1] == "|":
                start_line = line
                j = text.find("|;", i + 2)
                if j < 0:
                    issues.append(Issue(fname, start_line, "ERROR", "COMMENT",
                                        "comment khoi ';|' chua dong bang '|;'"))
                    body = text[i:]
                    handle_comment(body, start_line)
                    line += body.count("\n")
                    i = n
                    break
                body = text[i:j + 2]
                handle_comment(body, start_line)
                nl = body.count("\n")
                if nl:
                    line += nl
                    col0 = i + body.rfind("\n") + 1
                i = j + 2
                continue
            j = text.find("\n", i)
            if j < 0:
                j = n
            handle_comment(text[i:j], line)
            i = j
            continue
        if c == "(":
            toks.append(Tok("LP", "(", line, i - col0))
            i += 1
            continue
        if c == ")":
            toks.append(Tok("RP", ")", line, i - col0))
            i += 1
            continue
        if c == "'":
            toks.append(Tok("QUOTE", "'", line, i - col0))
            i += 1
            continue
        if c == '"':
            start_line, start_col = line, i - col0
            j = i + 1
            buf = []
            closed = False
            while j < n:
                ch = text[j]
                if ch == "\\" and j + 1 < n:
                    nxt = text[j + 1]
                    if nxt == "\n":
                        line += 1
                        col0 = j + 2
                    buf.append(ch + nxt)
                    j += 2
                    continue
                if ch == '"':
                    closed = True
                    break
                if ch == "\n":
                    line += 1
                    col0 = j + 1
                buf.append(ch)
                j += 1
            if not closed:
                issues.append(Issue(fname, start_line, "ERROR", "STRING",
                                    "chuoi '\"' mo o day nhung khong dong"))
                i = n
                break
            toks.append(Tok("STR", "".join(buf), start_line, start_col))
            i = j + 1
            continue
        # symbol / number / dot
        j = i
        while j < n and text[j] not in _DELIMS:
            j += 1
        word = text[i:j]
        if word == ".":
            toks.append(Tok("DOT", ".", line, i - col0))
        elif _NUM_RE.match(word):
            toks.append(Tok("NUM", word, line, i - col0))
        else:
            toks.append(Tok("SYM", word, line, i - col0))
        i = j
    return toks


# =====================================================================
# PARSER -> cay node
# =====================================================================
class Node:
    __slots__ = ("kind", "val", "items", "line", "end_line")

    def __init__(self, kind, val=None, items=None, line=0):
        self.kind = kind        # 'list' | 'quote' | 'sym' | 'num' | 'str' | 'dot'
        self.val = val          # sym: chu thuong; quote: node duoc quote
        self.items = items      # list: danh sach con
        self.line = line
        self.end_line = line

    @property
    def name(self):
        return self.val if self.kind == "sym" else None

    def __repr__(self):
        if self.kind == "list":
            return "(" + " ".join(map(repr, self.items)) + ")"
        if self.kind == "quote":
            return "'" + repr(self.val)
        return str(self.val)


def check_balance(toks, fname, issues):
    """Kiem tra can bang ngoac. Tra ve (balanced, recover_lines) - recover_lines la tap
    cac dong co '(' o cot 0 xuat hien khi con ngoac mo (dung de phuc hoi khi parse)."""
    stack = []
    balanced = True
    hints = []  # (dong '(' cot 0 xuat hien khi depth>0, dong mo ngoai cung)
    for t in toks:
        if t.kind == "LP":
            if t.col == 0 and stack:
                hints.append((t.line, stack[0].line, len(stack)))
            stack.append(t)
        elif t.kind == "RP":
            if stack:
                stack.pop()
            else:
                balanced = False
                issues.append(Issue(fname, t.line, "ERROR", "PAREN", "ngoac dong ')' thua"))
    if stack:
        balanced = False
        if not hints:  # co hint -> parse() phuc hoi tai '(' cot 0 va bao loi chi tiet
            issues.append(Issue(fname, stack[0].line, "ERROR", "PAREN",
                                "ngoac mo '(' chua dong (thieu %d ')' den cuoi file; "
                                "ngoac trong cung chua dong o dong %d)"
                                % (len(stack), stack[-1].line)))
    return balanced, (bool(stack) and bool(hints))


def parse(toks, fname, issues, recover_col0=False):
    """Parse token -> danh sach form top-level.
    recover_col0: '(' o cot 0 khi dang mo ngoac -> dong cuong buc cac list dang mo
    (gia dinh moi form top-level bat dau o cot 0) va bao ERROR."""
    root = []
    stack = []  # moi phan tu: [node, pending_quotes]

    def attach(node):
        # ap dung cac quote dang cho
        target = stack[-1][0].items if stack else root
        q = stack[-1][1] if stack else top_q
        while q and q[-1] == len(target):
            q.pop()
            qn = Node("quote", node, line=node.line)
            node = qn
        target.append(node)

    top_q = []
    for t in toks:
        if t.kind == "LP":
            if recover_col0 and t.col == 0 and stack:
                issues.append(Issue(fname, stack[0][0].line, "ERROR", "PAREN",
                                    "form bat dau o dong %d thieu %d ngoac dong ')' "
                                    "(phat hien khi gap '(' o cot 0 dong %d)"
                                    % (stack[0][0].line, len(stack), t.line)))
                while stack:
                    nd, _ = stack.pop()
                    nd.end_line = t.line
                    attach(nd)
            stack.append([Node("list", items=[], line=t.line), []])
        elif t.kind == "RP":
            if not stack:
                continue  # da bao trong check_balance
            nd, _ = stack.pop()
            nd.end_line = t.line
            attach(nd)
        elif t.kind == "QUOTE":
            target = stack[-1][0].items if stack else root
            q = stack[-1][1] if stack else top_q
            q.append(len(target))
        else:
            if t.kind == "SYM":
                nd = Node("sym", t.val.lower(), line=t.line)
            elif t.kind == "NUM":
                nd = Node("num", t.val, line=t.line)
            elif t.kind == "STR":
                nd = Node("str", t.val, line=t.line)
            else:
                nd = Node("dot", ".", line=t.line)
            attach(nd)
    if recover_col0 and stack:
        issues.append(Issue(fname, stack[0][0].line, "ERROR", "PAREN",
                            "form bat dau o dong %d thieu %d ngoac dong ')' den cuoi file"
                            % (stack[0][0].line, len(stack))))
    while stack:
        nd, _ = stack.pop()
        attach(nd)
    return root


# =====================================================================
# PHAN TICH
# =====================================================================
class Defun:
    def __init__(self, name, file, line, params, locals_, kind):
        self.name, self.file, self.line = name, file, line
        self.params, self.locals, self.kind = params, locals_, kind


def split_arglist(node):
    """(a b / c d) -> ([a,b],[c,d]); nil/() -> ([],[]). Tra ve None neu khong hop le."""
    if node is None:
        return None
    if node.kind == "sym" and node.val == "nil":
        return [], []
    if node.kind != "list":
        return None
    params, locs, cur = [], [], None
    cur = params
    for it in node.items:
        if it.kind != "sym":
            return None
        if it.val == "/":
            cur = locs
            continue
        cur.append(it)
    return params, locs


def is_global_name(name):
    return len(name) > 2 and name.startswith("*") and name.endswith("*")


class Project:
    def __init__(self):
        self.files = []          # (fname, forms, directives)
        self.issues = []
        self.defuns = {}         # name -> [Defun]
        self.externs = set()
        self.uses_activex = None  # (file, line)
        self.has_vl_load_com = False

    # ---------------- nap file ----------------
    def load(self, path, display):
        with open(path, "rb") as fh:
            raw = fh.read()
        try:
            text = raw.decode("utf-8-sig")
        except UnicodeDecodeError:
            text = raw.decode("cp1252", errors="replace")
            self.issues.append(Issue(display, 1, "INFO", "ENCODING",
                                     "file khong phai UTF-8 (doc tam bang cp1252)"))
        directives = {"extern": set(), "ignore": {}}
        toks = tokenize(text, display, self.issues, directives)
        balanced, recover = check_balance(toks, display, self.issues)
        forms = parse(toks, display, self.issues, recover_col0=recover)
        self.externs |= directives["extern"]
        self.files.append((display, forms, directives))
        # ky tu khong phai ASCII trong chuoi / ten ham-bien
        for t in toks:
            if t.kind == "STR" and any(ord(ch) > 127 for ch in t.val):
                self.issues.append(Issue(display, t.line, "WARN", "NON-ASCII",
                                         "chuoi co ky tu khong phai ASCII (VinaCAD/AutoCAD cu co the loi "
                                         "font); nen dung tieng Viet khong dau"))
            elif t.kind == "SYM" and any(ord(ch) > 127 for ch in t.val):
                self.issues.append(Issue(display, t.line, "WARN", "NON-ASCII",
                                         "ten '%s' co ky tu khong phai ASCII" % t.val))

    # ---------------- pass 1: thu thap defun ----------------
    def collect(self):
        for fname, forms, _ in self.files:
            for f in forms:
                self._collect_in(f, fname)

    def _collect_in(self, node, fname):
        if node.kind != "list" or not node.items:
            return
        head = node.items[0]
        if head.kind == "sym" and head.val in ("defun", "defun-q") and len(node.items) >= 2 \
                and node.items[1].kind == "sym":
            name = node.items[1].val
            al = split_arglist(node.items[2]) if len(node.items) >= 3 else None
            if al is not None:
                d = Defun(name, fname, node.line, [p.val for p in al[0]], [p.val for p in al[1]],
                          head.val)
                self.defuns.setdefault(name, []).append(d)
        for it in node.items:
            if it.kind == "list":
                self._collect_in(it, fname)

    def check_defuns(self):
        for name, defs in self.defuns.items():
            if name in BUILTINS and name != "*error*":
                for d in defs:
                    self.add(d.file, d.line, "WARN", "REDEF-BUILTIN",
                             "defun '%s' ghi de ham built-in" % name)
            if len(defs) < 2 or name == "*error*":
                continue
            first = defs[0]
            for d in defs[1:]:
                where = "%s:%d" % (first.file, first.line)
                if name.startswith("c:"):
                    self.add(d.file, d.line, "ERROR", "DUP-CMD",
                             "lenh '%s' bi dinh nghia trung (da co o %s)" % (name.upper(), where))
                else:
                    self.add(d.file, d.line, "WARN", "DUP-DEFUN",
                             "ham '%s' bi dinh nghia lai (da co o %s)" % (name, where))

    # ---------------- pass 2: duyet ma ----------------
    def analyze(self):
        for fname, forms, _ in self.files:
            self.cur_file = fname
            for f in forms:
                self.walk(f, None)
        if self.uses_activex and not self.has_vl_load_com:
            f, l = self.uses_activex
            self.add(f, l, "WARN", "VL-LOAD-COM",
                     "dung ham ActiveX (vla-/vlax-) nhung khong file nao goi (vl-load-com)")

    def add(self, f, line, level, code, msg):
        self.issues.append(Issue(f, line, level, code, msg))

    def known_function(self, name):
        if name in BUILTINS or name in self.defuns or name in self.externs:
            return True
        return False

    def risky_note(self, name):
        for pat, note in RISKY_FUNCTIONS:
            if fnmatch.fnmatchcase(name, pat):
                return note
        return None

    def in_scope(self, scope, name):
        s = scope
        while s is not None:
            if name in s["vars"]:
                return True
            s = s["parent"]
        return False

    def new_scope(self, parent, names, defun=None):
        return {"vars": set(names), "parent": parent,
                "defun": defun if defun is not None else (parent["defun"] if parent else None),
                "leaked": parent["leaked"] if (parent and defun is None) else set()}

    def check_call(self, name, nargs, line, scope):
        """Kiem tra mot loi goi ham ten 'name' voi nargs doi so (nargs=None: khong ro)."""
        f = self.cur_file
        if name in ACTIVEX_PREFIXES or name.startswith(ACTIVEX_PREFIXES):
            if self.uses_activex is None:
                self.uses_activex = (f, line)
        if name == "vl-load-com":
            self.has_vl_load_com = True
        note = self.risky_note(name)
        if note:
            self.add(f, line, "WARN", "RISKY", "'%s': %s" % (name, note))
        elif name.startswith("vla-"):
            self.add(f, line, "INFO", "ACTIVEX", "'%s' phu thuoc ActiveX (vla-)" % name)
        if name in self.defuns:
            defs = self.defuns[name]
            arities = set(len(d.params) for d in defs)
            if nargs is not None and len(arities) == 1:
                want = arities.pop()
                if nargs != want:
                    d = defs[0]
                    self.add(f, line, "ERROR", "ARITY",
                             "goi '%s' voi %d doi so, nhung dinh nghia (%s:%d) can %d"
                             % (name, nargs, d.file, d.line, want))
            return
        if name in BUILTINS:
            if nargs is not None and name in BUILTIN_ARITY:
                lo, hi = BUILTIN_ARITY[name]
                if nargs < lo or (hi is not None and nargs > hi):
                    rng = ("%d" % lo) if lo == hi else ("%d..%s" % (lo, "n" if hi is None else hi))
                    self.add(f, line, "ERROR", "ARITY",
                             "goi built-in '%s' voi %d doi so (can %s)" % (name, nargs, rng))
            return
        if name in self.externs or note or name.startswith("vla-"):
            return
        if scope is not None and self.in_scope(scope, name):
            return  # bien chua ham (vd. tham so fn)
        if name.startswith(("vl-", "vlax-")):
            self.add(f, line, "WARN", "UNDEF-FUNC",
                     "'%s' khong co trong danh sach built-in Visual LISP (kiem tra chinh ta)" % name)
        else:
            self.add(f, line, "ERROR", "UNDEF-FUNC",
                     "ham '%s' chua duoc dinh nghia (khong phai built-in, khong co defun trong du an)"
                     % name)

    def note_setq(self, sym, scope):
        name = sym.val
        if scope is None or scope["defun"] is None:
            return
        if name in ("t", "nil", "pi") :
            self.add(self.cur_file, sym.line, "ERROR", "SETQ-CONST",
                     "khong duoc gan gia tri cho hang so '%s'" % name)
            return
        if is_global_name(name) or self.in_scope(scope, name):
            return
        if name in scope["leaked"]:
            return
        scope["leaked"].add(name)
        self.add(self.cur_file, sym.line, "WARN", "LEAK",
                 "bien '%s' duoc setq trong '%s' nhung khong khai bao local (sau '/'): "
                 "bien ro ri toan cuc" % (name, scope["defun"]))

    def walk_body(self, items, scope):
        for it in items:
            self.walk(it, scope)

    def walk_lambda(self, node, scope):
        # node = (lambda args body...)
        items = node.items
        if len(items) < 2:
            self.add(self.cur_file, node.line, "ERROR", "SYNTAX", "lambda thieu danh sach tham so")
            return
        al = split_arglist(items[1])
        if al is None:
            self.add(self.cur_file, items[1].line, "ERROR", "SYNTAX",
                     "danh sach tham so cua lambda khong hop le")
            al = ([], [])
        names = [p.val for p in al[0] + al[1]]
        sc = self.new_scope(scope, names) if scope else None
        if scope is None:
            sc = None  # lambda top-level: bien la toan cuc, khong kiem tra ro ri
        self.walk_body(items[2:], sc)
        return len(al[0])

    def funarg(self, arg, scope, nargs_hint):
        """Doi so ham (vd. mapcar 'f). Tra ve None."""
        if arg.kind == "quote":
            q = arg.val
            if q.kind == "sym":
                self.check_call(q.val, nargs_hint, q.line, scope)
                return True
            if q.kind == "list" and q.items and q.items[0].name == "lambda":
                np = self.walk_lambda(q, scope)
                self._lambda_arity(q, np, nargs_hint)
                return True
        if arg.kind == "list" and arg.items and arg.items[0].name == "function" \
                and len(arg.items) == 2:
            return self.funarg(Node("quote", arg.items[1], line=arg.line), scope, nargs_hint)
        return False

    def _lambda_arity(self, node, np, nargs_hint):
        if np is not None and nargs_hint is not None and np != nargs_hint:
            self.add(self.cur_file, node.line, "ERROR", "ARITY",
                     "lambda co %d tham so nhung se duoc goi voi %d doi so" % (np, nargs_hint))

    def walk(self, node, scope):
        f = self.cur_file
        if node.kind == "quote":
            q = node.val
            # '(lambda ...) duoc xem la ma
            if q.kind == "list" and q.items and q.items[0].name == "lambda":
                self.walk_lambda(q, scope)
            return
        if node.kind != "list" or not node.items:
            return
        items = node.items
        head = items[0]
        args = items[1:]
        if head.kind == "list":
            if head.items and head.items[0].name == "lambda":
                np = self.walk_lambda(head, scope)
                self._lambda_arity(head, np, len(args))
            else:
                self.walk(head, scope)
            self.walk_body(args, scope)
            return
        if head.kind in ("num", "str", "dot"):
            self.add(f, node.line, "ERROR", "NOT-FUNC",
                     "phan tu dau list '%s' khong phai ham (thieu ' truoc list du lieu?)" % head.val)
            return
        if head.kind == "quote":
            self.add(f, node.line, "ERROR", "NOT-FUNC",
                     "phan tu dau list la gia tri quote, khong phai ham")
            return
        name = head.val

        if name in ("defun", "defun-q"):
            if len(items) < 3 or items[1].kind != "sym":
                self.add(f, node.line, "ERROR", "SYNTAX", "defun thieu ten hoac danh sach tham so")
                return
            al = split_arglist(items[2])
            if al is None:
                self.add(f, items[2].line, "ERROR", "SYNTAX",
                         "danh sach tham so cua defun '%s' khong hop le" % items[1].val)
                al = ([], [])
            seen = set()
            for p in al[0] + al[1]:
                if p.val in seen:
                    self.add(f, p.line, "WARN", "DUP-LOCAL",
                             "'%s' bi khai bao 2 lan trong danh sach tham so/bien cuc bo cua '%s'"
                             % (p.val, items[1].val))
                seen.add(p.val)
            sc = self.new_scope(scope, [p.val for p in al[0] + al[1]], defun=items[1].val)
            sc["leaked"] = set()
            self.walk_body(items[3:], sc)
            return
        if name == "lambda":
            self.walk_lambda(node, scope)
            return
        if name == "quote":
            return
        if name == "function":
            if len(args) == 1:
                self.funarg(Node("quote", args[0], line=node.line), scope, None)
            return
        if name == "setq":
            if len(args) % 2:
                self.add(f, node.line, "ERROR", "SYNTAX", "setq co so doi so le (thieu gia tri)")
            for k in range(0, len(args), 2):
                v = args[k]
                if v.kind != "sym":
                    self.add(f, v.line, "ERROR", "SYNTAX", "setq: phan tu thu %d khong phai ten bien"
                             % (k + 1))
                else:
                    self.note_setq(v, scope)
                if k + 1 < len(args):
                    self.walk(args[k + 1], scope)
            return
        if name == "set" and args and args[0].kind == "quote" and args[0].val.kind == "sym":
            self.note_setq(args[0].val, scope)
            self.walk_body(args[1:], scope)
            return
        if name in ("foreach", "vlax-for"):
            if len(args) < 2 or args[0].kind != "sym":
                self.add(f, node.line, "ERROR", "SYNTAX", "%s: thieu ten bien lap" % name)
                self.walk_body(args, scope)
                return
            self.check_call(name, len(args), node.line, scope)
            self.walk(args[1], scope)
            sc = self.new_scope(scope, [args[0].val]) if scope else None
            self.walk_body(args[2:], sc)
            return
        if name == "cond":
            for cl in args:
                if cl.kind != "list" or not cl.items:
                    self.add(f, cl.line, "ERROR", "SYNTAX", "menh de cua cond phai la list khong rong")
                    continue
                self.walk_body(cl.items, scope)
            return

        # loi goi ham thuong
        self.check_call(name, len(args), head.line, scope)
        if name in CODE_STRING_ARG and len(args) > CODE_STRING_ARG[name] \
                and args[CODE_STRING_ARG[name]].kind == "str":
            self.check_code_string(args[CODE_STRING_ARG[name]], name)
        if name in FUNARG_POS and len(args) > FUNARG_POS[name]:
            pos = FUNARG_POS[name]
            hint = None
            if name == "mapcar":
                hint = len(args) - 1
            elif name in ("vl-sort", "vl-sort-i"):
                hint = 2
            elif name in ("apply", "vl-catch-all-apply"):
                a2 = args[1] if len(args) > 1 else None
                if a2 is not None and a2.kind == "list" and a2.items and a2.items[0].name == "list":
                    hint = len(a2.items) - 1
                elif a2 is not None and a2.kind == "quote" and a2.val.kind == "list" \
                        and not any(x.kind == "dot" for x in a2.val.items):
                    hint = len(a2.val.items)
            else:
                hint = 1
            for k, a in enumerate(args):
                if k == pos and self.funarg(a, scope, hint):
                    continue
                self.walk(a, scope)
            return
        self.walk_body(args, scope)

    def check_code_string(self, node, fn):
        """chuoi ma lisp cua action_tile / new_dialog: kiem cu phap + ham chua dinh nghia.
        Bieu thuc chay o muc toan cuc (khong co bien cuc bo) voi $key $value $reason..."""
        code = re.sub(r'\\(.)', lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), node.val)
        if code.strip() == "":
            return
        sub = []
        toks = tokenize(code, self.cur_file, sub, {"extern": set(), "ignore": {}})
        check_balance(toks, self.cur_file, sub)
        forms = parse(toks, self.cur_file, sub)
        if sub:
            self.add(self.cur_file, node.line, "ERROR", "DCL-ACTION",
                     "chuoi ma cua %s loi cu phap: %s" % (fn, "; ".join(i.msg for i in sub)))
            return
        line0 = node.line - 1

        def shift(nd):
            nd.line += line0
            nd.end_line += line0
            if nd.kind == "list":
                for it in nd.items:
                    shift(it)
            elif nd.kind == "quote":
                shift(nd.val)
        for f in forms:
            shift(f)
            self.walk(f, None)
        for f in forms:
            self._dcl_vars(f)

    def _dcl_vars(self, nd):
        # goi ($value) nhu ham la sai
        if nd.kind == "list" and nd.items:
            h = nd.items[0]
            if h.kind == "sym" and h.val in DCL_ACTION_VARS:
                self.add(self.cur_file, h.line, "ERROR", "DCL-ACTION",
                         "'%s' la bien DCL, khong phai ham" % h.val)
            for it in nd.items:
                self._dcl_vars(it)

    # ---------------- ket qua ----------------
    def filtered(self, min_level):
        ign = {fname: d["ignore"] for fname, _, d in self.files}
        out = []
        for it in self.issues:
            rule = ign.get(it.file, {}).get(it.line, False)
            if rule is None or (rule and it.code in rule):
                continue
            if LEVELS[it.level] < LEVELS[min_level]:
                continue
            out.append(it)
        out.sort(key=lambda x: (x.file, x.line, -LEVELS[x.level], x.code))
        return out


def find_files(paths):
    res = []
    for p in paths:
        if os.path.isdir(p):
            for root, dirs, files in os.walk(p):
                dirs[:] = sorted(d for d in dirs if not d.startswith("."))
                for fn in sorted(files):
                    if fn.lower().endswith(".lsp"):
                        res.append(os.path.join(root, fn))
        elif os.path.isfile(p):
            res.append(p)
        else:
            raise FileNotFoundError(p)
    return res


def display_path(p):
    try:
        rel = os.path.relpath(p)
        return p if rel.startswith("..") else rel
    except ValueError:
        return p


def lint_paths(paths, min_level="INFO"):
    """API: tra ve danh sach Issue da loc va sap xep."""
    proj = Project()
    for p in find_files(paths):
        proj.load(p, display_path(p))
    proj.collect()
    proj.check_defuns()
    proj.analyze()
    return proj.filtered(min_level), proj


def main(argv=None):
    ap = argparse.ArgumentParser(description="Kiem tra tinh ma AutoLISP (AutoCAD/VinaCAD).")
    ap.add_argument("paths", nargs="+", help="file .lsp hoac thu muc (duyet de quy)")
    ap.add_argument("--json", action="store_true", help="xuat JSON")
    ap.add_argument("--min-level", default="INFO", choices=list(LEVELS),
                    help="muc thap nhat duoc hien thi (mac dinh INFO)")
    a = ap.parse_args(argv)
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    try:
        files = find_files(a.paths)
    except FileNotFoundError as e:
        print("lisplint: khong tim thay: %s" % e, file=sys.stderr)
        return 2
    if not files:
        print("lisplint: khong co file .lsp nao", file=sys.stderr)
        return 2
    issues, proj = lint_paths(a.paths, a.min_level)
    counts = {k: 0 for k in LEVELS}
    for it in proj.filtered("INFO"):
        counts[it.level] += 1
    if a.json:
        json.dump({"files": len(files), "summary": counts,
                   "issues": [i.as_dict() for i in issues]},
                  sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
    else:
        for it in issues:
            print(it.fmt())
        print("-- %d file, %d ERROR, %d WARN, %d INFO"
              % (len(files), counts["ERROR"], counts["WARN"], counts["INFO"]))
    return 1 if counts["ERROR"] else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:  # vd. ... | head
        sys.stderr.close()
        sys.exit(1)
