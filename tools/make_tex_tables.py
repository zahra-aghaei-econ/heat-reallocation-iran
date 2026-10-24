#!/usr/bin/env python3
"""
make_tex_tables.py
------------------
Builds the extra LaTeX table fragments and number macros for the paper from the
result datasets written by the Stata pipeline.  It does NOT run any regression:
every number is read from the .dta files in output/<run>/results/.

Usage (from the project root):
    python tools/make_tex_tables.py [RUN_NAME]

Default RUN_NAME = run3_new_period_svc.  Writes into output/<RUN_NAME>/tex/:
    progression.tex   specification ladder M1-M8, exit from agriculture (Days35)
    saturated.tex     M7 versus M9 (province x year x season FE), both heat measures
    standardized.tex  one-standard-deviation scaling of the M7 estimates
    thresholds.tex    Days35 / Days37 / Days40
    mechanism.tex     heat relative to local climatology
    periods.tex       heat x period interactions (cuts 1390 and 1397)
    numbers_extra.tex extra macros used in the text

Needs only python3 + pandas.  (The headline tables and numbers.tex come from
50_tex_tables.do.)  Fragments contain a tabular only; caption, label and notes
live in the paper.
"""
import sys
import os
import pandas as pd

RUN = sys.argv[1] if len(sys.argv) > 1 else "run3_new_period_svc"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "output", RUN, "results")
TEX = os.path.join(ROOT, "output", RUN, "tex")
os.makedirs(TEX, exist_ok=True)

OUT = {
    "exit_agri": "Exit from agriculture",
    "productive_exit": "Productive exit",
    "distress_exit": "Non-employment exit",
    "dest2": "Industry",
    "dest3": "Services",
    "dest4": "Unemployment",
    "dest5": "Inactivity",
}
MAIN3 = ["exit_agri", "productive_exit", "distress_exit"]
ALL7 = list(OUT)


def rd(name):
    return pd.read_stata(os.path.join(RES, name + ".dta"), convert_categoricals=False)


def stars(p):
    if pd.isna(p):
        return ""
    return "***" if p < 0.01 else "**" if p < 0.05 else "*" if p < 0.10 else ""


def num(x, d=3):
    s = f"{abs(x):.{d}f}"
    return ("-" if x < 0 and float(s) != 0 else "") + s


def cell(coef, p, d=3):
    s = num(coef, d)
    neg = s.startswith("-")
    body = ("-" if neg else "") + s.lstrip("-")
    st = stars(p)
    return f"${body}^{{{st}}}$" if st else f"${body}$"


def se_cell(se, d=3):
    return f"({se:.{d}f})"


def thousands(n):
    return f"{int(round(n)):,}".replace(",", "{,}")


def write(name, text):
    with open(os.path.join(TEX, name), "w", encoding="utf-8") as f:
        f.write(text)
    print("wrote", name)


def row2(label, cells, ses, indent=False):
    """two lines: coefficient line, standard-error line"""
    pre = "\\quad " if indent else ""
    a = f"{pre}{label} & " + " & ".join(cells) + " \\\\\n"
    b = " & " + " & ".join(ses) + " \\\\\n"
    return a + b


def get(df, **kw):
    m = pd.Series(True, index=df.index)
    for k, v in kw.items():
        m &= df[k] == v
    r = df[m]
    if len(r) != 1:
        raise ValueError(f"expected one row for {kw}, got {len(r)}")
    return r.iloc[0]


macros = {}
TW = {"37":"ThirtySeven","40":"Forty"}
W = {1:"One",2:"Two",3:"Three",4:"Four",5:"Five",6:"Six",7:"Seven",8:"Eight"}

# ---------------------------------------------------------------- ladder
lad = rd("lpm_ladder_results")
fam = "Days35"
expo = "days35_10_s0"
cols = []
for m in range(1, 9):
    cols.append(m)
cells, ses, rainc, rainse, rain2c, rain2se, ns, r2s = [], [], [], [], [], [], [], []
for m in cols:
    mm = f"M{m}"
    e = get(lad, family=fam, outcome="exit_agri", model=mm, term=expo)
    r1 = get(lad, family=fam, outcome="exit_agri", model=mm, term="rain100_s0")
    r2 = get(lad, family=fam, outcome="exit_agri", model=mm, term="rain100_sq_s0")
    cells.append(cell(e.coef, e.pvalue)); ses.append(se_cell(e.se))
    rainc.append(cell(r1.coef, r1.pvalue)); rainse.append(se_cell(r1.se))
    rain2c.append(cell(r2.coef, r2.pvalue)); rain2se.append(se_cell(r2.se))
    ns.append(thousands(e.n_used)); r2s.append(f"{e.r2:.3f}")
    macros[f"LadM{W[m]}Coef"] = num(e.coef)
    macros[f"LadM{W[m]}Se"] = f"{e.se:.3f}"
