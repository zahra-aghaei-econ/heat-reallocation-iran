*==============================================================================*
* 42_attrition.do
* Scheduled panel non-continuation and its consequences for the headline estimates.
*
* A  Origin-person file. Everybody aged 15 or more seen in turn 1 or 2 (origin) in a year in
*    which linkage is possible. person_return = 1 if the same person ID is seen again at the
*    scheduled return (turn 3 or 4, same season, one year later). household_return = 1 if the
*    household is seen again at the scheduled return. Within-household loss = person gone
*    although the household returned. Built from intermediate/lfs_individual.dta and
*    intermediate/transitions_same_season.dta; saved in intermediate/ (microdata, not for GitHub).
* B  Non-continuation by origin year (agriculture origin, weighted).
* C  Does weather predict non-continuation? M7 and M8 with Days35 and HeatDose35;
*    plus joint tests of heat x characteristic interactions.
* D  Continuation propensity (weighted logit with county, province-year, season and pair
*    fixed effects), stabilised inverse-probability weights, p1/p99 trimmed version,
*    weight diagnostics and covariate balance.
* E  Headline M7 under four weightings, same observations in columns 2 to 4:
*      1 baseline (survey weight), 2 survey weight on the common IPW sample,
*      3 survey weight x stabilised IPW, 4 survey weight x trimmed IPW.
*
* Switch: global PROP_METHOD "logit" (default) or "lpm" (linear probability model absorbing the
* fixed effects; faster and lighter in memory, probabilities clipped to [0.01, 0.99]).
*
* Output: output/<RUN_NAME>/tables/42_attrition.xlsx
*         output/<RUN_NAME>/results/attr_byyear.dta, lpm_attr_weather_results.dta,
*             attr_het_tests.dta, attr_propensity.dta, attr_weightdiag.dta, attr_balance.dta,
*             lpm_ipw_results.dta, attr_ipw_flow.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/42_attrition.log", text replace name(step)

global XL42 "$TABLES/42_attrition.xlsx"
if "$PROP_METHOD" == "" global PROP_METHOD "logit"

