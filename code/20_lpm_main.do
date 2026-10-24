*==============================================================================*
* 20_lpm_main.do
* Main linear probability models (LPM): effect of heat in the origin season on
* where agriculture workers are one year later.
*
* This is the first version. It runs the headline model (M7) for the two main
* heat measures and all seven outcomes. The other models of the thesis (ladder
* M1-M8, other weather families) will be added to this file step by step.
*
* Headline model (M7):
*   outcome (in percentage points) = heat + rain + rain^2 + age + age^2 + sex
*       + marital status + urban + county FE + province-by-year FE + season FE
*       [+ pair FE, only in run 1]
*   weights: Weight_origin;  standard errors clustered by county
*
* Output: output/<RUN_NAME>/tables/20_lpm_main.xlsx
*         output/<RUN_NAME>/results/lpm_main_results.dta   (one row per regression)
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/20_lpm_main.log", text replace name(step)

global XL20 "$TABLES/20_lpm_main.xlsx"

*------------------------------------------------------------------------------*
* 1. Data and sample
*------------------------------------------------------------------------------*
load_model_data

* Controls: age, age squared, sex, marital status, urban
global CTRL "c.age_origin c.age2_origin i.sex_origin i.marital_origin i.urban_origin"

* Base sample: agriculture at origin, known destination, valid weight and IDs, chosen years
gen byte flag_base = (job_origin == 1) & inrange(job_dest, 1, 5) ///
    & (Weight_origin > 0) & !missing(Weight_origin) ///
    & !missing(mix_id) & !missing(province_year) & !missing(pair_id) ///
    & inrange(season_origin, 1, 4) & $YEARS_IF

* All controls must be observed
gen byte flag_ctrl_ok = !missing(age_origin, age2_origin, sex_origin, marital_origin, urban_origin)

* One sample for each heat measure: matched weather with at least 60 percent valid days
gen byte smp_days35 = flag_base & weather_common_sample == 1 & flag_ctrl_ok ///
    & !missing(days35_10_s0, rain100_s0, rain100_sq_s0)
gen byte smp_heat35 = flag_base & weather_common_sample == 1 & flag_ctrl_ok ///
    & !missing(heat35_10_s0, rain100_s0, rain100_sq_s0)

keep if flag_base
count
local n_base = r(N)
count if smp_days35 == 1
local n_days35 = r(N)
count if smp_heat35 == 1
local n_heat35 = r(N)
di as result "Base sample: `n_base'   Days35 sample: `n_days35'   HeatDose35 sample: `n_heat35'"

* Weighted share of workers who leave agriculture (the baseline rate)
summarize exit_agri [aw = Weight_origin] if smp_days35 == 1
local base_exit = 100 * r(mean)

* Outcomes in percentage points
global OUTCOMES exit_agri productive_exit distress_exit dest2 dest3 dest4 dest5
foreach y of global OUTCOMES {
    gen double pp_`y' = 100 * `y'
}

*------------------------------------------------------------------------------*
* 2. Regressions
*------------------------------------------------------------------------------*
capture postclose res
postfile res str20 run str12 measure str20 outcome double coef se pvalue ci_lo ci_hi ///
    long n_used n_clusters double r2 using "$RESULTS/lpm_main_results.dta", replace

foreach m in days35 heat35 {
    local w "`m'_10_s0"
    foreach y of global OUTCOMES {
        reghdfe pp_`y' `w' rain100_s0 rain100_sq_s0 $CTRL ///
            if smp_`m' == 1 [pweight = Weight_origin], ///
            absorb($FE_LIST) vce(cluster mix_id)
        local b  = _b[`w']
        local se = _se[`w']
        local p  = 2 * ttail(e(df_r), abs(`b' / `se'))
        local lo = `b' - invttail(e(df_r), 0.025) * `se'
        local hi = `b' + invttail(e(df_r), 0.025) * `se'
        post res ("$RUN_NAME") ("`m'") ("`y'") (`b') (`se') (`p') (`lo') (`hi') ///
            (e(N)) (e(N_clust)) (e(r2))
    }
}
postclose res

