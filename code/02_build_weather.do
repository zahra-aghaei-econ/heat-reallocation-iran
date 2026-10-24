*==============================================================================*
* 02_build_weather.do
* Builds all weather variables from the daily weather file.
*
* Input : data/weather_daily.dta   (one row per county and day)
* Output: intermediate/weather_daily_base_county.dta   (clean daily weather, 1385 counties)
*         intermediate/weather_climatology.dta         (fixed county-season climate)
*         intermediate/weather_annual_rain.dta         (annual rain and its lags)
*         intermediate/weather_county_season.dta       (all weather variables, county x year x season)
*         output/data_build/02_weather_diagnostics.xlsx
*
* Seasons: 1 = spring, 2 = summer, 3 = fall, 4 = winter.
* Everything is built from the daily data, so nothing depends on old weather files.
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$BUILD/02_build_weather.log", text replace name(step)

global XL02 "$BUILD/02_weather_diagnostics.xlsx"

putexcel set "$XL02", sheet("00_Guide") replace
putexcel A1 = "Weather build diagnostics"
putexcel A3 = "Sheet"
putexcel B3 = "What it shows"
putexcel A4 = "cleaning"
putexcel B4 = "Number of daily rows repaired or checked."
putexcel A5 = "by_year"
putexcel B5 = "Share of county-seasons with enough valid days and with a usable climate, by year."
putexcel A6 = "reference_period"
putexcel B6 = "How many county-seasons have a usable fixed climate (reference years)."
putexcel clear

*==============================================================================*
* 1. Clean the daily file
*==============================================================================*
use "$WEATHER_FILE", clear

keep Province_85 county_85 Year month day season shamsidate tmax tmin mean_tem_daily rain_24

rename Year year
make_mix4, province(Province_85) county(county_85) generate(mix4)
drop Province_85 county_85
assert mix4 != ""

recast long shamsidate
recast byte month day season

count if !inrange(season, 1, 4) | missing(season)
assert r(N) == 0

* The date must agree with year, month and day
count if shamsidate != year*10000 + month*100 + day
assert r(N) == 0

* A few rows have Tmax below Tmin. We swap the two values.
gen byte swapped = !missing(tmax, tmin) & tmax < tmin
count if swapped == 1
local n_swapped = r(N)
gen double lo = cond(swapped == 1, tmax, tmin) if !missing(tmax, tmin)
gen double hi = cond(swapped == 1, tmin, tmax) if !missing(tmax, tmin)
replace tmin = lo if swapped == 1
replace tmax = hi if swapped == 1
drop lo hi

* Tmean is always (Tmin + Tmax) / 2. We count the rows where the file differed.
gen double tmean_formula = (tmin + tmax) / 2 if !missing(tmin, tmax)
count if !missing(mean_tem_daily, tmean_formula) & abs(mean_tem_daily - tmean_formula) > 0.001
local n_tmean_diff = r(N)
drop mean_tem_daily tmean_formula

