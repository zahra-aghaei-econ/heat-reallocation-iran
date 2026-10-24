*==============================================================================*
* 38_period_interactions.do
* Does the heat effect differ across periods? Main model M7 only (county, province-by-year
* and season fixed effects, individual controls, rain), with the heat variable interacted
* with period indicators. The fixed effects are the same in every period.
*     y = sum_k b_k * x * 1(origin year in period k) + rain + controls + M7 fixed effects
* Period splits (origin years):
*   1_cut1390        1384-1390 | 1391-1402
*   2_cut1397        1384-1397 | 1398-1402
*   3_three_periods  1384-1390 | 1391-1397 | 1398-1402
*   4_four_periods   1384-1390 | 1391-1397 | 1398-1399 | 1400-1402
*   5_each_year      one slope for each origin year
* (Origin years 1386, 1387, 1391 and 1396 have no same-season transitions, so the
*  periods contain the years that exist.) Each regression has a test that all slopes
*  in it are equal (F test, standard errors clustered by county).
* Sheet Year_heterogeneity: for the yearly slopes, the weighted mean, a Q test that they
* are all equal (it treats the yearly slopes as independent), and the trend per year
* (weighted by 1 / se^2).
*
* Output: output/<RUN_NAME>/tables/38_period_interactions.xlsx
*         output/<RUN_NAME>/results/lpm_period_results.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/38_period_interactions.log", text replace name(step)

global XL38 "$TABLES/38_period_interactions.xlsx"

prep_lpm_data

local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain')
make_sample, name(heat35) vars(heat35_10_s0 `rain')

* Period splits: pairs of first and last origin year of each period
local np 4
local pname1 "1_cut1390"
local pr1    "1384 1390 1391 1402"
local pname2 "2_cut1397"
local pr2    "1384 1397 1398 1402"
local pname3 "3_three_periods"
local pr3    "1384 1390 1391 1397 1398 1402"
local pname4 "4_four_periods"
local pr4    "1384 1390 1391 1397 1398 1399 1400 1402"

foreach m in days35 heat35 {
    local x "`m'_10_s0"
    forvalues p = 1/`np' {
        local nr : word count `pr`p''
        local G = `nr' / 2
        local terms_`m'_`p' ""
        local jt_`m'_`p' ""
        forvalues g = 1/`G' {
            local lo : word `=2*`g'-1' of `pr`p''
            local hi : word `=2*`g'' of `pr`p''
            gen double `m'_p`p'g`g' = `x' * inrange(year_origin, `lo', `hi')
            label var `m'_p`p'g`g' "`m', origin years `lo' to `hi'"
            local terms_`m'_`p' "`terms_`m'_`p'' `m'_p`p'g`g'"
            if `g' == 1 {
                local jt_`m'_`p' "`m'_p`p'g`g'"
            }
            else {
                local jt_`m'_`p' "`jt_`m'_`p'' = `m'_p`p'g`g'"
            }
        }
    }
    * one slope for each origin year
    quietly levelsof year_origin if smp_`m' == 1, local(years_`m')
    local terms_`m'_y ""
    local jt_`m'_y ""
    local first = 1
    foreach yr of local years_`m' {
        gen double `m'_y`yr' = `x' * (year_origin == `yr')
        label var `m'_y`yr' "`m', origin year `yr'"
        local terms_`m'_y "`terms_`m'_y' `m'_y`yr'"
        if `first' == 1 {
            local jt_`m'_y "`m'_y`yr'"
        }
        else {
            local jt_`m'_y "`jt_`m'_y' = `m'_y`yr'"
        }
        local first = 0
    }
}

open_results, file("$RESULTS/lpm_period_results.dta")

