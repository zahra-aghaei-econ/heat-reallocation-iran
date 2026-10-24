*==============================================================================*
* 47_asymmetry_county_normal.do
* Heat above and below the county average: the supervisor's version of the
* asymmetry test, with added-variable (binned scatter) plots.
*
* Idea (supervisor): for every county compute the average of Days35 over the sample.
* For every observation split the difference between its own Days35 and that average
* into a positive part and a negative part and let the two parts have separate
* coefficients in the main regression (M7).
*
* Two definitions of the "normal" level are run side by side:
*   CM  county mean       normal = mean of x in the county over all sample years and
*                         seasons (each county-season-year cell counts once).
*                         The normal is constant within a county, so the county fixed
*                         effect absorbs it and only above and below enter.
*   CS  county-season     normal = mean of x in the same county and the same season
*       mean              (the version of step 33). The normal varies across seasons
*                         within a county, so it enters as a third regressor.
* With x in tens (days for Days35, degree-days for HeatDose35):
*     above = max(x - normal, 0)      below = max(normal - x, 0)      x = normal + above - below
* The coefficient on below is the effect of a shortfall of ten units below the normal:
* if heat acts linearly and symmetrically, coefficient(above) = -coefficient(below).
* Symmetry test: coefficient(above) + coefficient(below) = 0.
*
* Regressions (all outcomes, both heat measures, both definitions): model M7 fixed
* effects, rain, rain squared, individual controls, weights Weight_origin, standard
* errors clustered by county.
*
* Figures (exit from agriculture and non-employment exit; both heat measures; both
* definitions) are added-variable plots, exact for the split regression (Frisch-Waugh-
* Lovell). Right panel, "above normal": x = above, residualised on below, normal (CS only),
* rain, controls and all M7 fixed effects; y = outcome residualised on the same variables
* (sample mean added back); points are group means of 25 weighted equal-sized groups of
* the residualised x; the solid line has the slope of the coefficient on above. Left
* panel, "below normal": the same with below, plotted as minus the residual so that
* moving to the left means a larger shortfall; the solid line has the slope of
* minus(coefficient on below). The dashed line is the slope of the main linear model.
* If the response is linear and symmetric the solid line of the left panel continues the
* solid line of the right panel and equals the dashed line.
*
* Output: output/<RUN_NAME>/tables/47_asymmetry_county_normal.xlsx
*         output/<RUN_NAME>/results/lpm_asym_cn_results.dta  (regressions)
*         output/<RUN_NAME>/results/asym_cn_points.dta        (plotted points)
*         output/<RUN_NAME>/results/asym_cn_deviation.dta     (distribution of the deviations)
*         output/<RUN_NAME>/graphs/asym_<cm|cs>_<measure>_<outcome>.pdf
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/47_asymmetry_county_normal.log", text replace name(step)

global XL47 "$TABLES/47_asymmetry_county_normal.xlsx"
local NB 25

