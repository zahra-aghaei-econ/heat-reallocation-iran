*==============================================================================*
* 46_county_shares.do
* County-level aggregate model (complement to the worker-level transition model).
*
* Outcome: weighted share (0-100) of the working-age population (age 15 or more) of a county in
* each of the five labor states (1 agriculture, 2 industry, 3 services, 4 unemployed,
* 5 inactive), from the LFS rows of all census turns. Cells with no state (employed without a
* sector code when UNCLASSIFIED_AS_SERVICES = 0) are left out of the denominator.
*
*   Annual model        share of county c in year t on weather of year t (Days35 and HeatDose35
*                       summed over the four seasons of the year; rain summed over the year;
*                       needs all four seasons observed).
*   Seasonal t+1 model  share of county c in season s of year t+1 on weather of the SAME season s
*                       in year t (the county analogue of the worker-level model).
*
* Estimated with analytic weights equal to the weighted population of the cell and standard
* errors clustered by county. Fixed-effect ladder: none, county, county + year(+season),
* county + province-by-year (+season) [baseline], + county trend, province-by-year-by-season.
*
* Blocks
*   A  Ladder for the agricultural share (annual and seasonal, Days35 and HeatDose35)
*   B  All five shares, annual and seasonal, baseline / county trend / saturated
*   C  Sample windows (annual) and minimum cell size (seasonal)
*   D  Controlled comparison on identical samples: seasonal against annual-summed Days35,
*      individual exit from agriculture and county agricultural and services shares
*
* Output: output/<RUN_NAME>/tables/46_county_shares.xlsx
*         output/<RUN_NAME>/results/cty_results.dta, cty_sample.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/46_county_shares.log", text replace name(step)

global XL46 "$TABLES/46_county_shares.xlsx"

*------------------------------------------------------------------------------*
* Helper: one regression, one row in the results file
*------------------------------------------------------------------------------*
capture program drop cty_run
program define cty_run
    version 17
    syntax , FAMily(string) SPEC(string) OUTcome(string) X(string) RAINv(string) ABSorb(string) ///
        WGT(string) [COND(string) NOTE(string)]
    if `"`cond'"' == "" local cond "1 == 1"
    local absopt "absorb(`absorb')"
    if "`absorb'" == "none" local absopt "noabsorb"
    capture quietly reghdfe `outcome' `x' `rainv' if `cond' [aweight = `wgt'], `absopt' vce(cluster mix_id)
    if _rc {
        post $CTY_H ("`family'") ("`spec'") ("`outcome'") ("`x'") (.) (.) (.) (.) (.) ("`note'")
        di as error "  failed: `family' | `spec' | `outcome' (rc = " _rc ")"
        exit
    }
    local b = _b[`x']
    local s = _se[`x']
    post $CTY_H ("`family'") ("`spec'") ("`outcome'") ("`x'") (`b') (`s') ///
        (`=2*ttail(e(df_r), abs(`b'/`s'))') (e(N)) (e(N_clust)) ("`note'")
    di as text "  `family' | `spec' | `outcome': b = " %9.4f `b' "  se = " %8.4f `s' "  N = " e(N)
end

*------------------------------------------------------------------------------*
* 1. County-season and county-year shares
*------------------------------------------------------------------------------*
use mix4 province85 year season job job_alt weight age using "$INTER/lfs_individual.dta", clear
keep if age >= 15 & !missing(age) & weight > 0 & !missing(weight) & inrange(season, 1, 4)
drop if mix4 == "" | missing(real(mix4))
gen byte state = job
if "$UNCLASSIFIED_AS_SERVICES" == "1" replace state = job_alt
drop if missing(state)
gen long one = 1
forvalues k = 1/5 {
    gen double wk`k' = weight * (state == `k')
}
rename weight w_all
tempfile seas ann
preserve
    collapse (sum) n_raw = one W = w_all wk1 wk2 wk3 wk4 wk5 (firstnm) province85, by(mix4 year season)
    save `seas'
restore
collapse (sum) n_raw = one W = w_all wk1 wk2 wk3 wk4 wk5 (firstnm) province85, by(mix4 year)
save `ann'

*------------------------------------------------------------------------------*
* 2. Weather: seasonal and annual
*------------------------------------------------------------------------------*
use mix4 year season days35_10_s0 heat35_10_s0 rain100_s0 rain100_sq_s0 using "$INTER/weather_county_season.dta", clear
tempfile wseas wann
rename year year_origin
save `wseas'
gen byte ok = !missing(days35_10_s0, heat35_10_s0, rain100_s0)
collapse (sum) days35_ann = days35_10_s0 heat35_ann = heat35_10_s0 rain100_ann = rain100_s0 n_ok = ok, by(mix4 year_origin)
replace days35_ann = . if n_ok < 4
replace heat35_ann = . if n_ok < 4
replace rain100_ann = . if n_ok < 4
gen double rain100_sq_ann = rain100_ann^2
label var days35_ann "Days35 /10 summed over the four seasons of the year"
label var heat35_ann "HeatDose35 /10 summed over the four seasons of the year"
label var rain100_ann "Rain /100 summed over the year"
drop n_ok
save `wann'

*------------------------------------------------------------------------------*
* 3. Estimation panels
*------------------------------------------------------------------------------*
* Seasonal t+1 panel: share in (county, season, year t+1) with weather of (county, season, year t)
use `seas', clear
rename year year_dest
gen int year_origin = year_dest - 1
merge m:1 mix4 year_origin season using `wseas', keep(match) nogen
merge m:1 mix4 year_origin using `wann', keep(master match) nogen
forvalues k = 1/5 {
    gen double sh`k' = 100 * wk`k' / W
}
egen long mix_id = group(mix4)
gen int prov = floor(real(mix4) / 100)
egen long province_year = group(prov year_origin)
egen long province_year_season = group(prov year_origin season)
gen double year_trend = year_origin - 1391
rename season season_origin
gen double popw = W
keep if inrange(year_origin, $FIRST_ORIGIN_YEAR, $LAST_ORIGIN_YEAR)
gen byte ok_s = !missing(days35_10_s0, heat35_10_s0, rain100_s0)
gen byte ok_a = !missing(days35_ann, heat35_ann, rain100_ann)
save "$INTER/county_panel_seasonal.dta", replace
quietly count if ok_s == 1
di as result "Seasonal county panel: " r(N) " cells"

