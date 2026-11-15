#!/usr/bin/env python3
"""Chay bo KT (lisp/*.lsp) tren 1 file DXF THAT bang trinh gia lap lispsim.

    python3 -I tools/run_dxf.py Template.dxf                       # KTMAU (Enter = tu doan) roi KTALL
    python3 -I tools/run_dxf.py Template.dxf --cfg lisp/KT_ChuanCongTy.txt --mode vinacad
    python3 -I tools/run_dxf.py Template.dxf --cmds KTALL,KTN,KTN,KTBC --samples 5 --json out.json

In: thoi gian, so lan goi ham defun, loi noi bo (crash / loi bi vl-catch-all-apply nuot), so loi KT
theo module / ma / muc, vai mau moi ma (handle de tra trong DXF). Xem docs/QA_TEMPLATE_RUN.md.
"""
import argparse
import collections
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lispsim import Session                       # noqa: E402
from lispsim.dxfload import load_dxf              # noqa: E402
from lispsim.ltypes import to_str                 # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, ".."))


def run_ktmau(dxf, mode="acad", lispdir=None, inputs=None, dwg=None):
    """KTMAU voi kich ban nhap lieu (mac dinh: Enter moi cau = tu doan) -> (session, result, cfg_text)"""
    d = dwg or load_dxf(dxf)
    s = Session(d, mode=mode, lispdir=lispdir)
    # KTMAU phai sinh file moi, khong doc file chuan co san
    p = s.cfg_path()
    if os.path.exists(p):
        os.remove(p)
    s.load_all()
    t = time.time()
    r = s.command("KTMAU", inputs or [])
    r.elapsed = time.time() - t
    return s, r, s.read_cfg()


def run_cmds(dxf, cfg_text, cmds=("KTALL",), mode="acad", lispdir=None, dwg=None):
    """-> (session, [(cmd, result, giay, so_lan_goi)])"""
    d = dwg or load_dxf(dxf)
    s = Session(d, mode=mode, lispdir=lispdir, cfg_text=cfg_text)
    lr = s.load_all()
    out = [("LOAD", lr, 0.0, 0)]
    for c in cmds:
        before = sum(s.I.calls.values())
        t = time.time()
        r = s.command(c)
        out.append((c, r, time.time() - t, sum(s.I.calls.values()) - before))
    return s, out


def internal(r):
    return ([("CRASH", e.msg, " > ".join(e.stack or [])) for e in r.errors]
            + [("NUOT", e.msg, " > ".join(e.stack or [])) for e in r.real_caught()]
            + [("SIM", b[0], " > ".join(b[1])) for b in r.sim_bugs])


def summarize(s, issues=None):
    iss = issues if issues is not None else s.issues()
    by_mod = collections.Counter((i["module"], i["sev"]) for i in iss)
    by_code = collections.Counter((i["module"], i["code"], i["sev"]) for i in iss)
    return iss, by_mod, by_code


def ent_handles(i):
    return [e.handle for e in i["ents"]]


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("dxf")
    ap.add_argument("--mode", default="acad", choices=["acad", "vinacad"])
    ap.add_argument("--cfg", help="file chuan (mac dinh: lisp/KT_ChuanCongTy.txt neu co, khong thi chay KTMAU)")
    ap.add_argument("--cmds", default="KTALL")
    ap.add_argument("--lispdir", default=None)
    ap.add_argument("--samples", type=int, default=3)
    ap.add_argument("--json", help="ghi ket qua ra file json")
    ap.add_argument("--save-cfg", help="luu file chuan KTMAU sinh ra")
    a = ap.parse_args(argv)

    t0 = time.time()
    lispdir = a.lispdir or os.path.join(ROOT, "lisp")
    cfgsrc = a.cfg
    if not cfgsrc and os.path.exists(os.path.join(lispdir, "KT_ChuanCongTy.txt")):
        cfgsrc = os.path.join(lispdir, "KT_ChuanCongTy.txt")
    report = {"dxf": a.dxf, "mode": a.mode, "lispdir": lispdir}
    if cfgsrc:
        with open(cfgsrc, encoding="latin-1") as f:
            cfg = f.read()
        report["cfg"] = cfgsrc
    else:
        s, r, cfg = run_ktmau(a.dxf, a.mode, lispdir)
        print("== KTMAU (%.1fs, %d lan goi) ==" % (r.elapsed, sum(s.I.calls.values())))
        for k in internal(r):
            print("  %s %s  [%s]" % k)
        report["cfg"] = "KTMAU"
        report["ktmau_internal"] = internal(r)
        if a.save_cfg and cfg:
            with open(a.save_cfg, "w", encoding="latin-1") as f:
                f.write(cfg)
    t = time.time()
    dwg = load_dxf(a.dxf)
    tl = time.time() - t
    print("== nap DXF %.1fs: %d doi tuong CSDL, %d doi tuong chinh, %d block ==" % (
        tl, len(dwg.ents), sum(1 for e in dwg.main if e.kind == "main"), len(dwg.blocks)))
    cmds = [c.strip() for c in a.cmds.split(",") if c.strip()]
    s, runs = run_cmds(a.dxf, cfg, cmds, a.mode, lispdir, dwg)
    report["runs"] = []
    for c, r, sec, ncall in runs:
        ints = internal(r)
        print("== %s: %.1fs, %d lan goi ham defun, %d loi noi bo ==" % (c, sec, ncall, len(ints)))
        for k in ints[:20]:
            print("  %s %s  [%s]" % k)
        if c != "LOAD":
            tail = r.out.strip().splitlines()[-6:]
            for ln in tail:
                print("   | " + ln[:150])
        report["runs"].append(dict(cmd=c, sec=round(sec, 2), calls=ncall, internal=ints))
    iss, by_mod, by_code = summarize(s)
    print("== %d loi KT ==" % len(iss))
    for (m, sev), n in sorted(by_mod.items()):
        print("  %-7s %-8s %5d" % (m, sev, n))
    print("-- theo ma --")
    for (m, code, sev), n in sorted(by_code.items()):
        print("  %-7s %-20s %-8s %5d" % (m, code, sev, n))
        if a.samples:
            for i in [x for x in iss if x["code"] == code and x["module"] == m and x["sev"] == sev][:a.samples]:
                print("        %s  %s" % (",".join(ent_handles(i))[:40], i["msg"][:110]))
    print("== vi pham (sua/xoa doi tuong goc): %d ==" % len(s.dwg.violations))
    top = sorted(s.I.calls.items(), key=lambda x: -x[1])[:12]
    print("== goi nhieu nhat: " + ", ".join("%s=%d" % x for x in top))
    print("== tong %.1fs ==" % (time.time() - t0))
    report["issues"] = [dict(module=i["module"], code=i["code"], sev=i["sev"], msg=i["msg"],
                             ents=ent_handles(i), space=i["space"]) for i in iss]
    report["violations"] = s.dwg.violations
    if a.json:
        with open(a.json, "w") as f:
            json.dump(report, f, ensure_ascii=False, indent=1, default=str)
    return report


if __name__ == "__main__":
    main()
