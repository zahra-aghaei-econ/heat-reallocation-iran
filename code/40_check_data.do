*==============================================================================*
* 40_check_data.do
* Checks of the survey data and of the merge to weather. No regressions here.
* It does not depend on the run settings (years, fixed effects), so it always covers
* all years in the individual file.
*
* Questions this answers:
*   1. Overview by year: rows, weighted size, missing county codes, share of rows with a
*      code in the list of 336 counties, share of employed people without a sector.
*   2. How many counties are present in each year and how many rows each county has.
*   3. Which codes outside the list appear (these are rows that can never be merged).
*   4. Does a county keep its identity over time? For each year we correlate the county
*      agriculture share and the county sample size with the previous year and with a
*      reference year. If the codes were shuffled from some year on, the correlation
*      drops sharply in that year (and stays low against the reference year).
*   5. Transitions: share of people who stay in the same county or province from one
*      year to the next. A jump in some origin year means the county codes of the two
*      surveys do not match.
*   6. Merge to weather by origin year and by season, and the counties that fail to merge.
*
* Output: output/<RUN_NAME>/tables/40_check_data.xlsx
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/40_check_data.log", text replace name(step)

global XL40 "$TABLES/40_check_data.xlsx"

* Reference year for the consistency check (a year before the period you are unsure about)
local REF_YEAR 1396

guide_sheet, file("$XL40") title("Checks of the survey data and the merge to weather") ///
    lines("Overview_by_year: Rows, weighted size, share of rows with missing code or code outside the 336 counties, share of the employed without sector code.|County_change: Each county's agriculture share and log sample size around 1396-1398, with the change from 1396 to 1397 (sorted by the size of the change in agriculture share); if only a few counties jump, suspect their codes; if all move a little, suspect the survey frame.|Counties_by_year: Number of counties present each year, and rows per county (min, median, max).|Codes_outside_list: County codes in the survey that are not among the 336 counties (top 10 per year).|County_consistency: Correlation across counties of agriculture share and of log sample size, this year against last year and against the reference year (`REF_YEAR').|Transitions_by_year: Transitions per origin year, share staying in the same county and same province, share merged to weather.|Merge_by_season: Share merged to valid weather by origin year and season.|Unmerged_counties: Counties with transitions that did not merge to weather, by origin year.|Notes: Rows are people aged 15 and over. Agriculture share is among employed people with a sector code, weighted.")

*------------------------------------------------------------------------------*
* The 336 counties
*------------------------------------------------------------------------------*
use "$LOOKUP/agro_region_crosswalk_1385.dta", clear
keep mix4
gen byte in_list = 1
tempfile stable
save `stable'

*------------------------------------------------------------------------------*
* 1. Individual file: overview, counties, outside codes, consistency
*------------------------------------------------------------------------------*
use year season mix4 province85 age Activity_Status weight job employed_unclassified ///
    using "$INTER/lfs_individual.dta", clear
keep if age >= 15 & !missing(age)

gen byte blank_code = (mix4 == "")
merge m:1 mix4 using `stable', keep(master match) nogen
replace in_list = 0 if missing(in_list)

gen long rows = 1
gen byte employed = (Activity_Status == 0)
gen double unclassified_emp = employed_unclassified if employed == 1
gen double pct_blank = 100 * blank_code
gen double pct_in_list = 100 * in_list
egen byte tag_in  = tag(year mix4) if in_list == 1
egen byte tag_out = tag(year mix4) if in_list == 0 & blank_code == 0

preserve
    collapse (sum) rows tag_in tag_out (sum) weight_sum = weight ///
        (mean) pct_blank pct_in_list unclassified_emp, by(year)
    rename tag_in n_counties_in_list
    rename tag_out n_codes_outside_list
    replace unclassified_emp = 100 * unclassified_emp
    rename unclassified_emp pct_employed_without_sector
    gen int missing_counties = 336 - n_counties_in_list
    export excel using "$XL40", sheet("Overview_by_year", modify) firstrow(variables)
restore

