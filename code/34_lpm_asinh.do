*==============================================================================*
* 34_lpm_asinh.do
* Inverse hyperbolic sine (asinh) of the heat variables. Many county-seasons have zero
* hot days, so a log is impossible; asinh(x) works with zeros.
* The size of the coefficient depends on the unit of x (asinh is log-like only for
* large values), so we show two units:
*   unit "days"  : asinh(x), x in days (HeatDose35: degree-days)
*   unit "tens"  : asinh(x / 10), x in tens of days (the unit of the main tables)
* The rain controls stay as in the main model. Model M7, all seven outcomes.
*
* Output: output/<RUN_NAME>/tables/34_lpm_asinh.xlsx
*         output/<RUN_NAME>/results/lpm_asinh_results.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/34_lpm_asinh.log", text replace name(step)

global XL34 "$TABLES/34_lpm_asinh.xlsx"

prep_lpm_data

local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain')
make_sample, name(heat35) vars(heat35_10_s0 `rain')

foreach m in days35 heat35 {
    gen double ash_`m'_days = asinh(`m'_10_s0 * 10)
    gen double ash_`m'_tens = asinh(`m'_10_s0)
    label var ash_`m'_days "asinh(`m' in days)"
    label var ash_`m'_tens "asinh(`m' in tens of days)"
}

open_results, file("$RESULTS/lpm_asinh_results.dta")
foreach y of global OUTCOMES {
    foreach m in days35 heat35 {
        local nm "Days35"
        if "`m'" == "heat35" local nm "HeatDose35"
        foreach u in days tens {
            run_lpm, family("Asinh_`nm'") panel("unit_`u'") model(7) outcome(`y') ///
                wvars("ash_`m'_`u' `rain'") terms("ash_`m'_`u'") rainterms("`rain'") sample(`m')
        }
    }
}
close_results

guide_sheet, file("$XL34") title("asinh of the heat variables (model M7)") lines("Days35_asinh: Coefficient on asinh of Days35, in percentage points of the outcome. Panel unit_days uses days, panel unit_tens uses tens of days.|HeatDose35_asinh: Same for heat dose (degree-days).|All_long: Every regression, one row per term.|Samples: Sample sizes.|Reading: asinh(x) is close to log(2x) when x is large, so the coefficient is roughly the change in the outcome for a 100 percent change in x. For small x it is close to linear. This is why the unit matters.")
export_wide, file("$XL34") sheet("Days35_asinh") family("Asinh_Days35")
export_wide, file("$XL34") sheet("HeatDose35_asinh") family("Asinh_HeatDose35")
export_long, file("$XL34") sheet("All_long")
export_samples, file("$XL34") sheet("Samples")

di as result "34 done."
log close step
