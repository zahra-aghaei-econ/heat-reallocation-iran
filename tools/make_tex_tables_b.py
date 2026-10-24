#!/usr/bin/env python3
"""
make_tex_tables_b.py
--------------------
LaTeX fragments for the descriptive and all-origin tables (batch A).
Reads result datasets of steps 11 and 25; runs no regression.  Every block is skipped
(with a message) if its input file does not exist yet.

Usage (project root):   python tools/make_tex_tables_b.py [RUN_NAME]
Writes into output/<RUN_NAME>/tex/:
    transition_matrix.tex   5x5 weighted row percentages
    sampleflow.tex          sample construction flow
    weatherstats.tex        weather descriptives (county-season-year cells)
    weathercorr.tex         correlations of related measures
    samplecomp.tex          sample composition by origin year
    allorigin.tex           all-origin matrix, one-SD scaling, Panels A and B
    allorigin_sd.tex        SD of heat in each origin sample
    allorigin_exit.tex      total exit per unit, with baseline exit
    numbers_b.tex           macros used in the text
Needs python3 + pandas only.
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
STATE = {1: "Agriculture", 2: "Industry", 3: "Services", 4: "Unemployed", 5: "Inactive"}


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


def num(x, d=3):
    s = f"{abs(x):.{d}f}"
    return ("$-$" if x < 0 and float(s) != 0 else "") + s


def mnum(x, d=3):
    """number for math mode"""
    s = f"{abs(x):.{d}f}"
    return ("-" if x < 0 and float(s) != 0 else "") + s


def th(n):
    return f"{int(round(n)):,}".replace(",", "{,}")


def write(name, text):
    with open(os.path.join(TEX, name), "w", encoding="utf-8") as f:
        f.write(text)
    print("wrote", name)


# ------------------------------------------------------------ transition matrix
if have("desc_transition_matrix"):
    d = rd("desc_transition_matrix")
    t = "\\begin{tabular}{lrrrrr}\n\\toprule\nOrigin $\\backslash$ Destination & Agriculture & Industry & Services & Unemployed & Inactive \\\\\n\\midrule\n"
    for o in range(1, 6):
        r = d[d.origin == o].sort_values("dest")
        t += STATE[o] + " & " + " & ".join(f"{v:.2f}" for v in r.share_pct) + " \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("transition_matrix.tex", t)
    macros["TMStayAgri"] = f"{d[(d.origin == 1) & (d.dest == 1)].share_pct.iloc[0]:.1f}"
    macros["TMAgriInactive"] = f"{d[(d.origin == 1) & (d.dest == 5)].share_pct.iloc[0]:.1f}"
    macros["TMAgriIndustry"] = f"{d[(d.origin == 1) & (d.dest == 2)].share_pct.iloc[0]:.1f}"
    macros["TMAgriServices"] = f"{d[(d.origin == 1) & (d.dest == 3)].share_pct.iloc[0]:.1f}"
    macros["TMAgriUnemp"] = f"{d[(d.origin == 1) & (d.dest == 4)].share_pct.iloc[0]:.1f}"
    macros["TMStayInd"] = f"{d[(d.origin == 2) & (d.dest == 2)].share_pct.iloc[0]:.1f}"
    macros["TMStayServ"] = f"{d[(d.origin == 3) & (d.dest == 3)].share_pct.iloc[0]:.1f}"
    macros["TMStayInact"] = f"{d[(d.origin == 5) & (d.dest == 5)].share_pct.iloc[0]:.1f}"
    macros["TMStayUnemp"] = f"{d[(d.origin == 4) & (d.dest == 4)].share_pct.iloc[0]:.1f}"

# ------------------------------------------------------------ sample flow
if have("desc_sample_flow"):
    d = rd("desc_sample_flow")
    t = "\\begin{tabular}{c p{0.50\\textwidth} r r r}\n\\toprule\nStep & Description & \\shortstack{Raw\\\\$N$} & \\shortstack{Weighted\\\\$N$} & \\shortstack{Share of\\\\raw (\\%)} \\\\\n\\midrule\n"
    for _, r in d.iterrows():
        t += f"{int(r.step)} & {r.description} & {th(r.n_raw)} & {th(r.n_weighted)} & {r.share_raw:.2f} \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("sampleflow.tex", t)
    macros["FlowAllRows"] = th(d.n_raw.iloc[0])
    macros["FlowAgriRows"] = th(d.n_raw.iloc[1])
    macros["FlowEstSample"] = th(d[d.step == 8].n_raw.iloc[0])
    macros["FlowEducSample"] = th(d[d.step == 13].n_raw.iloc[0])

# ------------------------------------------------------------ weather descriptives
NAMES = {
    "days35_10_s0": "Days35 /10", "heat35_10_s0": "HeatDose35 /10", "days37_10_s0": "Days37 /10",
    "days40_10_s0": "Days40 /10", "heat37_10_s0": "HeatDose37 /10", "heat40_10_s0": "HeatDose40 /10",
    "hdd35_tmean_10_s0": "HDD35, mean-temperature basis /10",
    "countp80_10_s0": "CountP80 /10", "countp90_10_s0": "CountP90 /10", "countp95_10_s0": "CountP95 /10",
    "dosep80_10_s0": "DoseP80 /10", "dosep90_10_s0": "DoseP90 /10", "dosep95_10_s0": "DoseP95 /10",
    "gdd8_32_sine_s1": "GDD(8,32), sine method, one-season lag /100",
    "hdd32_sine_s1": "HDD32, sine method, one-season lag /10",
    "gdd8_32_tmean_s1": "GDD(8,32), mean-temperature basis, one-season lag /100",
    "hdd32_tmean_s1": "HDD32, mean-temperature basis, one-season lag /10",
    "anom_tmean_s0": "Seasonal mean-temperature anomaly", "anom_tmean_sq_s0": "Squared mean-temperature anomaly",
    "tmean_s0": "Seasonal mean temperature ($^\\circ$C)", "tmean_sq_s0": "Squared seasonal mean temperature",
    "bin_tmax_le20_s0": "Tmax $\\leq20^\\circ$C bin /10", "bin_tmax_20_25_s0": "Tmax $20$--$25^\\circ$C bin /10",
    "bin_tmax_25_30_s0": "Tmax $25$--$30^\\circ$C bin /10", "bin_tmax_30_35_s0": "Tmax $30$--$35^\\circ$C bin /10",
    "bin_tmax_35_40_s0": "Tmax $35$--$40^\\circ$C bin /10", "bin_tmax_gt40_s0": "Tmax $>40^\\circ$C bin /10",
    "rain100_s0": "Seasonal rainfall /100", "rain100_lag13": "Mean rainfall over lags 1--3 /100",
}
if have("desc_weather_stats"):
    d = rd("desc_weather_stats")
    t = "\\begin{tabular}{p{0.38\\textwidth}rrrrrr}\n\\toprule\nMeasure & N & Mean & Std. dev. & Min & Median & Max \\\\\n\\midrule\n"
    for _, r in d.iterrows():
        t += f"{NAMES.get(r.varname, r.varname)} & {th(r.n)} & {num(r['mean'], 2)} & {num(r.sd, 2)} & {num(r['min'], 2)} & {num(r.p50, 2)} & {num(r['max'], 2)} \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("weatherstats.tex", t)
    macros["WCells"] = th(d.n.max())

# ------------------------------------------------------------ correlations
PAIRN = {
    "days35_10_s0": "Days35", "heat35_10_s0": "HeatDose35", "days37_10_s0": "Days37", "heat37_10_s0": "HeatDose37",
    "days40_10_s0": "Days40", "heat40_10_s0": "HeatDose40", "countp90_10_s0": "CountP90", "dosep90_10_s0": "DoseP90",
    "countp80_10_s0": "CountP80", "countp95_10_s0": "CountP95", "dosep80_10_s0": "DoseP80", "dosep95_10_s0": "DoseP95",
    "gdd8_32_sine_s1": "Sine GDD s1", "hdd32_sine_s1": "Sine HDD s1", "gdd8_32_sine_s2": "Sine GDD s2",
    "hdd32_sine_s2": "Sine HDD s2", "gdd8_32_tmean_s1": "Tmean-basis GDD s1", "hdd32_tmean_s1": "Tmean-basis HDD s1",
    "tmean_s0": "Tmean", "rain100_s0": "Rainfall",
}
if have("desc_weather_corr"):
    d = rd("desc_weather_corr")
    t = "\\begin{tabular}{lcc}\n\\toprule\nPair & Correlation & Flagged ($|r|\\geq0.80$) \\\\\n\\midrule\n"
    for _, r in d.iterrows():
        t += f"{PAIRN[r.var_a]} vs.\\ {PAIRN[r.var_b]} & {num(r['corr'], 3)} & {'Yes' if r.flagged else 'No'} \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("weathercorr.tex", t)
    c = d.set_index(["var_a", "var_b"])["corr"]
    macros["CorrDaysHeat"] = f"{c[('days35_10_s0', 'heat35_10_s0')]:.2f}"
    macros["CorrDaysRain"] = f"{c[('days35_10_s0', 'rain100_s0')]:.2f}"

# ------------------------------------------------------------ sample composition
if have("desc_sample_composition"):
    d = rd("desc_sample_composition").sort_values("year")
    t = "\\begin{tabular}{rrrrrrrrr}\n\\toprule\nYear & Female & Rural origin & Age & 15--29 & 30--44 & 45--64 & 65+ & Weighted N \\\\\n\\midrule\n"
    for _, r in d.iterrows():
        yr = "All" if int(r.year) == 0 else str(int(r.year))
        if int(r.year) == 0:
            t += "\\midrule\n"
        t += (f"{yr} & {r.female:.3f} & {r.rural:.3f} & {r.age:.2f} & {r.a1529:.3f} & {r.a3044:.3f} & "
              f"{r.a4564:.3f} & {r.a65p:.3f} & {th(r.n_weighted)} \\\\\n")
    t += "\\bottomrule\n\\end{tabular}\n"
    write("samplecomp.tex", t)

# ------------------------------------------------------------ all-origin matrix
if have("lpm_allorigin_results") and have("allorigin_sd"):
    res = rd("lpm_allorigin_results")
    res = res[res.kind == "exposure"].copy()
    res["origin"] = res.panel.str[-1].astype(int)
    sd = rd("allorigin_sd").set_index("origin")
    FAM = [("AllOrigin_Days35", "Panel A: Days35, one-standard-deviation increase", "sd_days35"),
           ("AllOrigin_HeatDose35", "Panel B: HeatDose35, one-standard-deviation increase", "sd_heat35")]
    t = ("\\begin{tabular}{lccccc}\n\\toprule\n& \\multicolumn{5}{c}{Destination state one year later}\\\\\n"
         "\\cmidrule(lr){2-6}\nOrigin state & Agriculture & Industry & Services & Unemployed & Inactive \\\\\n\\midrule\n")
    for i, (fam, title, sdv) in enumerate(FAM):
        if i:
            t += "\\midrule\n"
        t += f"\\multicolumn{{6}}{{l}}{{\\emph{{{title}}}}}\\\\\n"
        for o in range(1, 6):
            cells = []
            for k in range(1, 6):
                r = res[(res.family == fam) & (res.origin == o) & (res.outcome == f"dest{k}")]
                if len(r) != 1 or r.iloc[0].status != "ok":
                    cells.append("--")
                    continue
                r = r.iloc[0]
                f = sd.loc[o, sdv] / 10
                b, s = r.coef * f, r.se * f
                st = stars(r.pvalue)
                body = mnum(b) + (f"^{{{st}}}" if st else "")
                cells.append(f"\\shortstack{{${body}$\\\\({s:.3f})}}")
            t += STATE[o] + " & " + " & ".join(cells) + " \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("allorigin.tex", t)

    # SD table
    t = "\\begin{tabular}{lccc}\n\\toprule\nOrigin state & $N$ & Days35 (days) & HeatDose35 (degree-days) \\\\\n\\midrule\n"
    for o in range(1, 6):
        t += f"{STATE[o]} & {th(sd.loc[o, 'n_days35'])} & {sd.loc[o, 'sd_days35']:.2f} & {sd.loc[o, 'sd_heat35']:.2f} \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("allorigin_sd.tex", t)
    for o, nm in [(1, "Agri"), (2, "Ind"), (3, "Serv"), (4, "Unemp"), (5, "Inact")]:
        macros[f"AOSDDays{nm}"] = f"{sd.loc[o, 'sd_days35']:.2f}"
        macros[f"AOSDHeat{nm}"] = f"{sd.loc[o, 'sd_heat35']:.2f}"
        macros[f"AON{nm}"] = th(sd.loc[o, "n_days35"])

    # total exit per unit
    t = "\\begin{tabular}{lccc}\n\\toprule\nOrigin state & Baseline exit (\\%) & Days35 /10 & HeatDose35 /10 \\\\\n\\midrule\n"
    for o in range(1, 6):
        cs, ss = [], []
        for fam, _, _ in FAM:
            r = res[(res.family == fam) & (res.origin == o) & (res.outcome == f"exit_o{o}")]
            if len(r) == 1 and r.iloc[0].status == "ok":
                r = r.iloc[0]
                st = stars(r.pvalue)
                cs.append(f"${mnum(r.coef)}" + (f"^{{{st}}}" if st else "") + "$")
                ss.append(f"({r.se:.3f})")
            else:
                cs.append("--"); ss.append("")
        t += f"{STATE[o]} & {sd.loc[o, 'baseline_exit_pct']:.2f} & {cs[0]} & {cs[1]} \\\\\n & & {ss[0]} & {ss[1]} \\\\\n"
    t += "\\bottomrule\n\\end{tabular}\n"
    write("allorigin_exit.tex", t)

    # numbers for the text: agriculture row and the "into agriculture" column
    def sc(fam, o, outc):
        r = res[(res.family == fam) & (res.origin == o) & (res.outcome == outc)].iloc[0]
        f = sd.loc[o, "sd_days35" if fam == "AllOrigin_Days35" else "sd_heat35"] / 10
        return r.coef * f, r.se * f, r.pvalue
    b, s, p = sc("AllOrigin_Days35", 1, "dest1"); macros["AOAgriStayCoef"] = f"{b:.2f}".replace("-", "$-$")
    b, s, p = sc("AllOrigin_Days35", 4, "dest4"); macros["AOUnempStayCoef"] = f"{b:.2f}"; macros["AOUnempStayP"] = f"{p:.3f}"
    for o, nm in [(2, "Ind"), (3, "Serv"), (5, "Inact")]:
        b, s, p = sc("AllOrigin_Days35", o, "dest1")
        macros[f"AOInto{nm}Coef"] = f"{b:.2f}".replace("-", "$-$"); macros[f"AOInto{nm}P"] = f"{p:.3f}"

# ------------------------------------------------------------ macros
lines = ["% Written by tools/make_tex_tables_b.py (run " + RUN + "). Do not edit by hand."]
for k in sorted(macros):
    lines.append("\\newcommand{\\%s}{%s}" % (k, macros[k]))
write("numbers_b.tex", "\n".join(lines) + "\n")
