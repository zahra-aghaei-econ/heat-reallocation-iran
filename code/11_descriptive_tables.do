*==============================================================================*
* 11_descriptive_tables.do
* Descriptive tables of the thesis that need only the model-ready data:
*   A  Transition matrix: five labor states at the origin and one year later
*      (weighted row percentages, all transitions of the run, as in Table 1 of step 10).
*   B  Sample construction flow of the agriculture-origin sample (raw and weighted N).
*   C  Weather descriptive statistics at the county-season-year level.
*   D  Correlations between related weather measures (same unit as C).
*   E  Sample composition by origin year (agriculture-origin sample).
*
* Output: output/<RUN_NAME>/tables/11_descriptive_tables.xlsx
*         output/<RUN_NAME>/results/desc_transition_matrix.dta
*                                   desc_sample_flow.dta
*                                   desc_weather_stats.dta
*                                   desc_weather_corr.dta
*                                   desc_sample_composition.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/11_descriptive_tables.log", text replace name(step)

global XL11 "$TABLES/11_descriptive_tables.xlsx"

load_model_data

local rain "rain100_s0 rain100_sq_s0"

*------------------------------------------------------------------------------*
* Common flags (the same conditions as prep_lpm_data and make_sample)
*------------------------------------------------------------------------------*
gen byte f_dest   = inrange(job_dest, 1, 5)
gen byte f_weight = (Weight_origin > 0) & !missing(Weight_origin)
gen byte f_geo    = !missing(mix_id) & !missing(province_year) & !missing(pair_id) ///
                    & inrange(season_origin, 1, 4) & $YEARS_IF
gen byte f_ctrl   = !missing(age_origin, age2_origin, sex_origin, marital_origin, urban_origin)

*------------------------------------------------------------------------------*
* A. Transition matrix (all origin states)
*------------------------------------------------------------------------------*
gen byte base_all = f_dest & f_weight & f_geo & weather_common_sample == 1
tempname hA
tempfile fA
postfile `hA' byte origin byte dest double share_pct long n_origin double wn_origin using `fA', replace
forvalues o = 1/5 {
    quietly count if base_all == 1 & job_origin == `o'
    local n = r(N)
    quietly summarize Weight_origin if base_all == 1 & job_origin == `o'
    local wn = r(sum)
    forvalues d = 1/5 {
        gen byte __d = (job_dest == `d') if base_all == 1 & job_origin == `o'
        quietly summarize __d [aweight = Weight_origin] if base_all == 1 & job_origin == `o'
        post `hA' (`o') (`d') (100 * r(mean)) (`n') (`wn')
        drop __d
    }
}
postclose `hA'
preserve
    use `fA', clear
    label define st 1 "Agriculture" 2 "Industry" 3 "Services" 4 "Unemployed" 5 "Inactive"
    label values origin st
    label values dest st
    save "$RESULTS/desc_transition_matrix.dta", replace
restore

*------------------------------------------------------------------------------*
* B. Sample construction flow (agriculture-origin sample)
*------------------------------------------------------------------------------*
gen byte c01 = 1
gen byte c02 = c01 & job_origin == 1
gen byte c03 = c02 & f_dest
gen byte c04 = c03 & f_weight
gen byte c05 = c04 & f_geo
gen byte c06 = c05 & weather_key_matched == 1
gen byte c07 = c06 & weather_common_sample == 1
gen byte c08 = c07 & f_ctrl & !missing(days35_10_s0, rain100_s0, rain100_sq_s0)
gen byte c09 = c07 & f_ctrl & !missing(heat35_10_s0, rain100_s0, rain100_sq_s0)
gen byte c10 = c06 & weather_localclim_sample == 1 & f_ctrl ///
               & !missing(countp90_10_s0, rain100_s0, rain100_sq_s0)
gen byte c11 = c07 & f_ctrl & !missing(gdd8_32_sine_s1, hdd32_sine_s1, gdd8_32_sine_s2, hdd32_sine_s2, rain100_lag13)
gen byte c12 = c07 & f_ctrl & !missing(gdd8_32_tmean_s1, hdd32_tmean_s1, gdd8_32_tmean_s2, hdd32_tmean_s2, rain100_lag13)
gen byte c13 = c08 & !missing(educ_origin)

