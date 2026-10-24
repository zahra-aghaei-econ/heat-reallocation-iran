#!/usr/bin/env python3
"""
make_tex_tables_c.py
--------------------
LaTeX fragments for batch B (steps 26 and 27).  Reads result datasets only; runs no regression.
Every block is skipped if its input file is missing.

Usage (project root):   python tools/make_tex_tables_c.py [RUN_NAME]
Writes into output/<RUN_NAME>/tex/:
    timing.tex          exposure window and threshold, exit from agriculture (+ non-employment)
    rainrobust.tex      rainfall controls, M7
    rainrobust_m8.tex   rainfall controls, M8 (county trend)
    fittedrange.tex     share of fitted values outside [0,100]
    unemp_rural.tex     unemployed at origin, urban and rural slopes, Holm p
    numbers_c.tex       macros for the text
"""
import sys
import os
import pandas as pd

RUN = sys.argv[1] if len(sys.argv) > 1 else "run3_new_period_svc"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "output", RUN, "results")
TEX = os.path.join(ROOT, "output", RUN, "tex")
os.makedirs(TEX, exist_ok=True)
macros = {}


def have(name):
    ok = os.path.exists(os.path.join(RES, name + ".dta"))
    if not ok:
        print("skipped (missing):", name)
    return ok


def rd(name):
    return pd.read_stata(os.path.join(RES, name + ".dta"), convert_categoricals=False)


def stars(p):
    if pd.isna(p):
        return ""
    return "***" if p < 0.01 else "**" if p < 0.05 else "*" if p < 0.10 else ""


def mnum(x, d=3):
    s = f"{abs(x):.{d}f}"
    return ("-" if x < 0 and float(s) != 0 else "") + s


def cell(b, p, d=3):
    st = stars(p)
    return f"${mnum(b, d)}" + (f"^{{{st}}}" if st else "") + "$"


def two(b, se, p, d=3):
    return f"\\shortstack{{{cell(b, p, d)}\\\\({se:.{d}f})}}"


def pfmt(p):
    return "$<0.001$" if p < 0.001 else f"${p:.3f}$"


def th(n):
    return f"{int(round(n)):,}".replace(",", "{,}")


def write(name, text):
    with open(os.path.join(TEX, name), "w", encoding="utf-8") as f:
        f.write(text)
    print("wrote", name)


def get(df, **kw):
    m = pd.Series(True, index=df.index)
    for k, v in kw.items():
        m &= df[k] == v
    r = df[m]
    if len(r) != 1:
        raise ValueError(f"expected one row for {kw}, got {len(r)}")
    return r.iloc[0]


# ------------------------------------------------------------ timing
if have("lpm_timing_results"):
    d = rd("lpm_timing_results")
    d = d[d.kind == "exposure"]
    blocks = [
        ("Origin season (headline reference)", "1_origin_Days35", "1_origin_HeatDose35", "Days35 /10", "HeatDose35 /10"),
        ("Origin season, lower absolute threshold", "2_origin_Days32", "2_origin_HeatDose32", "Days32 /10", "HeatDose32 /10"),
        ("Preceding season", "3_preceding_Days35", "3_preceding_HeatDose35", "Days35 /10", "HeatDose35 /10"),
        ("Destination season", "4_destination_Days35", "4_destination_HeatDose35", "Days35 /10", "HeatDose35 /10"),
    ]
    t = ("\\begin{tabular}{llcccc}\n\\toprule\nExposure window & Measure & Exit from agriculture & $p$ & Non-employment exit & $N$ \\\\\n\\midrule\n")
    for i, (title, pd_, ph_, ld, lh) in enumerate(blocks):
        if i:
            t += "\\midrule\n"
        t += f"\\multicolumn{{6}}{{l}}{{\\emph{{{title}}}}}\\\\\n"
        for fam, pn, lab in [("Timing_Days", pd_, ld), ("Timing_Heat", ph_, lh)]:
            r = get(d, family=fam, panel=pn, outcome="exit_agri")
            r2 = get(d, family=fam, panel=pn, outcome="distress_exit")
            if r.status != "ok":
                t += f" & {lab} & -- & & -- & \\\\\n"
                continue
            t += (f" & {lab} & {two(r.coef, r.se, r.pvalue)} & {pfmt(r.pvalue)} & "
                  f"{two(r2.coef, r2.se, r2.pvalue)} & {th(r.n_used)} \\\\\n")
    t += "\\bottomrule\n\\end{tabular}\n"
    write("timing.tex", t)

    def mk(prefix, fam, pn):
        r = get(d, family=fam, panel=pn, outcome="exit_agri")
        macros[prefix + "Coef"] = mnum(r.coef)
        macros[prefix + "Se"] = f"{r.se:.3f}"
        macros[prefix + "P"] = f"{r.pvalue:.3f}"
    mk("TimDaysThirtyTwo", "Timing_Days", "2_origin_Days32")
    mk("TimHeatThirtyTwo", "Timing_Heat", "2_origin_HeatDose32")
    mk("TimDaysPrev", "Timing_Days", "3_preceding_Days35")
    mk("TimHeatPrev", "Timing_Heat", "3_preceding_HeatDose35")
    mk("TimDaysDest", "Timing_Days", "4_destination_Days35")
    mk("TimHeatDest", "Timing_Heat", "4_destination_HeatDose35")
    macros["TimNDest"] = th(get(d, family="Timing_Days", panel="4_destination_Days35", outcome="exit_agri").n_used)
    macros["TimNOrigin"] = th(get(d, family="Timing_Days", panel="1_origin_Days35", outcome="exit_agri").n_used)

