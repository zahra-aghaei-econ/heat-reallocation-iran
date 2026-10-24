*==============================================================================*
* 41_check_weather.do
* Does the county-season weather look right? No regressions here.
* Use it to check that county codes and season codes are merged correctly: the hottest
* counties should be in Khuzestan, Bushehr, Hormozgan and Sistan, the coldest in the
* northwest and the mountains, summer should be the hottest season, and so on.
*
* Years: the weather file ends in 1402. Change WY_FIRST / WY_LAST below to look at other years.
*
* Sheets:
*   Season_summary    mean, lowest and highest county value, by year and season
*   Extremes          5 highest and 5 lowest counties for each year, season (0 = whole year)
*                     and measure; names come from the daily weather file
*   Persistence       how well the county ranking in WY_FIRST-WY_LAST agrees with the
*                     earlier years (it should agree almost perfectly)
*   Season_order      mean temperature by season over all years (summer should be highest)
*
* Measures: tmax = mean daily maximum temperature (C); tmean = mean daily temperature (C);
* rain = total rainfall (mm, a sum over the season or the year); days35 = number of days with
* Tmax of 35C or more.
*
* Output: output/<RUN_NAME>/tables/41_check_weather.xlsx
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/41_check_weather.log", text replace name(step)

local WY_FIRST 1399
local WY_LAST  1402

global XL41 "$TABLES/41_check_weather.xlsx"

guide_sheet, file("$XL41") title("Checks of the county-season weather") ///
    lines("Season_summary: Mean, lowest and highest county value of each measure, by year and season.|Extremes: The 5 highest and 5 lowest counties by year, season (0 = whole year) and measure. Province and county names are from the daily weather file.|Persistence: Correlation across counties between the average of `WY_FIRST'-`WY_LAST' and the average of all earlier years, and the average difference. Counties keep their ranking, so the correlation should be close to 1.|Season_order: Mean temperature and rain by season over all counties and years. Season 1 = spring (Farvardin to Khordad), 2 = summer, 3 = autumn, 4 = winter.|Notes: Tmax and Tmean are in degrees Celsius. Rain is in millimetres. Many counties have zero rain in summer, so the lowest-rain list for summer is arbitrary among ties.")

*------------------------------------------------------------------------------*
* County names (from the daily weather file)
*------------------------------------------------------------------------------*
use Province_85 county_85 county province using "$DATA/weather_daily.dta", clear
make_mix4, province(Province_85) county(county_85) generate(mix4)
keep mix4 county province
duplicates drop mix4, force
tempfile names
save `names'

*------------------------------------------------------------------------------*
* County-season weather, plus whole-year rows (season 0)
*------------------------------------------------------------------------------*
use year season mix4 tmax_mean_s0 tmean_s0 rain_total_s0 raw_days35 n_valid_days_s0 ///
    using "$INTER/weather_county_season.dta", clear
rename tmax_mean_s0 tmax
rename tmean_s0     tmean
rename rain_total_s0 rain
rename raw_days35   days35

* Season order (all years)
preserve
    collapse (mean) tmax tmean rain days35, by(season)
    export excel using "$XL41", sheet("Season_order", modify) firstrow(variables)
restore

* Persistence of county climate: recent years against earlier years
preserve
    collapse (mean) tmax tmean rain days35, by(mix4 year)
    gen byte recent = inrange(year, `WY_FIRST', `WY_LAST')
    collapse (mean) tmax tmean rain days35, by(mix4 recent)
    reshape wide tmax tmean rain days35, i(mix4) j(recent)
    tempname P
    tempfile pers
    postfile `P' str12 measure double(corr_counties mean_diff_recent_earlier) using `pers', replace
    foreach m in tmax tmean rain days35 {
        quietly correlate `m'1 `m'0
        local r = r(rho)
        gen double d_`m' = `m'1 - `m'0
        quietly summarize d_`m'
        post `P' ("`m'") (`r') (r(mean))
    }
    postclose `P'
    use `pers', clear
    export excel using "$XL41", sheet("Persistence", modify) firstrow(variables)
restore

* Whole-year rows
keep if inrange(year, `WY_FIRST', `WY_LAST')
tempfile seasonal
save `seasonal'
collapse (mean) tmax tmean (sum) rain days35, by(mix4 year)
gen byte season = 0
append using `seasonal'
sort year season mix4

* Summary by year and season
preserve
    collapse (mean) mean_tmax = tmax mean_tmean = tmean mean_rain = rain mean_days35 = days35 ///
        (min) min_tmax = tmax min_tmean = tmean min_rain = rain ///
        (max) max_tmax = tmax max_tmean = tmean max_rain = rain max_days35 = days35 ///
        (count) n_counties = tmax, by(year season)
    export excel using "$XL41", sheet("Season_summary", modify) firstrow(variables)
restore

* Extremes
tempfile ext
local first = 1
foreach m in tmax tmean rain days35 {
    preserve
        keep year season mix4 `m'
        rename `m' value
        egen double rank_high = rank(-value), by(year season) unique
        egen double rank_low  = rank(value), by(year season) unique
        keep if rank_high <= 5 | rank_low <= 5
        gen str6 measure = "`m'"
        gen str7 group = cond(rank_high <= 5, "highest", "lowest")
        gen byte rank_in_group = cond(rank_high <= 5, rank_high, rank_low)
        keep year season measure group rank_in_group mix4 value
        if `first' == 0 append using `ext'
        save `ext', replace
    restore
    local first = 0
}
use `ext', clear
merge m:1 mix4 using `names', keep(master match) nogenerate
order year season measure group rank_in_group mix4 province county value
sort measure year season group rank_in_group
export excel using "$XL41", sheet("Extremes", modify) firstrow(variables)

di as result "41 done."
log close step