local d01 "All transition rows (all origin states)"
local d02 "Agriculture at origin"
local d03 "Known destination state"
local d04 "Positive survey weight"
local d05 "Valid geography and time, origin year inside the run period"
local d06 "Matched to county-season weather"
local d07 "Common weather sample (at least 60 percent valid days)"
local d08 "Days35 estimation sample (controls and rain observed)"
local d09 "HeatDose35 estimation sample"
local d10 "Local-climatology sample"
local d11 "Degree-day sample (sine method, lags 1-2)"
local d12 "Degree-day sample (mean-temperature basis, lags 1-2)"
local d13 "Days35 sample with education observed"

tempname hB
tempfile fB
postfile `hB' byte step str80 description long n_raw double n_weighted double share_raw using `fB', replace
quietly count if c01 == 1
local n1 = r(N)
forvalues s = 1/13 {
    local sn : display %02.0f `s'
    quietly count if c`sn' == 1
    local n = r(N)
    quietly summarize Weight_origin if c`sn' == 1
    local wn = r(sum)
    post `hB' (`s') ("`d`sn''") (`n') (`wn') (100 * `n' / `n1')
}
postclose `hB'
preserve
    use `fB', clear
    save "$RESULTS/desc_sample_flow.dta", replace
restore
drop c01-c13

*------------------------------------------------------------------------------*
* C and D. Weather descriptives and correlations
* Unit: one county in one origin year and season (cells of the Days35 sample).
*------------------------------------------------------------------------------*
gen byte smp_w = f_dest & f_weight & f_geo & job_origin == 1 & weather_common_sample == 1 ///
                 & f_ctrl & !missing(days35_10_s0, rain100_s0, rain100_sq_s0)
egen byte cell_tag = tag(mix_id year_origin season_origin) if smp_w == 1

local wlist "days35_10_s0 heat35_10_s0 days37_10_s0 days40_10_s0 heat37_10_s0 heat40_10_s0 hdd35_tmean_10_s0"
local wlist "`wlist' countp80_10_s0 countp90_10_s0 countp95_10_s0 dosep80_10_s0 dosep90_10_s0 dosep95_10_s0"
local wlist "`wlist' gdd8_32_sine_s1 hdd32_sine_s1 gdd8_32_tmean_s1 hdd32_tmean_s1"
local wlist "`wlist' anom_tmean_s0 anom_tmean_sq_s0 tmean_s0 tmean_sq_s0"
local wlist "`wlist' bin_tmax_le20_s0 bin_tmax_20_25_s0 bin_tmax_25_30_s0 bin_tmax_30_35_s0 bin_tmax_35_40_s0 bin_tmax_gt40_s0"
local wlist "`wlist' rain100_s0 rain100_lag13"

tempname hC
tempfile fC
postfile `hC' str32 varname str80 label long n double mean double sd double min double p50 double max using `fC', replace
foreach v of local wlist {
    local lb : variable label `v'
    quietly summarize `v' if cell_tag == 1, detail
    post `hC' ("`v'") ("`lb'") (r(N)) (r(mean)) (r(sd)) (r(min)) (r(p50)) (r(max))
}
postclose `hC'
preserve
    use `fC', clear
    save "$RESULTS/desc_weather_stats.dta", replace
restore

* Pairs of related measures (a | b)
local pairs "days35_10_s0|heat35_10_s0 days37_10_s0|heat37_10_s0 days40_10_s0|heat40_10_s0"
local pairs "`pairs' countp90_10_s0|dosep90_10_s0 countp80_10_s0|countp90_10_s0 countp90_10_s0|countp95_10_s0"
local pairs "`pairs' dosep80_10_s0|dosep90_10_s0 dosep90_10_s0|dosep95_10_s0"
local pairs "`pairs' gdd8_32_sine_s1|hdd32_sine_s1 gdd8_32_sine_s2|hdd32_sine_s2"
local pairs "`pairs' gdd8_32_sine_s1|gdd8_32_tmean_s1 hdd32_sine_s1|hdd32_tmean_s1"
local pairs "`pairs' tmean_s0|rain100_s0 days35_10_s0|rain100_s0 heat35_10_s0|rain100_s0"

tempname hD
tempfile fD
postfile `hD' str32 var_a str32 var_b double corr long n byte flagged using `fD', replace
foreach p of local pairs {
    local a = substr("`p'", 1, strpos("`p'", "|") - 1)
    local b = substr("`p'", strpos("`p'", "|") + 1, .)
    quietly correlate `a' `b' if cell_tag == 1
    local r = r(rho)
    local n = r(N)
    post `hD' ("`a'") ("`b'") (`r') (`n') (abs(`r') >= 0.8)
}
postclose `hD'
preserve
    use `fD', clear
    save "$RESULTS/desc_weather_corr.dta", replace
restore
drop smp_w cell_tag

*------------------------------------------------------------------------------*
* E. Sample composition by origin year (agriculture-origin Days35 sample)
*------------------------------------------------------------------------------*
gen byte smp_c = f_dest & f_weight & f_geo & job_origin == 1 & weather_common_sample == 1 ///
                 & f_ctrl & !missing(days35_10_s0, rain100_s0, rain100_sq_s0)
gen byte rural   = (urban_origin == 1)
gen byte a1529   = inrange(age_origin, 15, 29)
gen byte a3044   = inrange(age_origin, 30, 44)
gen byte a4564   = inrange(age_origin, 45, 64)
gen byte a65p    = (age_origin >= 65) & !missing(age_origin)

tempname hE
tempfile fE
postfile `hE' int year double female double rural double age double a1529 double a3044 ///
    double a4564 double a65p long n_raw double n_weighted using `fE', replace
quietly levelsof year_origin if smp_c == 1, local(yrs)
foreach y of local yrs {
    local m ""
    foreach v in female_origin rural age_origin a1529 a3044 a4564 a65p {
        quietly summarize `v' [aweight = Weight_origin] if smp_c == 1 & year_origin == `y'
        local m `m' (`r(mean)')
    }
    quietly count if smp_c == 1 & year_origin == `y'
    local n = r(N)
    quietly summarize Weight_origin if smp_c == 1 & year_origin == `y'
    post `hE' (`y') `m' (`n') (r(sum))
}
* All years together (year = 0)
local m ""
foreach v in female_origin rural age_origin a1529 a3044 a4564 a65p {
    quietly summarize `v' [aweight = Weight_origin] if smp_c == 1
    local m `m' (`r(mean)')
}
quietly count if smp_c == 1
local n = r(N)
quietly summarize Weight_origin if smp_c == 1
post `hE' (0) `m' (`n') (r(sum))
postclose `hE'
preserve
    use `fE', clear
    save "$RESULTS/desc_sample_composition.dta", replace
restore

*------------------------------------------------------------------------------*
* Excel
*------------------------------------------------------------------------------*
guide_sheet, file("$XL11") title("Descriptive tables (11)") lines("Transition_matrix: weighted row percentages, origin state in rows, state one year later in columns. Sample: all transitions with known destination, positive weight, run years and matched weather.|Sample_flow: Agriculture-origin sample, raw and weighted N at each construction step. Steps 8-13 are the estimation samples of the models.|Weather_stats: Mean, SD, min, median and max over county-season-year cells (each cell counted once) in the Days35 estimation sample. Measures with /10 or /100 are in estimation units.|Weather_corr: Pearson correlations over the same cells. flagged = 1 if |r| is at least 0.80.|Sample_composition: Agriculture-origin Days35 sample by origin year (year 0 = all years). Shares and mean age use Weight_origin; rural = urban_origin of the data (1 = rural origin).")

foreach t in transition_matrix sample_flow weather_stats weather_corr sample_composition {
    preserve
        use "$RESULTS/desc_`t'.dta", clear
        local sh = proper(subinstr("`t'", "_", " ", .))
        local sh = subinstr("`sh'", " ", "_", .)
        export excel using "$XL11", sheet("`sh'", modify) firstrow(variables)
    restore
}

di as result "11 done."
log close step