# ------------------------------------------------------------ rain controls
if have("lpm_rain_results"):
    d = rd("lpm_rain_results")
    de = d[d.kind == "exposure"]
    dt = d[d.kind == "test"]
    OUT3 = [("exit_agri", "Exit from agriculture"), ("distress_exit", "Non-employment exit"),
            ("productive_exit", "Productive exit")]
    for mnum_, fname in [(7, "rainrobust.tex"), (8, "rainrobust_m8.tex")]:
        t = ("\\begin{tabular}{lccc}\n\\toprule\n & No rainfall controls & Linear rainfall only & Linear + squared rainfall (baseline) \\\\\n\\midrule\n")
        for i, (fam, title) in enumerate([("Rain_Days35", "Panel A: Days35 /10"), ("Rain_HeatDose35", "Panel B: HeatDose35 /10")]):
            if i:
                t += "\\midrule\n"
            t += f"\\multicolumn{{4}}{{l}}{{\\emph{{{title}}}}}\\\\\n"
            for oc, ol in OUT3:
                cs, ss = [], []
                for pn in ["R0_no_rain", "R1_linear_rain", "R2_quadratic_rain"]:
                    r = get(de, family=fam, panel=pn, outcome=oc, model_num=mnum_)
                    cs.append(cell(r.coef, r.pvalue) if r.status == "ok" else "--")
                    ss.append(f"({r.se:.3f})" if r.status == "ok" else "")
                t += f"{ol} & " + " & ".join(cs) + " \\\\\n & " + " & ".join(ss) + " \\\\\n"
        t += "\\bottomrule\n\\end{tabular}\n"
        write(fname, t)
    # macros: stability and Wald tests
    r0 = get(de, family="Rain_Days35", panel="R0_no_rain", outcome="exit_agri", model_num=7).coef
    r1 = get(de, family="Rain_Days35", panel="R1_linear_rain", outcome="exit_agri", model_num=7).coef
    r2 = get(de, family="Rain_Days35", panel="R2_quadratic_rain", outcome="exit_agri", model_num=7).coef
    macros["RainDaysNone"] = mnum(r0)
    macros["RainDaysLinear"] = mnum(r1)
    macros["RainDaysQuad"] = mnum(r2)
    macros["RainMaxChangePct"] = f"{100 * max(abs(r0 - r2), abs(r1 - r2)) / abs(r2):.1f}"
    nm = {7: "MSeven", 8: "MEight"}
    for fam, tag in [("Rain_Days35", "Days"), ("Rain_HeatDose35", "Heat")]:
        for m in (7, 8):
            for oc, on in [("exit_agri", "Exit"), ("distress_exit", "Nonemp")]:
                r = get(dt, family=fam, panel="R2_quadratic_rain", outcome=oc, model_num=m)
                macros[f"RainWald{tag}{nm[m]}{on}"] = f"{r.pvalue:.3f}"

# ------------------------------------------------------------ fitted range
if have("fitted_range"):
    d = rd("fitted_range").set_index("outcome")
    names = [("exit_agri", "Exit from agriculture"), ("productive_exit", "Productive exit"),
             ("distress_exit", "Non-employment exit"), ("dest2", "Industry"), ("dest3", "Services"),
             ("dest4", "Unemployment"), ("dest5", "Inactivity")]
    t = "\\begin{tabular}{lrrrr}\n\\toprule\nOutcome & $N$ & Below 0 & Above 100 & Share outside \\\\\n\\midrule\n"
    for k, lab in names:
        r = d.loc[k]
        t += f"{lab} & {th(r.n_obs)} & {th(r.n_below)} & {th(r.n_above)} & {r.share_outside:.3f}\\% \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("fittedrange.tex", t)
    macros["FitOutExit"] = f"{d.loc['exit_agri'].share_outside:.3f}"
    macros["FitOutUnemp"] = f"{d.loc['dest4'].share_outside:.1f}"
    macros["FitOutServ"] = f"{d.loc['dest3'].share_outside:.1f}"