* Negative rain is not possible
count if rain_24 < 0 & !missing(rain_24)
local n_neg_rain = r(N)
assert `n_neg_rain' == 0

* Several current counties can belong to one 1385 county. If so, we take the
* simple mean of the raw daily values first. All nonlinear indicators come after.
gen byte one = 1
collapse (mean) tmax tmin rain_24 (sum) n_source_rows = one, ///
    by(mix4 year season shamsidate month day)
isid mix4 shamsidate

count if n_source_rows > 1
local n_multirow = r(N)

gen long mix = real(mix4)
label var mix4 "County code (1385 borders), 4 characters"
label var mix  "County code, number"

gen double tmean_day = (tmin + tmax) / 2 if !missing(tmin, tmax)
rename tmax    tmax_day
rename tmin    tmin_day
rename rain_24 rain_day
recast double tmax_day tmin_day rain_day

keep if year >= $REF_START

* Which days have usable data
gen byte valid_tmax_day  = !missing(tmax_day)
gen byte valid_tmean_day = !missing(tmean_day)
gen byte valid_rain_day  = !missing(rain_day)
gen byte valid_sine_day  = !missing(tmin_day, tmax_day)
gen byte valid_core_day  = !missing(tmin_day, tmax_day, tmean_day, rain_day)

*------------------------------------------------------------------------------*
* Daily terms
*------------------------------------------------------------------------------*
* Hot days and heat dose above a fixed cut-off
gen byte d_days35 = (tmax_day >= 35) if valid_tmax_day
gen byte d_days37 = (tmax_day >= 37) if valid_tmax_day
gen byte d_days40 = (tmax_day >= 40) if valid_tmax_day

gen double d_heat35 = max(tmax_day - 35, 0) if valid_tmax_day
gen double d_heat37 = max(tmax_day - 37, 0) if valid_tmax_day
gen double d_heat40 = max(tmax_day - 40, 0) if valid_tmax_day

* Tmax bins (20-25 is the left-out group later)
gen byte d_bin_le20  = (tmax_day <= 20)                  if valid_tmax_day
gen byte d_bin_20_25 = (tmax_day > 20 & tmax_day <= 25) if valid_tmax_day
gen byte d_bin_25_30 = (tmax_day > 25 & tmax_day <= 30) if valid_tmax_day
gen byte d_bin_30_35 = (tmax_day > 30 & tmax_day <= 35) if valid_tmax_day
gen byte d_bin_35_40 = (tmax_day > 35 & tmax_day <= 40) if valid_tmax_day
gen byte d_bin_gt40  = (tmax_day > 40)                  if valid_tmax_day

egen byte bin_check = rowtotal(d_bin_le20 d_bin_20_25 d_bin_25_30 d_bin_30_35 d_bin_35_40 d_bin_gt40)
assert bin_check == 1 if valid_tmax_day
drop bin_check

* Degree days from the daily mean temperature
gen double d_gdd8_32_tmean = min(max(tmean_day - 8, 0), 24) if valid_tmean_day
gen double d_hdd32_tmean   = max(tmean_day - 32, 0)        if valid_tmean_day
gen double d_hdd35_tmean   = max(tmean_day - 35, 0)        if valid_tmean_day

* Degree days with a sine curve between Tmin and Tmax (exact formula).
* Temperature during the day is: T = mid + amp * sin(theta).
* pp_k is the average of max(T - k, 0) over the day.
scalar PI = 4 * atan(1)

gen double mid = (tmin_day + tmax_day) / 2 if valid_sine_day
gen double amp = (tmax_day - tmin_day) / 2 if valid_sine_day

* above 8 degrees
gen double pp8 = .
replace pp8 = max(mid - 8, 0) if valid_sine_day & amp == 0
replace pp8 = 0               if valid_sine_day & amp > 0 & 8 >= mid + amp
replace pp8 = mid - 8         if valid_sine_day & amp > 0 & 8 <= mid - amp
gen double z8 = (8 - mid) / amp if valid_sine_day & amp > 0 & 8 > mid - amp & 8 < mid + amp
replace pp8 = ((mid - 8) * (PI - 2*asin(z8)) + 2*amp*sqrt(max(1 - z8^2, 0))) / (2*PI) if !missing(z8)

* above 32 degrees
gen double pp32 = .
replace pp32 = max(mid - 32, 0) if valid_sine_day & amp == 0
replace pp32 = 0                if valid_sine_day & amp > 0 & 32 >= mid + amp
replace pp32 = mid - 32         if valid_sine_day & amp > 0 & 32 <= mid - amp
gen double z32 = (32 - mid) / amp if valid_sine_day & amp > 0 & 32 > mid - amp & 32 < mid + amp
replace pp32 = ((mid - 32) * (PI - 2*asin(z32)) + 2*amp*sqrt(max(1 - z32^2, 0))) / (2*PI) if !missing(z32)

* useful heat (8 to 32) and harmful heat (above 32)
gen double d_gdd8_32_sine = pp8 - pp32 if valid_sine_day
gen double d_hdd32_sine   = pp32       if valid_sine_day
replace d_gdd8_32_sine = 0 if d_gdd8_32_sine < 0 & d_gdd8_32_sine > -1e-10
replace d_hdd32_sine   = 0 if d_hdd32_sine   < 0 & d_hdd32_sine   > -1e-10
assert d_gdd8_32_sine >= 0 if !missing(d_gdd8_32_sine)
assert d_hdd32_sine   >= 0 if !missing(d_hdd32_sine)
assert abs((d_gdd8_32_sine + d_hdd32_sine) - pp8) < 1e-8 if valid_sine_day

drop mid amp pp8 pp32 z8 z32

sort mix shamsidate
compress
save "$INTER/weather_daily_base_county.dta", replace

* Cleaning numbers to Excel
putexcel set "$XL02", sheet("cleaning") modify
putexcel A1 = "Cleaning of the daily weather file"
putexcel A3 = "Rows with Tmax below Tmin (values swapped)"
putexcel B3 = `n_swapped'
putexcel A4 = "Rows where the file Tmean differed from (Tmin+Tmax)/2 by more than 0.001"
putexcel B4 = `n_tmean_diff'
putexcel A5 = "County-days built from more than one current county"
putexcel B5 = `n_multirow'
putexcel A6 = "Rows with negative rain (must be 0)"
putexcel B6 = `n_neg_rain'
putexcel clear

*==============================================================================*
* 2. How many reference years does each county-season have?
*==============================================================================*
use "$INTER/weather_daily_base_county.dta", clear
keep if inrange(year, $REF_START, $REF_END)

* spring and summer have 93 days, fall and winter 90 (we use 90 for winter)
gen int expected_days_refyear = cond(inlist(season, 1, 2), 93, 90)

collapse (sum) n_tmax_days_refyear = valid_tmax_day ///
               n_tmean_days_refyear = valid_tmean_day ///
               n_sine_days_refyear = valid_sine_day ///
               n_rain_days_refyear = valid_rain_day ///
         (firstnm) expected_days_refyear, by(mix mix4 year season)

gen double tmax_coverage_refyear  = n_tmax_days_refyear  / expected_days_refyear
gen double tmean_coverage_refyear = n_tmean_days_refyear / expected_days_refyear
gen double sine_coverage_refyear  = n_sine_days_refyear  / expected_days_refyear
gen double rain_coverage_refyear  = n_rain_days_refyear  / expected_days_refyear

gen byte valid_ref_year_tmax  = tmax_coverage_refyear  >= $MIN_COVERAGE
gen byte valid_ref_year_tmean = tmean_coverage_refyear >= $MIN_COVERAGE
gen byte valid_ref_year_all   = tmax_coverage_refyear >= $MIN_COVERAGE ///
    & tmean_coverage_refyear >= $MIN_COVERAGE ///
    & sine_coverage_refyear >= $MIN_COVERAGE ///
    & rain_coverage_refyear >= $MIN_COVERAGE

isid mix year season
tempfile ref_year_coverage
save `ref_year_coverage', replace