*------------------------------------------------------------------------------*
* 3. Excel table
*------------------------------------------------------------------------------*
putexcel set "$XL20", sheet("00_Guide") replace
putexcel A1 = "Main LPM results (headline model M7)"
putexcel A3 = "Run"
putexcel B3 = "$RUN_NAME"
putexcel A4 = "Origin years"
putexcel B4 = "$FIRST_ORIGIN_YEAR to $LAST_ORIGIN_YEAR"
putexcel A5 = "Pair fixed effect in the model (1 = yes)"
putexcel B5 = $USE_PAIR_FE
putexcel A6 = "Fixed effects"
putexcel B6 = "$FE_LIST"
putexcel A7 = "Unclassified employed counted as services (1 = yes)"
putexcel B7 = $UNCLASSIFIED_AS_SERVICES
putexcel A9 = "Sheet"
putexcel B9 = "What it shows"
putexcel A10 = "Main_M7"
putexcel B10 = "Effect on each outcome, in percentage points, of ten more days with Tmax of 35C or more (Days35) and of ten more units of heat dose above 35C (HeatDose35, divided by 10)."
putexcel A11 = "Notes"
putexcel B11 = "Weights: Weight_origin. Standard errors clustered by county. Stars: * p<0.10, ** p<0.05, *** p<0.01."
putexcel A12 = "Weather: the heat variable is measured in the origin season. Rain and rain squared are controls."
putexcel clear

preserve
    use "$RESULTS/lpm_main_results.dta", clear
    gen str60 label = ""
    replace label = "Exit from agriculture"            if outcome == "exit_agri"
    replace label = "Productive exit (industry or services)" if outcome == "productive_exit"
    replace label = "Non-employment exit (unemployed or inactive)" if outcome == "distress_exit"
    replace label = "Industry"                          if outcome == "dest2"
    replace label = "Services"                          if outcome == "dest3"
    replace label = "Unemployment"                      if outcome == "dest4"
    replace label = "Inactivity"                        if outcome == "dest5"
    gen str6 stars = cond(pvalue < 0.01, "***", cond(pvalue < 0.05, "**", cond(pvalue < 0.10, "*", "")))
    gen str30 estimate = string(coef, "%9.3f") + stars
    gen str30 std_error = "(" + string(se, "%9.3f") + ")"
    export excel run measure label outcome coef se pvalue ci_lo ci_hi estimate std_error n_used n_clusters r2 ///
        using "$XL20", sheet("Main_M7", modify) firstrow(variables)
restore

putexcel set "$XL20", sheet("Sample") modify
putexcel A1 = "Sample sizes"
putexcel A3 = "Base sample (agriculture at origin, known destination, valid IDs and weight)"
putexcel B3 = `n_base'
putexcel A4 = "Days35 sample (matched weather, controls complete)"
putexcel B4 = `n_days35'
putexcel A5 = "HeatDose35 sample"
putexcel B5 = `n_heat35'
putexcel A6 = "Weighted exit rate from agriculture, Days35 sample (percent)"
putexcel B6 = `base_exit'
putexcel clear

*------------------------------------------------------------------------------*
* 4. Check against the thesis (old period only)
*------------------------------------------------------------------------------*
* Thesis (final version): Days35 sample N = 241,238; exit 0.778, productive exit 0.187,
* non-employment exit 0.591; weighted exit rate 31.98 percent.
if $LAST_ORIGIN_YEAR == 1398 {
    preserve
        use "$RESULTS/lpm_main_results.dta", clear
        keep if measure == "days35" & inlist(outcome, "exit_agri", "productive_exit", "distress_exit")
        gen double thesis = .
        replace thesis = 0.778 if outcome == "exit_agri"
        replace thesis = 0.187 if outcome == "productive_exit"
        replace thesis = 0.591 if outcome == "distress_exit"
        gen double difference = coef - thesis
        keep run outcome coef thesis difference n_used
        export excel using "$XL20", sheet("Check_vs_thesis", modify) firstrow(variables)
        list, noobs
    restore
    di as result "Thesis sample size: 241,238.  Ours: `n_days35'.  Thesis exit rate 31.98.  Ours: " %6.2f `base_exit'
}

di as result "20 done."
log close step
