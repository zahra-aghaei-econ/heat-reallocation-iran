*==============================================================================*
* 03_merge_model_ready.do
* Puts the weather onto the transitions. This gives the files used by all models.
*
* Input : intermediate/transitions_same_season.dta
*         intermediate/weather_county_season.dta
* Output: intermediate/model_ready.dta   (one row per person transition, all years)
*         output/data_build/03_model_ready_diagnostics.xlsx
*
* The file keeps ALL origin years. The models choose the years they use
* (FIRST_ORIGIN_YEAR to LAST_ORIGIN_YEAR set in 00_setup.do).
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$BUILD/03_merge_model_ready.log", text replace name(step)

global XL03 "$BUILD/03_model_ready_diagnostics.xlsx"

putexcel set "$XL03", sheet("00_Guide") replace
putexcel A1 = "Model-ready file diagnostics"
putexcel A3 = "Sheet"
putexcel B3 = "What it shows"
putexcel A4 = "merge_by_year"
putexcel B4 = "Transitions by origin year: merged to weather, valid weather, and counts of people in agriculture at the origin."
putexcel clear

*------------------------------------------------------------------------------*
* 1. Transitions and fixed effect variables
*------------------------------------------------------------------------------*
use "$INTER/transitions_same_season.dta", clear

* A transition needs a valid county code to be matched to weather
gen byte invalid_mix_key = (mix4_origin == "" | missing(real(mix4_origin)))
label var invalid_mix_key "County code at origin is missing or invalid"

* County number (used for county fixed effects and clustering)
egen long mix_id = group(mix4_origin) if invalid_mix_key == 0
label var mix_id "County ID (number), from the 4-character county code"

* Province x year fixed effect
egen long province_year = group(province85_origin year_origin), missing
label var province_year "Province x origin-year fixed effect"

* Linear time trend (used in the trend specification)
gen double year_trend = year_origin - 1391
label var year_trend "Origin year minus 1391"

*------------------------------------------------------------------------------*
* 2. Merge weather by county, year and season
*------------------------------------------------------------------------------*
preserve
    use "$INTER/weather_county_season.dta", clear
    rename mix4   mix4_origin
    rename year   year_origin
    rename season season_origin
    drop mix season_index
    isid mix4_origin year_origin season_origin
    tempfile weather_keyed
    save `weather_keyed', replace
restore

merge m:1 mix4_origin year_origin season_origin using `weather_keyed', ///
    keep(master match) gen(_merge_weather)

gen byte weather_key_matched = (_merge_weather == 3)
label var weather_key_matched "Matched to county-season weather"

gen byte weather_merge_status = .
replace weather_merge_status = 1 if _merge_weather == 1 & invalid_mix_key == 1
replace weather_merge_status = 2 if _merge_weather == 1 & invalid_mix_key == 0
replace weather_merge_status = 3 if _merge_weather == 3
label define weather_merge_lbl 1 "Invalid county code" 2 "County-season not in weather file" ///
    3 "Matched to weather", replace
label values weather_merge_status weather_merge_lbl
drop _merge_weather

count if weather_key_matched == 1
if r(N) == 0 {
    di as error "No transition was matched to weather. Check the county codes."
    exit 459
}

*------------------------------------------------------------------------------*
* 3. Sample flags
*------------------------------------------------------------------------------*
* Common sample: matched to weather and at least 60 percent of days observed
gen byte weather_common_sample = (weather_key_matched == 1 & weather_valid_s0 == 1)
label var weather_common_sample "Matched to weather with at least 60 percent valid days"

* Local-climate sample: common sample plus a usable reference climate
gen byte weather_localclim_sample = (weather_common_sample == 1 & ref_eligible == 1)
label var weather_localclim_sample "Common sample and usable reference climate"

compress
save "$INTER/model_ready.dta", replace

*------------------------------------------------------------------------------*
* 4. Diagnostics by origin year
*------------------------------------------------------------------------------*
preserve
    gen byte agri_origin_known_dest = (job_origin == 1 & !missing(job_dest))
    gen byte agri_in_common = (agri_origin_known_dest == 1 & weather_common_sample == 1)
    gen byte one = 1
    collapse (sum) transitions = one weather_key_matched weather_common_sample ///
        weather_localclim_sample agri_origin_known_dest agri_in_common, by(year_origin)
    export excel using "$XL03", sheet("merge_by_year", modify) firstrow(variables)
restore

di as result "03 done."
log close step