collapse (sum) n_valid_ref_years_tmax = valid_ref_year_tmax ///
               n_valid_ref_years_tmean = valid_ref_year_tmean ///
               n_valid_ref_years_all = valid_ref_year_all ///
               n_tmax_days_reference = n_tmax_days_refyear ///
               n_tmean_days_reference = n_tmean_days_refyear ///
               n_sine_days_reference = n_sine_days_refyear ///
               n_rain_days_reference = n_rain_days_refyear, by(mix mix4 season)

* The denominator is the full reference window, also for years with no data at all
gen long expected_days_reference = ($REF_END - $REF_START + 1) * cond(inlist(season, 1, 2), 93, 90)

gen double ref_coverage_tmax  = n_tmax_days_reference  / expected_days_reference
gen double ref_coverage_tmean = n_tmean_days_reference / expected_days_reference
gen double ref_coverage_sine  = n_sine_days_reference  / expected_days_reference
gen double ref_coverage_rain  = n_rain_days_reference  / expected_days_reference

gen byte ref_eligible_tmax  = n_valid_ref_years_tmax  >= $MIN_VALID_REF_YRS & ref_coverage_tmax  >= $MIN_COVERAGE
gen byte ref_eligible_tmean = n_valid_ref_years_tmean >= $MIN_VALID_REF_YRS & ref_coverage_tmean >= $MIN_COVERAGE
gen byte ref_eligible = (ref_eligible_tmax == 1 & ref_eligible_tmean == 1)

