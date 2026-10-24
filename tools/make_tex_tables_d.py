#!/usr/bin/env python3
"""
make_tex_tables_d.py
--------------------
LaTeX fragments for batch C (steps 28, 29, 42, 43, 44, 45).  Reads result datasets only; runs no
regression.  Every block is skipped if its input file is missing.

Usage (project root):   python tools/make_tex_tables_d.py [RUN_NAME]
Writes into output/<RUN_NAME>/tex/:
    linkage.tex, linkage_tiers.tex, linkage_validation.tex        (step 28)
    spatial_se.tex, spatial_ci.tex                                (step 29)
    attr_byyear.tex, attr_weather.tex, attr_het.tex,
    attr_propensity.tex, attr_weights.tex, attr_balance.tex,
    ipw_days35.tex, ipw_heat35.tex                                (step 42)
    het_tests.tex, het_slopes.tex                                 (step 43)
    idvar.tex                                                     (step 44)
    balance.tex                                                   (step 45)
    numbers_d.tex                                                 (macros for the text)
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

OUT7 = [("exit_agri", "Exit from agriculture"), ("productive_exit", "Productive exit"),
        ("distress_exit", "Non-employment exit"), ("dest2", "\\quad To industry"),
        ("dest3", "\\quad To services"), ("dest4", "\\quad To unemployment"),
        ("dest5", "\\quad To inactivity")]


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
    if pd.isna(p):
        return "--"
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


def sval(x):
    return str(x).strip()


# =============================================================== 28 linkage
if have("lpm_linkage_results"):
    d = rd("lpm_linkage_results")
    d = d[d.kind == "exposure"]
    t = ("\\begin{tabular}{lcccc}\n\\toprule\n & \\multicolumn{2}{c}{Days35 /10} & \\multicolumn{2}{c}{HeatDose35 /10} \\\\\n"
         "\\cmidrule(lr){2-3}\\cmidrule(lr){4-5}\nOutcome & Baseline sample & Member-number IDs only & Baseline sample & Member-number IDs only \\\\\n\\midrule\n")
    for oc, lab in OUT7:
        cells = []
        for fam in ["Linkage_Days35", "Linkage_HeatDose35"]:
            for pn in ["1_baseline", "2_strict"]:
                r = get(d, family=fam, panel=pn, outcome=oc)
                cells.append(two(r.coef, r.se, r.pvalue) if r.status == "ok" else "--")
        t += f"{lab} & " + " & ".join(cells) + " \\\\\n"
    t += "\\midrule\n"
    ns, cl = [], []
    for fam in ["Linkage_Days35", "Linkage_HeatDose35"]:
        for pn in ["1_baseline", "2_strict"]:
            r = get(d, family=fam, panel=pn, outcome="exit_agri")
            ns.append(th(r.n_used))
            cl.append(th(r.n_clusters))
    t += "Estimation observations & " + " & ".join(ns) + " \\\\\nCounty clusters & " + " & ".join(cl) + " \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("linkage.tex", t)
    b = get(d, family="Linkage_Days35", panel="1_baseline", outcome="exit_agri")
    s = get(d, family="Linkage_Days35", panel="2_strict", outcome="exit_agri")
    macros["LinkBaseExit"] = mnum(b.coef)
    macros["LinkStrictExit"] = mnum(s.coef)
    macros["LinkStrictExitSe"] = f"{s.se:.3f}"
    macros["LinkStrictExitP"] = f"{s.pvalue:.3f}"
    macros["LinkAttenExit"] = f"{100 * (1 - s.coef / b.coef):.0f}"
    macros["LinkStrictN"] = th(s.n_used)
    macros["LinkBaseN"] = th(b.n_used)
    bh = get(d, family="Linkage_HeatDose35", panel="1_baseline", outcome="exit_agri")
    sh = get(d, family="Linkage_HeatDose35", panel="2_strict", outcome="exit_agri")
    macros["LinkBaseExitHeat"] = mnum(bh.coef, 4)
    macros["LinkStrictExitHeat"] = mnum(sh.coef, 4)
    macros["LinkStrictExitHeatP"] = f"{sh.pvalue:.3f}"
    sig = 0
    same_sign = 0
    for oc, _ in OUT7:
        a = get(d, family="Linkage_Days35", panel="1_baseline", outcome=oc)
        c = get(d, family="Linkage_Days35", panel="2_strict", outcome=oc)
        same_sign += int((a.coef > 0) == (c.coef > 0))
        sig += int(c.pvalue < 0.05)
    macros["LinkSameSignN"] = str(same_sign)
    macros["LinkSigN"] = str(sig)

if have("linkage_flow"):
    d = rd("linkage_flow")
    macros["LinkFlowBase"] = th(d.n_obs.iloc[0])
    macros["LinkFlowStrict"] = th(d.n_obs.iloc[1])
    macros["LinkFlowRemoved"] = th(d.n_obs.iloc[2])
    macros["LinkFlowRemovedPct"] = f"{d.pct_of_baseline.iloc[2]:.1f}"
    macros["LinkFlowRemovedWPct"] = f"{d.pct_weighted.iloc[2]:.1f}"

if have("linkage_tiers"):
    d = rd("linkage_tiers")
    t = ("\\begin{tabular}{lrrrr}\n\\toprule\nID tier & $N$ & Share (\\%) & Same sex (\\%) & Age gap 0--2 years (\\%) \\\\\n\\midrule\n")
    for _, r in d.iterrows():
        ss = "--" if pd.isna(r.same_sex_pct) else f"{r.same_sex_pct:.2f}"
        ag = "--" if pd.isna(r.age_gap_ok_pct) else f"{r.age_gap_ok_pct:.2f}"
        t += f"{sval(r.label)} & {th(r.n_obs)} & {r.share:.2f} & {ss} & {ag} \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("linkage_tiers.tex", t)
    m = d[d.pid_source == 1]
    if len(m):
        macros["LinkTierOneShare"] = f"{m.share.iloc[0]:.1f}"

if have("linkage_byyear"):
    d = rd("linkage_byyear")
    pos = d[d.n_strict > 0]
    if len(pos):
        macros["LinkFirstStrictYear"] = str(int(pos.year_origin.min()))
    macros["LinkNoStrictYears"] = ", ".join(str(int(y)) for y in d[d.n_strict == 0].year_origin)

if have("linkage_validation"):
    d = rd("linkage_validation")
    t = ("\\begin{tabular}{lcc}\n\\toprule\nValidation statistic & All benchmark transitions & Agriculture-origin transitions \\\\\n\\midrule\n")
    a, g = d.iloc[0], d.iloc[1]

    def row(lbl, f, fmt):
        return f"{lbl} & {fmt(a[f])} & {fmt(g[f])} \\\\\n"
    def f0(x):
        return "--" if pd.isna(x) else th(x)
    def f3(x):
        return "--" if pd.isna(x) else f"{x:.3f}"
    def f4(x):
        return "--" if pd.isna(x) else f"{x:.4f}"
    t += row("Benchmark transitions", "bench_n", f0)
    t += row("Recovered by the fallback", "rec_n", f0)
    t += row("Recovery rate (\\%)", "rec_pct", f3)
    t += row("Exact-person matches", "exact_n", f0)
    t += row("Wrong-person matches", "wrong_n", f0)
    t += row("Exact-person agreement among recovered (\\%)", "exact_pct", f4)
    t += row("Wrong-person rate among recovered (\\%)", "wrong_pct", f4)
    t += row("Labor-state agreement (\\%)", "jobok_pct", f4)
    t += row("Agricultural-exit classification agreement (\\%)", "exitok_pct", f4)
    t += "\\bottomrule\n\\end{tabular}\n"
    write("linkage_validation.tex", t)
    macros["ValBenchAll"] = th(a.bench_n)
    macros["ValBenchAg"] = th(g.bench_n)
    macros["ValRecAll"] = f"{a.rec_pct:.1f}"
    macros["ValRecAg"] = f"{g.rec_pct:.1f}"
    macros["ValWrongAllN"] = th(a.wrong_n)
    macros["ValWrongAgN"] = th(g.wrong_n)
    macros["ValWrongAgPct"] = f"{g.wrong_pct:.4f}"
    macros["ValExitAgree"] = f"{g.exitok_pct:.3f}"
    macros["ValJobAgree"] = f"{g.jobok_pct:.3f}"

# =============================================================== 29 spatial inference
if have("spatial_inference_results"):
    d = rd("spatial_inference_results")
    d["exposure"] = d.exposure.map(sval)
    d["outcome"] = d.outcome.map(sval)
    t = ("\\begin{tabular}{lcccccc}\n\\toprule\n & & \\multicolumn{5}{c}{Standard error} \\\\\n\\cmidrule(lr){3-7}\n"
         "Outcome & Coefficient & County cluster & Two-way & Conley 100 km & Conley 200 km & Conley 300 km \\\\\n\\midrule\n")
    for i, (en, title) in enumerate([("Days35", "Panel A: Days35 /10"), ("HeatDose35", "Panel B: HeatDose35 /10")]):
        if i:
            t += "\\midrule\n"
        t += f"\\multicolumn{{7}}{{l}}{{\\emph{{{title}}}}}\\\\\n"
        for oc, lab in OUT7:
            rs = [get(d, exposure=en, outcome=oc, method_id=k) for k in (1, 2, 3, 4, 5)]
            dd = 4 if en == "HeatDose35" else 3
            t += (f"{lab} & {cell(rs[0].coef, rs[0].pvalue, dd)} & " + " & ".join(f"{r.se:.{dd}f}" for r in rs) + " \\\\\n")
    t += "\\bottomrule\n\\end{tabular}\n"
    write("spatial_se.tex", t)

    t = ("\\begin{tabular}{lccccc}\n\\toprule\nOutcome & County cluster & Two-way & Conley 100 km & Conley 200 km & Conley 300 km \\\\\n\\midrule\n")
    for i, (en, title) in enumerate([("Days35", "Panel A: Days35 /10"), ("HeatDose35", "Panel B: HeatDose35 /10")]):
        if i:
            t += "\\midrule\n"
        t += f"\\multicolumn{{6}}{{l}}{{\\emph{{{title}}}}}\\\\\n"
        for oc, lab in OUT7[:3]:
            rs = [get(d, exposure=en, outcome=oc, method_id=k) for k in (1, 2, 3, 4, 5)]
            dd = 4 if en == "HeatDose35" else 3
            t += f"{lab} & " + " & ".join(f"$[{mnum(r.ci_lo, dd)},\\,{mnum(r.ci_hi, dd)}]$" for r in rs) + " \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("spatial_ci.tex", t)

    e1 = get(d, exposure="Days35", outcome="exit_agri", method_id=1)
    e2 = get(d, exposure="Days35", outcome="exit_agri", method_id=2)
    e3 = get(d, exposure="Days35", outcome="exit_agri", method_id=3)
    e5 = get(d, exposure="Days35", outcome="exit_agri", method_id=5)
    macros["SpatSeCounty"] = f"{e1.se:.3f}"
    macros["SpatSeTwoway"] = f"{e2.se:.3f}"
    macros["SpatSeHacHundred"] = f"{e3.se:.3f}"
    macros["SpatSeHacThreeHundred"] = f"{e5.se:.3f}"
    macros["SpatRatioThreeHundred"] = f"{e5.se / e1.se:.2f}"
    macros["SpatPThreeHundred"] = f"{e5.pvalue:.4f}"
    macros["SpatCiLoThreeHundred"] = mnum(e5.ci_lo)
    macros["SpatCiHiThreeHundred"] = mnum(e5.ci_hi)
    for en, tag in [("Days35", "Days"), ("Heat" + "Dose35", "Heat")]:
        nsig = {}
        for k, nm in [(1, "County"), (2, "Twoway"), (3, "HacH"), (4, "HacTwoH"), (5, "HacThreeH")]:
            sub = d[(d.exposure == en) & (d.method_id == k)]
            nsig[nm] = int((sub.pvalue < 0.05).sum())
            macros[f"SpatSig{tag}{nm}"] = str(nsig[nm])
        ratios = []
        for oc, _ in OUT7:
            a = get(d, exposure=en, outcome=oc, method_id=1)
            b = get(d, exposure=en, outcome=oc, method_id=5)
            ratios.append(b.se / a.se)
        macros[f"SpatRatioMax{tag}"] = f"{max(ratios):.2f}"
        macros[f"SpatRatioMin{tag}"] = f"{min(ratios):.2f}"

# =============================================================== 44 identifying variation
if have("idvar_results"):
    d = rd("idvar_results")
    d["exposure"] = d.exposure.map(sval)
    d["panel"] = d.panel.map(sval)
    d["item"] = d["item"].map(sval)

    def v(en, pn, item):
        r = d[(d.exposure == en) & (d.panel == pn) & (d["item"] == item)]
        return float(r.value.iloc[0])
    t = "\\begin{tabular}{lcc}\n\\toprule\nDiagnostic & Days35 & HeatDose35 \\\\\n\\midrule\n"
    t += "\\multicolumn{3}{l}{\\emph{Panel A. Sample and fixed-effect cells}}\\\\\n"
    for it in ["Sample before singleton removal", "Baseline M7 estimation observations",
               "Saturated M9 estimation observations", "Common sample of the two models",
               "County clusters (M7)", "Province-year cells (M7)", "Province-year-season cells (M9)",
               "Observations removed by saturation"]:
        t += f"{it} & {th(v('Days35', 'A', it))} & {th(v('HeatDose35', 'A', it))} \\\\\n"
    for pn, title in [("B", "Panel B. Weighted residual variation"), ("C", "Panel C. Unweighted residual variation")]:
        t += f"\\midrule\n\\multicolumn{{3}}{{l}}{{\\emph{{{title}}}}}\\\\\n"
        for it in ["Raw SD", "Baseline residual SD", "Saturated residual SD", "Residual SD retained (%)",
                   "Residual variance retained (%)", "Residual variance absorbed (%)"]:
            lab = it.replace("(%)", "(\\%)")
            fmt = "{:.4f}" if "SD" in it and "(%)" not in it else "{:.2f}"
            t += f"{lab} & {fmt.format(v('Days35', pn, it))} & {fmt.format(v('HeatDose35', pn, it))} \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("idvar.tex", t)
    macros["IdvarSdRetainedDays"] = f"{v('Days35', 'B', 'Residual SD retained (%)'):.0f}"
    macros["IdvarSdRetainedHeat"] = f"{v('HeatDose35', 'B', 'Residual SD retained (%)'):.0f}"
    macros["IdvarVarRetainedDays"] = f"{v('Days35', 'B', 'Residual variance retained (%)'):.0f}"
    macros["IdvarVarRetainedHeat"] = f"{v('HeatDose35', 'B', 'Residual variance retained (%)'):.0f}"
    macros["IdvarCellsPY"] = th(v("Days35", "A", "Province-year cells (M7)"))
    macros["IdvarCellsPYS"] = th(v("Days35", "A", "Province-year-season cells (M9)"))
    macros["IdvarRemoved"] = th(v("Days35", "A", "Observations removed by saturation"))

# =============================================================== 45 balance
if have("balance_results"):
    d = rd("balance_results")
    d["exposure"] = d.exposure.map(sval)
    d["part"] = d.part.map(sval)
    d["characteristic"] = d.characteristic.map(sval)
    LAB = [("age", "Age (years)"), ("female", "Female (percentage points)"),
           ("married", "Married (percentage points)"), ("rural", "Rural origin (percentage points)")]
    t = ("\\begin{tabular}{lcc}\n\\toprule\nPredetermined characteristic & Days35 /10 & HeatDose35 /10 \\\\\n\\midrule\n")
    for k, lab in LAB:
        c = []
        for en in ["Days35", "HeatDose35"]:
            r = get(d, exposure=en, part="single", characteristic=k)
            c.append(two(r.coef, r.se, r.pvalue, 3 if en == "Days35" else 4))
        t += f"{lab} & " + " & ".join(c) + " \\\\\n"
    t += "\\midrule\nJoint $F$ test, $p$ value & "
    jp = []
    for en in ["Days35", "HeatDose35"]:
        r = get(d, exposure=en, part="joint", characteristic="all four")
        jp.append(pfmt(r.pvalue))
        macros["BalJointP" + ("Days" if en == "Days35" else "Heat")] = f"{r.pvalue:.3f}"
    t += " & ".join(jp) + " \\\\\n\\bottomrule\n\\end{tabular}\n"
    write("balance.tex", t)
    s = d[d.part == "single"]
    macros["BalMinP"] = f"{s.pvalue.min():.3f}"
    _ra = get(d, exposure="Days35", part="single", characteristic="age")
    macros["BalDaysAge"] = f"{_ra.coef:.2f}"
    macros["BalNSig"] = str(int((s.pvalue < 0.05).sum()))

# =============================================================== 42 attrition
if have("attr_byyear"):
    d = rd("attr_byyear")
    d["smp_name"] = d["smp_name"].map(sval)
    a = d[d["smp_name"] == "agri"].sort_values("year_origin")
    t = ("\\begin{tabular}{lcccc}\n\\toprule\nOrigin year & Person non-continuation (\\%) & Household non-return (\\%) & "
         "Within-household loss (\\%) & Weighted $N$ \\\\\n\\midrule\n")
    for _, r in a[a.year_origin > 0].iterrows():
        t += f"{int(r.year_origin)} & {r.person_pct:.1f} & {r.hh_pct:.1f} & {r.within_pct:.1f} & {th(r.w_total)} \\\\\n"
    p = a[a.year_origin == 0].iloc[0]
    t += (f"\\midrule\nPooled ({int((a.year_origin > 0).sum())} years) & {p.person_pct:.1f} & {p.hh_pct:.1f} & "
          f"{p.within_pct:.1f} & {th(p.w_total)} \\\\\n\\bottomrule\n\\end{{tabular}}\n")
    write("attr_byyear.tex", t)
    macros["AttrPooledPerson"] = f"{p.person_pct:.1f}"
    macros["AttrPooledHH"] = f"{p.hh_pct:.1f}"
    macros["AttrPooledWithin"] = f"{p.within_pct:.1f}"
    macros["AttrNYears"] = str(int((a.year_origin > 0).sum()))
    yy = a[a.year_origin > 0]
    macros["AttrMinPerson"] = f"{yy.person_pct.min():.0f}"
    macros["AttrMaxPerson"] = f"{yy.person_pct.max():.0f}"
    macros["AttrMaxPersonYear"] = str(int(yy.loc[yy.person_pct.idxmax(), "year_origin"]))
    macros["AttrOriginN"] = th(a[a.year_origin == 0].iloc[0].n_obs)

if have("lpm_attr_weather_results"):
    d = rd("lpm_attr_weather_results")
    d = d[d.kind == "exposure"]
    ROWS = [("agri_origin", "att_person", "Person non-continuation, agriculture origin"),
            ("agri_origin", "att_hh", "Household non-return, agriculture origin"),
            ("agri_origin", "att_within", "Within-household loss, agriculture origin"),
            ("all_origin", "att_person", "Person non-continuation, all origin states")]
    t = ("\\begin{tabular}{lcccc}\n\\toprule\n & \\multicolumn{2}{c}{Days35 /10} & \\multicolumn{2}{c}{HeatDose35 /10} \\\\\n"
         "\\cmidrule(lr){2-3}\\cmidrule(lr){4-5}\nOutcome (percentage points) & Preferred (M7) & + county trend (M8) & Preferred (M7) & + county trend (M8) \\\\\n\\midrule\n")
    for pn, oc, lab in ROWS:
        c = []
        for fam in ["AttrWeather_Days35", "AttrWeather_HeatDose35"]:
            for m in (7, 8):
                r = get(d, family=fam, panel=pn, outcome=oc, model_num=m)
                dd = 3 if fam.endswith("Days35") else 4
                c.append(two(r.coef, r.se, r.pvalue, dd) if r.status == "ok" else "--")
        t += f"{lab} & " + " & ".join(c) + " \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("attr_weather.tex", t)
    r = get(d, family="AttrWeather_Days35", panel="agri_origin", outcome="att_person", model_num=7)
    macros["AttrWeatherDaysCoef"] = mnum(r.coef)
    macros["AttrWeatherDaysSe"] = f"{r.se:.3f}"
    macros["AttrWeatherDaysP"] = f"{r.pvalue:.3f}"
    r = get(d, family="AttrWeather_HeatDose35", panel="agri_origin", outcome="att_person", model_num=7)
    macros["AttrWeatherHeatCoef"] = mnum(r.coef, 4)
    macros["AttrWeatherHeatP"] = f"{r.pvalue:.3f}"
    macros["AttrWeatherMinP"] = f"{d.pvalue.min():.3f}"
    macros["AttrWeatherNSig"] = str(int((d.pvalue < 0.05).sum()))
    macros["AttrWeatherNReg"] = str(len(d))

if have("attr_het_tests"):
    d = rd("attr_het_tests")
    d["exposure"] = d.exposure.map(sval)
    d["moderator"] = d.moderator.map(sval)
    LAB = {"sex_origin": "Sex", "urban_origin": "Rural origin", "marital_origin": "Marital status", "age_grp": "Age group"}
    t = "\\begin{tabular}{lcc}\n\\toprule\nHeat $\\times$ characteristic & Days35 /10 & HeatDose35 /10 \\\\\n\\midrule\n"
    for k, lab in LAB.items():
        c = [pfmt(get(d, exposure=en, moderator=k).pvalue) for en in ["Days35", "HeatDose35"]]
        t += f"{lab} & " + " & ".join(c) + " \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("attr_het.tex", t)
    macros["AttrHetMinP"] = f"{d.pvalue.min():.3f}"

if have("attr_propensity"):
    d = rd("attr_propensity")
    d["exposure"] = d.exposure.map(sval)
    a = d[d.exposure == "Days35"].iloc[0]
    b = d[d.exposure == "HeatDose35"].iloc[0]
    t = "\\begin{tabular}{lcc}\n\\toprule\nDiagnostic & Days35 & HeatDose35 \\\\\n\\midrule\n"
    t += "\\multicolumn{3}{l}{\\emph{Panel A. Sample}}\\\\\n"
    t += f"Eligible agriculture-origin workers & {th(a.candidate_n)} & {th(b.candidate_n)} \\\\\n"
    t += f"Propensity-model observations & {th(a.model_n)} & {th(b.model_n)} \\\\\n"
    t += f"Observed continuers & {th(a.continuer_n)} & {th(b.continuer_n)} \\\\\n"
    t += f"Weighted continuation rate (\\%) & {a.cont_rate:.2f} & {b.cont_rate:.2f} \\\\\n"
    t += f"County clusters & {th(a.clusters)} & {th(b.clusters)} \\\\\n"
    t += "\\midrule\n\\multicolumn{3}{l}{\\emph{Panel B. Continuation model: coefficient of the heat measure}}\\\\\n"
    t += f"Coefficient & {a.heat_b:.5f} & {b.heat_b:.5f} \\\\\n"
    t += f"County-clustered SE & {a.heat_se:.5f} & {b.heat_se:.5f} \\\\\n"
    t += f"$p$ value & {a.heat_p:.3f} & {b.heat_p:.3f} \\\\\n"
    t += f"Pseudo-$R^2$ (logit) or $R^2$ (linear) & {a.pseudo_r2:.3f} & {b.pseudo_r2:.3f} \\\\\n"
    t += f"Estimator & {sval(a.method)} & {sval(b.method)} \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("attr_propensity.tex", t)
    macros["AttrCandN"] = th(a.candidate_n)
    macros["AttrContN"] = th(a.continuer_n)
    macros["AttrContRate"] = f"{a.cont_rate:.1f}"
    macros["AttrPropMethod"] = sval(a.method)
    macros["AttrLogitDaysP"] = f"{a.heat_p:.3f}"
    macros["AttrLogitHeatP"] = f"{b.heat_p:.3f}"
    macros["AttrLogitDaysCoef"] = f"{a.heat_b:.4f}"
    macros["AttrLogitHeatCoef"] = f"{b.heat_b:.5f}"

if have("attr_weightdiag"):
    d = rd("attr_weightdiag")
    d["exposure"] = d.exposure.map(sval)
    d["object"] = d["object"].map(sval)
    BLOCKS = [("Predicted continuation", "Predicted continuation probability",
               [("mean", "Mean", 3), ("min", "Minimum", 3), ("p1", "1st percentile", 3), ("p5", "5th percentile", 3),
                ("p50", "Median", 3), ("p95", "95th percentile", 3), ("max", "Maximum", 3),
                ("n_lt_005", "Observations below 0.05", 0), ("n_lt_010", "Observations below 0.10", 0)]),
              ("Stabilized IPW", "Stabilized continuation weight (continuers)",
               [("mean", "Mean", 3), ("p1", "1st percentile", 3), ("p50", "Median", 3), ("p99", "99th percentile", 3),
                ("max", "Maximum", 3), ("n_gt_2", "Weights above 2", 0), ("n_gt_5", "Weights above 5", 0),
                ("kish_ess", "Kish effective sample size", 0)]),
              ("Trimmed IPW p1-p99", "Trimmed weight, p1 and p99 (continuers)",
               [("max", "Maximum", 3), ("kish_ess", "Kish effective sample size", 0)])]
    t = "\\begin{tabular}{lcc}\n\\toprule\n & Days35 & HeatDose35 \\\\\n\\midrule\n"
    for i, (obj, title, items) in enumerate(BLOCKS):
        if i:
            t += "\\midrule\n"
        t += f"\\multicolumn{{3}}{{l}}{{\\emph{{{title}}}}}\\\\\n"
        for col, lab, dd in items:
            vals = []
            for en in ["Days35", "HeatDose35"]:
                r = d[(d.exposure == en) & (d["object"] == obj)]
                x = r[col].iloc[0] if len(r) else float("nan")
                vals.append("--" if pd.isna(x) else (th(x) if dd == 0 else f"{x:.{dd}f}"))
            t += f"{lab} & {vals[0]} & {vals[1]} \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("attr_weights.tex", t)
    sw = d[(d.exposure == "Days35") & (d["object"] == "Stabilized IPW")].iloc[0]
    pc = d[(d.exposure == "Days35") & (d["object"] == "Predicted continuation")].iloc[0]
    macros["AttrSwMax"] = f"{sw['max']:.2f}"
    macros["AttrSwPtop"] = f"{sw.p99:.2f}"
    macros["AttrEss"] = th(sw.kish_ess)
    macros["AttrEssShare"] = f"{100 * sw.kish_ess / sw.n:.0f}"
    macros["AttrPhatMin"] = f"{pc['min']:.3f}"
    macros["AttrPhatLtTen"] = th(pc.n_lt_010)

if have("attr_balance"):
    d = rd("attr_balance")
    d["exposure"] = d.exposure.map(sval)
    d["covariate"] = d.covariate.map(sval)
    d["category"] = d.category.map(sval)
    s = d[d.exposure == "Days35"]
    t = ("\\begin{tabular}{llccccc}\n\\toprule\nCovariate & Category & Target mean & Continuers, survey weight & "
         "Continuers, survey $\\times$ IPW & SMD before & SMD after \\\\\n\\midrule\n")
    for _, r in s.iterrows():
        cat = "" if r.category == "Continuous" else r.category.replace("_", " ")
        dd = 3
        t += (f"{r.covariate} & {cat} & {r.target_mean:.{dd}f} & {r.pre_mean:.{dd}f} & {r.ipw_mean:.{dd}f} & "
              f"{r.smd_pre:.2f} & {r.smd_ipw:.2f} \\\\\n")
    t += "\\bottomrule\n\\end{tabular}\n"
    write("attr_balance.tex", t)
    macros["AttrMaxSmdPre"] = f"{s.smd_pre.abs().max():.1f}"
    macros["AttrMaxSmdPost"] = f"{s.smd_ipw.abs().max():.1f}"

if have("lpm_ipw_results"):
    d = rd("lpm_ipw_results")
    d = d[d.kind == "exposure"]
    for fam, fname, dd in [("IPW_Days35", "ipw_days35.tex", 3), ("IPW_HeatDose35", "ipw_heat35.tex", 4)]:
        t = ("\\begin{tabular}{lcccc}\n\\toprule\nOutcome & Baseline & Common sample, survey weight & "
             "Survey weight $\\times$ stabilized IPW & Survey weight $\\times$ trimmed IPW \\\\\n\\midrule\n")
        for oc, lab in OUT7:
            c = []
            for pn in ["1_baseline", "2_common_survey", "3_ipw", "4_ipw_trim"]:
                r = get(d, family=fam, panel=pn, outcome=oc)
                c.append(two(r.coef, r.se, r.pvalue, dd) if r.status == "ok" else "--")
            t += f"{lab} & " + " & ".join(c) + " \\\\\n"
        t += "\\midrule\nEstimation observations & " + " & ".join(
            th(get(d, family=fam, panel=pn, outcome="exit_agri").n_used)
            for pn in ["1_baseline", "2_common_survey", "3_ipw", "4_ipw_trim"]) + " \\\\\n"
        t += "\\bottomrule\n\\end{tabular}\n"
        write(fname, t)
    b = get(d, family="IPW_Days35", panel="1_baseline", outcome="exit_agri")
    c = get(d, family="IPW_Days35", panel="2_common_survey", outcome="exit_agri")
    i = get(d, family="IPW_Days35", panel="3_ipw", outcome="exit_agri")
    tr = get(d, family="IPW_Days35", panel="4_ipw_trim", outcome="exit_agri")
    macros["IpwBase"] = mnum(b.coef)
    macros["IpwCommon"] = mnum(c.coef)
    macros["IpwIpw"] = mnum(i.coef)
    macros["IpwIpwSe"] = f"{i.se:.3f}"
    macros["IpwIpwP"] = f"{i.pvalue:.4f}"
    macros["IpwTrim"] = mnum(tr.coef)
    macros["IpwChangePct"] = f"{100 * (i.coef / c.coef - 1):.1f}"
    macros["IpwN"] = th(i.n_used)
    hb = get(d, family="IPW_HeatDose35", panel="2_common_survey", outcome="exit_agri")
    hi = get(d, family="IPW_HeatDose35", panel="3_ipw", outcome="exit_agri")
    macros["IpwHeatCommon"] = mnum(hb.coef, 4)
    macros["IpwHeatIpw"] = mnum(hi.coef, 4)
    macros["IpwHeatChangePct"] = f"{100 * (hi.coef / hb.coef - 1):.1f}"

# =============================================================== 43 heterogeneity
if have("het_tests"):
    d = rd("het_tests")
    d["exposure"] = d.exposure.map(sval)
    d["moderator"] = d.moderator.map(sval)
    d["hypothesis"] = d.hypothesis.map(sval)
    t = ("\\begin{tabular}{>{\\raggedright\\arraybackslash}p{0.38\\textwidth}ccccc}\n\\toprule\nHypothesis & df & $F$ & Raw $p$ & Holm $p$ & BH $q$ \\\\\n\\midrule\n")
    for i, (en, title) in enumerate([("Days35", "Primary family: Days35 /10, exit from agriculture"),
                                     ("HeatDose35", "Secondary family: HeatDose35 /10, exit from agriculture")]):
        if i:
            t += "\\midrule\n"
        t += f"\\multicolumn{{6}}{{l}}{{\\emph{{{title}}}}}\\\\\n"
        for _, r in d[d.exposure == en].sort_values("mod_order").iterrows():
            t += (f"{r.hypothesis} & {int(r.df)} & {r.stat:.2f} & {pfmt(r.raw_p)} & {pfmt(r.holm_p)} & {pfmt(r.bh_q)} \\\\\n")
    t += "\\bottomrule\n\\end{tabular}\n"
    write("het_tests.tex", t)
    key = {"Sex": "Sex", "Residence": "Rural", "Education": "Educ", "Climate": "Clim"}
    for en, tag in [("Days35", "Days"), ("HeatDose35", "Heat")]:
        s = d[d.exposure == en]
        for k, nm in key.items():
            r = s[s.moderator == k].iloc[0]
            macros[f"HetRaw{tag}{nm}"] = f"{r.raw_p:.3f}"
            macros[f"HetHolm{tag}{nm}"] = f"{r.holm_p:.3f}"
        macros[f"HetMinHolm{tag}"] = f"{s.holm_p.min():.3f}"
        macros[f"HetMinRaw{tag}"] = f"{s.raw_p.min():.3f}"
        macros[f"HetNHolm{tag}"] = str(int((s.holm_p < 0.05).sum()))

if have("het_slopes"):
    s = rd("het_slopes")
    s["exposure"] = s.exposure.map(sval)
    s["moderator"] = s.moderator.map(sval)
    s["grp"] = s.grp.map(sval)
    c = rd("het_contrasts")
    c["exposure"] = c.exposure.map(sval)
    c["moderator"] = c.moderator.map(sval)
    c["contrast"] = c.contrast.map(sval)
    t = ("\\begin{tabular}{>{\\raggedright\\arraybackslash}p{0.40\\textwidth}rcc}\n\\toprule\nGroup & $N$ & Heat slope & 95\\% interval \\\\\n\\midrule\n")
    for i, (en, title, dd) in enumerate([("Days35", "Days35 /10: exit from agriculture", 3),
                                         ("HeatDose35", "HeatDose35 /10: exit from agriculture", 4)]):
        if i:
            t += "\\midrule\n"
        t += f"\\multicolumn{{4}}{{l}}{{\\emph{{{title}}}}}\\\\\n"
        for mo in ["Sex", "Residence", "Education", "Climate"]:
            ss = s[(s.exposure == en) & (s.moderator == mo)].sort_values("grp_order")
            for _, r in ss.iterrows():
                t += (f"{r.grp} & {th(r.n_used)} & {cell(r.slope, r.pvalue, dd)} ({r.se:.{dd}f}) & "
                      f"$[{mnum(r.ci_lo, dd)},\\,{mnum(r.ci_hi, dd)}]$ \\\\\n")
            cc = c[(c.exposure == en) & (c.moderator == mo)]
            for _, r in cc.iterrows():
                t += (f"\\quad\\emph{{{r.contrast}}} & & {cell(r['diff'], r.pvalue, dd)} ({r.se:.{dd}f}) & "
                      f"$[{mnum(r.ci_lo, dd)},\\,{mnum(r.ci_hi, dd)}]$ \\\\\n")
    t += "\\bottomrule\n\\end{tabular}\n"
    write("het_slopes.tex", t)
    for mo, nm in [("Sex", "Sex"), ("Residence", "Rural"), ("Climate", "Clim")]:
        ss = s[(s.exposure == "Days35") & (s.moderator == mo)].sort_values("grp_order")
        macros[f"HetSlopeA{nm}"] = mnum(ss.slope.iloc[0])
        macros[f"HetSlopeB{nm}"] = mnum(ss.slope.iloc[1])
    ee = s[(s.exposure == "Days35") & (s.moderator == "Education")].sort_values("grp_order")
    macros["HetSlopeEducLow"] = mnum(ee.slope.iloc[0])
    macros["HetSlopeEducSec"] = mnum(ee.slope.iloc[1])
    macros["HetSlopeEducTer"] = mnum(ee.slope.iloc[2])

if have("het_climate"):
    d = rd("het_climate")
    macros["HetNCool"] = str(int((d.hot_climate == 0).sum()))
    macros["HetNHot"] = str(int((d.hot_climate == 1).sum()))

# =============================================================== 46 county-level shares
if have("cty_results"):
    d = rd("cty_results")
    for c in ["family", "spec", "outcome", "exposure", "note"]:
        d[c] = d[c].map(sval)

    def g(fam, spec, oc):
        r = d[(d.family == fam) & (d.spec == spec) & (d.outcome == oc)]
        return r.iloc[0] if len(r) else None

    def pc(r, dd=3):
        if r is None or pd.isna(r.coef):
            return "--"
        return two(r.coef, r.se, r.pvalue, dd)

    SH = [("sh1", "Agriculture"), ("sh2", "Industry"), ("sh3", "Services"), ("sh4", "Unemployment"), ("sh5", "Inactivity")]
    # ---- main table: annual against seasonal
    cols = [("Annual", "L4_prov_year"), ("Annual", "L5_trend"), ("Seasonal", "L4_prov_year_season"),
            ("Seasonal", "L5_trend"), ("Seasonal", "L6_prov_year_season_fe")]
    t = ("\\begin{tabular}{lccccc}\n\\toprule\n & \\multicolumn{2}{c}{Annual exposure} & \\multicolumn{3}{c}{Seasonally aligned exposure ($t{+}1$)} \\\\\n"
         "\\cmidrule(lr){2-3}\\cmidrule(lr){4-6}\n & (1) & (2) & (3) & (4) & (5) \\\\\n\\midrule\n")
    for i, (nm, title, dd) in enumerate([("Days35", "Panel A: Days35 /10", 3), ("HeatDose35", "Panel B: HeatDose35 /10", 4)]):
        if i:
            t += "\\midrule\n"
        t += f"\\multicolumn{{6}}{{l}}{{\\emph{{{title}}}}}\\\\\n"
        cs = [pc(g(f"{a}_{nm}", sp, "sh1"), dd) for a, sp in cols]
        t += "Agricultural share & " + " & ".join(cs) + " \\\\\n"
    t += ("\\midrule\nCounty FE & Yes & Yes & Yes & Yes & Yes \\\\\nProvince$\\times$year FE & Yes & Yes & Yes & Yes & No \\\\\n"
          "Season FE & -- & -- & Yes & Yes & No \\\\\nProvince$\\times$year$\\times$season FE & -- & -- & No & No & Yes \\\\\n"
          "County linear trend & No & Yes & No & Yes & No \\\\\n\\midrule\n")
    rr = [g(f"{a}_Days35", sp, "sh1") for a, sp in cols]
    t += "$N$ & " + " & ".join(th(r.n_used) if r is not None and not pd.isna(r.n_used) else "--" for r in rr) + " \\\\\n"
    t += "Clusters (counties) & " + " & ".join(th(r.n_clusters) if r is not None and not pd.isna(r.n_clusters) else "--" for r in rr) + " \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("cty_main.tex", t)
    a1, a2, s1, s2, s3 = rr
    macros["CtyAnnDays"] = mnum(a1.coef)
    macros["CtyAnnDaysSe"] = f"{a1.se:.3f}"
    macros["CtyAnnDaysP"] = f"{a1.pvalue:.3f}"
    macros["CtySeasDays"] = mnum(s1.coef)
    macros["CtySeasDaysSe"] = f"{s1.se:.3f}"
    macros["CtySeasDaysP"] = f"{s1.pvalue:.4f}"
    macros["CtySeasTrendDays"] = mnum(s2.coef)
    macros["CtySatDays"] = mnum(s3.coef)
    macros["CtySatDaysP"] = f"{s3.pvalue:.3f}"
    macros["CtyNAnn"] = th(a1.n_used)
    macros["CtyNSeas"] = th(s1.n_used)
    macros["CtyClAnn"] = th(a1.n_clusters)
    macros["CtyClSeas"] = th(s1.n_clusters)
    h = [g(f"{a}_HeatDose35", sp, "sh1") for a, sp in cols]
    macros["CtyAnnHeatP"] = f"{h[0].pvalue:.3f}"
    macros["CtySeasHeat"] = mnum(h[2].coef, 4)
    macros["CtySeasHeatP"] = f"{h[2].pvalue:.4f}"
    macros["CtySatHeatP"] = f"{h[4].pvalue:.3f}"

    # ---- ladder
    LAD = [("L1_none", "No fixed effects", "L1_none"), ("L2_county", "County", "L2_county"),
           ("L3_county_year", "County + year (+ season)", "L3_county_year_season"),
           ("L4_prov_year", "County + province$\\times$year (+ season) [baseline]", "L4_prov_year_season"),
           ("L5_trend", "Baseline + county linear trend", "L5_trend"),
           (None, "County + province$\\times$year$\\times$season", "L6_prov_year_season_fe")]
    t = ("\\begin{tabular}{lcccc}\n\\toprule\n & \\multicolumn{2}{c}{Annual exposure} & \\multicolumn{2}{c}{Seasonal exposure ($t{+}1$)} \\\\\n"
         "\\cmidrule(lr){2-3}\\cmidrule(lr){4-5}\nFixed effects & Days35 /10 & HeatDose35 /10 & Days35 /10 & HeatDose35 /10 \\\\\n\\midrule\n")
    for sa, lab, ss in LAD:
        cs = []
        for fam, sp, dd in [("Annual_Days35", sa, 3), ("Annual_HeatDose35", sa, 4), ("Seasonal_Days35", ss, 3), ("Seasonal_HeatDose35", ss, 4)]:
            cs.append(pc(g(fam, sp, "sh1"), dd) if sp else "--")
        t += f"{lab} & " + " & ".join(cs) + " \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("cty_ladder.tex", t)

    # ---- five shares
    for fam_a, fam_s, fn in [("Annual", "Seasonal", None)]:
        pass
    t = ("\\begin{tabular}{lcccccc}\n\\toprule\n & \\multicolumn{3}{c}{Days35 /10} & \\multicolumn{3}{c}{HeatDose35 /10} \\\\\n"
         "\\cmidrule(lr){2-4}\\cmidrule(lr){5-7}\nShare & Baseline & + county trend & Saturated & Baseline & + county trend & Saturated \\\\\n\\midrule\n")
    t += "\\multicolumn{7}{l}{\\emph{Panel A: seasonal $t{+}1$}}\\\\\n"
    for oc, lab in SH:
        cs = []
        for nm, dd in [("Days35", 3), ("HeatDose35", 4)]:
            for sp in ["L4_prov_year_season", "L5_trend", "L6_prov_year_season_fe"]:
                cs.append(pc(g(f"Seasonal_{nm}", sp, oc), dd))
        t += f"{lab} & " + " & ".join(cs) + " \\\\\n"
    t += "\\midrule\n\\multicolumn{7}{l}{\\emph{Panel B: annual}}\\\\\n"
    for oc, lab in SH:
        cs = []
        for nm, dd in [("Days35", 3), ("HeatDose35", 4)]:
            for sp in ["L4_prov_year", "L5_trend", None]:
                cs.append(pc(g(f"Annual_{nm}", sp, oc), dd) if sp else "--")
        t += f"{lab} & " + " & ".join(cs) + " \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("cty_allshares.tex", t)
    sub = d[(d.family == "Seasonal_Days35") & (d.spec == "L4_prov_year_season")]
    if len(sub) == 5:
        macros["CtyAddUpSeas"] = f"{abs(sub.coef.sum()):.4f}"
        for oc, nm in [("sh1", "Agri"), ("sh2", "Ind"), ("sh3", "Serv"), ("sh4", "Unemp"), ("sh5", "Inact")]:
            r = sub[sub.outcome == oc].iloc[0]
            macros[f"CtySeas{nm}"] = mnum(r.coef)
            macros[f"CtySeas{nm}P"] = f"{r.pvalue:.3f}"

    # ---- sample windows and cell size
    t = ("\\begin{tabular}{lcc}\n\\toprule\n & Days35 /10 & HeatDose35 /10 \\\\\n\\midrule\n\\multicolumn{3}{l}{\\emph{Annual: origin-year window}}\\\\\n")
    for sp, lab in [("origin_to_1398", "Origin years through 1398"), ("full_period", "Full period")]:
        cs = [pc(g(f"Window_{nm}", sp, "sh1"), dd) for nm, dd in [("Days35", 3), ("HeatDose35", 4)]]
        t += f"{lab} & " + " & ".join(cs) + " \\\\\n"
    t += "\\midrule\n\\multicolumn{3}{l}{\\emph{Seasonal $t{+}1$: minimum raw LFS rows per county-season cell}}\\\\\n"
    cs = [pc(g(f"Seasonal_{nm}", "L4_prov_year_season", "sh1"), dd) for nm, dd in [("Days35", 3), ("HeatDose35", 4)]]
    t += "All cells & " + " & ".join(cs) + " \\\\\n"
    for c in (30, 50, 100):
        cs = [pc(g(f"CellSize_{nm}", f"min_cell_{c}", "sh1"), dd) for nm, dd in [("Days35", 3), ("HeatDose35", 4)]]
        t += f"At least {c} rows & " + " & ".join(cs) + " \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("cty_robust.tex", t)
    r = g("CellSize_Days35", "min_cell_100", "sh1")
    if r is not None:
        macros["CtyCellHundred"] = mnum(r.coef)
        macros["CtyCellHundredN"] = th(r.n_used)
    r = g("Window_Days35", "origin_to_1398", "sh1")
    if r is not None:
        macros["CtyWinShortP"] = f"{r.pvalue:.3f}"

    # ---- controlled comparison
    t = "\\begin{tabular}{lcc}\n\\toprule\n & Seasonal (headline) & Annual-summed \\\\\n\\midrule\n"
    for nm, title, dd in [("Days35", "Days35 /10", 3), ("HeatDose35", "HeatDose35 /10", 4)]:
        t += f"\\multicolumn{{3}}{{l}}{{\\emph{{{title}}}}}\\\\\n"
        ri = [g(f"Controlled_{nm}", sp, "exit_agri_indiv") for sp in ("seasonal", "annual_summed")]
        t += "Individual level: exit from agriculture & " + " & ".join(pc(r, dd) for r in ri) + " \\\\\n"
        if ri[0] is not None:
            t += "\\quad $N$ & " + " & ".join(th(r.n_used) for r in ri) + " \\\\\n"
        rc = [g(f"Controlled_{nm}", sp, "sh1") for sp in ("seasonal", "annual_summed")]
        t += "County level: agricultural share & " + " & ".join(pc(r, dd) for r in rc) + " \\\\\n"
        rs = [g(f"Controlled_{nm}", sp, "sh3") for sp in ("seasonal", "annual_summed")]
        t += "County level: services share & " + " & ".join(pc(r, dd) for r in rs) + " \\\\\n"
        if rc[0] is not None:
            t += "\\quad $N$ (county) & " + " & ".join(th(r.n_used) for r in rc) + " \\\\\n"
        if nm == "Days35":
            macros["CtlIndSeas"] = mnum(ri[0].coef)
            macros["CtlIndAnn"] = mnum(ri[1].coef)
            macros["CtlIndAnnSe"] = f"{ri[1].se:.3f}"
            macros["CtlIndAnnP"] = f"{ri[1].pvalue:.3f}"
            macros["CtlCtySeas"] = mnum(rc[0].coef)
            macros["CtlCtyAnn"] = mnum(rc[1].coef)
            macros["CtlCtyAnnP"] = f"{rc[1].pvalue:.3f}"
            macros["CtlServSeas"] = mnum(rs[0].coef)
            macros["CtlServAnn"] = mnum(rs[1].coef)
            macros["CtlServAnnP"] = f"{rs[1].pvalue:.3f}"
            macros["CtlNInd"] = th(ri[0].n_used)
            macros["CtlNCty"] = th(rc[0].n_used)
        if nm == "Days35":
            t += "\\midrule\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("cty_controlled.tex", t)

lines = ["% Written by tools/make_tex_tables_d.py (run " + RUN + "). Do not edit by hand."]
for k in sorted(macros):
    v = macros[k]
    lines.append("\\newcommand{\\%s}{%s}" % (k, v.replace("-", "$-$") if v.startswith("-") else v))
write("numbers_d.tex", "\n".join(lines) + "\n")