*------------------------------------------------------------------------------*
* Helper programs
*------------------------------------------------------------------------------*
capture program drop kish_ess
program define kish_ess, rclass
    syntax varname [if]
    marksample touse
    tempvar w2
    quietly gen double `w2' = `varlist'^2 if `touse'
    quietly summarize `varlist' if `touse'
    local s1 = r(sum)
    quietly summarize `w2' if `touse'
    local s2 = r(sum)
    return scalar ess = (`s1'^2) / `s2'
end

*------------------------------------------------------------------------------*
* A. Origin-person file
*------------------------------------------------------------------------------*
* Years in which linkage is possible at all (at least one matched transition)
use year_origin using "$INTER/transitions_same_season.dta", clear
bysort year_origin: keep if _n == 1
keep if inrange(year_origin, $FIRST_ORIGIN_YEAR, $LAST_ORIGIN_YEAR)
tempfile okyears
save `okyears'

* Household observed at the scheduled return
use ID year season census_turn using "$INTER/lfs_individual.dta", clear
keep if inlist(census_turn, 3, 4) & inrange(season, 1, 4)
keep if ID != ""
duplicates drop
rename year year_dest
rename season season_origin
rename census_turn dest_turn
gen byte hh_return = 1
tempfile hhdest
save `hhdest'

* Matched persons
use pid year_origin season_origin pair_id using "$INTER/transitions_same_season.dta", clear
gen byte person_return = 1
tempfile matched
save `matched'

* Origin side
use "$INTER/lfs_individual.dta", clear
drop if missing(pid)
drop if inlist(pid_source, 2, 3) & dup_pid_wave_season > 0
keep if inlist(census_turn, 1, 2) & inrange(season, 1, 4)
keep if age >= 15 & !missing(age)
keep if weight > 0 & !missing(weight)
duplicates tag pid year season census_turn, gen(dup_o)
drop if dup_o > 0
drop dup_o
rename year   year_origin
rename season season_origin
gen byte pair_id   = cond(census_turn == 1, 13, 24)
gen byte dest_turn = census_turn + 2
gen int  year_dest = year_origin + 1
rename mix4       mix4_origin
rename province85 province85_origin
rename weight     Weight_origin
rename age        age_origin
rename age2       age2_origin
rename sex        sex_origin
rename marital    marital_origin
rename urban      urban_origin
rename educ       educ_origin
gen byte job_origin = job
if "$UNCLASSIFIED_AS_SERVICES" == "1" replace job_origin = job_alt
merge m:1 year_origin using `okyears', keep(match) nogen
merge 1:1 pid year_origin season_origin pair_id using `matched', keep(master match) nogen
replace person_return = 0 if missing(person_return)
merge m:1 ID year_dest season_origin dest_turn using `hhdest', keep(master match) nogen
replace hh_return = 0 if missing(hh_return)
gen byte person_attrit = 1 - person_return
gen byte hh_attrit     = 1 - hh_return
gen byte within_loss   = (person_attrit == 1 & hh_return == 1)
gen byte agri_origin   = (job_origin == 1)

* Geography, time and weather
gen byte invalid_mix = (mix4_origin == "" | missing(real(mix4_origin)))
egen long mix_id = group(mix4_origin) if invalid_mix == 0
egen long province_year = group(province85_origin year_origin), missing
gen double year_trend = year_origin - 1391
preserve
    use mix4 year season days35_10_s0 heat35_10_s0 rain100_s0 rain100_sq_s0 ///
        using "$INTER/weather_county_season.dta", clear
    rename mix4 mix4_origin
    rename year year_origin
    rename season season_origin
    tempfile wx
    save `wx'
restore
merge m:1 mix4_origin year_origin season_origin using `wx', keep(master match) nogen

gen byte ctrl_ok = !missing(age_origin, age2_origin, sex_origin, marital_origin, urban_origin)
gen byte wx_ok   = !missing(days35_10_s0, heat35_10_s0, rain100_s0, rain100_sq_s0)
gen byte geo_ok  = !missing(mix_id, province_year)
gen byte main_attr = ctrl_ok & wx_ok & geo_ok
gen double pp_att_person = 100 * person_attrit
gen double pp_att_hh     = 100 * hh_attrit
gen double pp_att_within = 100 * within_loss
keep pid ID year_origin season_origin pair_id Weight_origin age_origin age2_origin sex_origin ///
    marital_origin urban_origin educ_origin job_origin agri_origin mix_id mix4_origin province_year ///
    year_trend days35_10_s0 heat35_10_s0 rain100_s0 rain100_sq_s0 person_return hh_return ///
    person_attrit hh_attrit within_loss ctrl_ok wx_ok geo_ok main_attr pp_att_person pp_att_hh pp_att_within
compress
save "$INTER/attrition_origin_person.dta", replace
count
di as result "Origin-person file rows: " r(N)
count if agri_origin == 1
di as result "Agriculture-origin rows: " r(N)

*------------------------------------------------------------------------------*
* B. Non-continuation by origin year
*------------------------------------------------------------------------------*
tempname hb
tempfile fb
postfile `hb' str12 smp_name int year_origin long n_obs double w_total double person_pct ///
    double hh_pct double within_pct using `fb', replace
foreach smp in agri all {
    local cnd "agri_origin == 1"
    if "`smp'" == "all" local cnd "inrange(agri_origin, 0, 1)"
    quietly levelsof year_origin if `cnd', local(yrs)
    foreach yy of local yrs {
        quietly count if year_origin == `yy' & `cnd'
        local n = r(N)
        quietly summarize Weight_origin if year_origin == `yy' & `cnd'
        local wt = r(sum)
        quietly summarize person_attrit [aweight = Weight_origin] if year_origin == `yy' & `cnd'
        local a = 100 * r(mean)
        quietly summarize hh_attrit [aweight = Weight_origin] if year_origin == `yy' & `cnd'
        local b = 100 * r(mean)
        quietly summarize within_loss [aweight = Weight_origin] if year_origin == `yy' & `cnd'
        local c = 100 * r(mean)
        post `hb' ("`smp'") (`yy') (`n') (`wt') (`a') (`b') (`c')
    }
    quietly count if `cnd'
    local n = r(N)
    quietly summarize Weight_origin if `cnd'
    local wt = r(sum)
    quietly summarize person_attrit [aweight = Weight_origin] if `cnd'
    local a = 100 * r(mean)
    quietly summarize hh_attrit [aweight = Weight_origin] if `cnd'
    local b = 100 * r(mean)
    quietly summarize within_loss [aweight = Weight_origin] if `cnd'
    local c = 100 * r(mean)
    post `hb' ("`smp'") (0) (`n') (`wt') (`a') (`b') (`c')
}
postclose `hb'
preserve
    use `fb', clear
    save "$RESULTS/attr_byyear.dta", replace
    export excel using "$XL42", sheet("By_year", modify) firstrow(variables)