gen double ref_coverage = min(ref_coverage_tmax, ref_coverage_tmean, ref_coverage_sine, ref_coverage_rain)
gen long n_valid_ref_years = min(n_valid_ref_years_tmax, n_valid_ref_years_tmean, n_valid_ref_years_all)

label var ref_eligible "Climate from reference years is usable (Tmax and Tmean)"

isid mix season
tempfile ref_coverage
save `ref_coverage', replace

quietly summarize ref_eligible, meanonly
local share_ref_ok = r(mean)

putexcel set "$XL02", sheet("reference_period") modify
putexcel A1 = "Reference period used for the fixed local climate"
putexcel A3 = "First reference year"
putexcel B3 = $REF_START
putexcel A4 = "Last reference year"
putexcel B4 = $REF_END
putexcel A5 = "Share of county-seasons with a usable climate"
putexcel B5 = `share_ref_ok'
putexcel clear

*==============================================================================*
* 3. Fixed county x season climate (percentiles of Tmax and mean Tmean)
*==============================================================================*
use "$INTER/weather_daily_base_county.dta", clear
keep if inrange(year, $REF_START, $REF_END)
merge m:1 mix year season using `ref_year_coverage', keep(master match) ///
    keepusing(valid_ref_year_tmax valid_ref_year_tmean) nogen

preserve
    keep if valid_ref_year_tmax == 1 & valid_tmax_day == 1
    collapse (p80) p80_tmax_ref = tmax_day ///
             (p90) p90_tmax_ref = tmax_day ///
             (p95) p95_tmax_ref = tmax_day ///
             (mean) clim_tmax_ref_s = tmax_day ///
             (count) n_tmax_days_climatology = tmax_day, by(mix mix4 season)
    tempfile tmax_clim
    save `tmax_clim', replace
restore

keep if valid_ref_year_tmean == 1 & valid_tmean_day == 1
collapse (mean) clim_tmean_ref_s = tmean_day ///
         (count) n_tmean_days_climatology = tmean_day, by(mix mix4 season)
tempfile tmean_clim
save `tmean_clim', replace

use `ref_coverage', clear
merge 1:1 mix season using `tmax_clim', nogen
merge 1:1 mix season using `tmean_clim', nogen

replace p80_tmax_ref = .          if ref_eligible_tmax != 1
replace p90_tmax_ref = .          if ref_eligible_tmax != 1
replace p95_tmax_ref = .          if ref_eligible_tmax != 1
replace clim_tmax_ref_s = .       if ref_eligible_tmax != 1
replace n_tmax_days_climatology = . if ref_eligible_tmax != 1
replace clim_tmean_ref_s = .      if ref_eligible_tmean != 1
replace n_tmean_days_climatology = . if ref_eligible_tmean != 1

label var p80_tmax_ref    "County-season P80 of daily Tmax, reference years"
label var p90_tmax_ref    "County-season P90 of daily Tmax, reference years"
label var p95_tmax_ref    "County-season P95 of daily Tmax, reference years"
label var clim_tmax_ref_s  "County-season mean Tmax, reference years"
label var clim_tmean_ref_s "County-season mean Tmean, reference years"

isid mix season
compress
save "$INTER/weather_climatology.dta", replace

*==============================================================================*
* 4. Annual rainfall and its lags (mean of t-1, t-2, t-3)
*==============================================================================*
use "$INTER/weather_daily_base_county.dta", clear

collapse (sum) annual_rain_mm = rain_day n_rain_days_year = valid_rain_day, by(mix mix4 year)