* Annual panel
use `ann', clear
rename year year_origin
merge m:1 mix4 year_origin using `wann', keep(match) nogen
forvalues k = 1/5 {
    gen double sh`k' = 100 * wk`k' / W
}
egen long mix_id = group(mix4)
gen int prov = floor(real(mix4) / 100)
egen long province_year = group(prov year_origin)
gen double year_trend = year_origin - 1391
gen double popw = W
keep if inrange(year_origin, $FIRST_ORIGIN_YEAR, $LAST_ORIGIN_YEAR)
gen byte ok_a = !missing(days35_ann, heat35_ann, rain100_ann)
save "$INTER/county_panel_annual.dta", replace
quietly count if ok_a == 1
di as result "Annual county panel: " r(N) " cells"

*------------------------------------------------------------------------------*
* 4. Regressions
*------------------------------------------------------------------------------*
tempname hh
tempfile ff
postfile `hh' str24 family str24 spec str20 outcome str16 exposure double coef double se ///
    double pvalue double n_used double n_clusters str40 note using `ff', replace
global CTY_H "`hh'"

local ARAIN "rain100_ann rain100_sq_ann"
local SRAIN "rain100_s0 rain100_sq_s0"

* ---------- A and B: annual ----------
use "$INTER/county_panel_annual.dta", clear
foreach m in days35 heat35 {
    local nm "Days35"
    if "`m'" == "heat35" local nm "HeatDose35"
    local x "`m'_ann"
    * ladder, agricultural share
    cty_run, family("Annual_`nm'") spec("L1_none") outcome(sh1) x(`x') rainv(`ARAIN') absorb(none) wgt(popw) cond(ok_a == 1)
    cty_run, family("Annual_`nm'") spec("L2_county") outcome(sh1) x(`x') rainv(`ARAIN') absorb("mix_id") wgt(popw) cond(ok_a == 1)
    cty_run, family("Annual_`nm'") spec("L3_county_year") outcome(sh1) x(`x') rainv(`ARAIN') absorb("mix_id year_origin") wgt(popw) cond(ok_a == 1)
    * baseline, trend, all shares
    forvalues k = 1/5 {
        cty_run, family("Annual_`nm'") spec("L4_prov_year") outcome(sh`k') x(`x') rainv(`ARAIN') ///
            absorb("mix_id province_year") wgt(popw) cond(ok_a == 1)
        cty_run, family("Annual_`nm'") spec("L5_trend") outcome(sh`k') x(`x') rainv(`ARAIN') ///
            absorb("mix_id province_year mix_id#c.year_trend") wgt(popw) cond(ok_a == 1)
    }
    * C: sample windows (agricultural share, baseline)
    cty_run, family("Window_`nm'") spec("origin_to_1398") outcome(sh1) x(`x') rainv(`ARAIN') ///
        absorb("mix_id province_year") wgt(popw) cond(ok_a == 1 & year_origin <= 1398)
    cty_run, family("Window_`nm'") spec("full_period") outcome(sh1) x(`x') rainv(`ARAIN') ///
        absorb("mix_id province_year") wgt(popw) cond(ok_a == 1)
}

* ---------- A, B and C: seasonal t+1 ----------
use "$INTER/county_panel_seasonal.dta", clear
foreach m in days35 heat35 {
    local nm "Days35"
    if "`m'" == "heat35" local nm "HeatDose35"
    local x "`m'_10_s0"
    cty_run, family("Seasonal_`nm'") spec("L1_none") outcome(sh1) x(`x') rainv(`SRAIN') absorb(none) wgt(popw) cond(ok_s == 1)
    cty_run, family("Seasonal_`nm'") spec("L2_county") outcome(sh1) x(`x') rainv(`SRAIN') absorb("mix_id") wgt(popw) cond(ok_s == 1)
    cty_run, family("Seasonal_`nm'") spec("L3_county_year_season") outcome(sh1) x(`x') rainv(`SRAIN') ///
        absorb("mix_id year_origin season_origin") wgt(popw) cond(ok_s == 1)
    forvalues k = 1/5 {
        cty_run, family("Seasonal_`nm'") spec("L4_prov_year_season") outcome(sh`k') x(`x') rainv(`SRAIN') ///
            absorb("mix_id province_year season_origin") wgt(popw) cond(ok_s == 1)
        cty_run, family("Seasonal_`nm'") spec("L5_trend") outcome(sh`k') x(`x') rainv(`SRAIN') ///
            absorb("mix_id province_year season_origin mix_id#c.year_trend") wgt(popw) cond(ok_s == 1)
        cty_run, family("Seasonal_`nm'") spec("L6_prov_year_season_fe") outcome(sh`k') x(`x') rainv(`SRAIN') ///
            absorb("mix_id province_year_season") wgt(popw) cond(ok_s == 1)
    }
    foreach c in 30 50 100 {
        cty_run, family("CellSize_`nm'") spec("min_cell_`c'") outcome(sh1) x(`x') rainv(`SRAIN') ///
            absorb("mix_id province_year season_origin") wgt(popw) cond(ok_s == 1 & n_raw >= `c')
    }
    * D: controlled comparison, county level (same seasonal sample, annual-summed regressor)
    cty_run, family("Controlled_`nm'") spec("seasonal") outcome(sh1) x(`x') rainv(`SRAIN') ///
        absorb("mix_id province_year season_origin") wgt(popw) cond(ok_s == 1 & ok_a == 1)
    cty_run, family("Controlled_`nm'") spec("annual_summed") outcome(sh1) x(`m'_ann) rainv(`SRAIN') ///
        absorb("mix_id province_year season_origin") wgt(popw) cond(ok_s == 1 & ok_a == 1)
    cty_run, family("Controlled_`nm'") spec("seasonal") outcome(sh3) x(`x') rainv(`SRAIN') ///
        absorb("mix_id province_year season_origin") wgt(popw) cond(ok_s == 1 & ok_a == 1)
    cty_run, family("Controlled_`nm'") spec("annual_summed") outcome(sh3) x(`m'_ann) rainv(`SRAIN') ///
        absorb("mix_id province_year season_origin") wgt(popw) cond(ok_s == 1 & ok_a == 1)
}

* ---------- D: controlled comparison, individual level ----------
tempfile wann2
use `wann', clear
rename mix4 mix4_origin
save `wann2'
prep_lpm_data
merge m:1 mix4_origin year_origin using `wann2', keep(master match) nogen
local rain "rain100_s0 rain100_sq_s0"
get_spec 7
local ctrl   "`r(controls)'"
local absorb "`r(absorb)'"
foreach m in days35 heat35 {
    local nm "Days35"
    if "`m'" == "heat35" local nm "HeatDose35"
    make_sample, name(c`m') vars(`m'_10_s0 `m'_ann `rain')
    foreach xx in `m'_10_s0 `m'_ann {
        local tag "seasonal"
        if "`xx'" == "`m'_ann" local tag "annual_summed"
        quietly reghdfe pp_exit_agri `xx' `rain' `ctrl' if smp_c`m' == 1 [pweight = Weight_origin], ///
            absorb(`absorb') vce(cluster mix_id)
        local b = _b[`xx']
        local s = _se[`xx']
        post `hh' ("Controlled_`nm'") ("`tag'") ("exit_agri_indiv") ("`xx'") (`b') (`s') ///
            (`=2*ttail(e(df_r), abs(`b'/`s'))') (e(N)) (e(N_clust)) ("individual level")
        di as text "  individual | `nm' | `tag': b = " %9.4f `b' "  se = " %8.4f `s' "  N = " e(N)
    }
}
postclose `hh'

use `ff', clear
save "$RESULTS/cty_results.dta", replace

guide_sheet, file("$XL46") title("County-level aggregate model (46)") lines("Results: one row per family, specification, outcome and exposure. Outcomes sh1 to sh5 are county shares (0-100) of agriculture, industry, services, unemployment and inactivity among people aged 15 or more; exit_agri_indiv is the worker-level exit from agriculture on the identical sample.|Annual_*: share in year t on weather summed over the four seasons of year t (needs all four seasons observed). Seasonal_*: share in season s of year t+1 on weather of season s in year t. Window_*: annual baseline over two origin-year windows. CellSize_*: seasonal baseline excluding county-season cells with fewer than 30, 50 or 100 raw LFS rows. Controlled_*: seasonal regressor against the annual-summed regressor on the same observations, at county and at worker level.|Specifications L1 none, L2 county, L3 county + year (+ season), L4 county + province-by-year (+ season) = baseline, L5 baseline + county trend, L6 county + province-by-year-by-season.|Notes: analytic weights = weighted population of the cell; standard errors clustered by county; rain and rain squared always included.")
export excel using "$XL46", sheet("Results", modify) firstrow(variables)

di as result "46 done."
log close step