restore

*------------------------------------------------------------------------------*
* C. Weather and non-continuation
*------------------------------------------------------------------------------*
global SAMPLE_LIST ""
gen byte smp_attagri = main_attr == 1 & agri_origin == 1 & Weight_origin > 0
gen byte smp_attall  = main_attr == 1 & Weight_origin > 0

open_results, file("$RESULTS/lpm_attr_weather_results.dta")
foreach m in 7 8 {
    foreach h in days35 heat35 {
        local nm "Days35"
        if "`h'" == "heat35" local nm "HeatDose35"
        local x "`h'_10_s0"
        local wv "`x' rain100_s0 rain100_sq_s0"
        run_lpm, family("AttrWeather_`nm'") panel("agri_origin") model(`m') outcome(att_person) ///
            wvars("`wv'") terms("`x'") rainterms("rain100_s0 rain100_sq_s0") sample(attagri)
        run_lpm, family("AttrWeather_`nm'") panel("agri_origin") model(`m') outcome(att_hh) ///
            wvars("`wv'") terms("`x'") rainterms("rain100_s0 rain100_sq_s0") sample(attagri)
        run_lpm, family("AttrWeather_`nm'") panel("agri_origin") model(`m') outcome(att_within) ///
            wvars("`wv'") terms("`x'") rainterms("rain100_s0 rain100_sq_s0") sample(attagri)
        run_lpm, family("AttrWeather_`nm'") panel("all_origin") model(`m') outcome(att_person) ///
            wvars("`wv'") terms("`x'") rainterms("rain100_s0 rain100_sq_s0") sample(attall)
    }
}
close_results
export_long, file("$XL42") sheet("Weather_long")

* Joint tests: does the heat effect on non-continuation differ by characteristic? (M7, agriculture origin)
get_spec 7
local absorb "`r(absorb)'"
gen byte age_grp = 1 + (age_origin >= 30) + (age_origin >= 45)
tempname hh2
tempfile fh2
postfile `hh2' str12 exposure str24 moderator long n_used double f_stat double pvalue using `fh2', replace
foreach h in days35 heat35 {
    local nm "Days35"
    if "`h'" == "heat35" local nm "HeatDose35"
    local x "`h'_10_s0"
    foreach mod in sex_origin urban_origin marital_origin age_grp {
        quietly reghdfe pp_att_person c.`x'##i.`mod' rain100_s0 rain100_sq_s0 c.age_origin c.age2_origin ///
            i.sex_origin i.marital_origin i.urban_origin if smp_attagri == 1 [pweight = Weight_origin], ///
            absorb(`absorb') vce(cluster mix_id)
        quietly testparm c.`x'#i.`mod'
        post `hh2' ("`nm'") ("`mod'") (e(N)) (r(F)) (r(p))
    }
}
postclose `hh2'
preserve
    use `fh2', clear
    save "$RESULTS/attr_het_tests.dta", replace
    export excel using "$XL42", sheet("Het_tests", modify) firstrow(variables)
restore
drop age_grp

*------------------------------------------------------------------------------*
* D. Continuation propensity and stabilised weights (agriculture origin)
*------------------------------------------------------------------------------*
keep if smp_attagri == 1
gen byte prop_cand = !missing(person_return, Weight_origin)
quietly count if prop_cand == 1
local NCAND = r(N)
quietly summarize person_return [aweight = Weight_origin] if prop_cand == 1
local RATE_ALL = 100 * r(mean)
di as result "Propensity candidates: `NCAND', weighted continuation rate: " %6.2f `RATE_ALL'

tempname hp hw hl
tempfile fp fw fl
postfile `hp' str12 exposure long candidate_n long model_n long continuer_n long clusters ///
    double cont_rate double heat_b double heat_se double heat_p double pseudo_r2 str8 method using `fp', replace
postfile `hw' str12 exposure str40 object long n double mean double sd double min double p1 double p5 ///
    double p50 double p95 double p99 double max double n_lt_005 double n_lt_010 double n_gt_099 ///
    double n_gt_2 double n_gt_5 double n_gt_10 double kish_ess using `fw', replace
postfile `hl' str12 exposure str24 covariate str40 category double target_mean double pre_mean ///
    double ipw_mean double target_sd double smd_pre double smd_ipw using `fl', replace

local fe "i.mix_id i.province_year i.season_origin i.pair_id"
local pctl "rain100_s0 rain100_sq_s0 age_origin age2_origin i.sex_origin i.marital_origin i.urban_origin"

foreach h in days35 heat35 {
    local nm "Days35"
    if "`h'" == "heat35" local nm "HeatDose35"
    local x "`h'_10_s0"
    capture drop phat_`h' psamp_`h' sw_`h' swtr_`h' finalw_`h'
    local method "$PROP_METHOD"
    if "`method'" == "logit" {
        capture quietly logit person_return `x' `pctl' `fe' [pweight = Weight_origin] if prop_cand == 1, ///
            vce(cluster mix_id) nolog iterate(100)
        if _rc {
            di as error "Logit failed for `nm' (rc = " _rc "). Falling back to the linear probability model."
            local method "lpm"
        }
    }
    if "`method'" == "logit" {
        gen byte psamp_`h' = e(sample)
        local b = _b[`x']
        local se = _se[`x']
        local p = 2 * normal(-abs(`b' / `se'))
        local ncl = e(N_clust)
        local pr2 = e(r2_p)
        predict double phat_`h' if psamp_`h', pr
    }
    else {
        quietly reghdfe person_return `x' rain100_s0 rain100_sq_s0 c.age_origin c.age2_origin i.sex_origin ///
            i.marital_origin i.urban_origin if prop_cand == 1 [pweight = Weight_origin], ///
            absorb(mix_id province_year season_origin pair_id) vce(cluster mix_id) resid
        gen byte psamp_`h' = e(sample)
        local b = _b[`x']
        local se = _se[`x']
        local p = 2 * ttail(e(df_r), abs(`b' / `se'))
        local ncl = e(N_clust)
        local pr2 = e(r2)
        predict double phat_`h' if psamp_`h', xbd
        replace phat_`h' = min(max(phat_`h', 0.01), 0.99) if psamp_`h' == 1
    }
    quietly count if psamp_`h' == 1
    local nmod = r(N)
    quietly count if psamp_`h' == 1 & person_return == 1
    local ncont = r(N)
    quietly summarize person_return [aweight = Weight_origin] if psamp_`h' == 1
    local pbar = r(mean)
    post `hp' ("`nm'") (`NCAND') (`nmod') (`ncont') (`ncl') (100 * `pbar') (`b') (`se') (`p') (`pr2') ("`method'")
    di as result "`nm': model N = `nmod', continuers = `ncont', heat coefficient = " %9.5f `b' " (se " %8.5f `se' ")"

    gen double sw_`h' = `pbar' / phat_`h' if psamp_`h' == 1 & person_return == 1 & phat_`h' > 0 & phat_`h' < 1
    quietly summarize sw_`h' if psamp_`h' == 1 & person_return == 1, detail
    local p1 = r(p1)
    local p99 = r(p99)
    gen double swtr_`h' = sw_`h'
    replace swtr_`h' = `p1'  if swtr_`h' < `p1'  & !missing(swtr_`h')
    replace swtr_`h' = `p99' if swtr_`h' > `p99' & !missing(swtr_`h')
    gen double finalw_`h' = Weight_origin * sw_`h'

    * Distribution diagnostics
    quietly count if psamp_`h' == 1 & phat_`h' < .05
    local a1 = r(N)
    quietly count if psamp_`h' == 1 & phat_`h' < .10
    local a2 = r(N)
    quietly count if psamp_`h' == 1 & phat_`h' > .99
    local a3 = r(N)
    quietly summarize phat_`h' if psamp_`h' == 1, detail
    post `hw' ("`nm'") ("Predicted continuation") (r(N)) (r(mean)) (r(sd)) (r(min)) (r(p1)) (r(p5)) ///
        (r(p50)) (r(p95)) (r(p99)) (r(max)) (`a1') (`a2') (`a3') (.) (.) (.) (.)
    foreach v in sw swtr {
        local lab "Stabilized IPW"
        if "`v'" == "swtr" local lab "Trimmed IPW p1-p99"
        quietly summarize `v'_`h' if psamp_`h' == 1 & person_return == 1, detail
        local mn = r(mean)
        local sdv = r(sd)
        local mi = r(min)
        local q1 = r(p1)
        local q5 = r(p5)
        local q50 = r(p50)
        local q95 = r(p95)
        local q99 = r(p99)
        local mx = r(max)
        local nn = r(N)
        quietly count if psamp_`h' == 1 & person_return == 1 & `v'_`h' > 2
        local g2 = r(N)
        quietly count if psamp_`h' == 1 & person_return == 1 & `v'_`h' > 5
        local g5 = r(N)
        quietly count if psamp_`h' == 1 & person_return == 1 & `v'_`h' > 10
        local g10 = r(N)
        quietly kish_ess `v'_`h' if psamp_`h' == 1 & person_return == 1
        post `hw' ("`nm'") ("`lab'") (`nn') (`mn') (`sdv') (`mi') (`q1') (`q5') (`q50') (`q95') (`q99') (`mx') ///
            (.) (.) (.) (`g2') (`g5') (`g10') (r(ess))
    }

    * Balance: target = all modelled workers (survey weight); pre = continuers (survey weight);
    * post = continuers (survey weight x stabilised IPW)
    foreach cv in `x' rain100_s0 age_origin {
        local clab "`cv'"
        if "`cv'" == "`x'" local clab "`nm'"
        if "`cv'" == "rain100_s0" local clab "Rainfall /100"
        if "`cv'" == "age_origin" local clab "Age"
        quietly summarize `cv' [aweight = Weight_origin] if psamp_`h' == 1
        local mt = r(mean)
        local st = r(sd)
        quietly summarize `cv' [aweight = Weight_origin] if psamp_`h' == 1 & person_return == 1
        local mpre = r(mean)
        quietly summarize `cv' [aweight = finalw_`h'] if psamp_`h' == 1 & person_return == 1
        local mpost = r(mean)
        post `hl' ("`nm'") ("`clab'") ("Continuous") (`mt') (`mpre') (`mpost') (`st') ///
            (100 * (`mpre' - `mt') / `st') (100 * (`mpost' - `mt') / `st')
    }
    foreach cv in sex_origin marital_origin urban_origin {
        local clab "Sex"
        if "`cv'" == "marital_origin" local clab "Marital status"
        if "`cv'" == "urban_origin" local clab "Rural origin"
        quietly levelsof `cv' if psamp_`h' == 1, local(levs)
        local vl : value label `cv'
        foreach lv of local levs {
            tempvar ind
            quietly gen byte `ind' = (`cv' == `lv') if psamp_`h' == 1
            local cat "`lv'"
            if "`vl'" != "" local cat : label `vl' `lv'
            quietly summarize `ind' [aweight = Weight_origin] if psamp_`h' == 1
            local mt = r(mean)
            local st = r(sd)
            quietly summarize `ind' [aweight = Weight_origin] if psamp_`h' == 1 & person_return == 1
            local mpre = r(mean)
            quietly summarize `ind' [aweight = finalw_`h'] if psamp_`h' == 1 & person_return == 1
            local mpost = r(mean)
            local s1 = .
            local s2 = .
            if `st' > 0 {
                local s1 = 100 * (`mpre' - `mt') / `st'
                local s2 = 100 * (`mpost' - `mt') / `st'
            }
            post `hl' ("`nm'") ("`clab'") ("`cat'") (`mt') (`mpre') (`mpost') (`st') (`s1') (`s2')
            drop `ind'
        }
    }
}
postclose `hp'
postclose `hw'
postclose `hl'

preserve
    use `fp', clear
    save "$RESULTS/attr_propensity.dta", replace
    export excel using "$XL42", sheet("Propensity", modify) firstrow(variables)
    use `fw', clear
    save "$RESULTS/attr_weightdiag.dta", replace
    export excel using "$XL42", sheet("Weights", modify) firstrow(variables)
    use `fl', clear
    save "$RESULTS/attr_balance.dta", replace
    export excel using "$XL42", sheet("Balance", modify) firstrow(variables)
restore

keep pid year_origin season_origin pair_id sw_days35 swtr_days35 sw_heat35 swtr_heat35
keep if !missing(sw_days35) | !missing(sw_heat35)
save "$INTER/attrition_ipw_weights.dta", replace

*------------------------------------------------------------------------------*
* E. Headline M7 under four weightings
*------------------------------------------------------------------------------*
prep_lpm_data
local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain')
make_sample, name(heat35) vars(heat35_10_s0 `rain')
merge m:1 pid year_origin season_origin pair_id using "$INTER/attrition_ipw_weights.dta", keep(master match) gen(_m_w)
gen byte smp_days35_ipw = smp_days35 == 1 & !missing(sw_days35)
gen byte smp_heat35_ipw = smp_heat35 == 1 & !missing(sw_heat35)

tempname hf
tempfile ff
postfile `hf' str12 exposure str40 stage long n_obs double w_total using `ff', replace
foreach h in days35 heat35 {
    local nm "Days35"
    if "`h'" == "heat35" local nm "HeatDose35"
    quietly count if smp_`h' == 1
    local n1 = r(N)
    quietly summarize Weight_origin if smp_`h' == 1
    post `hf' ("`nm'") ("Headline sample") (`n1') (r(sum))
    quietly count if smp_`h'_ipw == 1
    local n2 = r(N)
    quietly summarize Weight_origin if smp_`h'_ipw == 1
    post `hf' ("`nm'") ("Common IPW sample") (`n2') (r(sum))
}
postclose `hf'
preserve
    use `ff', clear
    save "$RESULTS/attr_ipw_flow.dta", replace
    export excel using "$XL42", sheet("IPW_flow", modify) firstrow(variables)
restore

gen double W0 = Weight_origin
open_results, file("$RESULTS/lpm_ipw_results.dta")
foreach y of global OUTCOMES {
    foreach h in days35 heat35 {
        local nm "Days35"
        if "`h'" == "heat35" local nm "HeatDose35"
        local x "`h'_10_s0"
        run_lpm, family("IPW_`nm'") panel("1_baseline") model(7) outcome(`y') wvars("`x' `rain'") ///
            terms("`x'") rainterms("`rain'") sample(`h')
        run_lpm, family("IPW_`nm'") panel("2_common_survey") model(7) outcome(`y') wvars("`x' `rain'") ///
            terms("`x'") rainterms("`rain'") sample(`h'_ipw)
    }
}
foreach h in days35 heat35 {
    replace Weight_origin = W0 * sw_`h' if smp_`h'_ipw == 1
    local nm "Days35"
    if "`h'" == "heat35" local nm "HeatDose35"
    local x "`h'_10_s0"
    foreach y of global OUTCOMES {
        run_lpm, family("IPW_`nm'") panel("3_ipw") model(7) outcome(`y') wvars("`x' `rain'") ///
            terms("`x'") rainterms("`rain'") sample(`h'_ipw)
    }
    replace Weight_origin = W0 * swtr_`h' if smp_`h'_ipw == 1
    foreach y of global OUTCOMES {
        run_lpm, family("IPW_`nm'") panel("4_ipw_trim") model(7) outcome(`y') wvars("`x' `rain'") ///
            terms("`x'") rainterms("`rain'") sample(`h'_ipw)
    }
    replace Weight_origin = W0
}
close_results
export_long, file("$XL42") sheet("IPW_long")

guide_sheet, file("$XL42") title("Attrition and continuation (42)") lines("By_year: weighted non-continuation (person), household non-return and within-household loss by origin year; smp_name agri = agriculture origin, all = every origin state; year 0 = pooled. Rates in percent.|Weather_long: heat measure (tens) on non-continuation indicators (0/100), models M7 and M8, panels agri_origin and all_origin; outcomes att_person, att_hh, att_within.|Het_tests: joint F test that the Days35 or HeatDose35 effect on person non-continuation does not differ by sex, rural origin, marital status or age group (agriculture origin, M7).|Propensity: continuation model for agriculture-origin workers (survey-weighted logit with county, province-by-year, season and pair fixed effects) with the heat coefficient, the share continuing, and the method actually used.|Weights: distribution of the predicted continuation probability and of the stabilised and trimmed weights, counts of large weights, Kish effective sample size.|Balance: weighted means of the modelled workers (target), of the continuers before and after weighting, and standardised mean differences in percent of the target standard deviation.|IPW_flow, IPW_long: headline M7 in four weightings: 1 baseline; 2 survey weight on the common IPW sample; 3 survey weight x stabilised IPW; 4 survey weight x trimmed IPW. Columns 2 to 4 use the same observations.|Notes: selection on observables only; the weights cannot correct selection on unobservables.")

di as result "42 done."
log close step