* A year counts only if at least 60 percent of days have rain data.
* Otherwise missing days would look like a drought.
gen double annual_rain_coverage = n_rain_days_year / 365.25
gen byte annual_rain_eligible = annual_rain_coverage >= $MIN_COVERAGE
gen double rain100_year = annual_rain_mm / 100 if annual_rain_eligible == 1

isid mix year
xtset mix year

gen double rain100_year_l1 = L1.rain100_year
gen double rain100_year_l2 = L2.rain100_year
gen double rain100_year_l3 = L3.rain100_year
gen double rain100_lag13 = (rain100_year_l1 + rain100_year_l2 + rain100_year_l3) / 3 ///
    if !missing(rain100_year_l1, rain100_year_l2, rain100_year_l3)
label var rain100_lag13 "Mean annual rainfall /100 mm in t-1, t-2, t-3"

keep mix mix4 year rain100_year annual_rain_coverage annual_rain_eligible ///
     rain100_year_l1 rain100_year_l2 rain100_year_l3 rain100_lag13
compress
save "$INTER/weather_annual_rain.dta", replace

*==============================================================================*
* 5. County x year x season weather variables
*==============================================================================*
use "$INTER/weather_daily_base_county.dta", clear
merge m:1 mix season using "$INTER/weather_climatology.dta", keep(master match) nogen

* Days above the local climate (strictly greater than the reference percentile)
gen byte d_countp80 = (tmax_day > p80_tmax_ref) if valid_tmax_day & ref_eligible_tmax == 1
gen byte d_countp90 = (tmax_day > p90_tmax_ref) if valid_tmax_day & ref_eligible_tmax == 1
gen byte d_countp95 = (tmax_day > p95_tmax_ref) if valid_tmax_day & ref_eligible_tmax == 1

gen double d_dosep80 = max(tmax_day - p80_tmax_ref, 0) if valid_tmax_day & ref_eligible_tmax == 1
gen double d_dosep90 = max(tmax_day - p90_tmax_ref, 0) if valid_tmax_day & ref_eligible_tmax == 1
gen double d_dosep95 = max(tmax_day - p95_tmax_ref, 0) if valid_tmax_day & ref_eligible_tmax == 1

collapse ///
    (sum) n_valid_days_s0 = valid_core_day ///
          n_tmax_days_s0  = valid_tmax_day ///
          n_tmean_days_s0 = valid_tmean_day ///
          n_rain_days_s0  = valid_rain_day ///
          n_sine_days_s0  = valid_sine_day ///
          rain_total_s0   = rain_day ///
          raw_days35 = d_days35 raw_days37 = d_days37 raw_days40 = d_days40 ///
          raw_heat35 = d_heat35 raw_heat37 = d_heat37 raw_heat40 = d_heat40 ///
          raw_countp80 = d_countp80 raw_countp90 = d_countp90 raw_countp95 = d_countp95 ///
          raw_dosep80 = d_dosep80 raw_dosep90 = d_dosep90 raw_dosep95 = d_dosep95 ///
          raw_bin_le20 = d_bin_le20 raw_bin_20_25 = d_bin_20_25 ///
          raw_bin_25_30 = d_bin_25_30 raw_bin_30_35 = d_bin_30_35 ///
          raw_bin_35_40 = d_bin_35_40 raw_bin_gt40 = d_bin_gt40 ///
          raw_gdd8_32_sine = d_gdd8_32_sine raw_hdd32_sine = d_hdd32_sine ///
          raw_gdd8_32_tmean = d_gdd8_32_tmean raw_hdd32_tmean = d_hdd32_tmean ///
          raw_hdd35_tmean = d_hdd35_tmean ///
    (mean) tmean_s0 = tmean_day tmax_mean_s0 = tmax_day ///
    (firstnm) p80_tmax_ref p90_tmax_ref p95_tmax_ref ///
              clim_tmax_ref_s clim_tmean_ref_s ///
              ref_eligible ref_eligible_tmax ref_eligible_tmean ///
              ref_coverage ref_coverage_tmax ref_coverage_tmean n_valid_ref_years, ///
    by(mix mix4 year season)

