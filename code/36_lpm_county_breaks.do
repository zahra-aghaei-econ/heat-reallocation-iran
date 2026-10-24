*==============================================================================*
* 36_lpm_county_breaks.do
* Robustness to counties whose survey sample changes sharply around 1397.
* Script 40 (sheet County_change) shows that a few counties lose most of their rows
* or change their agriculture share from 1396 to 1397 (for example 0617 and 0928).
* Three versions of the preferred model, Days35 and HeatDose35, all seven outcomes:
*   A_all     M7 with all counties (the headline result)
*   B_drop    M7 without the counties in DROP_COUNTIES
*   C_post    M7 plus a separate county intercept before and after the break year
*             (county x post fixed effect), all counties kept
*
* To change the counties or the break year, edit the two lines below.
*
* Output: output/<RUN_NAME>/tables/36_lpm_county_breaks.xlsx
*         output/<RUN_NAME>/results/lpm_breaks_results.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/36_lpm_county_breaks.log", text replace name(step)

local DROP_COUNTIES "0617 0928"
local BREAK_YEAR 1397

global XL36 "$TABLES/36_lpm_county_breaks.xlsx"

prep_lpm_data

gen byte post_break = (year_origin > `BREAK_YEAR')
label var post_break "Origin year after `BREAK_YEAR'"

gen byte drop_county = 0
foreach c of local DROP_COUNTIES {
    replace drop_county = 1 if mix4_origin == "`c'"
}
quietly count if drop_county == 1
di as result "Rows in the dropped counties (`DROP_COUNTIES'): " r(N)

local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain')
make_sample, name(heat35) vars(heat35_10_s0 `rain')
foreach m in days35 heat35 {
    gen byte smp_`m'_drop = smp_`m' == 1 & drop_county == 0
    global SAMPLE_LIST "$SAMPLE_LIST `m'_drop"
}

open_results, file("$RESULTS/lpm_breaks_results.dta")
foreach y of global OUTCOMES {
    foreach m in days35 heat35 {
        local fam "Breaks_Days35"
        if "`m'" == "heat35" local fam "Breaks_HeatDose35"
        run_lpm, family("`fam'") panel("A_all") model(7) outcome(`y') ///
            wvars("`m'_10_s0 `rain'") terms("`m'_10_s0") rainterms("`rain'") sample(`m')
        run_lpm, family("`fam'") panel("B_drop") model(7) outcome(`y') ///
            wvars("`m'_10_s0 `rain'") terms("`m'_10_s0") rainterms("`rain'") sample(`m'_drop)
        run_lpm, family("`fam'") panel("C_post") model(10) outcome(`y') ///
            wvars("`m'_10_s0 `rain'") terms("`m'_10_s0") rainterms("`rain'") sample(`m')
    }
}
close_results

*------------------------------------------------------------------------------*
* Excel
*------------------------------------------------------------------------------*
guide_sheet, file("$XL36") title("Robustness to county breaks around the survey change of 1397") ///
    lines("Compare: Heat coefficient for the three versions side by side (A_all, B_drop, C_post), with standard error, p-value and sample size.|Days35, HeatDose35: Full result tables for each heat measure, one panel per version.|All_long: Every regression, one row per term.|Samples: Sample sizes.|Notes: A_all = model M7 with all counties. B_drop = M7 without the counties listed in DROP_COUNTIES in the script (0617 and 0928). C_post = M7 plus county x (origin year after 1397) fixed effects, so each county may have a different level before and after the break.")

preserve
    use "$RES_FILE", clear
    keep if kind == "exposure" & status == "ok"
    keep family panel outcome coef se pvalue n_used
    reshape wide coef se pvalue n_used, i(family outcome) j(panel) string
    export excel using "$XL36", sheet("Compare", modify) firstrow(variables)
restore

export_wide, file("$XL36") sheet("Days35") family("Breaks_Days35")
export_wide, file("$XL36") sheet("HeatDose35") family("Breaks_HeatDose35")
export_long, file("$XL36") sheet("All_long")
export_samples, file("$XL36") sheet("Samples")

di as result "36 done."
log close step