prep_lpm_data
local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain')
make_sample, name(heat35) vars(heat35_10_s0 `rain')

get_spec 7
local ctrl   "`r(controls)'"
local absorb "`r(absorb)'"

*------------------------------------------------------------------------------*
* 1. Normal, above and below, for both definitions
*------------------------------------------------------------------------------*
tempname hd
tempfile fd
postfile `hd' str6 defn str12 measure double mean_x double sd_x double mean_above double mean_below ///
    double share_above double share_below double sd_dev double n_obs using `fd', replace

foreach m in days35 heat35 {
    local x "`m'_10_s0"
    egen byte ctag = tag(mix_id year_origin season_origin) if smp_`m' == 1
    * county mean over county-season-year cells
    egen double nt_cm = mean(`x') if ctag == 1, by(mix_id)
    egen double cm_normal_`m' = max(nt_cm), by(mix_id)
    * county-season mean
    egen double nt_cs = mean(`x') if ctag == 1, by(mix_id season_origin)
    egen double cs_normal_`m' = max(nt_cs), by(mix_id season_origin)
    drop ctag nt_cm nt_cs
    foreach dn in cm cs {
        replace `dn'_normal_`m' = . if smp_`m' != 1
        gen double `dn'_above_`m' = max(`x' - `dn'_normal_`m', 0) if !missing(`dn'_normal_`m')
        gen double `dn'_below_`m' = max(`dn'_normal_`m' - `x', 0) if !missing(`dn'_normal_`m')
        quietly count if smp_`m' == 1 & abs(`x' - (`dn'_normal_`m' + `dn'_above_`m' - `dn'_below_`m')) > 1e-8
        if r(N) > 0 di as error "47: decomposition does not add up in " r(N) " rows (`dn' `m')"
        quietly summarize `x' [aw = Weight_origin] if smp_`m' == 1
        local mx = r(mean)
        local sx = r(sd)
        quietly summarize `dn'_above_`m' [aw = Weight_origin] if smp_`m' == 1
        local ma = r(mean)
        quietly summarize `dn'_below_`m' [aw = Weight_origin] if smp_`m' == 1
        local mb = r(mean)
        quietly count if smp_`m' == 1
        local nn = r(N)
        quietly count if smp_`m' == 1 & `dn'_above_`m' > 0
        local sa = 100 * r(N) / `nn'
        quietly count if smp_`m' == 1 & `dn'_below_`m' > 0
        local sb = 100 * r(N) / `nn'
        tempvar dev
        quietly gen double `dev' = `x' - `dn'_normal_`m' if smp_`m' == 1
        quietly summarize `dev' [aw = Weight_origin]
        local sdd = r(sd)
        drop `dev'
        post `hd' ("`dn'") ("`m'") (`mx') (`sx') (`ma') (`mb') (`sa') (`sb') (`sdd') (`nn')
        di as text "`dn' `m': mean above " %6.3f `ma' ", mean below " %6.3f `mb' ", share above " %5.1f `sa' ", share below " %5.1f `sb' ", SD of deviation " %6.3f `sdd'
    }
}
postclose `hd'

*------------------------------------------------------------------------------*
* 2. Regressions
*------------------------------------------------------------------------------*
open_results, file("$RESULTS/lpm_asym_cn_results.dta")
foreach y of global OUTCOMES {
    foreach m in days35 heat35 {
        local nm "Days35"
        if "`m'" == "heat35" local nm "HeatDose35"
        local x "`m'_10_s0"
        local tlb "Symmetry test: above = -below (F)"

        run_lpm, family("AsymCM_`nm'") panel("1_M7_linear") model(7) outcome(`y') ///
            wvars("`x' `rain'") terms("`x'") rainterms("`rain'") sample(`m')
        run_lpm, family("AsymCM_`nm'") panel("2_M7_split_county_mean") model(7) outcome(`y') ///
            wvars("cm_above_`m' cm_below_`m' `rain'") terms("cm_above_`m' cm_below_`m'") ///
            rainterms("`rain'") sample(`m') ///
            jtest("cm_above_`m' + cm_below_`m' = 0") jname("symmetry_test") jlabel("`tlb'")

        run_lpm, family("AsymCS_`nm'") panel("1_M7_linear") model(7) outcome(`y') ///
            wvars("`x' `rain'") terms("`x'") rainterms("`rain'") sample(`m')
        run_lpm, family("AsymCS_`nm'") panel("2_M7_split_county_season_mean") model(7) outcome(`y') ///
            wvars("cs_normal_`m' cs_above_`m' cs_below_`m' `rain'") ///
            terms("cs_above_`m' cs_below_`m' cs_normal_`m'") rainterms("`rain'") sample(`m') ///
            jtest("cs_above_`m' + cs_below_`m' = 0") jname("symmetry_test") jlabel("`tlb'")
    }
}
close_results

*------------------------------------------------------------------------------*
* 3. Added-variable plots
*------------------------------------------------------------------------------*
tempname hp
tempfile fp
postfile `hp' str6 defn str12 measure str20 outcome str6 side byte bin double x double y ///
    double ci_lo double ci_hi double n_bin double slope double slope_se double sym_p using `fp', replace

foreach dn in cm cs {
    foreach m in days35 heat35 {
        local nm "Days35"
        local unit "tens of days"
        if "`m'" == "heat35" {
            local nm "HeatDose35"
            local unit "tens of degree-days"
        }
        local x "`m'_10_s0"
        local A "`dn'_above_`m'"
        local B "`dn'_below_`m'"
        local others "`rain' `ctrl'"
        local dtxt "county mean"
        if "`dn'" == "cs" {
            local others "`others' cs_normal_`m'"
            local dtxt "county-season mean"
        }

        foreach y in exit_agri distress_exit {
            local ylab : variable label pp_`y'

            * full split model and linear model (slopes and standard errors for the figure)
            quietly reghdfe pp_`y' `A' `B' `others' if smp_`m' == 1 [pweight = Weight_origin], ///
                absorb(`absorb') vce(cluster mix_id)
            local ba = _b[`A']
            local sa = _se[`A']
            local bb = _b[`B']
            local sb = _se[`B']
            quietly test `A' + `B' = 0
            local psym = r(p)
            quietly reghdfe pp_`y' `x' `rain' `ctrl' if smp_`m' == 1 [pweight = Weight_origin], ///
                absorb(`absorb') vce(cluster mix_id)
            local bl = _b[`x']
            quietly summarize pp_`y' [aw = Weight_origin] if smp_`m' == 1
            local ybar = r(mean)

            * added-variable residuals
            capture drop ry_a rx_a ry_b rx_b
            quietly reghdfe pp_`y' `B' `others' if smp_`m' == 1 [pweight = Weight_origin], absorb(`absorb') resid(ry_a)
            quietly reghdfe `A'    `B' `others' if smp_`m' == 1 [pweight = Weight_origin], absorb(`absorb') resid(rx_a)
            quietly reghdfe pp_`y' `A' `others' if smp_`m' == 1 [pweight = Weight_origin], absorb(`absorb') resid(ry_b)
            quietly reghdfe `B'    `A' `others' if smp_`m' == 1 [pweight = Weight_origin], absorb(`absorb') resid(rx_b)
            * left panel: minus the residual of below (shortfall grows to the left)
            replace rx_b = -rx_b

            foreach sd in a b {
                local slope = `ba'
                local sse   = `sa'
                if "`sd'" == "b" {
                    local slope = -`bb'
                    local sse   = `sb'
                }
                capture drop bin_`sd'
                xtile bin_`sd' = rx_`sd' [pweight = Weight_origin] if smp_`m' == 1 & !missing(ry_`sd', rx_`sd'), nq(`NB')
                quietly regress ry_`sd' ibn.bin_`sd' if smp_`m' == 1 [pweight = Weight_origin], noconstant vce(cluster mix_id)
                matrix bm_`sd' = e(b)
                matrix Vm_`sd' = e(V)
            }

            foreach sd in a b {
                    preserve
                        keep if smp_`m' == 1 & !missing(bin_`sd')
                        egen double n_bin = total(1), by(bin_`sd')
                        collapse (mean) xa = rx_`sd' n_bin [aw = Weight_origin], by(bin_`sd')
                        gen double yb = .
                        gen double se = .
                        forvalues i = 1/`=_N' {
                            replace yb = bm_`sd'[1, `i'] in `i'
                            replace se = sqrt(Vm_`sd'[`i', `i']) in `i'
                        }
                        gen double ya    = yb + `ybar'
                        gen double ci_lo = ya - 1.96 * se
                        gen double ci_hi = ya + 1.96 * se
                        local slope = `ba'
                        local sse   = `sa'
                        if "`sd'" == "b" {
                            local slope = -`bb'
                            local sse   = `sb'
                        }
                        gen double fit_own = `ybar' + `slope' * xa
                        gen double fit_lin = `ybar' + `bl' * xa
                        forvalues i = 1/`=_N' {
                            post `hp' ("`dn'") ("`m'") ("`y'") ("`sd'") (bin_`sd'[`i']) (xa[`i']) (ya[`i']) ///
                                (ci_lo[`i']) (ci_hi[`i']) (n_bin[`i']) (`slope') (`sse') (`psym')
                        }
                        local sl_txt = string(`slope', "%5.3f")
                        local se_txt = string(`sse', "%5.3f")
                        local ttl "Below the normal: slope `sl_txt' (SE `se_txt')"
                        local xt "Shortfall below the normal (`unit'); left = further below"
                        if "`sd'" == "a" {
                            local ttl "Above the normal: slope `sl_txt' (SE `se_txt')"
                            local xt "Excess above the normal (`unit'); right = further above"
                        }
                        twoway (rcap ci_lo ci_hi xa, lcolor(gs11) lwidth(thin)) ///
                               (scatter ya xa, msymbol(O) msize(small) mcolor(navy)) ///
                               (line fit_own xa, lcolor(maroon) lwidth(medthick)) ///
                               (line fit_lin xa, lcolor(gs6) lpattern(dash) lwidth(medthin)), ///
                            title("`ttl'", size(medsmall)) xtitle("`xt'", size(vsmall)) ytitle("") ///
                            legend(off) graphregion(color(white)) ylabel(, angle(0) grid) ///
                            name(g_`sd', replace) nodraw
                    restore
            }
            local ptxt = string(`psym', "%5.3f")
            local lintxt = string(`bl', "%5.3f")
            graph combine g_b g_a, rows(1) ycommon graphregion(color(white)) ///
                title("`nm': `ylab'", size(medium)) ///
                subtitle("Normal = `dtxt'. Dashed: main linear slope `lintxt'. Test above + below = 0: p = `ptxt'", size(small)) ///
                note("Added-variable plot (25 weighted bins; bars 95% CI clustered by county), net of the other component, M7 fixed effects, rain and controls.", size(vsmall))
            graph export "$GRAPHS/asym_`dn'_`m'_`y'.pdf", replace
            capture graph drop g_a g_b
            drop ry_a rx_a ry_b rx_b bin_a bin_b
        }
    }
}
postclose `hp'

preserve
    use `fp', clear
    save "$RESULTS/asym_cn_points.dta", replace
    use `fd', clear
    save "$RESULTS/asym_cn_deviation.dta", replace
restore

*------------------------------------------------------------------------------*
* 4. Excel
*------------------------------------------------------------------------------*
guide_sheet, file("$XL47") title("Heat above and below the county average (47)") ///
    lines("Summary: for each definition of the normal (county mean = CM, county-season mean = CS), heat measure and outcome, the coefficient on above (ten more units than normal), on below (ten fewer units than normal), their sum and the symmetry p value.|Deviation: distribution of the deviation of heat from the normal (weighted mean of above and below, share of observations above and below, SD).|Points: plotted points of the added-variable figures (side a = above panel, side b = below panel with x = minus the residual).|Notes: above = max(x - normal, 0), below = max(normal - x, 0), x = normal + above - below. Under CM the normal is constant within county and absorbed by the county fixed effect. Under CS it varies by season and enters as a third regressor. Model M7, weights Weight_origin, standard errors clustered by county. Coefficients are percentage points per ten units.")

preserve
    use "$RESULTS/lpm_asym_cn_results.dta", clear
    keep if substr(panel, 1, 1) == "2"
    gen str8 part = ""
    replace part = "above" if kind == "exposure" & strpos(term, "_above") > 0
    replace part = "below" if kind == "exposure" & strpos(term, "_below") > 0
    replace part = "test"  if kind == "test"
    keep if part != ""
    keep family panel outcome part coef se pvalue n_used
    bysort family panel outcome: egen long N = max(n_used)
    drop n_used
    reshape wide coef se pvalue, i(family panel outcome N) j(part) string
    rename coefabove   b_above
    rename seabove     se_above
    rename pvalueabove p_above
    rename coefbelow   b_below
    rename sebelow     se_below
    rename pvaluebelow p_below
    rename coeftest    F_symmetry
    rename pvaluetest  p_symmetry
    capture drop setest
    gen double sum_above_below = b_above + b_below
    gen byte ord = 1
    replace ord = 2 if outcome == "productive_exit"
    replace ord = 3 if outcome == "distress_exit"
    replace ord = 4 if outcome == "dest2"
    replace ord = 5 if outcome == "dest3"
    replace ord = 6 if outcome == "dest4"
    replace ord = 7 if outcome == "dest5"
    sort family panel ord
    drop ord
    order family panel outcome b_above se_above p_above b_below se_below p_below sum_above_below F_symmetry p_symmetry N
    export excel using "$XL47", sheet("Summary", modify) firstrow(variables)
restore

preserve
    use "$RESULTS/asym_cn_deviation.dta", clear
    export excel using "$XL47", sheet("Deviation", modify) firstrow(variables)
restore
preserve
    use "$RESULTS/asym_cn_points.dta", clear
    export excel using "$XL47", sheet("Points", modify) firstrow(variables)
restore

export_long, file("$XL47") sheet("All_long")
export_samples, file("$XL47") sheet("Samples")

di as result "47 done."
log close step