* Share of days with data in the season
gen int expected_days_s0 = cond(inlist(season, 1, 2), 93, 90)
gen double coverage_tmax_s0  = n_tmax_days_s0  / expected_days_s0
gen double coverage_tmean_s0 = n_tmean_days_s0 / expected_days_s0
gen double coverage_sine_s0  = n_sine_days_s0  / expected_days_s0
gen double coverage_rain_s0  = n_rain_days_s0  / expected_days_s0
gen double weather_coverage_s0 = min(coverage_tmax_s0, coverage_tmean_s0, coverage_sine_s0, coverage_rain_s0)
gen byte weather_valid_s0 = coverage_tmax_s0 >= $MIN_COVERAGE & coverage_tmean_s0 >= $MIN_COVERAGE ///
    & coverage_sine_s0 >= $MIN_COVERAGE & coverage_rain_s0 >= $MIN_COVERAGE
label var weather_valid_s0 "At least 60 percent of days have data (all weather sources)"

* Main variables. Names: days35_10_s0 = days with Tmax >= 35, divided by 10, same season.
gen double days35_10_s0 = raw_days35 / 10
gen double days37_10_s0 = raw_days37 / 10
gen double days40_10_s0 = raw_days40 / 10

gen double heat35_10_s0 = raw_heat35 / 10
gen double heat37_10_s0 = raw_heat37 / 10
gen double heat40_10_s0 = raw_heat40 / 10

gen double countp80_10_s0 = raw_countp80 / 10
gen double countp90_10_s0 = raw_countp90 / 10
gen double countp95_10_s0 = raw_countp95 / 10

gen double dosep80_10_s0 = raw_dosep80 / 10
gen double dosep90_10_s0 = raw_dosep90 / 10
gen double dosep95_10_s0 = raw_dosep95 / 10

gen double bin_tmax_le20_s0  = raw_bin_le20  / 10
gen double bin_tmax_20_25_s0 = raw_bin_20_25 / 10
gen double bin_tmax_25_30_s0 = raw_bin_25_30 / 10
gen double bin_tmax_30_35_s0 = raw_bin_30_35 / 10
gen double bin_tmax_35_40_s0 = raw_bin_35_40 / 10
gen double bin_tmax_gt40_s0  = raw_bin_gt40  / 10

gen double gdd8_32_sine_s0  = raw_gdd8_32_sine  / 100
gen double hdd32_sine_s0    = raw_hdd32_sine    / 10
gen double gdd8_32_tmean_s0 = raw_gdd8_32_tmean / 100
gen double hdd32_tmean_s0   = raw_hdd32_tmean   / 10
gen double hdd35_tmean_10_s0 = raw_hdd35_tmean  / 10

gen double rain100_s0    = rain_total_s0 / 100
gen double rain100_sq_s0 = rain100_s0^2

gen double tmean_sq_s0 = tmean_s0^2
gen double anom_tmean_s0    = tmean_s0 - clim_tmean_ref_s if ref_eligible_tmean == 1
gen double anom_tmean_sq_s0 = anom_tmean_s0^2

* The Tmax bins must add up to the number of valid days
egen double bin_total = rowtotal(bin_tmax_le20_s0 bin_tmax_20_25_s0 bin_tmax_25_30_s0 ///
    bin_tmax_30_35_s0 bin_tmax_35_40_s0 bin_tmax_gt40_s0)
assert abs(bin_total - n_tmax_days_s0/10) < 1e-6 if n_tmax_days_s0 > 0
drop bin_total

* Same 60 percent rule for every weather variable
local wvars days35_10_s0 days37_10_s0 days40_10_s0 heat35_10_s0 heat37_10_s0 heat40_10_s0 ///
    countp80_10_s0 countp90_10_s0 countp95_10_s0 dosep80_10_s0 dosep90_10_s0 dosep95_10_s0 ///
    bin_tmax_le20_s0 bin_tmax_20_25_s0 bin_tmax_25_30_s0 bin_tmax_30_35_s0 ///
    bin_tmax_35_40_s0 bin_tmax_gt40_s0 gdd8_32_sine_s0 hdd32_sine_s0 ///
    gdd8_32_tmean_s0 hdd32_tmean_s0 hdd35_tmean_10_s0 rain100_s0 rain100_sq_s0 ///
    tmean_s0 tmean_sq_s0 tmax_mean_s0 anom_tmean_s0 anom_tmean_sq_s0
