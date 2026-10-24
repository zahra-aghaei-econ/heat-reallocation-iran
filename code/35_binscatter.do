*==============================================================================*
* 35_binscatter.do
* Binned scatter plots of the heat effect (model M7).
* Both the outcome and the heat variable are residualized on rain, the individual controls
* and all fixed effects of M7 (Frisch-Waugh-Lovell). The heat variable is then cut into
* 50 groups of equal weighted size and each point is the group mean of the residualized
* outcome (the sample mean of the outcome is added back) against the group mean of the
* residualized heat variable (centred at zero: the heat that the fixed effects and controls
* cannot explain). Bars are 95 percent confidence intervals (standard errors clustered by
* county). The solid line has the slope of the M7 coefficient; the dashed curve is a
* quadratic fit through the 50 points (weighted by group size) to show curvature.
* Observations are weighted with Weight_origin.
*
* Output: output/<RUN_NAME>/graphs/bs_fwl_<measure>_<outcome>.pdf
*         output/<RUN_NAME>/results/binscatter_points.dta (all plotted points)
*         output/<RUN_NAME>/tables/35_binscatter.xlsx (plotted points and slopes)
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/35_binscatter.log", text replace name(step)

global XL35 "$TABLES/35_binscatter.xlsx"
local NBINS 50

prep_lpm_data

local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain')
make_sample, name(heat35) vars(heat35_10_s0 `rain')

get_spec 7
local ctrl   "`r(controls)'"
local absorb "`r(absorb)'"

tempfile pts
capture postclose bp
postfile bp str12 measure str20 outcome byte bin double x double y double ci_lo double ci_hi ///
    double n_bin double slope using `pts', replace

foreach m in days35 heat35 {
    local x "`m'_10_s0"
    local xl "Days with Tmax of 35C or more (tens of days), net of fixed effects and controls"
    if "`m'" == "heat35" local xl "Heat dose above 35C (tens of degree-days), net of fixed effects and controls"

    * Residualize the heat variable on rain, controls and fixed effects
    quietly reghdfe `x' `rain' `ctrl' if smp_`m' == 1 [pweight = Weight_origin], ///
        absorb(`absorb') resid(rx)
    xtile bin_fwl = rx [pweight = Weight_origin] if smp_`m' == 1, nq(`NBINS')

    foreach y of global OUTCOMES {
        local ylab : variable label pp_`y'
        quietly reghdfe pp_`y' `rain' `ctrl' if smp_`m' == 1 [pweight = Weight_origin], ///
            absorb(`absorb') resid(ry)
        quietly summarize pp_`y' [aw = Weight_origin] if smp_`m' == 1
        local ybar = r(mean)

        * Slope (equals the M7 coefficient) and bin means with clustered standard errors
        quietly regress ry rx if smp_`m' == 1 [pweight = Weight_origin], vce(cluster mix_id)
        local slope = _b[rx]
        quietly regress ry ibn.bin_fwl if smp_`m' == 1 [pweight = Weight_origin], noconstant vce(cluster mix_id)
        matrix bb = e(b)
        matrix VV = e(V)

        preserve
            keep if smp_`m' == 1
            egen double n_bin = total(1), by(bin_fwl)
            collapse (mean) xa = rx n_bin [aw = Weight_origin], by(bin_fwl)
            gen double yb = .
            gen double se = .
            forvalues i = 1/`=_N' {
                replace yb = bb[1, `i']           in `i'
                replace se = sqrt(VV[`i', `i'])   in `i'
            }
            gen double ya    = yb + `ybar'
            gen double ci_lo = ya - 1.96 * se
            gen double ci_hi = ya + 1.96 * se
            gen double fit   = `ybar' + `slope' * xa
            forvalues i = 1/`=_N' {
                post bp ("`m'") ("`y'") (bin_fwl[`i']) (xa[`i']) (ya[`i']) (ci_lo[`i']) (ci_hi[`i']) (n_bin[`i']) (`slope')
            }
            twoway (rcap ci_lo ci_hi xa, lcolor(gs11) lwidth(thin)) ///
                   (scatter ya xa, msymbol(O) msize(small) mcolor(navy)) ///
                   (line fit xa, lcolor(maroon) lwidth(medthick)) ///
                   (qfit ya xa [aweight = n_bin], lcolor(forest_green) lpattern(dash) lwidth(medthin)), ///
                xtitle("`xl'", size(small)) ytitle("`ylab', adjusted", size(small)) ///
                legend(order(2 "Bin mean (95% CI)" 3 "Linear fit (M7 slope)" 4 "Quadratic fit") ///
                    rows(1) position(6) size(small) region(lstyle(none))) ///
                graphregion(color(white)) ylabel(, angle(0) grid)
            graph export "$GRAPHS/bs_fwl_`m'_`y'.pdf", replace
        restore
        drop ry
    }
    drop rx bin_fwl
}
postclose bp

use `pts', clear
save "$RESULTS/binscatter_points.dta", replace

guide_sheet, file("$XL35") title("Binned scatter plots (model M7)") lines("Points: Every plotted point. bin = group of the residualized heat variable (50 equal-sized groups); x = mean residualized heat; y = mean residualized outcome plus the sample mean; ci_lo and ci_hi = 95 percent interval (clustered by county); n_bin = observations; slope = M7 coefficient (the line in the figure).|Notes: Outcomes are percentage points. Residualized means the part not explained by rain, the individual controls and the M7 fixed effects. The old raw-unit plots (bs_raw_*) were removed because the fixed effects were taken out of the outcome but not out of the heat variable.")
export excel using "$XL35", sheet("Points", modify) firstrow(variables)

di as result "35 done."
log close step
