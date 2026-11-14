#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""sim_match.py - mo phong toi gian thuat toan cua lisp/KT_Match.lsp (module KHOP).

Muc dich: chung minh logic gom nhom truc, so khoang cach truc, kiem dim-truc,
kiem vi tri / so sanh cao do phat hien dung loi va KHONG bao nham.
Ban LISP phai theo dung cac buoc o day (cung ten ham, tien to ktmat: ben LISP).

Chay:  python3 tests/sim_match.py      (exit 0 = moi kich ban dung)

Du lieu don vi: mm trong Model (khoang cach model = kich thuoc that).
Cao do: met. Toa do Y cua ky hieu cao do: mm.
"""
import sys
from statistics import median

TOL = 1.0          # SETTING DUNG_SAI_KICH_THUOC (mm)
TOL_LV = 5.0       # SETTING DUNG_SAI_CAO_DO (mm)
NEAR_LV = 0.1      # SETTING CAODO_LECH_NGHI (m)
TOL_V = 0.0011     # 2 gia tri cao do coi la bang nhau (m)


# ---------------------------------------------------------------- tien ich
def family(name):
    return "SO" if name[0].isdigit() else "CHU"


def natkey(n):
    return (0, int(n), n) if n.isdigit() else (1, 0, n)


def pairkey(a, b):
    return tuple(sorted((a, b), key=natkey))


def chain_groups(items, keyf, tol):
    """gom chuoi: sap theo keyf, tach nhom khi buoc nhay > tol (ktmat:chain)"""
    items = sorted(items, key=keyf)
    groups, cur, last = [], [], None
    for it in items:
        k = keyf(it)
        if cur and k - last > tol:
            groups.append(cur)
            cur = []
        cur.append(it)
        last = k
    if cur:
        groups.append(cur)
    return groups


# ---------------------------------------------------------------- truc
def build_sequences(unit, issues):
    """tra ve list (fam, orient, [(name, c), ...]) cho 1 unit (ktmat:unit-seqs)"""
    seqs = []
    dup_seen = set()
    fams = {}
    for b in unit["bubbles"]:
        fams.setdefault(family(b[0]), []).append(b)
    for fam, bs in fams.items():
        sizes = [b[3] for b in bs if b[3] > 0]
        rowtol = max(0.5 * median(sizes) if sizes else 0.0, TOL)
        for orient, along, across in (("H", 1, 2), ("V", 2, 1)):
            for g in chain_groups(bs, lambda b: b[across], rowtol):
                if len(set(b[0] for b in g)) < 2:
                    continue
                g = sorted(g, key=lambda b: b[along])
                seg = [(g[0][0], g[0][along])]
                segs = []
                for b in g[1:]:
                    nm, c = b[0], b[along]
                    names = [s[0] for s in seg]
                    if nm in names:
                        c0 = seg[names.index(nm)][1]
                        if abs(c - c0) <= TOL:
                            continue          # 2 bubble chong nhau: bo qua
                        sp = [seg[i + 1][1] - seg[i][1] for i in range(len(seg) - 1)]
                        med = median(sp) if sp else 0.0
                        gap = c - seg[-1][1]
                        if (nm == seg[0][0] or nm == seg[-1][0]) and med > 0 and gap > 1.5 * med:
                            segs.append(seg)  # ban ve thu 2 dat canh: tach doan
                            seg = [(nm, c)]
                        else:
                            if (unit["label"], nm) not in dup_seen:
                                dup_seen.add((unit["label"], nm))
                                issues.append(("KHOP-TRUNGTRUC", "LOI",
                                               "Truc %s lap 2 lan trong %s (%d / %d)"
                                               % (nm, unit["label"], c0, c)))
                        continue
                    seg.append((nm, c))
                segs.append(seg)
                for s in segs:
                    if len(s) >= 2:
                        seqs.append((fam, orient, s))
    seqs.sort(key=lambda s: -len(s[2]))
    return seqs


def check_axes(units, issues):
    votes = {}        # key -> list (label, value, consec)
    orders = {}       # fam -> list (label, [names])
    for u in units:
        u["seqs"] = build_sequences(u, issues)
        upairs = {}
        for fam, orient, s in u["seqs"]:
            orders.setdefault(fam, [])
            if not any(o[0] == u["label"] for o in orders[fam]):
                orders[fam].append((u["label"], [n for n, _ in s]))
            for i in range(len(s)):
                for j in range(i + 1, len(s)):
                    k = pairkey(s[i][0], s[j][0])
                    v = abs(s[j][1] - s[i][1])
                    cons = (j == i + 1)
                    if k in upairs:
                        v0, c0, rep = upairs[k]
                        if abs(v - v0) > TOL and not rep and (cons or c0):
                            issues.append(("KHOP-TRUC", "LOI",
                                           "Truc %s-%s trong %s khong thong nhat: %d / %d"
                                           % (k[0], k[1], u["label"], v0, v)))
                            rep = True
                        upairs[k] = (v0, c0 or cons, rep)
                    else:
                        upairs[k] = (v, cons, False)
        for k, (v, c, _) in upairs.items():
            votes.setdefault(k, []).append((u["label"], v, c))
    # bo phieu giua cac ban ve (ktmat:vote)
    for k in sorted(votes, key=lambda k: (natkey(k[0]), natkey(k[1]))):
        lst = votes[k]
        if len(lst) < 2:
            continue
        clusters = []
        for it in sorted(lst, key=lambda x: x[1]):
            if clusters and abs(it[1] - clusters[-1][0][1]) <= TOL:
                clusters[-1].append(it)
            else:
                clusters.append([it])
        if len(clusters) < 2:
            continue
        clusters.sort(key=lambda c: -len(c))
        if len(clusters[0]) > len(clusters[1]):
            ref = clusters[0]
            for c in clusters[1:]:
                for it in c:
                    if it[2]:
                        issues.append(("KHOP-TRUC", "LOI", "Truc %s-%s: %s = %d, %s = %d"
                                       % (k[0], k[1], it[0], it[1],
                                          ",".join(r[0] for r in ref), ref[0][1])))
        elif any(it[2] for it in lst):
            issues.append(("KHOP-TRUC", "LOI", "Truc %s-%s: %s"
                           % (k[0], k[1], ", ".join("%s = %d" % (it[0], it[1]) for it in lst))))
    # thu tu (ktmat:order)
    for fam, lst in orders.items():
        if len(lst) < 2:
            continue
        ref = max(lst, key=lambda o: len(o[1]))
        for lab, names in lst:
            if lab == ref[0]:
                continue
            com = [n for n in ref[1] if n in names]
            if len(com) < 3:
                continue
            mine = [n for n in names if n in com]
            if mine != com and mine != com[::-1]:
                issues.append(("KHOP-THUTU", "CANHBAO", "Thu tu truc khac: %s: %s ; %s: %s"
                               % (ref[0], ",".join(com), lab, ",".join(mine))))


def check_dims(units, issues):
    tolm = max(2 * TOL, 5.0)
    for u in units:
        for d in u["dims"]:
            p13, p14, dr, val = d
            idx = 0 if dr == "H" else 1
            for fam, orient, s in u["seqs"]:
                if orient != dr:
                    continue
                a = [n for n, c in s if abs(c - p13[idx]) <= tolm]
                b = [n for n, c in s if abs(c - p14[idx]) <= tolm]
                if a and b and a[0] != b[0]:
                    ca = dict(s)[a[0]]
                    cb = dict(s)[b[0]]
                    ad = abs(cb - ca)
                    if abs(val - ad) > TOL:
                        ends = {s[0][0], s[-1][0]}
                        code = "KHOP-TONG" if ({a[0], b[0]} == ends and len(s) >= 3) else "KHOP-DIMTRUC"
                        issues.append((code, "LOI", "Dim truc %s-%s ghi %d, khoang cach truc = %d (%s)"
                                       % (a[0], b[0], val, ad, u["label"])))
                    break


# ---------------------------------------------------------------- cao do
def check_levels(units, issues):
    for u in units:
        if not ({"MD", "MC"} & u["flags"]):
            continue
        kinds = {}
        for lv in u["levels"]:
            kinds.setdefault(lv[3], []).append(lv)
        for kind, syms in kinds.items():
            if len(syms) < 2:
                continue
            zeros = [s for s in syms if abs(s[0]) < 1e-6]
            if zeros:
                datums = [(g[0][2], 0.0) for g in chain_groups(zeros, lambda s: s[2], TOL_LV)]
            else:
                m = min(syms, key=lambda s: s[0])
                datums = [(m[2], m[0])]
            for v, x, y, _ in syms:
                best = None
                for yd, vd in datums:
                    err = abs(y - (yd + (v - vd) * 1000.0))
                    if best is None or err < best[0]:
                        best = (err, yd, vd)
                if best[0] > TOL_LV:
                    meas = best[2] + (y - best[1]) / 1000.0
                    issues.append(("KHOP-CAODO-VITRI", "LOI",
                                   "Cao do %+.3f dat sai vi tri, do duoc %+.3f (%s)"
                                   % (v, meas, u["label"])))
    # giua cac mat dung / mat cat
    sets = []
    for u in units:
        if {"MD", "MC"} & u["flags"]:
            vals = sorted(set(round(lv[0], 3) for lv in u["levels"]))
            if vals:
                sets.append((u["label"], vals))
    if len(sets) >= 2:
        mx = [(lab, vals[-1]) for lab, vals in sets]
        if max(m for _, m in mx) - min(m for _, m in mx) > TOL_V:
            issues.append(("KHOP-CAODO", "CANHBAO", "Cao do dinh khac nhau: "
                           + ", ".join("%s = %+.3f" % m for m in mx)))
        seen = set()
        for i in range(len(sets)):
            for j in range(i + 1, len(sets)):
                (l1, s1), (l2, s2) = sets[i], sets[j]
                for v1 in s1:
                    if any(abs(v1 - w) <= TOL_V for w in s2):
                        continue
                    for v2 in s2:
                        if any(abs(v2 - w) <= TOL_V for w in s1):
                            continue
                        if TOL_V < abs(v1 - v2) <= NEAR_LV and (l1, l2, v1, v2) not in seen:
                            seen.add((l1, l2, v1, v2))
                            issues.append(("KHOP-CAODO", "CANHBAO",
                                           "Cao do lech: %s = %+.3f, %s = %+.3f"
                                           % (l1, v1, l2, v2)))
    # cao do ghi tren mat bang
    ref = [lv[0] for u in units if "MC" in u["flags"] for lv in u["levels"]]
    if not ref:
        ref = [lv[0] for u in units if "MD" in u["flags"] for lv in u["levels"]]
    if ref:
        for u in units:
            if "MB" in u["flags"] and not ({"MD", "MC"} & u["flags"]):
                for lv in u["levels"]:
                    if not any(abs(lv[0] - r) <= TOL_V for r in ref):
                        issues.append(("KHOP-CAODO-MB", "GOIY",
                                       "Cao do %+.3f tren mat bang %s khong co tren mat cat"
                                       % (lv[0], u["label"])))


def run(units):
    issues = []
    check_axes(units, issues)
    check_dims(units, issues)
    check_levels(units, issues)
    return issues


# ---------------------------------------------------------------- du lieu gia lap
BAY_X = [0, 3600, 7200, 11000, 14600]           # truc 1..5
BAY_Y = [0, 4200, 8000, 11500]                  # truc A..D
NUM = ["1", "2", "3", "4", "5"]
LET = ["A", "B", "C", "D"]
LEVELS = [0.0, 3.6, 7.2, 10.2]                  # +-0.000, +3.600, +7.200, mai +10.200


def plan(label, ox, oy, xs=BAY_X, ys=BAY_Y, lv=None, dims=None):
    b = []
    for n, x in zip(NUM, xs):           # hang tren + hang duoi
        b.append((n, ox + x, oy + ys[-1] + 2500, 800))
        b.append((n, ox + x, oy - 2500, 800))
    for n, y in zip(LET, ys):           # cot trai + cot phai
        b.append((n, ox - 2500, oy + y, 800))
        b.append((n, ox + xs[-1] + 2500, oy + y, 800))
    d = []
    for i in range(len(xs) - 1):        # chuoi dim truc ngang
        d.append(((ox + xs[i], 0), (ox + xs[i + 1], 0), "H", xs[i + 1] - xs[i]))
    d.append(((ox + xs[0], 0), (ox + xs[-1], 0), "H", xs[-1] - xs[0]))
    if dims:
        d += dims
    return {"label": label, "flags": {"MB"}, "bubbles": b, "dims": d,
            "levels": [(v, ox, oy, "TEXT") for v in (lv or [])]}


def section(label, ox, oy, ys=BAY_Y, lv=LEVELS, lvy=None, flag="MC"):
    b = [(n, ox + y, oy - 2000, 800) for n, y in zip(LET, ys)]   # truc A..D nam ngang
    lvy = lvy or [v * 1000 for v in lv]
    levels = []
    for v, y in zip(lv, lvy):
        levels.append((v, ox - 1500, oy + y, "BLOCK"))        # ben trai
        levels.append((v, ox + ys[-1] + 1500, oy + y, "BLOCK"))  # ben phai
    d = [((ox + ys[0], 0), (ox + ys[-1], 0), "H", ys[-1] - ys[0])]
    return {"label": label, "flags": {flag}, "bubbles": b, "dims": d, "levels": levels}


def codes(iss):
    return sorted(i[0] for i in iss)


def scenario_clean():
    units = [plan("KT-01", 0, 0, lv=[0.0]), plan("KT-02", 50000, 0, lv=[3.6]),
             section("KT-05", 100000, 0), section("KT-04", 150000, 0, flag="MD")]
    return run(units)


def scenario_errors():
    ys_bad = list(BAY_Y)
    ys_bad[1] += 100                                   # mat cat: truc B lech 100
    lvy = [v * 1000 for v in LEVELS]
    lvy[1] -= 50                                       # +3.600 dat thap 50 mm
    units = [plan("KT-01", 0, 0, lv=[0.0]),
             plan("KT-02", 50000, 0, lv=[3.55],        # COS +3.550 khong co tren mat cat
                  dims=[((50000 + 3600, 0), (50000 + 7200, 0), "H", 3500)]),  # dim ghi de sai
             section("KT-05", 100000, 0, ys=ys_bad, lvy=lvy),
             section("KT-04", 150000, 0, lv=[0.0, 3.6, 7.15, 10.5], flag="MD")]   # mai 10.5, +7.150
    return run(units)


def scenario_side_by_side():
    """2 mat bang dat canh nhau trong cung 1 khung + 1 mat bang lap truc that"""
    u = plan("KT-01", 0, 0)
    u2 = plan("X", 30000, 0)
    u["bubbles"] += u2["bubbles"]
    bad = plan("KT-03", 0, 0)
    bad["bubbles"].append(("3", 9000, BAY_Y[-1] + 2500, 800))   # danh nham ten truc 4 -> "3"
    bad["bubbles"] = [b for b in bad["bubbles"]
                      if not (b[0] == "4" and b[2] > 0)]
    return run([u, bad])


def scenario_order():
    swapped = plan("KT-02", 50000, 0)
    ren = {"B": "C", "C": "B"}
    swapped["bubbles"] = [(ren.get(n, n), x, y, s) for n, x, y, s in swapped["bubbles"]]
    return run([plan("KT-01", 0, 0), plan("KT-03", 100000, 0), swapped])


def main():
    ok = True

    def expect(name, iss, want):
        nonlocal ok
        got = codes(iss)
        good = got == sorted(want)
        ok = ok and good
        print("[%s] %s" % ("OK " if good else "SAI", name))
        for i in iss:
            print("     %-17s %-7s %s" % i)
        if not good:
            print("     mong doi:", sorted(want), "\n     thuc te :", got)

    expect("1. Ho so dung - khong duoc bao gi", scenario_clean(), [])
    expect("2. Lech truc B (mat cat), lech cao do, dim ghi de, mai khac",
           scenario_errors(),
           ["KHOP-TRUC", "KHOP-TRUC",                 # A-B va B-C tren KT-05
            "KHOP-DIMTRUC",                           # dim 2-3 ghi 3500 tren KT-02
            "KHOP-CAODO-VITRI", "KHOP-CAODO-VITRI",   # +3.600 (2 ben) tren KT-05
            "KHOP-CAODO", "KHOP-CAODO",               # dinh 10.2 vs 10.5 + 7.200/7.150
            "KHOP-CAODO-MB"])                          # +3.550 tren mat bang
    expect("3. 2 mat bang canh nhau (khong bao) + trung ten truc that",
           scenario_side_by_side(), ["KHOP-TRUNGTRUC"])
    expect("4. Thu tu truc B/C bi doi", scenario_order(),
           ["KHOP-THUTU", "KHOP-TRUC", "KHOP-TRUC"])   # A-C, B-D (cap lien tiep tren KT-02)
    print("\nKET QUA:", "DAT" if ok else "KHONG DAT")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