foreach v of local wvars {
    replace `v' = . if weather_valid_s0 != 1
}

* Local-climate variables also need a usable reference climate
foreach v in countp80_10_s0 countp90_10_s0 countp95_10_s0 dosep80_10_s0 dosep90_10_s0 dosep95_10_s0 {
    replace `v' = . if ref_eligible_tmax != 1
}
foreach v in anom_tmean_s0 anom_tmean_sq_s0 {
    replace `v' = . if ref_eligible_tmean != 1
}

* Lags of one and two seasons (exact: the season before, and two seasons before)
gen long season_index = 4*year + season
isid mix season_index
xtset mix season_index

gen double gdd8_32_sine_s1 = L1.gdd8_32_sine_s0
gen double hdd32_sine_s1   = L1.hdd32_sine_s0
gen double gdd8_32_sine_s2 = L2.gdd8_32_sine_s0
gen double hdd32_sine_s2   = L2.hdd32_sine_s0

gen double gdd8_32_tmean_s1 = L1.gdd8_32_tmean_s0
gen double hdd32_tmean_s1   = L1.hdd32_tmean_s0
gen double gdd8_32_tmean_s2 = L2.gdd8_32_tmean_s0
gen double hdd32_tmean_s2   = L2.hdd32_tmean_s0

* Annual rainfall lags (mean of t-1, t-2, t-3)
merge m:1 mix year using "$INTER/weather_annual_rain.dta", keep(master match) ///
    keepusing(rain100_lag13) nogen

label var days35_10_s0  "Days with Tmax >= 35C in the season, /10"
label var days37_10_s0  "Days with Tmax >= 37C in the season, /10"
label var days40_10_s0  "Days with Tmax >= 40C in the season, /10"
label var heat35_10_s0  "Sum of (Tmax - 35C) over hot days in the season, /10"
label var heat37_10_s0  "Sum of (Tmax - 37C) over hot days in the season, /10"
label var heat40_10_s0  "Sum of (Tmax - 40C) over hot days in the season, /10"
label var countp90_10_s0 "Days above the local P90 of Tmax, /10"
label var dosep90_10_s0  "Sum of Tmax above the local P90, /10"
label var rain100_s0     "Seasonal rain, /100 mm"
label var rain100_sq_s0  "Seasonal rain /100, squared"
label var anom_tmean_s0  "Season Tmean minus county-season reference Tmean"
label var anom_tmean_sq_s0 "Squared Tmean anomaly"
label var gdd8_32_sine_s1 "Sine GDD(8,32) one season before, /100"
label var hdd32_sine_s1   "Sine HDD above 32C one season before, /10"
label var gdd8_32_sine_s2 "Sine GDD(8,32) two seasons before, /100"
label var hdd32_sine_s2   "Sine HDD above 32C two seasons before, /10"
label var gdd8_32_tmean_s1 "Tmean GDD(8,32) one season before, /100"
label var hdd32_tmean_s1   "Tmean HDD above 32C one season before, /10"
label var gdd8_32_tmean_s2 "Tmean GDD(8,32) two seasons before, /100"
label var hdd32_tmean_s2   "Tmean HDD above 32C two seasons before, /10"
label var hdd35_tmean_10_s0 "Tmean degrees above 35C in the season, /10"

sort mix year season
isid mix year season
compress
save "$INTER/weather_county_season.dta", replace

* By-year check: how many county-seasons are valid
preserve
    collapse (count) county_seasons = mix (mean) share_valid_weather = weather_valid_s0 ///
        share_ref_ok = ref_eligible mean_days35_10 = days35_10_s0 mean_rain100 = rain100_s0, by(year)
    keep if year >= 1384
    export excel using "$XL02", sheet("by_year", modify) firstrow(variables)
restore

di as result "02 done."
log close step
