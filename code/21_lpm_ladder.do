*==============================================================================*
* 21_lpm_ladder.do
* The model ladder M1-M8 for the two headline heat measures:
*   Days35    = days with Tmax >= 35C in the origin season (per 10 days)
*   HeatDose35 = sum of (Tmax - 35C) over hot days (per 10 degree-days)
* All seven outcomes. Each step adds controls or fixed effects (see lib_models.do):
*   M1 weather only | M2 + age, sex | M3 + marital | M4 + urban
*   M5 + year, season (and pair) FE | M6 + county FE
*   M7 county + province-by-year + season FE (headline) | M8 M7 + county trends
*
* Output: output/<RUN_NAME>/tables/21_lpm_ladder.xlsx
*         output/<RUN_NAME>/results/lpm_ladder_results.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/21_lpm_ladder.log", text replace name(step)

global XL21 "$TABLES/21_lpm_ladder.xlsx"

prep_lpm_data

local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain')
make_sample, name(heat35) vars(heat35_10_s0 `rain')

open_results, file("$RESULTS/lpm_ladder_results.dta")

foreach y of global OUTCOMES {
    forvalues m = 1/8 {
        run_lpm, family("Days35") panel("Main") model(`m') outcome(`y') ///
            wvars("days35_10_s0 `rain'") terms("days35_10_s0") rainterms("`rain'") sample(days35)
        run_lpm, family("HeatDose35") panel("Main") model(`m') outcome(`y') ///
            wvars("heat35_10_s0 `rain'") terms("heat35_10_s0") rainterms("`rain'") sample(heat35)
    }
}
close_results

*------------------------------------------------------------------------------*
* Excel
*------------------------------------------------------------------------------*
guide_sheet, file("$XL21") title("Model ladder M1-M8, headline heat measures") lines("Days35: Effect of ten more days with Tmax of 35C or more, one column per outcome, one row per model.|HeatDose35: Effect of ten more units of heat dose above 35C.|Rain_controls: Coefficients on rain and rain squared (same models).|All_long: Every regression, one row per term.|Samples: Sample sizes and the weighted exit rate.|Models: M1 weather only. M2 + age, age squared, sex. M3 + marital status. M4 + urban. M5 + year and season FE (+ pair FE if used). M6 + county FE. M7 county + province-by-year + season FE (headline). M8 = M7 + county-specific linear trends.")
export_wide, file("$XL21") sheet("Days35") family("Days35")
export_wide, file("$XL21") sheet("HeatDose35") family("HeatDose35")
export_wide, file("$XL21") sheet("Rain_controls") family("Days35") kind("control")
export_long, file("$XL21") sheet("All_long")
export_samples, file("$XL21") sheet("Samples")

di as result "21 done."
log close step
