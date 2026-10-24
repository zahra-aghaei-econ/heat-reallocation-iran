*==============================================================================*
* 26_lpm_timing_rain_fitted.do
* Three robustness exercises for the headline model (agriculture-origin sample, M7):
*   A  Exposure timing and a lower threshold. Outcome: all seven outcomes.
*        origin_ref   Days35 / HeatDose35 in the origin season (the headline)
*        thr32        Days32 / HeatDose32 in the origin season (Tmax of 32C or more)
*        preceding    Days35 / HeatDose35 in the season before the origin season
*        destination  Days35 / HeatDose35 in the same season one year later (destination season)
*      The weather of other windows is built here from the daily and county-season files;
*      it follows the same rules as step 02 (sum of days, divided by ten, missing if
*      fewer than 60 percent of the days of the season are observed).
*   B  Rainfall controls: no rain (R0), linear rain (R1), linear and squared rain (R2 = headline),
*      for models M7 and M8 (county trend), outcomes exit, non-employment exit, productive exit.
*      With R2 the joint Wald test that both rain terms are zero is added (row rain_block_wald).
*   C  Share of fitted values outside [0, 100] (M7, Days35), seven outcomes. The fitted value
*      is the full linear prediction including the absorbed fixed effects.
*
* Output: output/<RUN_NAME>/tables/26_lpm_timing_rain_fitted.xlsx
*         output/<RUN_NAME>/results/lpm_timing_results.dta, lpm_rain_results.dta,
*                                   fitted_range.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/26_lpm_timing_rain_fitted.log", text replace name(step)

global XL26 "$TABLES/26_lpm_timing_rain_fitted.xlsx"

prep_lpm_data

*------------------------------------------------------------------------------*
* Weather of other windows
*------------------------------------------------------------------------------*
tempfile wk
preserve
    * Days32 and HeatDose32 from the daily file
    use mix4 year season tmax_day valid_tmax_day using "$INTER/weather_daily_base_county.dta", clear
    gen byte   x_d32 = (tmax_day >= 32) if valid_tmax_day
    gen double x_h32 = max(tmax_day - 32, 0) if valid_tmax_day
    collapse (sum) raw_d32 = x_d32 raw_h32 = x_h32, by(mix4 year season)
    tempfile w32
    save `w32'

    use mix4 year season days35_10_s0 heat35_10_s0 using "$INTER/weather_county_season.dta", clear
    merge 1:1 mix4 year season using `w32', keep(master match) nogen
    gen double d32 = raw_d32 / 10 if !missing(days35_10_s0)
    gen double h32 = raw_h32 / 10 if !missing(days35_10_s0)
    rename days35_10_s0 d35
    rename heat35_10_s0 h35
    rename mix4 mix4_origin
    gen long sidx = 4 * year + season
    keep mix4_origin sidx d32 h32 d35 h35
    isid mix4_origin sidx
    save `wk'
restore

gen long sidx = 4 * year_origin + season_origin
merge m:1 mix4_origin sidx using `wk', keepusing(d32 h32) keep(master match) nogen
rename d32 days32_10_s0
rename h32 heat32_10_s0
label var days32_10_s0 "Days with Tmax >= 32C in the season, /10"
label var heat32_10_s0 "Sum of (Tmax - 32C) over days with Tmax >= 32C, /10"

gen long sidx_prev = 4 * year_origin + season_origin - 1
gen long sidx_dest = 4 * (year_origin + 1) + season_origin
drop sidx
rename sidx_prev sidx   // now the index of the season before the origin season
merge m:1 mix4_origin sidx using `wk', keepusing(d35 h35) keep(master match) nogen
rename d35 days35_prev_10
rename h35 heat35_prev_10
drop sidx
gen long sidx = sidx_dest
merge m:1 mix4_origin sidx using `wk', keepusing(d35 h35) keep(master match) nogen
rename d35 days35_dest_10
rename h35 heat35_dest_10
drop sidx sidx_dest
label var days35_prev_10 "Days35 /10 in the season before the origin season"
label var heat35_prev_10 "HeatDose35 /10 in the season before the origin season"
label var days35_dest_10 "Days35 /10 in the destination season (same season, one year later)"
label var heat35_dest_10 "HeatDose35 /10 in the destination season (same season, one year later)"

quietly summarize days35_10_s0
di as text "Check: mean Days35 origin season = " %6.3f r(mean)
quietly summarize days35_prev_10
di as text "Check: mean Days35 preceding season = " %6.3f r(mean) "   N = " r(N)
quietly summarize days35_dest_10
di as text "Check: mean Days35 destination season = " %6.3f r(mean) "   N = " r(N)