yn = lambda L: " & ".join("Yes" if v else "No" for v in L)
t = "\\begin{tabular}{l" + "c" * 8 + "}\n\\toprule\n"
t += " & " + " & ".join(f"({i})" for i in range(1, 9)) + " \\\\\n\\midrule\n"
t += row2("Days35 /10", cells, ses)
t += row2("Rainfall /100", rainc, rainse)
t += row2("Rainfall$^2$", rain2c, rain2se)
t += "\\midrule\n"
t += "Age, age$^2$, sex & " + yn([0, 1, 1, 1, 1, 1, 1, 1]) + " \\\\\n"
t += "Marital status & " + yn([0, 0, 1, 1, 1, 1, 1, 1]) + " \\\\\n"
t += "Rural-origin indicator & " + yn([0, 0, 0, 1, 1, 1, 1, 1]) + " \\\\\n"
t += "County FE & " + yn([0, 0, 0, 0, 0, 1, 1, 1]) + " \\\\\n"
t += "Province$\\times$year FE & " + yn([0, 0, 0, 0, 0, 0, 1, 1]) + " \\\\\n"
t += "Origin-year FE & " + yn([0, 0, 0, 0, 1, 1, 0, 0]) + " \\\\\n"
t += "Season FE & " + yn([0, 0, 0, 0, 1, 1, 1, 1]) + " \\\\\n"
t += "County linear trend & " + yn([0, 0, 0, 0, 0, 0, 0, 1]) + " \\\\\n"
t += "\\midrule\n$N$ & " + " & ".join(ns) + " \\\\\n$R^{2}$ & " + " & ".join(r2s) + " \\\\\n"
t += "\\bottomrule\n\\end{tabular}\n"
write("progression.tex", t)

# ---------------------------------------------------------------- saturated
sat = rd("lpm_saturated_results")
t = "\\begin{tabular}{lcccc}\n\\toprule\n"
t += " & \\multicolumn{2}{c}{Days35 /10} & \\multicolumn{2}{c}{HeatDose35 /10} \\\\\n"
t += "\\cmidrule(lr){2-3}\\cmidrule(lr){4-5}\n"
t += " & Preferred (M7) & Prov.$\\times$year$\\times$season FE & Preferred (M7) & Prov.$\\times$year$\\times$season FE \\\\\n\\midrule\n"
spec = [("Days35", "M7", "days35_10_s0"), ("Days35", "M9", "days35_10_s0"),
        ("HeatDose35", "M7", "heat35_10_s0"), ("HeatDose35", "M9", "heat35_10_s0")]
nobs = None
ncl = None
for o in ["exit_agri", "productive_exit", "distress_exit"]:
    cs, ss = [], []
    for fa, mo, te in spec:
        r = get(sat, family=fa, outcome=o, model=mo, term=te)
        cs.append(cell(r.coef, r.pvalue)); ss.append(se_cell(r.se))
        nobs, ncl = r.n_used, r.n_clusters
        if fa == "Days35" and mo == "M9":
            macros[f"SatDays{ {'exit_agri':'Exit','productive_exit':'Prod','distress_exit':'Nonemp'}[o] }Coef"] = num(r.coef)
            macros[f"SatDays{ {'exit_agri':'Exit','productive_exit':'Prod','distress_exit':'Nonemp'}[o] }Se"] = f"{r.se:.3f}"
            macros[f"SatDays{ {'exit_agri':'Exit','productive_exit':'Prod','distress_exit':'Nonemp'}[o] }P"] = f"{r.pvalue:.3f}"
    t += row2(OUT[o], cs, ss)
for o in ["dest2", "dest3", "dest4", "dest5"]:
    cs, ss = [], []
    for fa, mo, te in spec:
        r = get(sat, family=fa, outcome=o, model=mo, term=te)
        cs.append(cell(r.coef, r.pvalue)); ss.append(se_cell(r.se))
        if fa == "Days35" and mo == "M9":
            k = {"dest2": "Ind", "dest3": "Serv", "dest4": "Unemp", "dest5": "Inact"}[o]
            macros[f"SatDays{k}Coef"] = num(r.coef)
            macros[f"SatDays{k}Se"] = f"{r.se:.3f}"
            macros[f"SatDays{k}P"] = f"{r.pvalue:.3f}"
    t += row2(OUT[o], cs, ss, indent=True)
