*==============================================================================*
* 25_lpm_allorigin.do
* Reallocation from ALL origin states (thesis section "Reallocation across all origin states").
* The headline model M7 is estimated separately for people who start in each of the five
* labor states (agriculture, industry, services, unemployed, inactive). Outcomes:
*   dest1 ... dest5   in the state k one year later (0/100)
*   exit_o<k>         left the origin state k (0/100)
* Heat measures: Days35 and HeatDose35 (tens), each in its own regression, with rain and
* rain squared and the usual individual controls. Weights Weight_origin; clusters = county.
*
* Standard deviations: for the standardized table the standard deviation of the heat measure
* is taken (weighted) inside each origin-state sample. It is stored in units of days / degree-
* days (SD of the variable divided by ten is the SD in the estimation units, so the coefficient
* per standard deviation is  coef * sd_units / 10).
*
* Output: output/<RUN_NAME>/tables/25_lpm_allorigin.xlsx
*         output/<RUN_NAME>/results/lpm_allorigin_results.dta
*         output/<RUN_NAME>/results/allorigin_sd.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/25_lpm_allorigin.log", text replace name(step)

global XL25 "$TABLES/25_lpm_allorigin.xlsx"

load_model_data

* Base sample: every origin state (prep_lpm_data keeps agriculture only, so we do it here)
gen byte flag_base = inrange(job_origin, 1, 5) & inrange(job_dest, 1, 5) ///
    & (Weight_origin > 0) & !missing(Weight_origin) ///
    & !missing(mix_id) & !missing(province_year) & !missing(pair_id) ///
    & inrange(season_origin, 1, 4) & $YEARS_IF
gen byte flag_ctrl_ok = !missing(age_origin, age2_origin, sex_origin, marital_origin, urban_origin)
keep if flag_base

forvalues k = 1/5 {
    gen byte pp_dest`k'   = 100 * (job_dest == `k')
    gen byte pp_exit_o`k' = 100 * (job_dest != `k')
}

local rain "rain100_s0 rain100_sq_s0"
global SAMPLE_LIST ""
make_sample, name(days35) vars(days35_10_s0 `rain')
make_sample, name(heat35) vars(heat35_10_s0 `rain')

* One sample per origin state and heat measure (same complete cases within a heat measure)
forvalues o = 1/5 {
    foreach m in days35 heat35 {
        gen byte smp_a`m'`o' = smp_`m' == 1 & job_origin == `o'
    }
}

*------------------------------------------------------------------------------*
* Standard deviations and baseline exit by origin state
*------------------------------------------------------------------------------*
tempname hs
tempfile fs
postfile `hs' byte origin long n_days35 long n_heat35 double wn_days35 ///
    double sd_days35 double sd_heat35 double baseline_exit_pct using `fs', replace
forvalues o = 1/5 {
    quietly count if smp_adays35`o' == 1
    local n1 = r(N)
    quietly count if smp_aheat35`o' == 1
    local n2 = r(N)
    quietly summarize Weight_origin if smp_adays35`o' == 1
    local wn = r(sum)
    quietly summarize days35_10_s0 [aweight = Weight_origin] if smp_adays35`o' == 1
    local sd1 = 10 * r(sd)
    quietly summarize heat35_10_s0 [aweight = Weight_origin] if smp_aheat35`o' == 1
    local sd2 = 10 * r(sd)
    quietly summarize pp_exit_o`o' [aweight = Weight_origin] if smp_adays35`o' == 1
    post `hs' (`o') (`n1') (`n2') (`wn') (`sd1') (`sd2') (r(mean))
}
postclose `hs'
preserve
    use `fs', clear
    label define st 1 "Agriculture" 2 "Industry" 3 "Services" 4 "Unemployed" 5 "Inactive"
    label values origin st
    save "$RESULTS/allorigin_sd.dta", replace
restore

*------------------------------------------------------------------------------*
* Regressions
*------------------------------------------------------------------------------*
open_results, file("$RESULTS/lpm_allorigin_results.dta")

foreach m in days35 heat35 {
    local nm "Days35"
    if "`m'" == "heat35" local nm "HeatDose35"
    local x "`m'_10_s0"
    forvalues o = 1/5 {
        foreach y in dest1 dest2 dest3 dest4 dest5 exit_o`o' {
            run_lpm, family("AllOrigin_`nm'") panel("origin`o'") model(7) outcome(`y') ///
                wvars("`x' `rain'") terms("`x'") rainterms("`rain'") sample(a`m'`o')
        }
    }
}
close_results

*------------------------------------------------------------------------------*
* Excel: long results plus standardized coefficients
*------------------------------------------------------------------------------*
guide_sheet, file("$XL25") title("Reallocation from all origin states (M7)") lines("Results_long: every regression (panel = origin state 1-5: 1 agriculture, 2 industry, 3 services, 4 unemployed, 5 inactive; outcome dest<k> = in state k one year later, exit_o<k> = left the origin state). Coefficients are per ten units of the heat measure, in percentage points.|Standardized: coefficient and standard error per one standard deviation of the heat measure (coef * sd_units / 10), stars from the original p value.|SD_baseline: sample sizes, standard deviation of each heat measure in days / degree-days, baseline exit rate (weighted, percent).|Notes: Model M7 = county + province-by-year + season fixed effects, controls age, age squared, sex, marital status, rural origin, rain and rain squared; weights Weight_origin; standard errors clustered by county.")

export_long, file("$XL25") sheet("Results_long")

preserve
    use "$RESULTS/lpm_allorigin_results.dta", clear
    keep if kind == "exposure"
    gen byte origin = real(substr(panel, 7, 1))
    merge m:1 origin using "$RESULTS/allorigin_sd.dta", nogen keepusing(sd_days35 sd_heat35)
    gen double sd_units = cond(family == "AllOrigin_Days35", sd_days35, sd_heat35)
    gen double coef_std = coef * sd_units / 10
    gen double se_std   = se * sd_units / 10
    gen str4 stars = cond(pvalue < 0.01, "***", cond(pvalue < 0.05, "**", cond(pvalue < 0.10, "*", "")))
    keep family origin outcome coef se coef_std se_std stars pvalue n_used n_clusters sd_units
    sort family origin outcome
    export excel using "$XL25", sheet("Standardized", modify) firstrow(variables)
restore

preserve
    use "$RESULTS/allorigin_sd.dta", clear
    export excel using "$XL25", sheet("SD_baseline", modify) firstrow(variables)
restore

* Check: the five destination coefficients of one origin state add up to zero
preserve
    use "$RESULTS/lpm_allorigin_results.dta", clear
    keep if kind == "exposure" & inlist(outcome, "dest1", "dest2", "dest3", "dest4", "dest5")
    collapse (sum) sum_coef = coef, by(family panel)
    list, noobs
    quietly summarize sum_coef
    di as result "Largest absolute sum of destination coefficients within a row: " %9.6f max(abs(r(min)), abs(r(max)))
restore

di as result "25 done."
log close step
