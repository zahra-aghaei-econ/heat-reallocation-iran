"""
Province crop-area check of the agro-climatic regions.

Input : Statistical Centre of Iran, "Results of the annual-crop survey 1399-1400",
        Excel tables by province (kept outside the repository).
        Tables used: 9 (all annual crops) and the crop tables 12-54 (even numbers).
        The survey covers ANNUAL crops only: date palms, pistachios and other orchards
        are not in it, so the hot-arid date belt cannot be checked with this file.
Input : lookups/agro_region_crosswalk_1385.dta and lookups/county_codebook_1385.dta
Output: output/region_check/province_crop_check.xlsx and .../province_crop_table.tex
Run   : python tools/province_crop_check.py "<path to the survey excel>"
"""
import sys, re
import pandas as pd

src = sys.argv[1]
root = sys.argv[2] if len(sys.argv) > 2 else "."
x = pd.ExcelFile(src)
names = {s.strip(): s for s in x.sheet_names}

def norm(s):
    return re.sub(r"\s+", " ", str(s).replace("ي", "ی").replace("ك", "ک").replace("‌", " ")).strip()

crops = {12: "Wheat", 24: "Barley", 18: "Rice", 20: "Cotton", 36: "Saffron", 52: "Sugarcane",
         38: "Potato", 26: "Sugar beet", 14: "Beans", 16: "Chickpea", 22: "Onion",
         32: "Forage maize", 34: "Grain maize", 40: "Canola", 42: "Tomato", 44: "Watermelon",
         48: "Alfalfa", 28: "Melon etc.", 30: "Cucumber", 46: "Carrot, radish, turnip",
         50: "Other vegetables", 54: "Other annual crops"}

def read(n):
    d = pd.read_excel(x, names[str(n)], header=None)
    out = {}
    for r in d.iloc[3:].itertuples(index=False):
        k = norm(r[0])
        if k not in ("nan", ""):
            out[k] = r
    return out

t9 = read(9)
prov = [k for k in t9 if k not in ("کل کشور", "سایر")]
df = pd.DataFrame({"province_fa": prov}).set_index("province_fa")
df["total_sown_ha"] = [float(t9[p][2]) for p in prov]
df["irrigated_ha"] = [float(t9[p][5]) for p in prov]
df["rainfed_ha"] = [float(t9[p][8]) for p in prov]
for n, c in crops.items():
    t = read(n)
    df[c] = [float(t[p][2]) if p in t and pd.notna(t[p][2]) else 0.0 for p in prov]
listed = list(crops.values())
df["Not in a listed crop"] = (df["total_sown_ha"] - df[listed].sum(axis=1)).clip(lower=0)

# Alborz was part of Tehran in 1385: add it to Tehran for the match with the 1385 regions
combo = df.copy()
combo.loc["تهران"] = combo.loc["تهران"] + combo.loc["البرز"]
combo = combo.drop(index="البرز")

# Regions per province (1385 counties)
cw = pd.read_stata(f"{root}/lookups/agro_region_crosswalk_1385.dta")
cb = pd.read_stata(f"{root}/lookups/county_codebook_1385.dta")
m = cw.merge(cb[["mix4", "prov_fa"]], on="mix4", how="left")
m["prov_fa"] = m["prov_fa"].map(norm)
rname = {1: "Caspian rice", 2: "Highland cereal", 3: "Plateau cereal and orchard",
         4: "Khorasan saffron and wheat", 5: "Warm lowland wheat", 6: "Hot arid date belt"}
reg = (m.groupby(["prov_fa", "agro_region"]).size().unstack(fill_value=0))
def reg_text(p):
    if p not in reg.index: return ""
    r = reg.loc[p]; r = r[r > 0].sort_values(ascending=False)
    return "; ".join(f"{rname[int(k)]} ({int(v)})" for k, v in r.items())

# Match province names between the two sources (spelling differences)
alias = {"آذربایجان شرقی": ["آذربایجان شرقی"], "کهگلویه و بویراحمد": ["کهگیلویه و بویراحمد", "کهگلویه و بویراحمد"]}
def find_prov(p):
    if p in reg.index: return p
    for a in alias.get(p, []):
        if a in reg.index: return a
    fix = lambda t: t.replace(" ", "").replace("کهگلویه", "کهگیلویه")
    cand = [q for q in reg.index if fix(q) == fix(p)]
    return cand[0] if cand else None

shares = combo[listed + ["Not in a listed crop"]].div(combo["total_sown_ha"], axis=0) * 100
rows = []
for p in combo.index:
    s = shares.loc[p].drop("Not in a listed crop").sort_values(ascending=False)
    q = find_prov(p)
    rows.append({
        "province": p,
        "total_sown_ha": round(combo.loc[p, "total_sown_ha"]),
        "rainfed_pct": round(100 * combo.loc[p, "rainfed_ha"] / combo.loc[p, "total_sown_ha"], 1),
        "top1": f"{s.index[0]} {s.iloc[0]:.0f}%", "top2": f"{s.index[1]} {s.iloc[1]:.0f}%",
        "top3": f"{s.index[2]} {s.iloc[2]:.0f}%",
        "our_regions_counties": reg_text(q) if q else "NO MATCH",
    })
summ = pd.DataFrame(rows)

with pd.ExcelWriter(f"{root}/output/region_check/province_crop_check.xlsx") as w:
    pd.DataFrame({"Notes": [
        "Source: Statistical Centre of Iran, annual-crop survey 1399-1400 (tables by province). Annual crops only: dates, pistachios and other orchards are not included.",
        "Summary: top three crops by share of sown area, rainfed share, and the regions assigned to the province's counties in our crosswalk (number of counties in parentheses).",
        "Area_ha: sown area in hectares by crop. Share_pct: percent of the province's total sown area.",
        "Alborz is added to Tehran so the provinces match the 1385 county codes.",
        "Caution: for crops with a short table (saffron, cotton, sugarcane, canola and a few others) the survey lists only the main provinces and puts the rest under Other. A province not listed shows 0 here although it may grow some of the crop; its area is then inside the column Not in a listed crop."]}).to_excel(w, sheet_name="00_Guide", index=False)
    summ.to_excel(w, sheet_name="Summary", index=False)
    combo.round(0).to_excel(w, sheet_name="Area_ha")
    shares.round(1).to_excel(w, sheet_name="Share_pct")

# LaTeX table: main crops only
top_crops = ["Wheat", "Barley", "Rice", "Alfalfa", "Saffron", "Sugarcane", "Cotton", "Potato"]
tex = ["\\begin{tabular}{lrrrrrrrrr}", "\\toprule",
       "Province & Rainfed & " + " & ".join(top_crops) + " \\\\", "\\midrule"]
for p in combo.index:
    row = [p, f"{100*combo.loc[p,'rainfed_ha']/combo.loc[p,'total_sown_ha']:.0f}"]
    row += [f"{shares.loc[p, c]:.0f}" for c in top_crops]
    tex.append(" & ".join(row) + " \\\\")
tex += ["\\bottomrule", "\\end{tabular}"]
open(f"{root}/output/region_check/province_crop_table.tex", "w", encoding="utf-8").write("\n".join(tex))
print(summ.to_string(max_colwidth=60))
