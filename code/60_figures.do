*==============================================================================*
* 60_figures.do
* Coefficient figures (dot and whisker, 95 percent confidence intervals) made from the
* results datasets of the model scripts. This script runs no regressions.
* A figure is skipped (with a message) if the results file it needs does not exist,
* so you can run this after any subset of the model scripts.
*
* Output: output/<RUN_NAME>/graphs/coef_*.pdf
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/60_figures.log", text replace name(step)

local XD "Percentage points per ten additional days with Tmax of 35C or more"
local XH "Percentage points per ten additional units of heat dose above 35C"

* 1. Main figure: preferred model against the saturated fixed effects
foreach f in Days35 HeatDose35 {
    local xt "`XD'"
    if "`f'" == "HeatDose35" local xt "`XH'"
    fig_coef, file("$RESULTS/lpm_saturated_results.dta") out("$GRAPHS/coef_main_`f'.pdf") ///
        xtitle("`xt'") ///
        series(family=`f',model=7 | family=`f',model=9) ///
        labels(Preferred specification | Province-by-year-by-season FE)
}

* 2. Before and after a cut year: one regression with heat x period interactions (step 38, model M7).
*    Cut 1390 = origin years 1384-1390 and 1391-1402; cut 1397 = 1384-1397 and 1398-1402.
foreach cut in 1390 1397 {
    local pn = cond("`cut'" == "1390", 1, 2)
    local after = `cut' + 1
    foreach f in Days35 HeatDose35 {
        local xt "`XD'"
        local stem "days35"
        if "`f'" == "HeatDose35" {
            local xt "`XH'"
            local stem "heat35"
        }
        fig_coef, file("$RESULTS/lpm_period_results.dta") out("$GRAPHS/coef_periods`cut'_`f'.pdf") ///
            xtitle("`xt'") ///
            series(family=Per_`f',panel=`pn'_cut`cut',term=`stem'_p`pn'g1 | family=Per_`f',panel=`pn'_cut`cut',term=`stem'_p`pn'g2) ///
            labels(Origin years up to `cut' | Origin years from `after')
    }
}

* 3. Coefficient by origin year (step 38, one regression with a separate heat slope for each year).
*    Dots are the yearly slopes for total exit and non-employment exit with 95 percent intervals.
foreach f in Days35 HeatDose35 {
    capture confirm file "$RESULTS/lpm_period_results.dta"
    if _rc continue
    local stem "days35"
    local yt "Percentage points per ten additional days with Tmax of 35C or more"
    if "`f'" == "HeatDose35" {
        local stem "heat35"
        local yt "Percentage points per ten additional units of heat dose above 35C"
    }
    preserve
        use "$RESULTS/lpm_period_results.dta", clear
        keep if family == "Year_`f'" & kind == "exposure" & status == "ok" & inlist(outcome, "exit_agri", "distress_exit")
        gen int yr = real(substr(term, -4, 4))
        gen double xx = yr + cond(outcome == "exit_agri", -0.12, 0.12)
        twoway (rcap ci_lo ci_hi xx if outcome == "exit_agri", lcolor("31 95 139") lwidth(thin)) ///
               (scatter coef xx if outcome == "exit_agri", mcolor("31 95 139") msymbol(O) msize(small)) ///
               (rcap ci_lo ci_hi xx if outcome == "distress_exit", lcolor("179 90 31") lwidth(thin)) ///
               (scatter coef xx if outcome == "distress_exit", mcolor("179 90 31") msymbol(S) msize(small)), ///
            yline(0, lcolor(gs8) lwidth(thin)) ///
            xlabel(1384 1388 1392 1396 1400, labsize(small)) xtitle("Origin year") ///
            ytitle("`yt'", size(small)) ///
            ylabel(, angle(0) grid glcolor(gs14)) ///
            legend(order(2 "Total exit" 4 "Non-employment exit") rows(1) position(6) size(small) region(lstyle(none))) ///
            graphregion(color(white)) plotregion(margin(small))
        graph export "$GRAPHS/coef_years_`f'.pdf", replace
    restore
}

* 4. Linear model against the two-sided (asymmetry) model is shown in tables, not here.

di as result "60 done."
log close step