# ------------------------------------------------------------ unemployed x rural
if have("lpm_unemp_rural_results"):
    d = rd("lpm_unemp_rural_results")
    LAB = [("u_remain", "Remain unemployed"), ("u_exit", "Exit unemployment to any other state"),
           ("u_anyemp", "Enter any employment"), ("u_nonfarm", "Enter nonfarm employment (industry or services)"),
           ("u_agri", "Enter agriculture"), ("u_ind", "Enter industry"), ("u_serv", "Enter services"),
           ("u_inact", "Enter inactivity"), ("u_nonemp", "Remain non-employed (unemployed or inactive)")]
    t = "\\begin{tabular}{lcccc}\n\\toprule\nOutcome & Urban slope & Rural slope & Rural $-$ Urban & Holm $p$ \\\\\n\\midrule\n"
    for i, (nm_, title) in enumerate([("Days35", "Panel A: Days35, per 10 origin-season days at or above $35^\\circ$C"),
                                      ("HeatDose35", "Panel B: HeatDose35, per 10 degree-days above $35^\\circ$C")]):
        if i:
            t += "\\midrule\n"
        t += f"\\multicolumn{{5}}{{l}}{{\\emph{{{title}}}}}\\\\\n"
        s = d[d.measure == nm_].set_index("outcome").loc[[k for k, _ in LAB]]
        # Holm step-down over the nine outcomes
        order = s.int_p.sort_values().index.tolist()
        m = len(order)
        adj, run = {}, 0.0
        for j, k in enumerate(order):
            run = max(run, (m - j) * s.loc[k, "int_p"])
            adj[k] = min(1.0, run)
        for k, lab in LAB:
            r = s.loc[k]
            t += (f"{lab} & {two(r.urban_b, r.urban_se, r.urban_p)} & {two(r.rural_b, r.rural_se, r.rural_p)} & "
                  f"{cell(r.int_b, r.int_p)} & ${adj[k]:.3f}$ \\\\\n")
        if nm_ == "Days35":
            macros["UnRuralN"] = th(s.n_obs.iloc[0])
            macros["UnRuralShareRural"] = f"{100 * s.share_rural.iloc[0]:.0f}"
            macros["UnRuralDaysRemainUrban"] = mnum(s.loc["u_remain", "urban_b"])
            macros["UnRuralDaysRemainRural"] = mnum(s.loc["u_remain", "rural_b"])
            macros["UnRuralDaysRemainDiffP"] = f"{s.loc['u_remain', 'int_p']:.3f}"
            macros["UnRuralMinHolmDays"] = f"{min(adj.values()):.3f}"
        else:
            macros["UnRuralMinHolmHeat"] = f"{min(adj.values()):.3f}"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("unemp_rural.tex", t)

# ------------------------------------------------------------ education check (step 23)
if have("lpm_education_results"):
    d = rd("lpm_education_results")
    d = d[d.kind == "exposure"]
    ROWS = [("E1", "Full sample, preferred specification, no education"),
            ("E2", "Education-observed sample, preferred specification, no education"),
            ("E3", "Education-observed sample, preferred specification, + education"),
            ("E4", "Education-observed sample, + county trend, no education"),
            ("E5", "Education-observed sample, + county trend, + education")]
    t = "\\begin{tabular}{>{\\raggedright\\arraybackslash}p{0.46\\textwidth}ccc}\n\\toprule\n & Exit from agriculture & Productive exit & Non-employment exit \\\\\n\\midrule\n"
    ns = {}
    for i, (fam, title) in enumerate([("Educ_Days35", "Days35 /10"), ("Educ_HeatDose35", "HeatDose35 /10")]):
        if i:
            t += "\\midrule\n"
        t += f"\\multicolumn{{4}}{{l}}{{\\emph{{{title}}}}}\\\\\n"
        for pn, lab in ROWS:
            cs, ss = [], []
            for oc in ["exit_agri", "productive_exit", "distress_exit"]:
                r = d[(d.family == fam) & (d.panel == pn) & (d.outcome == oc)]
                if len(r) != 1 or r.iloc[0].status != "ok":
                    cs.append("--"); ss.append("")
                    continue
                r = r.iloc[0]
                cs.append(cell(r.coef, r.pvalue)); ss.append(f"({r.se:.3f})")
                ns[pn] = r.n_used
            t += f"{lab} & " + " & ".join(cs) + " \\\\\n & " + " & ".join(ss) + " \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("education.tex", t)
    macros["EducNFull"] = th(ns["E1"])
    macros["EducNObs"] = th(ns["E2"])

lines = ["% Written by tools/make_tex_tables_c.py (run " + RUN + "). Do not edit by hand."]
for k in sorted(macros):
    v = macros[k]
    lines.append("\\newcommand{\\%s}{%s}" % (k, v.replace("-", "$-$") if v.startswith("-") else v))
write("numbers_c.tex", "\n".join(lines) + "\n")