t += "\\midrule\nObservations & " + " & ".join([thousands(nobs)] * 4) + " \\\\\n"
t += "County clusters & " + " & ".join([str(int(ncl))] * 4) + " \\\\\n"
t += "\\bottomrule\n\\end{tabular}\n"
write("saturated.tex", t)
macros["NClusters"] = str(int(ncl))
# share of exit that is non-employment, M7 and M9
m7 = get(sat, family="Days35", outcome="exit_agri", model="M7", term="days35_10_s0")
m7n = get(sat, family="Days35", outcome="distress_exit", model="M7", term="days35_10_s0")
m9 = get(sat, family="Days35", outcome="exit_agri", model="M9", term="days35_10_s0")
m9n = get(sat, family="Days35", outcome="distress_exit", model="M9", term="days35_10_s0")
macros["ShareNonempBase"] = f"{100 * m7n.coef / m7.coef:.0f}"
macros["ShareNonempSat"] = f"{100 * m9n.coef / m9.coef:.0f}"

for o, nm in [("exit_agri", "Exit"), ("productive_exit", "Prod"), ("distress_exit", "Nonemp")]:
    r = get(sat, family="HeatDose35", outcome=o, model="M9", term="heat35_10_s0")
    macros[f"SatHeat{nm}Coef"] = num(r.coef); macros[f"SatHeat{nm}Se"] = f"{r.se:.3f}"; macros[f"SatHeat{nm}P"] = f"{r.pvalue:.3f}"
macros["SatExitRatio"] = f"{100 * m9.coef / m7.coef:.0f}"
macros["SatNonempRatio"] = f"{100 * m9n.coef / m7n.coef:.0f}"
# ---------------------------------------------------------------- standardized
ss_ = rd("summary_stats")
t2 = ss_[ss_.table_id == "T2"].set_index("varname")
sd_d = float(t2.loc["days35_10_s0", "sd"])
sd_h = float(t2.loc["heat35_10_s0", "sd"])
macros["SDDaysDays"] = f"{10 * sd_d:.1f}"        # SD in days
macros["SDHeatTens"] = f"{sd_h:.1f}"             # SD in tens of degree units
main = rd("lpm_main_results")
t = "\\begin{tabular}{lcc}\n\\toprule\nOutcome & Days35: 1 SD & HeatDose35: 1 SD \\\\\n\\midrule\n"
for o in ALL7:
    rd_ = get(main, measure="days35", outcome=o)
    rh_ = get(main, measure="heat35", outcome=o)
    ind = o in ["dest2", "dest3", "dest4", "dest5"]
    t += row2(OUT[o] if not ind else OUT[o],
              [cell(rd_.coef * sd_d, rd_.pvalue), cell(rh_.coef * sd_h, rh_.pvalue)],
              [se_cell(rd_.se * sd_d), se_cell(rh_.se * sd_h)], indent=ind)
    if o in ("exit_agri", "distress_exit"):
        k = "Exit" if o == "exit_agri" else "Nonemp"
        macros[f"SdDays{k}"] = num(rd_.coef * sd_d)
        macros[f"SdHeat{k}"] = num(rh_.coef * sd_h)
        mean_ = {"exit_agri": float(t2.loc["exit_agri", "mean"]) * 100,
                 "distress_exit": float(t2.loc["distress_exit", "mean"]) * 100}[o]
        macros[f"SdDays{k}Pct"] = f"{100 * rd_.coef * sd_d / mean_:.1f}"
        macros[f"SdHeat{k}Pct"] = f"{100 * rh_.coef * sd_h / mean_:.1f}"
t += "\\midrule\n$N$ & " + " & ".join([thousands(rd_.n_used)] * 2) + " \\\\\n\\bottomrule\n\\end{tabular}\n"
write("standardized.tex", t)

