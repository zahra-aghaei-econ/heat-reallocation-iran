*==============================================================================*
* 23_lpm_education.do
* Education appendix. Education is not in the main models because it is missing
* for part of the sample. Here we check that the headline results do not depend on it.
*
* Five regressions for each heat measure (Days35, HeatDose35) and each outcome:
*   E1  M7, full sample, no education
*   E2  M7, only people with education observed, no education
*   E3  M7, same sample as E2, WITH education categories   (E2 vs E3: effect of education)
*   E4  M8, only people with education observed, no education
*   E5  M8, same sample as E4, WITH education categories   (E4 vs E5: effect of education)
*
* Output: output/<RUN_NAME>/tables/23_lpm_education.xlsx
*         output/<RUN_NAME>/results/lpm_education_results.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/23_lpm_education.log", text replace name(step)

global XL23 "$TABLES/23_lpm_education.xlsx"

prep_lpm_data

local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain')
make_sample, name(heat35) vars(heat35_10_s0 `rain')
make_sample, name(days35_educ) vars(days35_10_s0 `rain' educ_origin)
make_sample, name(heat35_educ) vars(heat35_10_s0 `rain' educ_origin)

*------------------------------------------------------------------------------*
* Education missing: by year, by season, and the categories
*------------------------------------------------------------------------------*
tempfile md
capture postclose mh
postfile mh str12 breakdown str40 group long n_obs long n_educ_missing double share_missing using `md', replace
quietly count if weather_common_sample == 1
local nt = r(N)
quietly count if weather_common_sample == 1 & missing(educ_origin)
post mh ("overall") ("all") (`nt') (r(N)) (r(N) / `nt')
quietly levelsof year_origin if weather_common_sample == 1, local(yrs)
foreach y of local yrs {
    quietly count if weather_common_sample == 1 & year_origin == `y'
    local nt = r(N)
    quietly count if weather_common_sample == 1 & year_origin == `y' & missing(educ_origin)
    post mh ("year") ("`y'") (`nt') (r(N)) (r(N) / `nt')
}
forvalues s = 1/4 {
    quietly count if weather_common_sample == 1 & season_origin == `s'
    local nt = r(N)
    quietly count if weather_common_sample == 1 & season_origin == `s' & missing(educ_origin)
    post mh ("season") ("`s'") (`nt') (r(N)) (r(N) / `nt')
}
postclose mh

*------------------------------------------------------------------------------*
* Regressions
*------------------------------------------------------------------------------*
open_results, file("$RESULTS/lpm_education_results.dta")

foreach y of global OUTCOMES {
    foreach m in days35 heat35 {
        local w "`m'_10_s0"
        local fam "Educ_Days35"
        if "`m'" == "heat35" local fam "Educ_HeatDose35"

        run_lpm, family("`fam'") panel("E1") model(7) outcome(`y') wvars("`w' `rain'") ///
            terms("`w'") rainterms("`rain'") sample(`m')
        run_lpm, family("`fam'") panel("E2") model(7) outcome(`y') wvars("`w' `rain'") ///
            terms("`w'") rainterms("`rain'") sample(`m'_educ)
        run_lpm, family("`fam'") panel("E3") model(7) outcome(`y') wvars("`w' `rain'") ///
            terms("`w'") rainterms("`rain'") sample(`m'_educ) extra("i.educ_origin")
        run_lpm, family("`fam'") panel("E4") model(8) outcome(`y') wvars("`w' `rain'") ///
            terms("`w'") rainterms("`rain'") sample(`m'_educ)
        run_lpm, family("`fam'") panel("E5") model(8) outcome(`y') wvars("`w' `rain'") ///
            terms("`w'") rainterms("`rain'") sample(`m'_educ) extra("i.educ_origin")
    }
}
close_results

*------------------------------------------------------------------------------*
* Excel
*------------------------------------------------------------------------------*
guide_sheet, file("$XL23") title("Education appendix") lines("Days35: Effect of ten more hot days, five regressions E1-E5 for each outcome.|HeatDose35: Same for heat dose.|Educ_missing: Share of observations without education, overall, by year and by season (agriculture at origin, matched weather).|All_long: Every regression, one row per term.|Samples: Sample sizes.|E1 to E5: E1 M7 full sample. E2 M7 with education observed. E3 same as E2 plus education categories. E4 M8 with education observed. E5 same as E4 plus education categories.")
export_wide, file("$XL23") sheet("Days35") family("Educ_Days35")
export_wide, file("$XL23") sheet("HeatDose35") family("Educ_HeatDose35")
export_long, file("$XL23") sheet("All_long")
export_samples, file("$XL23") sheet("Samples")
preserve
    use `md', clear
    export excel using "$XL23", sheet("Educ_missing", modify) firstrow(variables)
restore

di as result "23 done."
log close step