* Rows per county and year
preserve
    keep if in_list == 1
    collapse (sum) rows, by(year mix4)
    tempfile county_year_rows
    save `county_year_rows'
    collapse (min) rows_min = rows (median) rows_median = rows (max) rows_max = rows ///
        (count) n_counties = rows, by(year)
    export excel using "$XL40", sheet("Counties_by_year", modify) firstrow(variables)
restore

* Codes outside the list
preserve
    keep if in_list == 0 & blank_code == 0
    collapse (sum) rows, by(year mix4)
    gen long neg_rows = -rows
    sort year neg_rows
    by year: keep if _n <= 10
    drop neg_rows
    export excel using "$XL40", sheet("Codes_outside_list", modify) firstrow(variables)
restore

* County consistency over time
preserve
    keep if in_list == 1
    gen double agri = (job == 1) if employed == 1 & employed_unclassified == 0
    collapse (mean) agri_share = agri [aweight = weight], by(year mix4)
    merge 1:1 year mix4 using `county_year_rows', nogenerate
    gen double ln_rows = ln(rows)
    keep year mix4 agri_share ln_rows
    reshape wide agri_share ln_rows, i(mix4) j(year)

    tempfile wide
    save `wide'

    tempname P
    tempfile corr
    postfile `P' int year double(rho_agri_prev rho_agri_ref rho_lnrows_prev rho_lnrows_ref) ///
        using `corr', replace
    forvalues y = 1385/1403 {
        local p = `y' - 1
        local a1 = .
        local a2 = .
        local n1 = .
        local n2 = .
        capture confirm variable agri_share`y' agri_share`p' agri_share`REF_YEAR'
        if !_rc {
            capture quietly correlate agri_share`y' agri_share`p'
            if !_rc local a1 = r(rho)
            capture quietly correlate agri_share`y' agri_share`REF_YEAR'
            if !_rc local a2 = r(rho)
            capture quietly correlate ln_rows`y' ln_rows`p'
            if !_rc local n1 = r(rho)
            capture quietly correlate ln_rows`y' ln_rows`REF_YEAR'
            if !_rc local n2 = r(rho)
        }
        post `P' (`y') (`a1') (`a2') (`n1') (`n2')
    }
    postclose `P'
    use `corr', clear
    foreach v of varlist rho_* {
        replace `v' = round(`v', 0.001)
    }
    label var rho_agri_prev "Corr. of county agriculture share with previous year"
    label var rho_agri_ref "Corr. of county agriculture share with reference year"
    label var rho_lnrows_prev "Corr. of log county sample size with previous year"
    label var rho_lnrows_ref "Corr. of log county sample size with reference year"
    export excel using "$XL40", sheet("County_consistency", modify) firstrow(variables)

    * Which counties move most between 1396, 1397 and 1398 (and 1391 to 1392)?
    use `wide', clear
    gen double d_lnrows_1392 = ln_rows1392 - ln_rows1391
    gen double d_agri_1392   = agri_share1392 - agri_share1391
    gen double d_lnrows_1397 = ln_rows1397 - ln_rows1396
    gen double d_agri_1397   = agri_share1397 - agri_share1396
    gen double d_lnrows_1398 = ln_rows1398 - ln_rows1397
    gen double d_agri_1398   = agri_share1398 - agri_share1397
    merge 1:1 mix4 using "$LOOKUP/agro_region_crosswalk_1385.dta", ///
        keepusing(province_name agro_region) keep(master match) nogenerate
    gen double abs_d_agri_1397 = abs(d_agri_1397)
    gsort -abs_d_agri_1397
    keep mix4 province_name agro_region agri_share1391 agri_share1392 agri_share1396 agri_share1397 ///
        agri_share1398 agri_share1399 ln_rows1396 ln_rows1397 ln_rows1398 ///
        d_agri_1392 d_lnrows_1392 d_agri_1397 d_lnrows_1397 d_agri_1398 d_lnrows_1398
    export excel using "$XL40", sheet("County_change", modify) firstrow(variables)
restore

*------------------------------------------------------------------------------*
* 2. Transitions: same county / province and merge to weather
*------------------------------------------------------------------------------*
use year_origin season_origin mix4_origin province85_origin province85_dest same_county ///
    invalid_mix_key weather_key_matched weather_common_sample ///
    using "$INTER/model_ready.dta", clear

gen double same_province = (province85_origin == province85_dest) ///
    if !missing(province85_origin) & !missing(province85_dest)
gen long transitions = 1

preserve
    collapse (sum) transitions (mean) same_county same_province invalid_mix_key ///
        weather_key_matched weather_common_sample, by(year_origin)
    foreach v in same_county same_province invalid_mix_key weather_key_matched weather_common_sample {
        replace `v' = round(100 * `v', 0.01)
    }
    rename same_county pct_same_county
    rename same_province pct_same_province
    rename invalid_mix_key pct_invalid_code
    rename weather_key_matched pct_matched_weather
    rename weather_common_sample pct_valid_weather
    export excel using "$XL40", sheet("Transitions_by_year", modify) firstrow(variables)
restore

preserve
    collapse (sum) transitions (mean) weather_common_sample, by(year_origin season_origin)
    replace weather_common_sample = round(100 * weather_common_sample, 0.01)
    rename weather_common_sample pct_valid_weather
    export excel using "$XL40", sheet("Merge_by_season", modify) firstrow(variables)
restore

preserve
    keep if weather_common_sample == 0
    collapse (sum) not_merged = transitions, by(year_origin mix4_origin)
    gen long neg_n = -not_merged
    sort year_origin neg_n
    by year_origin: keep if _n <= 10
    drop neg_n
    export excel using "$XL40", sheet("Unmerged_counties", modify) firstrow(variables)
restore

di as result "40 done."
log close step