# ---------------------------------------------------------------- thresholds
fam7 = rd("lpm_families_M7_results")
t = "\\begin{tabular}{lccc}\n\\toprule\n & Days35 /10 & Days37 /10 & Days40 /10 \\\\\n\\midrule\n"
for o in MAIN3:
    a = get(main, measure="days35", outcome=o)
    b = get(fam7, family="F6_Thresholds", panel="Days37", outcome=o, kind="exposure")
    c = get(fam7, family="F6_Thresholds", panel="Days40", outcome=o, kind="exposure")
    t += row2(OUT[o], [cell(a.coef, a.pvalue), cell(b.coef, b.pvalue), cell(c.coef, c.pvalue)],
              [se_cell(a.se), se_cell(b.se), se_cell(c.se)])
t += "\\midrule\n$N$ & " + " & ".join([thousands(a.n_used)] * 3) + " \\\\\n\\bottomrule\n\\end{tabular}\n"
write("thresholds.tex", t)
for nm, pn in [("37", "Days37"), ("40", "Days40")]:
    b = get(fam7, family="F6_Thresholds", panel=pn, outcome="exit_agri", kind="exposure")
    macros[f"Days{TW[nm]}ExitCoef"] = num(b.coef)
    macros[f"Days{TW[nm]}ExitSe"] = f"{b.se:.3f}"
for nm, pn in [("37", "HeatDose37"), ("40", "HeatDose40")]:
    b = get(fam7, family="F6_Thresholds", panel=pn, outcome="exit_agri", kind="exposure")
    macros[f"Heat{TW[nm]}ExitCoef"] = num(b.coef)
    macros[f"Heat{TW[nm]}ExitSe"] = f"{b.se:.3f}"

# ---------------------------------------------------------------- mechanism
t = "\\begin{tabularx}{0.98\\textwidth}{>{\\raggedright\\arraybackslash}Xccc}\n\\toprule\n"
t += " & Exit from agriculture & Productive exit & Non-employment exit \\\\\n\\midrule\n"
loc = fam7[(fam7.family == "F4_LocalClimate") & (fam7.kind == "exposure")]
for term, lab in [("countp90_10_s0", "Days above county-season 90th pct. of $T_{\\max}$ /10"),
                  ("anom_tmean_s0", "Mean-temperature anomaly"),
                  ("anom_tmean_sq_s0", "Mean-temperature anomaly$^2$")]:
    cs, ss = [], []
    for o in MAIN3:
        r = get(loc, outcome=o, term=term)
        cs.append(cell(r.coef, r.pvalue)); ss.append(se_cell(r.se))
    t += row2(lab, cs, ss)
t += "\\midrule\n$N$ & " + " & ".join([thousands(r.n_used)] * 3) + " \\\\\n\\bottomrule\n\\end{tabularx}\n"
write("mechanism.tex", t)
r = get(loc, outcome="exit_agri", term="countp90_10_s0")
macros["PNinetyExitCoef"] = num(r.coef); macros["PNinetyExitSe"] = f"{r.se:.3f}"; macros["PNinetyExitP"] = f"{r.pvalue:.3f}"

# ---------------------------------------------------------------- bins (macros only)
for lab, term in [("BinThirtyToThirtyfive", "bin_tmax_30_35_s0"), ("BinThirtyfiveToForty", "bin_tmax_35_40_s0"), ("BinAboveForty", "bin_tmax_gt40_s0")]:
    r = get(fam7, family="F5_FlexibleForm", panel="A_TmaxBins", outcome="exit_agri", term=term)
    macros[lab + "Coef"] = num(r.coef); macros[lab + "Se"] = f"{r.se:.3f}"

