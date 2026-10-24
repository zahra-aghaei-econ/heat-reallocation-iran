*==============================================================================*
* 31_lpm_regions.do
* Does the effect of heat differ across agro-climatic regions?
* Six regions (crosswalk in lookups/agro_region_crosswalk_1385.dta):
*   1 Caspian rice          2 Highland cereal        3 Plateau cereal and orchard
*   4 Khorasan saffron/wheat 5 Warm lowland wheat    6 Hot arid date belt
*
* Two ways, both with the headline model M7 and all seven outcomes:
*   A. One pooled regression with a separate heat slope for each region
*      (rain controls and fixed effects are common). A test checks that the six
*      slopes are equal.
*   B. A separate regression for each region (everything can differ by region).
*
* Output: output/<RUN_NAME>/tables/31_lpm_regions.xlsx
*         output/<RUN_NAME>/results/lpm_regions_results.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/31_lpm_regions.log", text replace name(step)

global XL31 "$TABLES/31_lpm_regions.xlsx"

prep_lpm_data
add_region

local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain' agro_region)
make_sample, name(heat35) vars(heat35_10_s0 `rain' agro_region)

* Region-specific heat variables and region samples
foreach m in days35 heat35 {
    local jt_`m' ""
    local terms_`m' ""
    forvalues r = 1/6 {
        gen double `m'_r`r' = `m'_10_s0 * (agro_region == `r')
        label var `m'_r`r' "`m' x region `r'"
        local terms_`m' "`terms_`m'' `m'_r`r'"
        gen byte smp_`m'_R`r' = smp_`m' == 1 & agro_region == `r'
        global SAMPLE_LIST "$SAMPLE_LIST `m'_R`r'"
    }
    local jt_`m' "`m'_r1 = `m'_r2 = `m'_r3 = `m'_r4 = `m'_r5 = `m'_r6"
}

open_results, file("$RESULTS/lpm_regions_results.dta")

foreach y of global OUTCOMES {
    foreach m in days35 heat35 {
        local fam "Regions_Days35"
        if "`m'" == "heat35" local fam "Regions_HeatDose35"

        * A. pooled, region-specific slopes
        run_lpm, family("`fam'") panel("A_pooled_region_slopes") model(7) outcome(`y') ///
            wvars("`terms_`m'' `rain'") terms("`terms_`m''") rainterms("`rain'") ///
            sample(`m') jtest("`jt_`m''")

        * B. separate regression for each region
        forvalues r = 1/6 {
            run_lpm, family("`fam'") panel("B_separate_region`r'") model(7) outcome(`y') ///
                wvars("`m'_10_s0 `rain'") terms("`m'_10_s0") rainterms("`rain'") sample(`m'_R`r')
        }
    }
}
close_results

*------------------------------------------------------------------------------*
* Region profile: size, climate and exit rate of each region
*------------------------------------------------------------------------------*
tempfile prof
capture postclose pf
postfile pf byte region str30 region_name long n_obs long n_counties double mean_days35 ///
    double mean_heat35 double mean_rain100 double exit_rate_pct using `prof', replace
forvalues r = 1/6 {
    local nm : label region_lbl `r'
    quietly count if smp_days35 == 1 & agro_region == `r'
    local n = r(N)
    tempvar tag
    quietly egen byte `tag' = tag(mix_id) if smp_days35 == 1 & agro_region == `r'
    quietly count if `tag' == 1
    local nc = r(N)
    drop `tag'
    quietly summarize days35_10_s0 [aw = Weight_origin] if smp_days35 == 1 & agro_region == `r'
    local md = r(mean)
    quietly summarize heat35_10_s0 [aw = Weight_origin] if smp_days35 == 1 & agro_region == `r'
    local mh = r(mean)
    quietly summarize rain100_s0 [aw = Weight_origin] if smp_days35 == 1 & agro_region == `r'
    local mr = r(mean)
    quietly summarize exit_agri [aw = Weight_origin] if smp_days35 == 1 & agro_region == `r'
    local ex = 100 * r(mean)
    post pf (`r') ("`nm'") (`n') (`nc') (`md') (`mh') (`mr') (`ex')
}
postclose pf

*------------------------------------------------------------------------------*
* Excel
*------------------------------------------------------------------------------*
guide_sheet, file("$XL31") title("Heterogeneity by agro-climatic region (model M7)") lines("Days35_regions: Effect of ten more hot days. Panel A: one pooled regression with a separate slope for each region (term names end in _r1 to _r6). Panel B: a separate regression for each region (panel B_separate_regionK).|HeatDose35_regions: Same for heat dose.|Test_equal_slopes: F test that the six pooled slopes of panel A are equal (the p-value is shown in each outcome column).|Region_profile: Observations, counties, mean weather and exit rate by region.|All_long: Every regression, one row per term.|Samples: Sample sizes.|Regions: 1 Caspian rice. 2 Highland cereal. 3 Plateau cereal and orchard. 4 Khorasan saffron and wheat. 5 Warm lowland wheat. 6 Hot arid date belt.")
export_wide, file("$XL31") sheet("Days35_regions") family("Regions_Days35")
export_wide, file("$XL31") sheet("HeatDose35_regions") family("Regions_HeatDose35")
export_wide, file("$XL31") sheet("Test_equal_slopes") family("Regions_Days35") kind("test")
export_wide, file("$XL31") sheet("Test_equal_slopes_Heat") family("Regions_HeatDose35") kind("test")
export_long, file("$XL31") sheet("All_long")
export_samples, file("$XL31") sheet("Samples")
preserve
    use `prof', clear
    export excel using "$XL31", sheet("Region_profile", modify) firstrow(variables)
restore

di as result "31 done."
log close step