foreach y of global OUTCOMES {
    foreach m in days35 heat35 {
        local nm "Days35"
        if "`m'" == "heat35" local nm "HeatDose35"
        forvalues p = 1/`np' {
            run_lpm, family("Per_`nm'") panel("`pname`p''") model(7) outcome(`y') ///
                wvars("`terms_`m'_`p'' `rain'") terms("`terms_`m'_`p''") ///
                rainterms("`rain'") sample(`m') jtest("`jt_`m'_`p''")
        }
        run_lpm, family("Year_`nm'") panel("5_each_year") model(7) outcome(`y') ///
            wvars("`terms_`m'_y' `rain'") terms("`terms_`m'_y'") ///
            rainterms("`rain'") sample(`m') jtest("`jt_`m'_y'")
    }
}
close_results

*------------------------------------------------------------------------------*
* Excel
*------------------------------------------------------------------------------*
guide_sheet, file("$XL38") title("Heat effect by period (model M7, heat interacted with period)") ///
    lines("Days35, HeatDose35: Slopes by period. Each panel is one regression with one slope per period (the fixed effects are the same in all periods). Panels: 1_cut1390, 2_cut1397, 3_three_periods, 4_four_periods.|Test_Days35, Test_HeatDose35: Test that the slopes in a regression are equal (p value).|Years_Days35, Years_HeatDose35: One slope for each origin year in a single regression.|Year_heterogeneity: Weighted mean of the yearly slopes, Q test that they are equal, trend per year.|All_long: All rows of the results file.|Notes: Slopes are percentage points per ten additional hot days (Days35) or ten units of heat dose. Single years are noisy (standard errors are large), so yearly slopes should be read together with the Q test.")

export_wide, file("$XL38") sheet("Days35") family("Per_Days35")
export_wide, file("$XL38") sheet("HeatDose35") family("Per_HeatDose35")
export_wide, file("$XL38") sheet("Test_Days35") family("Per_Days35") kind("test")
export_wide, file("$XL38") sheet("Test_HeatDose35") family("Per_HeatDose35") kind("test")
export_wide, file("$XL38") sheet("Years_Days35") family("Year_Days35")
export_wide, file("$XL38") sheet("Years_HeatDose35") family("Year_HeatDose35")
export_wide, file("$XL38") sheet("Test_Years_Days35") family("Year_Days35") kind("test")
export_wide, file("$XL38") sheet("Test_Years_HeatDose35") family("Year_HeatDose35") kind("test")

preserve
    use "$RESULTS/lpm_period_results.dta", clear
    keep if substr(family, 1, 5) == "Year_" & kind == "exposure" & status == "ok"
    gen int origin_year = real(substr(term, strlen(term) - 3, 4))
    gen double wgt = 1 / se^2
    egen double sum_w = total(wgt), by(family outcome)
    gen double wb = wgt * coef
    egen double sum_wb = total(wb), by(family outcome)
    gen double mean_coef = sum_wb / sum_w
    gen double q_i = wgt * (coef - mean_coef)^2
    egen double Q = total(q_i), by(family outcome)
    egen int n_years = count(coef), by(family outcome)
    gen double p_equal = chi2tail(n_years - 1, Q)
    tempfile het
    save `het'
    statsby trend_per_year = _b[origin_year] trend_se = _se[origin_year], by(family outcome) clear: ///
        regress coef origin_year [aweight = wgt]
    merge 1:m family outcome using `het', nogenerate keep(match)
    bysort family outcome: keep if _n == 1
    gen double trend_t = trend_per_year / trend_se
    gen byte ord = 1
    replace ord = 2 if outcome == "productive_exit"
    replace ord = 3 if outcome == "distress_exit"
    replace ord = 4 if outcome == "dest2"
    replace ord = 5 if outcome == "dest3"
    replace ord = 6 if outcome == "dest4"
    replace ord = 7 if outcome == "dest5"
    sort family ord
    keep family outcome n_years mean_coef Q p_equal trend_per_year trend_se trend_t
    order family outcome n_years mean_coef Q p_equal trend_per_year trend_se trend_t
    export excel using "$XL38", sheet("Year_heterogeneity", modify) firstrow(variables)
restore

export_long, file("$XL38") sheet("All_long")
export_samples, file("$XL38") sheet("Samples")

di as result "38 done."
log close step