# ---------------------------------------------------------------- periods
per = rd("lpm_period_results")
cuts = [("1_cut1390", "p1", "1384--1390", "1391--1402"), ("2_cut1397", "p2", "1384--1397", "1398--1402")]
t = "\\begin{tabular}{lccccccc}\n\\toprule\n"
t += " & \\multicolumn{3}{c}{Headline outcomes} & \\multicolumn{4}{c}{Destinations} \\\\\n\\cmidrule(lr){2-4}\\cmidrule(lr){5-8}\n"
t += " & Exit & Productive & Non-empl. & Industry & Services & Unempl. & Inactivity \\\\\n\\midrule\n"
for pf, fname, pref, tag in [("Per_Days35", "Days35", "days35", "A"), ("Per_HeatDose35", "HeatDose35", "heat35", "B")]:
    t += f"\\multicolumn{{8}}{{l}}{{\\emph{{Panel {tag}. {fname} /10}}}} \\\\\n"
    sub = per[per.family == pf]
    for panel, code, lab1, lab2 in cuts:
        cs1, ss1, cs2, ss2, ps = [], [], [], [], []
        for o in ALL7:
            a = get(sub, panel=panel, outcome=o, term=f"{pref}_{code}g1")
            b = get(sub, panel=panel, outcome=o, term=f"{pref}_{code}g2")
            f_ = get(sub, panel=panel, outcome=o, term="equal_coefficients_F")
            cs1.append(cell(a.coef, a.pvalue)); ss1.append(se_cell(a.se))
            cs2.append(cell(b.coef, b.pvalue)); ss2.append(se_cell(b.se))
            ps.append(f"{f_.pvalue:.2f}")
            if o in ("exit_agri", "productive_exit", "distress_exit"):
                on = {"exit_agri": "Exit", "productive_exit": "Prod", "distress_exit": "Nonemp"}[o]
                k = f"{fname.replace('HeatDose35','Heat').replace('Days35','Days')}Cut{'A' if panel[0]=='1' else 'B'}{on}"
                macros[k + "EarlyCoef"] = num(a.coef); macros[k + "EarlySe"] = f"{a.se:.3f}"
                macros[k + "LateCoef"] = num(b.coef); macros[k + "LateSe"] = f"{b.se:.3f}"
                macros[k + "P"] = f"{f_.pvalue:.2f}"
        t += row2(lab1, cs1, ss1)
        t += row2(lab2, cs2, ss2)
        t += "$p$-value, equal & " + " & ".join(ps) + " \\\\\n"
        if panel == "1_cut1390":
            t += "\\addlinespace\n"
    if pf == "Per_Days35":
        t += "\\midrule\n"
t += "\\midrule\n$N$ & " + " & ".join([thousands(a.n_used)] * 7) + " \\\\\n\\bottomrule\n\\end{tabular}\n"
write("periods.tex", t)

# each-year tests
yr = rd("lpm_period_results")
for pf, k in [("Year_Days35", "Days"), ("Year_HeatDose35", "Heat")]:
    sub = yr[(yr.family == pf) & (yr.panel == "5_each_year") & (yr.term == "equal_coefficients_F")]
    for o, nm in [("exit_agri", "Exit"), ("productive_exit", "Prod"), ("distress_exit", "Nonemp")]:
        r = sub[sub.outcome == o]
        if len(r) == 1:
            macros[f"Year{k}{nm}P"] = f"{r.iloc[0].pvalue:.2f}"

# ---------------------------------------------------------------- asymmetry
asy = rd("lpm_asymmetry_results")
asy = asy[asy.panel == "2_M7_split"]
t = "\\begin{tabular}{lcccc}\n\\toprule\n"
t += " & \\multicolumn{2}{c}{Days35 /10} & \\multicolumn{2}{c}{HeatDose35 /10} \\\\\n\\cmidrule(lr){2-3}\\cmidrule(lr){4-5}\n"
t += " & Exit & Non-employment exit & Exit & Non-employment exit \\\\\n\\midrule\n"
combos = [("Asym_Days35", "days35", "exit_agri"), ("Asym_Days35", "days35", "distress_exit"),
          ("Asym_HeatDose35", "heat35", "exit_agri"), ("Asym_HeatDose35", "heat35", "distress_exit")]
for comp, lab in [("normal", "Normal level (county-season mean)"), ("above", "Above the normal"), ("below", "Below the normal (size of the shortfall)")]:
    cs, ss = [], []
    for fa, st, o in combos:
        r = get(asy, family=fa, outcome=o, term=f"{st}_{comp}")
        cs.append(cell(r.coef, r.pvalue)); ss.append(se_cell(r.se))
    t += row2(lab, cs, ss)
ps = [f"{get(asy, family=fa, outcome=o, term='symmetry_test').pvalue:.3f}" for fa, st, o in combos]
t += "\\midrule\n$p$-value, above $+$ below $=0$ & " + " & ".join(ps) + " \\\\\n"
t += "$N$ & " + " & ".join([thousands(r.n_used)] * 4) + " \\\\\n\\bottomrule\n\\end{tabular}\n"
write("asymmetry.tex", t)
macros["SymDaysExitP"] = ps[0]; macros["SymDaysNonempP"] = ps[1]
macros["SymHeatExitP"] = ps[2]; macros["SymHeatNonempP"] = ps[3]

# ---------------------------------------------------------------- regions (pooled regression, separate slope per region)
reg = rd("lpm_regions_results")
reg = reg[reg.panel == "A_pooled_region_slopes"]
RN = {1: "Caspian rice", 2: "Highland cereal", 3: "Plateau cereal and orchard",
      4: "Khorasan saffron and wheat", 5: "Warm lowland wheat", 6: "Hot arid date belt"}
