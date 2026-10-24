*==============================================================================*
* 29_spatial_inference.do
* Spatially robust inference for the headline model M7 (point estimates do not change).
* Exposures: Days35 and HeatDose35 (tens). Outcomes: the seven headline outcomes.
*
* Standard errors reported for the same coefficient:
*   1  county cluster (the baseline of the paper)
*   2  two-way cluster: county and province-by-year
*   3  Conley-type spatial HAC, Bartlett kernel, cutoff 100 km
*   4  same, 200 km
*   5  same, 300 km
*
* How the spatial HAC is built. Individual scores of the Frisch-Waugh-Lovell regression
* (weight x residualised heat x full-model residual) are summed to county x year x season
* cells. The county-cluster "meat" (arbitrary dependence inside a county over all years and
* seasons) is kept. For every pair of different counties in the same year and season that
* are closer than the cutoff, the cross term is added with the weight 1 - d/cutoff, where
* d is the great-circle distance between the county centroids. The raw score variance is
* scaled so that it reproduces the county-cluster standard error of reghdfe exactly, and
* the same factor is applied to the spatial variance. Conley p values and confidence
* intervals use the normal distribution; the clustered ones use the t distribution.
*
* Input needed: lookups/county_centroids_1385.dta (centroids of the 1385 counties).
* Output: output/<RUN_NAME>/tables/29_spatial_inference.xlsx
*         output/<RUN_NAME>/results/spatial_inference_results.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/29_spatial_inference.log", text replace name(step)

global XL29 "$TABLES/29_spatial_inference.xlsx"

capture confirm file "$LOOKUP/county_centroids_1385.dta"
if _rc {
    di as error "Missing $LOOKUP/county_centroids_1385.dta (county centroids). Copy it into the lookups folder."
    exit 601
}

*------------------------------------------------------------------------------*
* Mata: cross-county spatial terms
*------------------------------------------------------------------------------*
capture mata: mata drop spat_add()
mata:
real rowvector spat_add(real colvector s, real colvector t, real colvector lat, ///
                        real colvector lon, real rowvector cut)
{
    real matrix info
    real rowvector out
    real scalar g, i, j, m, a, b, dlat, dlon, aa, cc, d, w, R, rad

    out  = J(1, cols(cut), 0)
    info = panelsetup(t, 1)
    R    = 6371.0088
    rad  = pi() / 180

    for (g = 1; g <= rows(info); g++) {
        a = info[g, 1]
        b = info[g, 2]
        if (b > a) {
            for (i = a; i <= b - 1; i++) {
                for (j = i + 1; j <= b; j++) {
                    dlat = (lat[j] - lat[i]) * rad
                    dlon = (lon[j] - lon[i]) * rad
                    aa = sin(dlat / 2)^2 + cos(lat[i] * rad) * cos(lat[j] * rad) * sin(dlon / 2)^2
                    if (aa < 0) aa = 0
                    if (aa > 1) aa = 1
                    cc = 2 * asin(sqrt(aa))
                    d  = R * cc
                    for (m = 1; m <= cols(cut); m++) {
                        if (d < cut[m]) {
                            w = 1 - d / cut[m]
                            out[m] = out[m] + 2 * w * s[i] * s[j]
                        }
                    }
                }
            }
        }
    }
    return(out)
}
end

