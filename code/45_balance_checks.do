*==============================================================================*
* 45_balance_checks.do
* Balance of predetermined characteristics with respect to heat exposure (identification check).
*
* The fixed effects of M7 and rain controls are kept; the individual controls are NOT included
* (they are the outcome here). If heat is as good as random given the fixed effects, it should
* not predict who is in the agriculture-origin sample.
*   Part 1  each predetermined characteristic on Days35 / HeatDose35: age, female, married,
*           rural origin (coefficients in the units of the characteristic; for the
*           indicators in percentage points)
*   Part 2  reverse regression: heat on all four characteristics together, joint F test
*
* Output: output/<RUN_NAME>/tables/45_balance_checks.xlsx
*         output/<RUN_NAME>/results/balance_results.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/45_balance_checks.log", text replace name(step)

global XL45 "$TABLES/45_balance_checks.xlsx"

prep_lpm_data
local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain')
make_sample, name(heat35) vars(heat35_10_s0 `rain')

decode marital_origin, gen(marital_label)
gen double c_age     = age_origin
gen double c_female  = 100 * female_origin
gen double c_married = 100 * (marital_label == "Married")
gen double c_rural   = 100 * urban_origin

get_spec 7
local absorb "`r(absorb)'"

tempname h
tempfile f
postfile `h' str12 exposure str12 part str12 characteristic long n_used long n_clusters ///
    double coef double se double pvalue double stat double mean_dep using `f', replace

foreach m in days35 heat35 {
    local nm "Days35"
    if "`m'" == "heat35" local nm "HeatDose35"
    local x "`m'_10_s0"
    foreach c in age female married rural {
        quietly reghdfe c_`c' `x' `rain' if smp_`m' == 1 [pweight = Weight_origin], absorb(`absorb') ///
            vce(cluster mix_id)
        local b = _b[`x']
        local s = _se[`x']
        quietly summarize c_`c' [aweight = Weight_origin] if e(sample)
        post `h' ("`nm'") ("single") ("`c'") (e(N)) (e(N_clust)) (`b') (`s') ///
            (`=2*ttail(e(df_r), abs(`b'/`s'))') (.) (r(mean))
    }
    quietly reghdfe `x' c_age c_female c_married c_rural `rain' if smp_`m' == 1 [pweight = Weight_origin], ///
        absorb(`absorb') vce(cluster mix_id)
    quietly test c_age c_female c_married c_rural
    post `h' ("`nm'") ("joint") ("all four") (e(N)) (e(N_clust)) (.) (.) (r(p)) (r(F)) (.)
}
postclose `h'
use `f', clear
save "$RESULTS/balance_results.dta", replace
list, noobs
guide_sheet, file("$XL45") title("Balance of predetermined characteristics (45)") lines("Part single: coefficient of the heat measure (tens) on one predetermined characteristic of the agriculture-origin sample (age in years; female, married and rural origin as 0/100), with M7 fixed effects (county, province-by-year, season) and rain controls, without individual controls. Weights Weight_origin, standard errors clustered by county.|Part joint: heat on the four characteristics together; stat = F, pvalue = joint test that all four coefficients are zero.")
export excel using "$XL45", sheet("Results", modify) firstrow(variables)

di as result "45 done."
log close step