t = "\\begin{tabular}{lcccccc}\n\\toprule\n"
t += " & \\multicolumn{3}{c}{Days35 /10} & \\multicolumn{3}{c}{HeatDose35 /10} \\\\\n\\cmidrule(lr){2-4}\\cmidrule(lr){5-7}\n"
t += " & Exit & Productive & Non-empl. & Exit & Productive & Non-empl. \\\\\n\\midrule\n"
for k in range(1, 7):
    cs, ss = [], []
    for fa, st in [("Regions_Days35", "days35"), ("Regions_HeatDose35", "heat35")]:
        for o in MAIN3:
            r = get(reg, family=fa, outcome=o, term=f"{st}_r{k}")
            cs.append(cell(r.coef, r.pvalue)); ss.append(se_cell(r.se))
    t += row2(RN[k], cs, ss)
ps = []
for fa in ["Regions_Days35", "Regions_HeatDose35"]:
    for o in MAIN3:
        ps.append(f"{get(reg, family=fa, outcome=o, term='equal_coefficients_F').pvalue:.3f}")
t += "\\midrule\n$p$-value, equal slopes & " + " & ".join(ps) + " \\\\\n"
t += "$N$ & " + " & ".join([thousands(r.n_used)] * 6) + " \\\\\n\\bottomrule\n\\end{tabular}\n"
write("regions.tex", t)
macros["RegEqualP"] = ps[0]
macros["SDHeatDeg"] = f"{10 * sd_h:.0f}"

# ---------------------------------------------------------------- descriptive macros
import numpy as np
w = rd("weather_trend_days35")
slope = np.polyfit(w.year, w.days35, 1)[0]
macros["WTrendPerDecade"] = f"{10 * slope:.1f}"
macros["WMeanEarly"] = f"{w[w.year <= 1369].days35.mean():.1f}"
macros["WMeanLate"] = f"{w[(w.year >= 1390) & (w.year <= 1402)].days35.mean():.1f}"
macros["WMeanLast"] = f"{w[w.year >= 1400].days35.mean():.1f}"
macros["WFirstYear"] = str(int(w.year.min())); macros["WLastYear"] = str(int(w.year.max()))
ts = rd("timeseries_shares").set_index("year")
macros["AgriEmpFirst"] = f"{ts.loc[1384, 'emp_agri']:.1f}"
macros["AgriEmpLast"] = f"{ts.loc[ts.index.max(), 'emp_agri']:.1f}"
macros["AgriEmpLastYear"] = str(int(ts.index.max()))
macros["IndEmpFirst"] = f"{ts.loc[1384, 'emp_ind']:.1f}"
macros["IndEmpLast"] = f"{ts.loc[ts.index.max(), 'emp_ind']:.1f}"
macros["ServEmpFirst"] = f"{ts.loc[1384, 'emp_serv']:.1f}"
macros["ServEmpLast"] = f"{ts.loc[ts.index.max(), 'emp_serv']:.1f}"
macros["RuralShare"] = f"{100 * float(t2[t2.label.str.contains('urban_origin = 1')].iloc[0]['mean']):.1f}"
macros["MeanAge"] = f"{float(t2.loc['age_origin', 'mean']):.1f}"
macros["MeanDaysRaw"] = f"{10 * float(t2.loc['days35_10_s0', 'mean']):.1f}"
macros["StayAgri"] = f"{100 - 100 * float(t2.loc['exit_agri', 'mean']):.2f}"
t1 = ss_[ss_.table_id == "T1"]
macros["NAllTrans"] = thousands(float(t1.iloc[0]["n_obs"]))
macros["AgriShareOfTrans"] = f"{100 * float(t2.loc['exit_agri', 'n_obs']) / float(t1.iloc[0]['n_obs']):.1f}"
macros["MeanRaw"] = macros["MeanDaysRaw"]

# ---------------------------------------------------------------- misc macros
macros["SDDaysNote"] = macros["SDDaysDays"]
lines = ["% Written by tools/make_tex_tables.py (run " + RUN + "). Do not edit by hand."]
for k in sorted(macros):
    v = macros[k]
    lines.append("\\newcommand{\\%s}{%s}" % (k, v.replace("-", "$-$") if v.startswith("-") else v))
write("numbers_extra.tex", "\n".join(lines) + "\n")
