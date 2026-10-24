*==============================================================================*
* 27_lpm_unemployed_rural.do
* Unemployed at the origin: does the heat response differ between urban and rural origin?
* Model M7 on the unemployment-origin sample (job_origin == 4). The heat measure enters
* once as x (slope for urban origin) and once as x times the rural-origin indicator
* (urban_origin == 1 means RURAL in the data). Rural slope = x + interaction (lincom).
* Nine outcomes (0/100): remain unemployed, exit unemployment, enter any employment,
* enter non-farm employment, enter agriculture, enter industry, enter services, enter
* inactivity, remain non-employed (unemployed or inactive).
* Heat measures: Days35 and HeatDose35 (tens), each in its own regression.
* The Holm adjustment of the rural-minus-urban p values (nine outcomes per panel) is
* done in tools/make_tex_tables_c.py.
*
* Output: output/<RUN_NAME>/tables/27_lpm_unemployed_rural.xlsx
*         output/<RUN_NAME>/results/lpm_unemp_rural_results.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/27_lpm_unemployed_rural.log", text replace name(step)

global XL27 "$TABLES/27_lpm_unemployed_rural.xlsx"

load_model_data
keep if job_origin == 4 & inrange(job_dest, 1, 5) ///
    & (Weight_origin > 0) & !missing(Weight_origin) ///
    & !missing(mix_id) & !missing(province_year) & !missing(pair_id) ///
    & inrange(season_origin, 1, 4) & $YEARS_IF ///
    & weather_common_sample == 1 ///
    & !missing(age_origin, age2_origin, sex_origin, marital_origin, urban_origin) ///
    & !missing(days35_10_s0, heat35_10_s0, rain100_s0, rain100_sq_s0)
count
di as result "Unemployment-origin sample: " r(N)

gen byte rural = (urban_origin == 1)
gen double days35_rural = days35_10_s0 * rural
gen double heat35_rural = heat35_10_s0 * rural

* Outcomes
gen byte u_remain   = 100 * (job_dest == 4)
gen byte u_exit     = 100 * (job_dest != 4)
gen byte u_anyemp   = 100 * inlist(job_dest, 1, 2, 3)
gen byte u_nonfarm  = 100 * inlist(job_dest, 2, 3)
gen byte u_agri     = 100 * (job_dest == 1)
gen byte u_ind      = 100 * (job_dest == 2)
gen byte u_serv     = 100 * (job_dest == 3)
gen byte u_inact    = 100 * (job_dest == 5)
gen byte u_nonemp   = 100 * inlist(job_dest, 4, 5)
local outs "u_remain u_exit u_anyemp u_nonfarm u_agri u_ind u_serv u_inact u_nonemp"

get_spec 7
local ctrl   "`r(controls)'"
local absorb "`r(absorb)'"
local rain   "rain100_s0 rain100_sq_s0"

tempname h
tempfile f
postfile `h' str12 measure str12 outcome long n_obs long n_clusters ///
    double urban_b double urban_se double urban_p ///
    double int_b double int_se double int_p ///
    double rural_b double rural_se double rural_p double share_rural using `f', replace

quietly summarize rural [aweight = Weight_origin]
local shr = r(mean)

foreach m in days35 heat35 {
    local nm "Days35"
    if "`m'" == "heat35" local nm "HeatDose35"
    local x "`m'_10_s0"
    local xr "`m'_rural"
    foreach y of local outs {
        quietly reghdfe `y' `x' `xr' `rain' `ctrl' [pweight = Weight_origin], ///
            absorb(`absorb') vce(cluster mix_id)
        local n  = e(N)
        local nc = e(N_clust)
        local ub = _b[`x']
        local us = _se[`x']
        local up = 2 * ttail(e(df_r), abs(`ub' / `us'))
        local ib = _b[`xr']
        local is = _se[`xr']
        local ip = 2 * ttail(e(df_r), abs(`ib' / `is'))
        quietly lincom `x' + `xr'
        local rb = r(estimate)
        local rs = r(se)
        local rp = 2 * ttail(e(df_r), abs(`rb' / `rs'))
        post `h' ("`nm'") ("`y'") (`n') (`nc') (`ub') (`us') (`up') (`ib') (`is') (`ip') ///
            (`rb') (`rs') (`rp') (`shr')
        di as text "  [`nm' | `y']  urban " %7.3f `ub' "  rural " %7.3f `rb' "  diff p = " %6.3f `ip'
    }
}
postclose `h'
preserve
    use `f', clear
    save "$RESULTS/lpm_unemp_rural_results.dta", replace
    gen str4 su = cond(urban_p < 0.01, "***", cond(urban_p < 0.05, "**", cond(urban_p < 0.10, "*", "")))
    gen str4 sr = cond(rural_p < 0.01, "***", cond(rural_p < 0.05, "**", cond(rural_p < 0.10, "*", "")))
    gen str4 si = cond(int_p < 0.01, "***", cond(int_p < 0.05, "**", cond(int_p < 0.10, "*", "")))
    guide_sheet, file("$XL27") title("Unemployment-origin transitions: urban and rural heat slopes (27)") lines("Results: one row per heat measure and outcome. urban_* = heat slope for urban origin, int_* = interaction (rural minus urban), rural_* = rural slope (x + interaction, lincom). Outcomes are 0/100 so coefficients are percentage points per ten units of the heat measure.|Notes: Model M7 on people unemployed at the origin; weights Weight_origin; standard errors clustered by county. The Holm-adjusted p value is computed in the python step.")
    export excel using "$XL27", sheet("Results", modify) firstrow(variables)
restore

di as result "27 done."
log close step
