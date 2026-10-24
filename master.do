*==============================================================================*
* master.do
* Runs the whole project in order.
*
* How to use:
*   1. Put the two raw files in the data folder, with these names:
*        data/lfs.dta            (labor force survey)
*        data/weather_daily.dta  (daily weather by county)
*   2. Set ROOT below (or start Stata in the folder that contains this file).
*   3. Choose RUN_NAME. Then run this file.
*   4. After Stata, run the Python scripts in tools/ (see README.md).
*
* Each step has a switch (1 = run, 0 = skip). The data steps (01-03) only need
* to be run once. They do not depend on RUN_NAME.
*==============================================================================*

clear all
set more off

*------------------------------------------------------------------------------*
* 1. Things you may change
*------------------------------------------------------------------------------*
* Either write the full path of this folder here, for example
*   global ROOT "C:/projects/heat_reallocation_iran"
* or leave it empty and first move Stata into this folder (File > Change Working
* Directory, or: cd "C:/projects/heat_reallocation_iran"). Use forward slashes.
global ROOT ""
if "$ROOT" == "" global ROOT "`c(pwd)'"
capture confirm file "$ROOT/code/00_setup.do"
if _rc {
    di as error "ROOT is not the folder that contains master.do: $ROOT"
    exit 601
}

* run1_old_period_pairFE : old years, with pair fixed effects (only to check the thesis numbers)
* run2_old_period        : old years, no pair fixed effects
* run3_new_period        : new years, no pair fixed effects
global RUN_NAME "run3_new_period"

* Employed people without a sector code (about 2.5 percent from 1401):
*   1 = counted as services (the version reported in the paper; the output folder
*       gets the ending _svc, so this run writes to output/run3_new_period_svc)
*   0 = left out (robustness version; output/run3_new_period)
global UNCLASSIFIED_AS_SERVICES 1

* Switches (1 = run, 0 = skip). All are 1 for a full reproduction.
* Steps 01-03 build the data files in intermediate/ and are needed once. Later steps
* only read intermediate/ and the results of earlier steps, so any step can be rerun alone.
local RUN_01_PANEL    = 1
local RUN_02_WEATHER  = 1
local RUN_03_MERGE    = 1
local RUN_10_SUMMARY = 1
local RUN_11_DESCRIPTIVE = 1
local RUN_20_LPM_MAIN = 1
local RUN_21_LADDER = 1
local RUN_22_FAMILIES = 1
local RUN_23_EDUCATION = 1
local RUN_24_SATURATED = 1
local RUN_25_ALLORIGIN = 1
local RUN_26_TIMING_RAIN = 1
local RUN_27_UNEMP_RURAL = 1
local RUN_28_LINKAGE = 1
local RUN_29_SPATIAL = 1
local RUN_42_ATTRITION = 1
local RUN_43_HETEROGENEITY = 1
local RUN_44_IDVAR = 1
local RUN_45_BALANCE = 1
local RUN_46_COUNTY = 1
local RUN_47_ASYM_COUNTYNORMAL = 1
local RUN_30_TIMESERIES = 1
local RUN_31_REGIONS = 1
local RUN_32_PERIODS = 1
local RUN_33_ASYMMETRY = 1
local RUN_34_ASINH = 1
local RUN_35_BINSCATTER = 1
local RUN_36_BREAKS = 1
local RUN_37_RAWRATES = 1
local RUN_38_PERIODS = 1
local RUN_39_WEATHERTREND = 1
local RUN_40_CHECK_DATA = 1
local RUN_41_CHECK_WEATHER = 1
local RUN_50_TEXTABLES = 1
local RUN_60_FIGURES = 1
local RUN_61_MAPS = 1
* Step 22 only: quick test with one outcome (1 = yes). Leave empty for the full run.
global PILOT_22 ""
* Step 42: continuation propensity method: "logit" (thesis version, heavy) or "lpm" (fast fallback)
global PROP_METHOD "logit"

*------------------------------------------------------------------------------*
* 2. Settings, then the steps
*------------------------------------------------------------------------------*
do "$ROOT/code/00_setup.do"

capture log close master
log using "$LOGS/master.log", text replace name(master)

if `RUN_01_PANEL'   do "$CODE/01_build_individual_panel.do"
if `RUN_02_WEATHER' do "$CODE/02_build_weather.do"
if `RUN_03_MERGE'   do "$CODE/03_merge_model_ready.do"
if `RUN_10_SUMMARY' do "$CODE/10_summary_stats.do"
if `RUN_11_DESCRIPTIVE' do "$CODE/11_descriptive_tables.do"
if `RUN_20_LPM_MAIN' do "$CODE/20_lpm_main.do"
if `RUN_21_LADDER' do "$CODE/21_lpm_ladder.do"
if `RUN_22_FAMILIES' do "$CODE/22_lpm_weather_families.do"
if `RUN_23_EDUCATION' do "$CODE/23_lpm_education.do"
if `RUN_24_SATURATED' do "$CODE/24_lpm_saturated_fe.do"
if `RUN_25_ALLORIGIN' do "$CODE/25_lpm_allorigin.do"
if `RUN_26_TIMING_RAIN' do "$CODE/26_lpm_timing_rain_fitted.do"
if `RUN_27_UNEMP_RURAL' do "$CODE/27_lpm_unemployed_rural.do"
if `RUN_28_LINKAGE' do "$CODE/28_lpm_person_linkage.do"
if `RUN_29_SPATIAL' do "$CODE/29_spatial_inference.do"
if `RUN_30_TIMESERIES' do "$CODE/30_timeseries_shares.do"
if `RUN_31_REGIONS' do "$CODE/31_lpm_regions.do"
if `RUN_32_PERIODS' do "$CODE/32_lpm_periods.do"
if `RUN_33_ASYMMETRY' do "$CODE/33_lpm_asymmetry.do"
if `RUN_34_ASINH' do "$CODE/34_lpm_asinh.do"
if `RUN_35_BINSCATTER' do "$CODE/35_binscatter.do"
if `RUN_36_BREAKS' do "$CODE/36_lpm_county_breaks.do"
if `RUN_37_RAWRATES' do "$CODE/37_raw_exit_rates.do"
if `RUN_38_PERIODS' do "$CODE/38_period_interactions.do"
if `RUN_39_WEATHERTREND' do "$CODE/39_weather_trend.do"
if `RUN_40_CHECK_DATA' do "$CODE/40_check_data.do"
if `RUN_41_CHECK_WEATHER' do "$CODE/41_check_weather.do"
if `RUN_42_ATTRITION' do "$CODE/42_attrition.do"
if `RUN_43_HETEROGENEITY' do "$CODE/43_heterogeneity.do"
if `RUN_44_IDVAR' do "$CODE/44_identifying_variation.do"
if `RUN_45_BALANCE' do "$CODE/45_balance_checks.do"
if `RUN_46_COUNTY' do "$CODE/46_county_shares.do"
if `RUN_47_ASYM_COUNTYNORMAL' do "$CODE/47_asymmetry_county_normal.do"
if `RUN_50_TEXTABLES' do "$CODE/50_tex_tables.do"
if `RUN_60_FIGURES' do "$CODE/60_figures.do"
if `RUN_61_MAPS' do "$CODE/61_maps.do"

di as result "master.do finished. Next: the Python scripts in tools/ (README.md, section How to run)."
log close master
