*==============================================================================*
* 44_identifying_variation.do
* How much variation in heat is left when the fixed effects are made more demanding?
* Compares M7 (county + province-year + season) with M9 (county + province-year-season).
* For Days35 and HeatDose35 on the common estimation sample of the two models:
*   Panel A  sample sizes, clusters, number of province-year and province-year-season cells
*   Panel B  weighted standard deviation of the heat measure: raw, residual after M7 and
*            after M9 (rain, rain squared and the individual controls partialled out as well)
*   Panel C  the same unweighted
* Standard deviations are in the units of the regressor (tens of days, tens of degree-days).
*
* Output: output/<RUN_NAME>/tables/44_identifying_variation.xlsx
*         output/<RUN_NAME>/results/idvar_results.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/44_identifying_variation.log", text replace name(step)

global XL44 "$TABLES/44_identifying_variation.xlsx"

prep_lpm_data
local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain')
make_sample, name(heat35) vars(heat35_10_s0 `rain')

get_spec 7
local ctrl "`r(controls)'"
local abs7 "`r(absorb)'"
get_spec 9
local abs9 "`r(absorb)'"

tempname h
tempfile f
postfile `h' str12 exposure str8 panel str60 item double value using `f', replace

foreach m in days35 heat35 {
    local nm "Days35"
    if "`m'" == "heat35" local nm "HeatDose35"
    local x "`m'_10_s0"

    quietly count if smp_`m' == 1
    local n0 = r(N)

    quietly reghdfe pp_exit_agri `x' `rain' `ctrl' if smp_`m' == 1 [pweight = Weight_origin], ///
        absorb(`abs7') vce(cluster mix_id)
    capture drop s7
    gen byte s7 = e(sample)
    local n7 = e(N)
    local g7 = e(N_clust)
    quietly reghdfe pp_exit_agri `x' `rain' `ctrl' if smp_`m' == 1 [pweight = Weight_origin], ///
        absorb(`abs9') vce(cluster mix_id)
    capture drop s9
    gen byte s9 = e(sample)
    local n9 = e(N)
    capture drop common
    gen byte common = s7 == 1 & s9 == 1
    quietly count if common == 1
    local nc = r(N)

    egen byte t_py = tag(province_year) if common == 1
    quietly count if t_py == 1
    local npy = r(N)
    egen byte t_pys = tag(province_year_season) if common == 1
    quietly count if t_pys == 1
    local npys = r(N)
    drop t_py t_pys

    post `h' ("`nm'") ("A") ("Sample before singleton removal") (`n0')
    post `h' ("`nm'") ("A") ("Baseline M7 estimation observations") (`n7')
    post `h' ("`nm'") ("A") ("Saturated M9 estimation observations") (`n9')
    post `h' ("`nm'") ("A") ("Common sample of the two models") (`nc')
    post `h' ("`nm'") ("A") ("County clusters (M7)") (`g7')
    post `h' ("`nm'") ("A") ("Province-year cells (M7)") (`npy')
    post `h' ("`nm'") ("A") ("Province-year-season cells (M9)") (`npys')
    post `h' ("`nm'") ("A") ("Observations removed by saturation") (`n7' - `nc')

    * Residualise the heat measure
    capture drop r7 r9
    quietly reghdfe `x' `rain' `ctrl' if common == 1 [pweight = Weight_origin], absorb(`abs7') ///
        vce(cluster mix_id) residuals(r7)
    quietly reghdfe `x' `rain' `ctrl' if common == 1 [pweight = Weight_origin], absorb(`abs9') ///
        vce(cluster mix_id) residuals(r9)

    foreach wt in W U {
        local aw ""
        local pn "B"
        if "`wt'" == "W" local aw "[aweight = Weight_origin]"
        else local pn "C"
        quietly summarize `x' `aw' if common == 1
        local sd_raw = r(sd)
        quietly summarize r7 `aw' if common == 1
        local sd7 = r(sd)
        quietly summarize r9 `aw' if common == 1
        local sd9 = r(sd)
        post `h' ("`nm'") ("`pn'") ("Raw SD") (`sd_raw')
        post `h' ("`nm'") ("`pn'") ("Baseline residual SD") (`sd7')
        post `h' ("`nm'") ("`pn'") ("Saturated residual SD") (`sd9')
        post `h' ("`nm'") ("`pn'") ("Residual SD retained (%)") (100 * `sd9' / `sd7')
        post `h' ("`nm'") ("`pn'") ("Residual variance retained (%)") (100 * (`sd9' / `sd7')^2)
        post `h' ("`nm'") ("`pn'") ("Residual variance absorbed (%)") (100 * (1 - (`sd9' / `sd7')^2))
    }
    drop s7 s9 common r7 r9
}
postclose `h'
use `f', clear
save "$RESULTS/idvar_results.dta", replace

guide_sheet, file("$XL44") title("Identifying variation under fixed-effect saturation (44)") lines("Results: panel A = sample and cells, panel B = weighted standard deviations of the heat measure, panel C = unweighted. Residual SD is the SD of the heat measure after partialling out rain, rain squared, individual controls and the fixed effects of M7 (baseline) or M9 (county + province-by-year-by-season, saturated), on the common sample of the two models.|Heat units: tens of days (Days35) and tens of degree-days (HeatDose35).")
export excel using "$XL44", sheet("Results", modify) firstrow(variables)

di as result "44 done."
log close step
