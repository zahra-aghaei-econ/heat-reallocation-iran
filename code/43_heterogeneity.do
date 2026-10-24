*==============================================================================*
* 43_heterogeneity.do
* A small pre-specified heterogeneity family with a multiple-testing adjustment.
*
* Outcome: exit from agriculture (percentage points). Model M7.
* Primary exposure: Days35 (tens). Secondary exposure (robustness family): HeatDose35.
*
*   H1  sex                female against male
*   H2  residence          rural against urban origin (urban_origin = 1 means RURAL)
*   H3  education          low / secondary / tertiary, one fixed sample with classifiable education
*   H4  historical climate cooler against hotter counties
*
* Education groups (from the value labels of educ_origin)
*   low        Primary, Lower_Secondary
*   secondary  Higher_Secondary, Pre_University
*   tertiary   Short_Cycle_Tertiary, Bachelors, Masters, Doctoral
*   missing and unclassified categories are left out of H3 only.
* Historical climate: the fixed county-season reference temperature (clim_tmean_ref_s, the
*   reference years of step 02) averaged over the four seasons; split at the unweighted
*   county median among the counties of the headline sample. The main effect is absorbed
*   by the county fixed effects, only the interaction with heat is identified.
*
* Inference: heterogeneity is judged by the direct interaction (joint Wald test for
*   education), not by comparing significance of subgroup slopes. The four tests of a
*   family are adjusted with Holm (family-wise error) and Benjamini-Hochberg (false discovery).
*
* Output: output/<RUN_NAME>/tables/43_heterogeneity.xlsx
*         output/<RUN_NAME>/results/het_slopes.dta, het_contrasts.dta, het_tests.dta,
*             het_climate.dta, het_educ_audit.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/43_heterogeneity.log", text replace name(step)

global XL43 "$TABLES/43_heterogeneity.xlsx"