*------------------------------------------------------------------------------*
* Samples
*------------------------------------------------------------------------------*
local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain')
make_sample, name(heat35) vars(heat35_10_s0 `rain')
make_sample, name(days32) vars(days32_10_s0 `rain')
make_sample, name(heat32) vars(heat32_10_s0 `rain')
make_sample, name(daysprev) vars(days35_prev_10 `rain')
make_sample, name(heatprev) vars(heat35_prev_10 `rain')
make_sample, name(daysdest) vars(days35_dest_10 `rain')
make_sample, name(heatdest) vars(heat35_dest_10 `rain')

*------------------------------------------------------------------------------*
* A. Timing and threshold
*------------------------------------------------------------------------------*
open_results, file("$RESULTS/lpm_timing_results.dta")
foreach y of global OUTCOMES {
    run_lpm, family("Timing_Days") panel("1_origin_Days35") model(7) outcome(`y') ///
        wvars("days35_10_s0 `rain'") terms("days35_10_s0") rainterms("`rain'") sample(days35)
    run_lpm, family("Timing_Days") panel("2_origin_Days32") model(7) outcome(`y') ///
        wvars("days32_10_s0 `rain'") terms("days32_10_s0") rainterms("`rain'") sample(days32)
    run_lpm, family("Timing_Days") panel("3_preceding_Days35") model(7) outcome(`y') ///
        wvars("days35_prev_10 `rain'") terms("days35_prev_10") rainterms("`rain'") sample(daysprev)
    run_lpm, family("Timing_Days") panel("4_destination_Days35") model(7) outcome(`y') ///
        wvars("days35_dest_10 `rain'") terms("days35_dest_10") rainterms("`rain'") sample(daysdest)

    run_lpm, family("Timing_Heat") panel("1_origin_HeatDose35") model(7) outcome(`y') ///
        wvars("heat35_10_s0 `rain'") terms("heat35_10_s0") rainterms("`rain'") sample(heat35)
    run_lpm, family("Timing_Heat") panel("2_origin_HeatDose32") model(7) outcome(`y') ///
        wvars("heat32_10_s0 `rain'") terms("heat32_10_s0") rainterms("`rain'") sample(heat32)
    run_lpm, family("Timing_Heat") panel("3_preceding_HeatDose35") model(7) outcome(`y') ///
        wvars("heat35_prev_10 `rain'") terms("heat35_prev_10") rainterms("`rain'") sample(heatprev)
    run_lpm, family("Timing_Heat") panel("4_destination_HeatDose35") model(7) outcome(`y') ///
        wvars("heat35_dest_10 `rain'") terms("heat35_dest_10") rainterms("`rain'") sample(heatdest)
}
close_results
export_long, file("$XL26") sheet("Timing_long")

*------------------------------------------------------------------------------*
* B. Rainfall controls
*------------------------------------------------------------------------------*
open_results, file("$RESULTS/lpm_rain_results.dta")
foreach m in 7 8 {
    foreach y in exit_agri productive_exit distress_exit {
        foreach h in days35 heat35 {
            local nm "Days35"
            if "`h'" == "heat35" local nm "HeatDose35"
            local x "`h'_10_s0"
            run_lpm, family("Rain_`nm'") panel("R0_no_rain") model(`m') outcome(`y') ///
                wvars("`x'") terms("`x'") sample(`h')
            run_lpm, family("Rain_`nm'") panel("R1_linear_rain") model(`m') outcome(`y') ///
                wvars("`x' rain100_s0") terms("`x'") rainterms("rain100_s0") sample(`h')
            run_lpm, family("Rain_`nm'") panel("R2_quadratic_rain") model(`m') outcome(`y') ///
                wvars("`x' `rain'") terms("`x'") rainterms("`rain'") sample(`h') ///
                jtest("rain100_s0 rain100_sq_s0") jname("rain_block_wald") ///
                jlabel("Joint test that both rain terms are zero (F)")
        }
    }
}
close_results
export_long, file("$XL26") sheet("Rain_long")

*------------------------------------------------------------------------------*
* C. Fitted values outside [0, 100] (M7, Days35)
*------------------------------------------------------------------------------*
get_spec 7
local ctrl   "`r(controls)'"
local absorb "`r(absorb)'"
tempname hf
tempfile ff
postfile `hf' str24 outcome long n_obs long n_below long n_above double share_below ///
    double share_above double share_outside double wshare_outside using `ff', replace
foreach y of global OUTCOMES {
    quietly reghdfe pp_`y' days35_10_s0 `rain' `ctrl' if smp_days35 == 1 ///
        [pweight = Weight_origin], absorb(`absorb') vce(cluster mix_id) resid
    tempvar fit esample
    quietly predict double `fit', xbd
    quietly gen byte `esample' = e(sample)
    quietly count if `esample' == 1
    local n = r(N)
    quietly count if `esample' == 1 & `fit' < 0
    local nb = r(N)
    quietly count if `esample' == 1 & `fit' > 100 & !missing(`fit')
    local na = r(N)
    quietly gen byte __out = (`fit' < 0 | `fit' > 100) if `esample' == 1 & !missing(`fit')
    quietly summarize __out [aweight = Weight_origin] if `esample' == 1
    local wo = 100 * r(mean)
    drop __out `fit' `esample'
    post `hf' ("`y'") (`n') (`nb') (`na') (100 * `nb' / `n') (100 * `na' / `n') ///
        (100 * (`nb' + `na') / `n') (`wo')
    di as result "`y': below 0 = `nb', above 100 = `na', of `n'"
}
postclose `hf'
preserve
    use `ff', clear
    save "$RESULTS/fitted_range.dta", replace
restore

*------------------------------------------------------------------------------*
* Excel
*------------------------------------------------------------------------------*
guide_sheet, file("$XL26") title("Timing, rainfall controls and fitted range (26)") lines("Timing_long: family Timing_Days / Timing_Heat; panel 1 = origin season (headline), 2 = threshold 32C, 3 = season before the origin season, 4 = destination season (same season one year later). Model M7, all seven outcomes. Weather of other windows is built in this script from the daily and county-season files.|Rain_long: family Rain_Days35 / Rain_HeatDose35; panels R0 (no rain), R1 (linear rain), R2 (linear and squared rain, the headline); models M7 and M8 (M8 = M7 + county-specific trend). Row rain_block_wald (kind test) is the F test that both rain terms are zero in R2.|Fitted_range: share of fitted values from M7 (Days35, headline sample) below 0 or above 100, with the absorbed fixed effects included, unweighted counts; the last column is the weighted share outside.|Notes: Outcomes are in percentage points. Standard errors are clustered by county; weights Weight_origin.")
preserve
    use "$RESULTS/fitted_range.dta", clear
    export excel using "$XL26", sheet("Fitted_range", modify) firstrow(variables)
restore

di as result "26 done."
log close step
