*==============================================================================*
* 32_lpm_periods.do
* Does the effect of heat differ before and after the sanctions period?
* Split of the origin years: up to CUT_YEAR (default 1390) versus after.
* There are no transitions for origin year 1391, so a cut at 1390 or at 1391 gives the
* same two groups.
*
* Two ways, headline model M7, all seven outcomes (industry is the outcome of interest):
*   A. One pooled regression with a separate heat slope for each period and a test
*      that the two slopes are equal.
*   B. A separate regression for each period.
*
* To try another cut year, add it to the list in the next line.
*
* Output: output/<RUN_NAME>/tables/32_lpm_periods.xlsx
*         output/<RUN_NAME>/results/lpm_periods_results.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/32_lpm_periods.log", text replace name(step)

local CUT_YEARS "1390 1397"

global XL32 "$TABLES/32_lpm_periods.xlsx"

prep_lpm_data

local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain')
make_sample, name(heat35) vars(heat35_10_s0 `rain')

open_results, file("$RESULTS/lpm_periods_results.dta")

foreach cut of local CUT_YEARS {
    foreach m in days35 heat35 {
        gen double `m'_pre`cut'  = `m'_10_s0 * (year_origin <= `cut')
        gen double `m'_post`cut' = `m'_10_s0 * (year_origin >  `cut')
        label var `m'_pre`cut'  "`m' x origin year <= `cut'"
        label var `m'_post`cut' "`m' x origin year > `cut'"
        gen byte smp_`m'_pre`cut'  = smp_`m' == 1 & year_origin <= `cut'
        gen byte smp_`m'_post`cut' = smp_`m' == 1 & year_origin >  `cut'
        global SAMPLE_LIST "$SAMPLE_LIST `m'_pre`cut' `m'_post`cut'"
    }

    foreach y of global OUTCOMES {
        foreach m in days35 heat35 {
            local fam "Period`cut'_Days35"
            if "`m'" == "heat35" local fam "Period`cut'_HeatDose35"

            run_lpm, family("`fam'") panel("A_pooled_two_slopes") model(7) outcome(`y') ///
                wvars("`m'_pre`cut' `m'_post`cut' `rain'") terms("`m'_pre`cut' `m'_post`cut'") ///
                rainterms("`rain'") sample(`m') jtest("`m'_pre`cut' = `m'_post`cut'")

            run_lpm, family("`fam'") panel("B_separate_pre") model(7) outcome(`y') ///
                wvars("`m'_10_s0 `rain'") terms("`m'_10_s0") rainterms("`rain'") sample(`m'_pre`cut')
            run_lpm, family("`fam'") panel("B_separate_post") model(7) outcome(`y') ///
                wvars("`m'_10_s0 `rain'") terms("`m'_10_s0") rainterms("`rain'") sample(`m'_post`cut')
        }
    }
}
close_results

*------------------------------------------------------------------------------*
* Excel
*------------------------------------------------------------------------------*
guide_sheet, file("$XL32") title("Before and after the cut year (model M7)") lines("One pair of sheets for each cut year and heat measure. Panel A: pooled regression with one slope before and one after (terms ending in pre and post). Panel B: separate regressions for the two periods.|Test sheets: F test that the two pooled slopes are equal (the p-value is shown in each outcome column).|All_long: Every regression, one row per term.|Samples: Sample sizes.|Notes: Origin years up to the cut year are the first period. There are no transitions for origin year 1391.")
foreach cut of local CUT_YEARS {
    export_wide, file("$XL32") sheet("Days35_cut`cut'") family("Period`cut'_Days35")
    export_wide, file("$XL32") sheet("HeatDose35_cut`cut'") family("Period`cut'_HeatDose35")
    export_wide, file("$XL32") sheet("Test_Days35_cut`cut'") family("Period`cut'_Days35") kind("test")
    export_wide, file("$XL32") sheet("Test_Heat_cut`cut'") family("Period`cut'_HeatDose35") kind("test")
}
export_long, file("$XL32") sheet("All_long")
export_samples, file("$XL32") sheet("Samples")

di as result "32 done."
log close step