prep_lpm_data
local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain')
make_sample, name(heat35) vars(heat35_10_s0 `rain')

get_spec 7
local absorb "`r(absorb)'"

*------------------------------------------------------------------------------*
* Moderators
*------------------------------------------------------------------------------*
* Education
local vl : value label educ_origin
if "`vl'" == "" {
    di as error "educ_origin has no value label; cannot group education safely."
    exit 459
}
decode educ_origin, gen(educ_label)
replace educ_label = strtrim(educ_label)
gen byte educ3 = .
replace educ3 = 1 if inlist(educ_label, "Primary", "Lower_Secondary")
replace educ3 = 2 if inlist(educ_label, "Higher_Secondary", "Pre_University")
replace educ3 = 3 if inlist(educ_label, "Short_Cycle_Tertiary", "Bachelors", "Masters", "Doctoral")
label define educ3lbl 1 "Low: primary or lower secondary" 2 "Secondary: higher secondary or pre-univ." ///
    3 "Tertiary", replace
label values educ3 educ3lbl

preserve
    gen byte in_days = smp_days35 == 1
    gen double w_days = Weight_origin * in_days
    collapse (count) n_all = Weight_origin (sum) n_days35 = in_days w_days35 = w_days (first) educ3, by(educ_label)
    gen str40 grouping = "Excluded or unclassified"
    replace grouping = "Low" if educ3 == 1
    replace grouping = "Secondary" if educ3 == 2
    replace grouping = "Tertiary" if educ3 == 3
    sort grouping educ_label
    save "$RESULTS/het_educ_audit.dta", replace
    export excel using "$XL43", sheet("Educ_audit", modify) firstrow(variables)
restore

* Historical climate
capture confirm variable clim_tmean_ref_s
if _rc {
    di as error "clim_tmean_ref_s is not in model_ready.dta. Re-run steps 02 and 03."
    exit 111
}
tempfile clim
preserve
    keep mix_id season_origin clim_tmean_ref_s smp_days35
    collapse (mean) ref = clim_tmean_ref_s (max) in_primary = smp_days35, by(mix_id season_origin)
    drop if missing(ref)
    bysort mix_id: gen byte nseas = _N
    collapse (mean) climate_temp = ref (max) in_primary (first) nseas, by(mix_id)
    replace climate_temp = . if nseas < 4
    quietly summarize climate_temp if in_primary == 1 & nseas == 4, detail
    local med = r(p50)
    di as result "County median reference temperature (headline counties): " %7.3f `med'
    gen byte hot_climate = (climate_temp >= `med') if in_primary == 1 & nseas == 4 & !missing(climate_temp)
    label define hotlbl 0 "Cooler historical climate" 1 "Hotter historical climate", replace
    label values hot_climate hotlbl
    quietly count if hot_climate == 0
    local ncool = r(N)
    quietly count if hot_climate == 1
    local nhot = r(N)
    di as result "Cooler counties: `ncool'   hotter counties: `nhot'"
    save "$RESULTS/het_climate.dta", replace
    save `clim'
restore
merge m:1 mix_id using `clim', keep(master match) keepusing(climate_temp hot_climate) nogen

gen byte smp_days35_ed = smp_days35 == 1 & !missing(educ3)
gen byte smp_heat35_ed = smp_heat35 == 1 & !missing(educ3)
gen byte smp_days35_cl = smp_days35 == 1 & !missing(hot_climate)
gen byte smp_heat35_cl = smp_heat35 == 1 & !missing(hot_climate)

*------------------------------------------------------------------------------*
* Regressions
*------------------------------------------------------------------------------*
tempname hs hc ht
tempfile fs fc ft
postfile `hs' str12 exposure byte mod_order str12 moderator byte grp_order str60 grp long n_used long n_clusters ///
    double slope double se double pvalue double ci_lo double ci_hi using `fs', replace
postfile `hc' str12 exposure byte mod_order str12 moderator str60 contrast long n_used ///
    double diff double se double pvalue double ci_lo double ci_hi using `fc', replace
postfile `ht' str12 exposure byte mod_order str12 moderator str60 hypothesis byte df double stat ///
    double raw_p long n_used using `ft', replace

local ctrl_all "c.age_origin c.age2_origin i.sex_origin i.marital_origin i.urban_origin"

foreach h in days35 heat35 {
    local nm "Days35"
    if "`h'" == "heat35" local nm "HeatDose35"
    local x "`h'_10_s0"

    * ---- H1 sex ----
    local smp "smp_`h'"
    quietly reghdfe pp_exit_agri c.`x'##i.female_origin `rain' c.age_origin c.age2_origin ///
        i.marital_origin i.urban_origin if `smp' == 1 [pweight = Weight_origin], ///
        absorb(`absorb') vce(cluster mix_id)
    local n = e(N)
    local nc = e(N_clust)
    local df = e(df_r)
    local tc = invttail(`df', 0.025)
    local lab0 "Male"
    local lab1 "Female"
    foreach g in 0 1 {
        if `g' == 0 quietly lincom _b[`x']
        else quietly lincom _b[`x'] + _b[1.female_origin#c.`x']
        local b = r(estimate)
        local s = r(se)
        post `hs' ("`nm'") (1) ("Sex") (`g') ("`lab`g''") (`n') (`nc') (`b') (`s') ///
            (`=2*ttail(`df', abs(`b'/`s'))') (`=`b'-`tc'*`s'') (`=`b'+`tc'*`s'')
    }
    quietly lincom _b[1.female_origin#c.`x']
    local b = r(estimate)
    local s = r(se)
    post `hc' ("`nm'") (1) ("Sex") ("Female minus male") (`n') (`b') (`s') ///
        (`=2*ttail(`df', abs(`b'/`s'))') (`=`b'-`tc'*`s'') (`=`b'+`tc'*`s'')
    quietly test 1.female_origin#c.`x'
    post `ht' ("`nm'") (1) ("Sex") ("Slope differs by sex") (1) (r(F)) (r(p)) (`n')

    * ---- H2 residence ----
    quietly reghdfe pp_exit_agri c.`x'##i.urban_origin `rain' c.age_origin c.age2_origin ///
        i.sex_origin i.marital_origin if `smp' == 1 [pweight = Weight_origin], ///
        absorb(`absorb') vce(cluster mix_id)
    local n = e(N)
    local nc = e(N_clust)
    local df = e(df_r)
    local tc = invttail(`df', 0.025)
    local lab0 "Urban origin"
    local lab1 "Rural origin"
    foreach g in 0 1 {
        if `g' == 0 quietly lincom _b[`x']
        else quietly lincom _b[`x'] + _b[1.urban_origin#c.`x']
        local b = r(estimate)
        local s = r(se)
        post `hs' ("`nm'") (2) ("Residence") (`g') ("`lab`g''") (`n') (`nc') (`b') (`s') ///
            (`=2*ttail(`df', abs(`b'/`s'))') (`=`b'-`tc'*`s'') (`=`b'+`tc'*`s'')
    }
    quietly lincom _b[1.urban_origin#c.`x']
    local b = r(estimate)
    local s = r(se)
    post `hc' ("`nm'") (2) ("Residence") ("Rural minus urban") (`n') (`b') (`s') ///
        (`=2*ttail(`df', abs(`b'/`s'))') (`=`b'-`tc'*`s'') (`=`b'+`tc'*`s'')
    quietly test 1.urban_origin#c.`x'
    post `ht' ("`nm'") (2) ("Residence") ("Slope differs by residence") (1) (r(F)) (r(p)) (`n')

    * ---- H3 education ----
    quietly reghdfe pp_exit_agri c.`x'##i.educ3 `rain' `ctrl_all' if smp_`h'_ed == 1 ///
        [pweight = Weight_origin], absorb(`absorb') vce(cluster mix_id)
    local n = e(N)
    local nc = e(N_clust)
    local df = e(df_r)
    local tc = invttail(`df', 0.025)
    foreach g in 1 2 3 {
        if `g' == 1 quietly lincom _b[`x']
        else quietly lincom _b[`x'] + _b[`g'.educ3#c.`x']
        local b = r(estimate)
        local s = r(se)
        local gl : label educ3lbl `g'
        post `hs' ("`nm'") (3) ("Education") (`g') ("`gl'") (`n') (`nc') (`b') (`s') ///
            (`=2*ttail(`df', abs(`b'/`s'))') (`=`b'-`tc'*`s'') (`=`b'+`tc'*`s'')
    }
    foreach g in 2 3 {
        quietly lincom _b[`g'.educ3#c.`x']
        local b = r(estimate)
        local s = r(se)
        local gl : label educ3lbl `g'
        post `hc' ("`nm'") (3) ("Education") ("`gl' minus low") (`n') (`b') (`s') ///
            (`=2*ttail(`df', abs(`b'/`s'))') (`=`b'-`tc'*`s'') (`=`b'+`tc'*`s'')
    }
    quietly testparm 2.educ3#c.`x' 3.educ3#c.`x'
    post `ht' ("`nm'") (3) ("Education") ("Slopes differ across the three groups") (2) (r(F)) (r(p)) (`n')

    * ---- H4 historical climate ----
    quietly reghdfe pp_exit_agri c.`x'##i.hot_climate `rain' `ctrl_all' if smp_`h'_cl == 1 ///
        [pweight = Weight_origin], absorb(`absorb') vce(cluster mix_id)
    local n = e(N)
    local nc = e(N_clust)
    local df = e(df_r)
    local tc = invttail(`df', 0.025)
    local lab0 "Cooler historical climate"
    local lab1 "Hotter historical climate"
    foreach g in 0 1 {
        if `g' == 0 quietly lincom _b[`x']
        else quietly lincom _b[`x'] + _b[1.hot_climate#c.`x']
        local b = r(estimate)
        local s = r(se)
        post `hs' ("`nm'") (4) ("Climate") (`g') ("`lab`g''") (`n') (`nc') (`b') (`s') ///
            (`=2*ttail(`df', abs(`b'/`s'))') (`=`b'-`tc'*`s'') (`=`b'+`tc'*`s'')
    }
    quietly lincom _b[1.hot_climate#c.`x']
    local b = r(estimate)
    local s = r(se)
    post `hc' ("`nm'") (4) ("Climate") ("Hotter minus cooler") (`n') (`b') (`s') ///
        (`=2*ttail(`df', abs(`b'/`s'))') (`=`b'-`tc'*`s'') (`=`b'+`tc'*`s'')
    quietly test 1.hot_climate#c.`x'
    post `ht' ("`nm'") (4) ("Climate") ("Slope differs by historical climate") (1) (r(F)) (r(p)) (`n')
}
postclose `hs'
postclose `hc'
postclose `ht'

preserve
    use `fs', clear
    save "$RESULTS/het_slopes.dta", replace
    export excel using "$XL43", sheet("Group_slopes", modify) firstrow(variables)
    use `fc', clear
    save "$RESULTS/het_contrasts.dta", replace
    export excel using "$XL43", sheet("Contrasts", modify) firstrow(variables)

    * Multiple-testing adjustment within each exposure (four tests)
    use `ft', clear
    bysort exposure (raw_p mod_order): gen int rk = _n
    bysort exposure (raw_p mod_order): gen int mm = _N
    gen double hs_ = min((mm - rk + 1) * raw_p, 1)
    gen double holm_p = hs_
    bysort exposure (rk): replace holm_p = max(hs_, holm_p[_n - 1]) if _n > 1
    replace holm_p = min(holm_p, 1)
    gen double bs_ = min(raw_p * mm / rk, 1)
    gen double bh_q = bs_
    gsort exposure -rk
    by exposure: replace bh_q = min(bs_, bh_q[_n - 1]) if _n > 1
    drop hs_ bs_ mm
    sort exposure mod_order
    save "$RESULTS/het_tests.dta", replace
    export excel using "$XL43", sheet("Tests", modify) firstrow(variables)
    list exposure moderator raw_p holm_p bh_q, noobs sepby(exposure)
restore

guide_sheet, file("$XL43") title("Pre-specified heterogeneity with multiplicity control (43)") lines("Group_slopes: effect of ten more days (Days35) or ten more degree-days (HeatDose35) on exit from agriculture, in percentage points, for each group; model M7.|Contrasts: direct differences between groups (interaction coefficients) with standard errors and p values.|Tests: one hypothesis per moderator (education is one joint test of two interaction terms), raw p value and p values adjusted within the four tests of an exposure: Holm (family-wise error) and Benjamini-Hochberg (false discovery rate).|Educ_audit: education categories and how they were grouped (low, secondary, tertiary, or excluded).|Notes: Education uses one fixed sample with classifiable education. The historical-climate split is at the unweighted county median of the four-season mean reference temperature among the counties of the headline sample. Rural origin means urban_origin = 1.")

di as result "43 done."
log close step
