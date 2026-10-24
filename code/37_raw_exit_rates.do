*==============================================================================*
* 37_raw_exit_rates.do
* Raw (unadjusted) exit rates from agriculture, for reading the regression coefficients.
* Weighted means of the seven outcomes (percent of agriculture-origin workers who are in
* each destination one year later) in the Days35 estimation sample, no regression.
*
* Sheets:
*   Overall        mean of each outcome, and the headline Days35 and HeatDose35 coefficients
*                  from step 20 as a share of that mean (coefficient / mean)
*   By_year        by origin year
*   By_season      by origin season (1 spring, 2 summer, 3 autumn, 4 winter)
*   By_region      by agro-climatic region
*   By_heat        by number of hot days (Tmax >= 35C) in the origin season: none, 1-9, 10-19, 20 or more
*   By_period      before and after 1390, and before and after 1397 (origin years)
*
* Outcomes are in percent. The mean of "Productive exit" is the sum of Industry and Services,
* and the mean of "Non-employment exit" is the sum of Unemployment and Inactivity.
*
* Output: output/<RUN_NAME>/tables/37_raw_exit_rates.xlsx
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/37_raw_exit_rates.log", text replace name(step)

global XL37 "$TABLES/37_raw_exit_rates.xlsx"

prep_lpm_data
add_region

local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain')
keep if smp_days35 == 1

* Number of hot days in the season (days35_10_s0 is in tens of days)
gen double hot_days = days35_10_s0 * 10
gen byte heat_group = 1 if hot_days == 0
replace heat_group = 2 if hot_days > 0  & hot_days < 10
replace heat_group = 3 if hot_days >= 10 & hot_days < 20
replace heat_group = 4 if hot_days >= 20
label define heat_lbl 1 "No day at or above 35C" 2 "1 to 9 days" 3 "10 to 19 days" 4 "20 days or more", replace
label values heat_group heat_lbl

gen byte period1390 = cond(year_origin <= 1390, 1, 2)
gen byte period1397 = cond(year_origin <= 1397, 1, 2)
label define per1_lbl 1 "Origin year up to 1390" 2 "Origin year after 1390", replace
label define per2_lbl 1 "Origin year up to 1397" 2 "Origin year after 1397", replace
label values period1390 per1_lbl
label values period1397 per2_lbl


guide_sheet, file("$XL37") title("Raw exit rates from agriculture (no regression)") ///
    lines("Overall: Weighted mean of each outcome in the Days35 sample (percent), and the main Days35 and HeatDose35 coefficients (M7) as a share of that mean.|By_year, By_season, By_region, By_heat, By_period: The same weighted means for subgroups. n_rows is the number of rows.|Notes: Outcomes are percent of agriculture-origin workers in each state one year later. Productive exit = Industry + Services. Non-employment exit = Unemployment + Inactivity. Weights are Weight_origin. By_heat groups workers by the number of days with Tmax of 35C or more in the origin season. These are raw means: they do not hold anything else fixed.")

*------------------------------------------------------------------------------*
* Overall
*------------------------------------------------------------------------------*
gen byte all_rows = 1
egen long n_rows_all = total(1)

preserve
    collapse (mean) pp_exit_agri pp_productive_exit pp_distress_exit pp_dest2 pp_dest3 pp_dest4 pp_dest5 ///
        n_rows_all [aweight = Weight_origin]
    rename n_rows_all n_rows
    gen byte one = 1
    reshape long pp_, i(one n_rows) j(outcome) string
    rename pp_ raw_mean_pct
    drop one
    tempfile means
    save `means'
restore

preserve
    use "$RESULTS/lpm_main_results.dta", clear
    keep measure outcome coef
    reshape wide coef, i(outcome) j(measure) string
    rename coefdays35 coef_days35_per10days
    rename coefheat35 coef_heat35_per10units
    merge 1:1 outcome using `means', nogenerate keep(master match)
    gen double days35_coef_over_mean_pct = 100 * coef_days35_per10days / raw_mean_pct
    gen double heat35_coef_over_mean_pct = 100 * coef_heat35_per10units / raw_mean_pct
    order outcome raw_mean_pct coef_days35_per10days days35_coef_over_mean_pct coef_heat35_per10units heat35_coef_over_mean_pct
    export excel using "$XL37", sheet("Overall", modify) firstrow(variables)
restore

*------------------------------------------------------------------------------*
* Subgroups
*------------------------------------------------------------------------------*
foreach g in year_origin season_origin agro_region heat_group {
    local sheet "By_`g'"
    if "`g'" == "year_origin"   local sheet "By_year"
    if "`g'" == "season_origin" local sheet "By_season"
    if "`g'" == "agro_region"   local sheet "By_region"
    if "`g'" == "heat_group"    local sheet "By_heat"
    preserve
        egen long n_rows = total(1), by(`g')
        collapse (mean) pp_exit_agri pp_productive_exit pp_distress_exit pp_dest2 pp_dest3 pp_dest4 pp_dest5 ///
            n_rows [aweight = Weight_origin], by(`g')
        foreach v of varlist pp_* {
            local nm = substr("`v'", 4, .)
            rename `v' `nm'
        }
        if inlist("`g'", "agro_region", "heat_group") {
            decode `g', gen(group_label)
        }
        export excel using "$XL37", sheet("`sheet'", modify) firstrow(variables)
    restore
}

* Periods (both cuts in one sheet)
tempfile per
preserve
    egen long n_rows = total(1), by(period1390)
    collapse (mean) pp_exit_agri pp_productive_exit pp_distress_exit pp_dest2 pp_dest3 pp_dest4 pp_dest5 ///
        n_rows [aweight = Weight_origin], by(period1390)
    decode period1390, gen(group)
    drop period1390
    save `per'
restore
preserve
    egen long n_rows = total(1), by(period1397)
    collapse (mean) pp_exit_agri pp_productive_exit pp_distress_exit pp_dest2 pp_dest3 pp_dest4 pp_dest5 ///
        n_rows [aweight = Weight_origin], by(period1397)
    decode period1397, gen(group)
    drop period1397
    append using `per'
    order group
    foreach v of varlist pp_* {
        local nm = substr("`v'", 4, .)
        rename `v' `nm'
    }
    export excel using "$XL37", sheet("By_period", modify) firstrow(variables)
restore

di as result "37 done."
log close step
