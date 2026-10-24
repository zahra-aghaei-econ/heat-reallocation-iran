*==============================================================================*
* 33_lpm_asymmetry.do
* Is the effect of heat symmetric? Do ten MORE hot days than normal move the outcome
* by the same amount as ten FEWER hot days than normal, with the opposite sign?
*
* Normal = mean of the heat variable in the same county and the same season of the year
* (over the years of the estimation sample; each county-season-year cell counts once).
* For heat variable x (Days35 or HeatDose35, in tens):
*     normal = mean of x in the county and season
*     above  = max(x - normal, 0)     ten days more than normal  -> above = 1
*     below  = max(normal - x, 0)     ten days fewer than normal -> below = 1
* so x = normal + above - below in every row.
*
* Two regressions for each outcome and each heat variable (all with rain, rain squared
* and the individual controls; model M7 fixed effects; weights Weight_origin; standard
* errors clustered by county):
*   1_M7_linear    y = b x                                 (the main model)
*   2_M7_split     y = b_n normal + b_a above + b_b below  (M7 fixed effects)
*                  If b_n = b_a = -b_b this is exactly the main model.
* Symmetry test (rows symmetry_test): b_a + b_b = 0, that is, the two effects have the
* same size and opposite signs. A small p value means the response is not symmetric.
*
* Output: output/<RUN_NAME>/tables/33_lpm_asymmetry.xlsx
*         output/<RUN_NAME>/results/lpm_asymmetry_results.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/33_lpm_asymmetry.log", text replace name(step)

global XL33 "$TABLES/33_lpm_asymmetry.xlsx"

prep_lpm_data

local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain')
make_sample, name(heat35) vars(heat35_10_s0 `rain')

*------------------------------------------------------------------------------*
* Normal, above and below (county and season)
*------------------------------------------------------------------------------*
foreach m in days35 heat35 {
    local x "`m'_10_s0"
    local unit "ten days"
    if "`m'" == "heat35" local unit "ten units"
    egen byte cell_tag = tag(mix_id year_origin season_origin) if smp_`m' == 1
    egen double norm_t = mean(`x') if cell_tag == 1, by(mix_id season_origin)
    egen double `m'_normal = max(norm_t), by(mix_id season_origin)
    replace `m'_normal = . if smp_`m' != 1
    gen double `m'_above = max(`x' - `m'_normal, 0) if !missing(`m'_normal)
    gen double `m'_below = max(`m'_normal - `x', 0) if !missing(`m'_normal)
    label var `m'_normal "`m' normal of county and season (`unit')"
    label var `m'_above  "`m' above normal (`unit' more than normal)"
    label var `m'_below  "`m' below normal (`unit' fewer than normal)"
    drop cell_tag norm_t

    * check: x = normal + above - below
    quietly count if smp_`m' == 1 & abs(`x' - (`m'_normal + `m'_above - `m'_below)) > 1e-8
    if r(N) > 0 di as error "33: decomposition does not add up in " r(N) " rows (`m')"
    quietly summarize `m'_above if smp_`m' == 1 [aw = Weight_origin]
    di as text "`m': mean above = " %6.3f r(mean)
    quietly summarize `m'_below if smp_`m' == 1 [aw = Weight_origin]
    di as text "`m': mean below = " %6.3f r(mean)
}

*------------------------------------------------------------------------------*
* Regressions
*------------------------------------------------------------------------------*
open_results, file("$RESULTS/lpm_asymmetry_results.dta")

foreach y of global OUTCOMES {
    foreach m in days35 heat35 {
        local nm "Days35"
        if "`m'" == "heat35" local nm "HeatDose35"
        local x "`m'_10_s0"
        local tst "`m'_above + `m'_below = 0"
        local tlb "Symmetry test: above = -below (F)"

        run_lpm, family("Asym_`nm'") panel("1_M7_linear") model(7) outcome(`y') ///
            wvars("`x' `rain'") terms("`x'") rainterms("`rain'") sample(`m')

        run_lpm, family("Asym_`nm'") panel("2_M7_split") model(7) outcome(`y') ///
            wvars("`m'_normal `m'_above `m'_below `rain'") terms("`m'_above `m'_below `m'_normal") ///
            rainterms("`rain'") sample(`m') jtest("`tst'") jname("symmetry_test") jlabel("`tlb'")
    }
}
close_results

*------------------------------------------------------------------------------*
* Excel
*------------------------------------------------------------------------------*
guide_sheet, file("$XL33") title("Symmetry: effect of heat above and below the county-season normal (model M7)") ///
    lines("Summary: For the split model, the coefficient on above (ten more hot days than normal) and on below (ten fewer hot days than normal), their sum (zero if the effect is symmetric) and the p value of the symmetry test.|Days35, HeatDose35: All coefficients. Panels: 1_M7_linear = main model; 2_M7_split = x split into normal + above - below.|Test_Days35, Test_HeatDose35: Symmetry test (H0: coefficient on above + coefficient on below = 0).|All_long: All rows of the results file, including rain controls.|Samples: Sample sizes.|Notes: Normal is the mean of the heat variable in the same county and season over the sample years. above = max(x - normal, 0), below = max(normal - x, 0). Under symmetry the two coefficients have the same size and opposite signs.")

export_wide, file("$XL33") sheet("Days35") family("Asym_Days35")
export_wide, file("$XL33") sheet("HeatDose35") family("Asym_HeatDose35")
export_wide, file("$XL33") sheet("Test_Days35") family("Asym_Days35") kind("test")
export_wide, file("$XL33") sheet("Test_HeatDose35") family("Asym_HeatDose35") kind("test")

* Summary: one row per heat variable, panel and outcome
preserve
    use "$RESULTS/lpm_asymmetry_results.dta", clear
    keep if panel == "2_M7_split"
    gen str8 part = ""
    replace part = "above" if kind == "exposure" & strpos(term, "_above") > 0
    replace part = "below" if kind == "exposure" & strpos(term, "_below") > 0
    replace part = "test"  if kind == "test"
    keep if part != ""
    keep family panel outcome part coef se pvalue n_used
    bysort family panel outcome: egen long N = max(n_used)
    drop n_used
    reshape wide coef se pvalue, i(family panel outcome N) j(part) string
    rename coefabove   b_above
    rename seabove     se_above
    rename pvalueabove p_above
    rename coefbelow   b_below
    rename sebelow     se_below
    rename pvaluebelow p_below
    rename coeftest    F_symmetry
    rename pvaluetest  p_symmetry
    capture drop setest
    gen double sum_above_below = b_above + b_below
    gen double size_ratio_below_to_above = abs(b_below) / abs(b_above)
    gen byte ord = 1
    replace ord = 2 if outcome == "productive_exit"
    replace ord = 3 if outcome == "distress_exit"
    replace ord = 4 if outcome == "dest2"
    replace ord = 5 if outcome == "dest3"
    replace ord = 6 if outcome == "dest4"
    replace ord = 7 if outcome == "dest5"
    sort family panel ord
    drop ord
    order family panel outcome b_above se_above p_above b_below se_below p_below ///
        sum_above_below size_ratio_below_to_above F_symmetry p_symmetry N
    export excel using "$XL33", sheet("Summary", modify) firstrow(variables)
restore

export_long, file("$XL33") sheet("All_long")
export_samples, file("$XL33") sheet("Samples")

di as result "33 done."
log close step
