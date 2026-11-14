#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Test cho lisplint.py.  Chay:  python3 -m unittest tools/test_lisplint.py -v
(hoac python3 tools/test_lisplint.py)"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import lisplint  # noqa: E402

ROOT = os.path.dirname(HERE)
SAMPLE = os.path.join(ROOT, "lisp", "legacy", "CheckDimOverlap.lsp")


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="lisplint_")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write(self, name, src):
        p = os.path.join(self.tmp, name)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(textwrap.dedent(src).lstrip("\n"))
        return p

    def lint(self, src=None, files=None, min_level="INFO"):
        if src is not None:
            self.write("a.lsp", src)
        for k, v in (files or {}).items():
            self.write(k, v)
        issues, _ = lisplint.lint_paths([self.tmp], min_level)
        return issues

    @staticmethod
    def find(issues, code, level=None, line=None):
        return [i for i in issues if i.code == code and (level is None or i.level == level)
                and (line is None or i.line == line)]

    def assertNoErrors(self, issues):
        errs = [i.fmt() for i in issues if i.level == "ERROR"]
        self.assertEqual(errs, [], "\n".join(errs))


class TestSample(Base):
    def test_sample_has_no_error(self):
        self.assertTrue(os.path.isfile(SAMPLE), SAMPLE)
        issues, _ = lisplint.lint_paths([SAMPLE])
        self.assertNoErrors(issues)
        # khong co bien ro ri, khong co ham chua dinh nghia
        self.assertEqual(self.find(issues, "LEAK"), [])
        self.assertEqual(self.find(issues, "UNDEF-FUNC"), [])
        # vla-get-ActiveDocument -> RISKY, vla-StartUndoMark -> ACTIVEX info
        self.assertTrue(self.find(issues, "RISKY", "WARN", 261))
        self.assertTrue(self.find(issues, "ACTIVEX", "INFO", 268))

    def test_cli_sample_exit_zero(self):
        r = subprocess.run([sys.executable, os.path.join(HERE, "lisplint.py"), SAMPLE],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("0 ERROR", r.stdout)


class TestTokenizer(Base):
    def test_strings_comments_do_not_count_parens(self):
        iss = self.lint(r'''
        ;; comment co ngoac ( ( (
        ;| comment khoi
           ( ( ) nhieu dong
        |;
        (defun f (/ s)
          (setq s "chuoi co ( va \" va \\ va \n ;khong phai comment")
          (princ s) ; ) ) )
          (princ))
        ''')
        self.assertNoErrors(iss)

    def test_tokens(self):
        toks = lisplint.tokenize(r'(a "x\"y" \'(1 . 2) ;c' + "\n" + r'b) ;|z|; 1e-9 .5', "t", [],
                                 {"extern": set(), "ignore": {}})
        kinds = [t.kind for t in toks]
        self.assertEqual(kinds, ["LP", "SYM", "STR", "QUOTE", "LP", "NUM", "DOT", "NUM", "RP",
                                 "SYM", "RP", "NUM", "NUM"])
        self.assertEqual(toks[2].val, r'x\"y')
        self.assertEqual(toks[9].line, 2)

    def test_line_count_after_multiline_string_and_block_comment(self):
        iss = self.lint('''
        (setq a "dong1
        dong2")
        ;| x
        y |;
        (khongco)
        ''')
        self.assertTrue(self.find(iss, "UNDEF-FUNC", "ERROR", 5))

    def test_unterminated_string(self):
        iss = self.lint('''
        (defun f ()
          (princ "chua dong)
          )
        ''')
        self.assertTrue(self.find(iss, "STRING", "ERROR", 2))

    def test_unterminated_block_comment(self):
        iss = self.lint('''
        (princ)
        ;| khong dong
        (princ)
        ''')
        self.assertTrue(self.find(iss, "COMMENT", "ERROR", 2))


class TestParens(Base):
    def test_missing_close_paren_reports_form_line(self):
        iss = self.lint('''
        (defun f1 ()
          (princ "a")
        (defun f2 ()
          (princ "b"))
        ''')
        e = self.find(iss, "PAREN", "ERROR")
        self.assertEqual(len(e), 1, [i.fmt() for i in iss])
        self.assertEqual(e[0].line, 1)
        self.assertIn("dong 3", e[0].msg)
        # phuc hoi: f2 van duoc phan tich doc lap, khong co loi phu
        self.assertEqual(self.find(iss, "UNDEF-FUNC"), [])

    def test_missing_close_paren_at_eof(self):
        iss = self.lint('''
        (defun f1 ()
          (if T
            (princ "a")
        ''')
        e = self.find(iss, "PAREN", "ERROR")
        self.assertEqual(len(e), 1)
        self.assertEqual(e[0].line, 1)

    def test_extra_close_paren(self):
        iss = self.lint('''
        (defun f1 ()
          (princ "a"))
        )
        (princ)
        ''')
        self.assertTrue(self.find(iss, "PAREN", "ERROR", 3))


class TestUndefined(Base):
    def test_undefined_function_error(self):
        iss = self.lint('''
        (defun c:X ()
          (ham-khong-co 1 2)
          (princ))
        ''')
        self.assertTrue(self.find(iss, "UNDEF-FUNC", "ERROR", 2))

    def test_defined_in_other_file(self):
        iss = self.lint(files={
            "a.lsp": "(defun c:X () (lib:help 1) (princ))\n",
            "sub/b.lsp": "(defun lib:help (n) (princ n))\n",
        })
        self.assertEqual(self.find(iss, "UNDEF-FUNC"), [])

    def test_not_function_positions(self):
        iss = self.lint('''
        (defun f (a b / c d)
          (setq c '((0 . "LINE") (8 . "0") (foo bar)))
          (setq d (mapcar '(lambda (x y) (+ x y)) '(1 2) '(3 4)))
          (setq d (mapcar (function (lambda (x) (* x 2))) '(1 2)))
          (setq d ((lambda (p q) (list p q)) a b))
          (cond ((= a 1) (princ "1"))
                ((cdr (assoc 50 c)))
                (T (princ "khac")))
          (quote (khong la ham))
          (princ))
        ''')
        self.assertNoErrors(iss)
        self.assertEqual(self.find(iss, "LEAK"), [])

    def test_calls_inside_quoted_lambda_are_checked(self):
        iss = self.lint('''
        (defun f (l) (vl-sort l '(lambda (a b) (khong-co a b))))
        ''')
        self.assertTrue(self.find(iss, "UNDEF-FUNC", "ERROR", 1))

    def test_quoted_function_symbol_checked(self):
        iss = self.lint('''
        (defun f (l) (mapcar 'khong-co l) (vl-catch-all-apply 'cung-khong-co (list l)))
        ''')
        names = sorted(i.msg.split("'")[1] for i in self.find(iss, "UNDEF-FUNC", "ERROR"))
        self.assertEqual(names, ["cung-khong-co", "khong-co"])

    def test_number_as_head_is_error(self):
        iss = self.lint('(setq a (1 2 3))\n')
        self.assertTrue(self.find(iss, "NOT-FUNC", "ERROR", 1))

    def test_extern_directive_and_ignore(self):
        iss = self.lint('''
        ; lisplint: extern LM:ssget
        (defun f () (LM:ssget "x")
          (khong-co) ; lisplint: ignore=UNDEF-FUNC
          (khong-co-2))
        ''')
        u = self.find(iss, "UNDEF-FUNC")
        self.assertEqual([i.line for i in u], [4])

    def test_activex_info_and_unknown_vlax_warn(self):
        iss = self.lint('''
        (vl-load-com)
        (defun f (o) (vla-Delete o) (vlax-khong-co o))
        ''')
        self.assertTrue(self.find(iss, "ACTIVEX", "INFO", 2))
        self.assertTrue(self.find(iss, "UNDEF-FUNC", "WARN", 2))
        self.assertNoErrors(iss)

    def test_missing_vl_load_com(self):
        iss = self.lint('(defun f () (vlax-get-acad-object))\n')
        self.assertTrue(self.find(iss, "VL-LOAD-COM", "WARN"))


class TestLeak(Base):
    def test_leak_warn(self):
        iss = self.lint('''
        (defun f (a / b)
          (setq b 1 c 2 *G* 3)
          (setq c 4)
          (foreach x (list 1 2) (setq b x))
          (set 'd 5)
          (princ))
        ''')
        leaks = sorted((i.line, i.msg.split("'")[1]) for i in self.find(iss, "LEAK", "WARN"))
        self.assertEqual(leaks, [(2, "c"), (5, "d")])

    def test_setq_param_and_lambda_locals_ok(self):
        iss = self.lint('''
        (defun f (a)
          (setq a (1+ a))
          (mapcar '(lambda (x / y) (setq y x x (* 2 y))) (list a)))
        ''')
        self.assertEqual(self.find(iss, "LEAK"), [])

    def test_toplevel_setq_not_leak(self):
        iss = self.lint('(setq abc 1)\n')
        self.assertEqual(self.find(iss, "LEAK"), [])


class TestRisky(Base):
    def test_risky_functions(self):
        iss = self.lint('''
        (vl-load-com)
        (defun f (e o / s)
          (setq s (acet-ss-to-list e))
          (dos_msgbox "x" "y" 1 1)
          (getpropertyvalue e "Layer")
          (vlax-curve-getEndParam e)
          (vl-registry-read "HKEY" "x")
          (vlr-object-reactor nil nil nil)
          (command-s "_.LINE")
          (vla-put-Color o 1)
          (princ))
        ''')
        lines = sorted(i.line for i in self.find(iss, "RISKY", "WARN"))
        self.assertEqual(lines, [3, 4, 5, 6, 7, 8, 9, 10])
        self.assertEqual(self.find(iss, "UNDEF-FUNC"), [])
        self.assertNoErrors(iss)

    def test_risky_list_is_editable(self):
        self.assertTrue(any(p == "acet-*" for p, _ in lisplint.RISKY_FUNCTIONS))


class TestArity(Base):
    def test_wrong_arity_error(self):
        iss = self.lint(files={
            "a.lsp": "(defun lib:add (a b) (+ a b))\n",
            "b.lsp": "(defun c:T1 () (lib:add 1) (lib:add 1 2) (lib:add 1 2 3) (princ))\n",
        })
        a = self.find(iss, "ARITY", "ERROR")
        self.assertEqual(len(a), 2, [i.fmt() for i in iss])

    def test_mapcar_arity(self):
        iss = self.lint('''
        (defun two (a b) (+ a b))
        (defun f (l) (mapcar 'two l) (mapcar 'two l l))
        ''')
        self.assertEqual(len(self.find(iss, "ARITY", "ERROR")), 1)

    def test_conflicting_definitions_skip_arity(self):
        iss = self.lint(files={
            "a.lsp": "(defun g (a) a)\n",
            "b.lsp": "(defun g (a b) a)\n(g 1)\n(g 1 2)\n",
        })
        self.assertEqual(self.find(iss, "ARITY"), [])
        self.assertTrue(self.find(iss, "DUP-DEFUN", "WARN"))

    def test_if_too_many_args(self):
        iss = self.lint('(defun f (a) (if a (princ 1) (princ 2) (princ 3)))\n')
        self.assertTrue(self.find(iss, "ARITY", "ERROR", 1))

    def test_setq_odd(self):
        iss = self.lint('(setq a 1 b)\n')
        self.assertTrue(self.find(iss, "SYNTAX", "ERROR", 1))


class TestDuplicates(Base):
    def test_dup_defun_warn_and_cmd_error(self):
        iss = self.lint(files={
            "a.lsp": "(defun util (x) x)\n(defun c:ABC () (princ))\n",
            "b.lsp": "(defun util (x) x)\n(defun C:abc () (princ))\n",
        })
        self.assertTrue(self.find(iss, "DUP-DEFUN", "WARN"))
        self.assertEqual(len(self.find(iss, "DUP-CMD", "ERROR")), 1)


class TestNonAscii(Base):
    def test_non_ascii_string(self):
        iss = self.lint('''
        (defun c:X ()
          (princ "\\nChọn đối tượng: ")
          (princ "\\nChon doi tuong: ")
          (princ))
        ''')
        self.assertEqual([i.line for i in self.find(iss, "NON-ASCII", "WARN")], [2])


class TestCli(Base):
    def test_json_and_exit_code(self):
        self.write("bad.lsp", "(defun c:X () (khong-co))\n")
        r = subprocess.run([sys.executable, os.path.join(HERE, "lisplint.py"), self.tmp, "--json"],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)
        data = json.loads(r.stdout)
        self.assertEqual(data["summary"]["ERROR"], 1)
        self.assertEqual(data["issues"][0]["code"], "UNDEF-FUNC")

    def test_text_format(self):
        p = self.write("bad.lsp", "(defun c:X () (khong-co))\n")
        r = subprocess.run([sys.executable, os.path.join(HERE, "lisplint.py"), p],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)
        first = r.stdout.splitlines()[0]
        self.assertRegex(first, r"^.*bad\.lsp:1: ERROR: .+ \[UNDEF-FUNC\]$")

    def test_missing_path_exit_2(self):
        r = subprocess.run([sys.executable, os.path.join(HERE, "lisplint.py"),
                            os.path.join(self.tmp, "khong_ton_tai.lsp")],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)


if __name__ == "__main__":
    unittest.main()