*------------------------------------------------------------------------------*
* Data and samples
*------------------------------------------------------------------------------*
prep_lpm_data
local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain')
make_sample, name(heat35) vars(heat35_10_s0 `rain')

merge m:1 mix4_origin using "$LOOKUP/county_centroids_1385.dta", ///
    keepusing(latitude longitude shared_geometry) keep(master match) gen(_m_geo)
quietly count if (smp_days35 == 1 | smp_heat35 == 1) & _m_geo != 3
if r(N) > 0 {
    di as error "Some estimation observations have no county centroid: " r(N)
    exit 459
}

get_spec 7
local ctrl   "`r(controls)'"
local absorb "`r(absorb)'"

tempname hr
tempfile fr
postfile `hr' str12 exposure byte outcome_order str24 outcome byte method_id str40 method ///
    double cutoff_km double coef double se double stat double pvalue double ci_lo double ci_hi ///
    long n_used long n_clusters double calib_factor using `fr', replace

local zcrit = invnormal(0.975)
local nexp = 0
foreach m in days35 heat35 {
    local nexp = `nexp' + 1
    local ename "Days35"
    if "`m'" == "heat35" local ename "HeatDose35"
    local X "`m'_10_s0"
    di as text _n "=============== Exposure: `ename' ==============="

    * Lock the estimation sample with the first outcome
    quietly reghdfe pp_exit_agri `X' `rain' `ctrl' if smp_`m' == 1 [pweight = Weight_origin], ///
        absorb(`absorb') vce(cluster mix_id)
    capture drop m7s
    gen byte m7s = e(sample)
    local G_M7 = e(N_clust)
    local N_M7 = e(N)
    di as result "`ename': N = `N_M7', county clusters = `G_M7', coefficient on exit = " %9.5f _b[`X']

    * Residualise the heat measure once (Frisch-Waugh-Lovell)
    capture drop xres
    quietly reghdfe `X' `rain' `ctrl' if m7s == 1 [pweight = Weight_origin], ///
        absorb(`absorb') vce(cluster mix_id) residuals(xres)
    quietly summarize Weight_origin if m7s == 1, meanonly
    local wmean = r(mean)
    capture drop wn
    gen double wn = Weight_origin / `wmean' if m7s == 1
    quietly gen double bread_i = wn * xres^2 if m7s == 1
    quietly summarize bread_i if m7s == 1, meanonly
    local BREAD = r(mean) * r(N)
    drop bread_i

    local o = 0
    foreach y of global OUTCOMES {
        local o = `o' + 1
        capture drop ehat
        quietly reghdfe pp_`y' `X' `rain' `ctrl' if m7s == 1 [pweight = Weight_origin], ///
            absorb(`absorb') vce(cluster mix_id) residuals(ehat)
        local b    = _b[`X']
        local se_c = _se[`X']
        local df_c = e(df_r)
        local n    = e(N)
        local g    = e(N_clust)
        local t_c  = `b' / `se_c'
        local p_c  = 2 * ttail(`df_c', abs(`t_c'))
        local tc   = invttail(`df_c', 0.025)

        quietly reghdfe pp_`y' `X' `rain' `ctrl' if m7s == 1 [pweight = Weight_origin], ///
            absorb(`absorb') vce(cluster mix_id province_year)
        local se_2 = _se[`X']
        local df_2 = e(df_r)
        local t_2  = `b' / `se_2'
        local p_2  = 2 * ttail(`df_2', abs(`t_2'))
        local tc2  = invttail(`df_2', 0.025)

        * Scores summed to county x year x season cells
        preserve
            keep if m7s == 1
            gen double score = wn * xres * ehat
            keep mix_id year_origin season_origin latitude longitude score
            collapse (sum) cell = score, by(mix_id year_origin season_origin latitude longitude)
            gen long tt = 10 * year_origin + season_origin
            bysort mix_id: egen double cscore = total(cell)
            egen byte ctag = tag(mix_id)
            gen double csq = cscore^2 if ctag
            quietly summarize csq, meanonly
            local MEAT_C = r(sum)
            sort tt mix_id
            mata: st_matrix("SPADD", spat_add(st_data(., "cell"), st_data(., "tt"), ///
                st_data(., "latitude"), st_data(., "longitude"), (100, 200, 300)))
        restore

        local VRAW  = `MEAT_C' / (`BREAD'^2)
        local CALIB = (`se_c'^2) / `VRAW'

        post `hr' ("`ename'") (`o') ("`y'") (1) ("County cluster (baseline)") (.) (`b') (`se_c') ///
            (`t_c') (`p_c') (`=`b'-`tc'*`se_c'') (`=`b'+`tc'*`se_c'') (`n') (`g') (`CALIB')
        post `hr' ("`ename'") (`o') ("`y'") (2) ("Two-way: county and province-year") (.) (`b') (`se_2') ///
            (`t_2') (`p_2') (`=`b'-`tc2'*`se_2'') (`=`b'+`tc2'*`se_2'') (`n') (`g') (.)
        local k = 0
        foreach c in 100 200 300 {
            local k = `k' + 1
            local V = `CALIB' * (`MEAT_C' + el(SPADD, 1, `k')) / (`BREAD'^2)
            if `V' > 0 {
                local se_s = sqrt(`V')
                local z    = `b' / `se_s'
                local p_s  = 2 * (1 - normal(abs(`z')))
                local lo   = `b' - `zcrit' * `se_s'
                local hi   = `b' + `zcrit' * `se_s'
            }
            else {
                local se_s = .
                local z = .
                local p_s = .
                local lo = .
                local hi = .
            }
            post `hr' ("`ename'") (`o') ("`y'") (`=2+`k'') ("Conley-type HAC, `c' km") (`c') (`b') (`se_s') ///
                (`z') (`p_s') (`lo') (`hi') (`n') (`g') (`CALIB')
        }
        di as text "  `ename' | `y': b=" %8.4f `b' "  se county=" %7.4f `se_c' "  two-way=" %7.4f `se_2' ///
            "  hac100=" %7.4f sqrt(`CALIB' * (`MEAT_C' + el(SPADD, 1, 1)) / (`BREAD'^2)) ///
            "  hac300=" %7.4f sqrt(`CALIB' * (`MEAT_C' + el(SPADD, 1, 3)) / (`BREAD'^2))
    }
    drop m7s xres wn
}
postclose `hr'

use `fr', clear
save "$RESULTS/spatial_inference_results.dta", replace
guide_sheet, file("$XL29") title("Spatially robust inference, model M7 (29)") lines("Results: one row per exposure, outcome and inference method. method 1 = county cluster (baseline), 2 = two-way cluster county and province-year, 3 to 5 = Conley-type spatial HAC with Bartlett kernel and cutoffs 100, 200 and 300 km.|Coefficients are identical across methods; only the standard error, p value and 95 percent interval change. Percentage points per ten units of the heat measure.|The spatial variance keeps arbitrary dependence inside a county over all years and seasons and adds cross-county terms within the same year and season for county centroids closer than the cutoff. It is scaled to reproduce the county-cluster standard error of reghdfe, and uses normal critical values.|Notes: Model M7, weights Weight_origin, headline samples of step 20.")
export excel using "$XL29", sheet("Results", modify) firstrow(variables)

di as result "29 done."
log close step
