*==============================================================================*
* 24_lpm_saturated_fe.do
* Preferred model M7 against the saturated version M9:
*   M7  county + province-by-year + season fixed effects
*   M9  county + province-by-year-by-season fixed effects
* All seven outcomes, Days35 and HeatDose35. This is the comparison in the main
* coefficient figure.
*
* Output: output/<RUN_NAME>/tables/24_lpm_saturated_fe.xlsx
*         output/<RUN_NAME>/results/lpm_saturated_results.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/24_lpm_saturated_fe.log", text replace name(step)

global XL24 "$TABLES/24_lpm_saturated_fe.xlsx"

prep_lpm_data

local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain')
make_sample, name(heat35) vars(heat35_10_s0 `rain')

open_results, file("$RESULTS/lpm_saturated_results.dta")
foreach y of global OUTCOMES {
    foreach m in 7 9 {
        run_lpm, family("Days35") panel("Main") model(`m') outcome(`y') ///
            wvars("days35_10_s0 `rain'") terms("days35_10_s0") rainterms("`rain'") sample(days35)
        run_lpm, family("HeatDose35") panel("Main") model(`m') outcome(`y') ///
            wvars("heat35_10_s0 `rain'") terms("heat35_10_s0") rainterms("`rain'") sample(heat35)
    }
}
close_results

guide_sheet, file("$XL24") title("Preferred model M7 and the saturated model M9") lines("Days35: Rows M7 and M9 for each term. M7 = county FE + province-by-year FE + season FE. M9 = county FE + province-by-year-by-season FE.|HeatDose35: Same for heat dose.|All_long: Every regression, one row per term.|Samples: Sample sizes.")
export_wide, file("$XL24") sheet("Days35") family("Days35")
export_wide, file("$XL24") sheet("HeatDose35") family("HeatDose35")
export_long, file("$XL24") sheet("All_long")
export_samples, file("$XL24") sheet("Samples")

di as result "24 done."
log close step
