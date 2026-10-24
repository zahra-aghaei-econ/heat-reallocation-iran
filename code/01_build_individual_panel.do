*==============================================================================*
* 01_build_individual_panel.do
* Reads the raw LFS, builds a person ID and the five labor-market states,
* and then builds the one-year transitions (origin -> destination).
*
* Input : data/lfs.dta
* Output: intermediate/lfs_individual.dta
*         intermediate/transitions_same_season.dta   (main file)
*         intermediate/transitions_annual.dta        (no season rule, used in robustness)
*         output/data_build/01_individual_panel_diagnostics.xlsx
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$BUILD/01_build_individual_panel.log", text replace name(step)

global XL01 "$BUILD/01_individual_panel_diagnostics.xlsx"

* Start the Excel file with a guide sheet
putexcel set "$XL01", sheet("00_Guide") replace
putexcel A1 = "Individual panel diagnostics"
putexcel A3 = "Sheet"
putexcel B3 = "What it shows"
putexcel A4 = "lfs_by_year"
putexcel B4 = "Rows, person-ID source, ambiguous IDs, employed people without a sector, agriculture share, by survey year."
putexcel A5 = "transitions_same_season"
putexcel B5 = "Origin rows (turn 1 or 2) and how many were found again one year later in the same season, by origin year."
putexcel A6 = "transitions_annual"
putexcel B6 = "Same as above but without the same-season rule."
putexcel clear

*------------------------------------------------------------------------------*
* 1. Load the LFS (only the variables we need)
*------------------------------------------------------------------------------*
use ID Sex Birth_Year Birth_Month Member_Number Relationship Age Education_Level ///
    Marital_Status Urban_Rural Activity_Status Main_Job_Workplace_ISIC_Code Industry ///
    Weight Year Season Census_Turn Province_85_code County_85_code ///
    using "$LFS_FILE", clear

* These three must be numbers, not text
confirm numeric variable Year Season Census_Turn

rename Year        year
rename Season      season
rename Census_Turn census_turn
rename Weight      weight

count
local n_raw = r(N)

*------------------------------------------------------------------------------*
* 2. County code (1385 counties) and province
*------------------------------------------------------------------------------*
make_mix4, province(Province_85_code) county(County_85_code) generate(mix4)
count if missing(mix4)
local n_missing_mix4 = r(N)
if `n_missing_mix4' > 0.01 * _N {
    di as error "More than 1 percent of rows have no county code. Check Province_85_code and County_85_code."
    exit 459
}

gen int province85 = real(Province_85_code)
label var province85 "Province code (1385 borders)"

*------------------------------------------------------------------------------*
* 3. Person ID
*------------------------------------------------------------------------------*
* The LFS has no person ID, so we build one from household ID and personal traits.
*   Tier 1: household ID + member number + birth year + sex
*   Tier 2: household ID + relationship + birth year + birth month + sex
*   Tier 3: household ID + relationship + birth year + sex   (weakest)
* Tier 2 and 3 are used only when the member number is missing.

gen str8 id_hh_s = strtrim(ID)
gen str1 sex_s   = string(Sex, "%01.0f")          if !missing(Sex)
gen str2 by_s    = string(Birth_Year, "%02.0f")   if !missing(Birth_Year)
gen str2 bm_s    = string(Birth_Month, "%02.0f")  if !missing(Birth_Month)
gen str2 mn_s    = string(Member_Number, "%02.0f") if !missing(Member_Number)
gen str2 rel_s   = string(Relationship, "%02.0f") if !missing(Relationship)

gen byte pid_source = .
label define pid_source_lbl 1 "Member number" 2 "Relationship + birth month" 3 "Relationship only", replace
label values pid_source pid_source_lbl
label var pid_source "How the person ID was built"

gen str40 pid_str = ""

replace pid_str = "M_" + id_hh_s + "_" + mn_s + "_" + by_s + "_" + sex_s ///
    if id_hh_s != "" & mn_s != "" & by_s != "" & sex_s != ""
replace pid_source = 1 if pid_str != ""

replace pid_str = "RMB_" + id_hh_s + "_" + rel_s + "_" + by_s + "_" + bm_s + "_" + sex_s ///
    if pid_str == "" & id_hh_s != "" & rel_s != "" & by_s != "" & bm_s != "" & sex_s != ""
replace pid_source = 2 if missing(pid_source) & pid_str != ""

replace pid_str = "RB_" + id_hh_s + "_" + rel_s + "_" + by_s + "_" + sex_s ///
    if pid_str == "" & id_hh_s != "" & rel_s != "" & by_s != "" & sex_s != ""
replace pid_source = 3 if missing(pid_source) & pid_str != ""

egen long pid = group(pid_str) if pid_str != ""
label var pid "Numeric person ID"
drop id_hh_s sex_s by_s bm_s mn_s rel_s

* Same person twice in the same wave means the ID is not unique.
* For the weaker tiers (2 and 3) we drop such cases later.
duplicates tag pid year season census_turn if !missing(pid), gen(dup_pid_wave_season)
duplicates tag pid year census_turn if !missing(pid), gen(dup_pid_wave_annual)

*------------------------------------------------------------------------------*
* 4. Labor-market state
*------------------------------------------------------------------------------*
* Activity_Status: 0 = employed, 1 = unemployed, 2 = inactive.
* For the employed we find the sector from the industry text (new years)
* or from the ISIC code (all years).

gen str10 isic_main = strtrim(Main_Job_Workplace_ISIC_Code)
replace isic_main = "" if inlist(isic_main, ".", "0", "00000")
replace isic_main = subinstr(isic_main, " ", "", .)
gen long isic_num = real(isic_main)
gen int  isic2    = real(substr(isic_main, 1, 2))

gen str120 industry_clean = lower(strtrim(Industry))
replace industry_clean = subinstr(industry_clean, char(160), " ", .)
replace industry_clean = strtrim(itrim(industry_clean))

gen byte sector = .

* (a) Industry text first
replace sector = 1 if Activity_Status == 0 & strpos(industry_clean, "agriculture") > 0
replace sector = 2 if Activity_Status == 0 & missing(sector) & ( ///
    strpos(industry_clean, "mining") > 0 | ///
    strpos(industry_clean, "manufacturing") > 0 | ///
    strpos(industry_clean, "electricity") > 0 | ///
    strpos(industry_clean, "water supply") > 0 | ///
    strpos(industry_clean, "construction") > 0 )
replace sector = 3 if Activity_Status == 0 & missing(sector) & industry_clean != ""

* (b) Old years (before 1392): 3 or 4 digit codes
replace sector = 1 if Activity_Status == 0 & missing(sector) & year < 1392 & inrange(isic_num, 111, 500)
replace sector = 2 if Activity_Status == 0 & missing(sector) & year < 1392 & inrange(isic_num, 1000, 4550)
replace sector = 3 if Activity_Status == 0 & missing(sector) & year < 1392 & inrange(isic_num, 5000, 9999)

* (c) New years (1392 on): 4 or 5 digit codes. Leading zeros can be lost.
replace sector = 1 if Activity_Status == 0 & missing(sector) & year >= 1392 & (inrange(isic_num, 111, 3220) | inrange(isic2, 1, 3))
replace sector = 2 if Activity_Status == 0 & missing(sector) & year >= 1392 & inrange(isic_num, 5100, 43999)
replace sector = 3 if Activity_Status == 0 & missing(sector) & year >= 1392 & inrange(isic_num, 45000, 99000)

* (d) Last step: first two digits of the code (this is what works for 1402-1403,
*     where the file only has 2-digit ISIC divisions)
replace sector = 1 if Activity_Status == 0 & missing(sector) & inrange(isic2, 1, 3)
replace sector = 2 if Activity_Status == 0 & missing(sector) & inrange(isic2, 5, 43)
replace sector = 3 if Activity_Status == 0 & missing(sector) & inrange(isic2, 45, 99)

label define sector_lbl 1 "Agriculture" 2 "Industry" 3 "Services", replace
label values sector sector_lbl
label var sector "Sector of main job (employed only)"

gen byte job = .
replace job = sector if Activity_Status == 0 & inlist(sector, 1, 2, 3)
replace job = 4 if Activity_Status == 1
replace job = 5 if Activity_Status == 2
label define job_lbl 1 "Agriculture" 2 "Industry" 3 "Services" 4 "Unemployed" 5 "Inactive", replace
label values job job_lbl
label var job "Labor-market state (5 categories)"

* Employed people whose sector we could not find (they get no job state)
gen byte employed_unclassified = (Activity_Status == 0 & missing(sector))

* Alternative version: they are counted as services (used only if the switch is on)
gen byte job_alt = job
replace job_alt = 3 if employed_unclassified == 1
label values job_alt job_lbl
label var job_alt "Labor-market state, unclassified employed counted as services"

*------------------------------------------------------------------------------*
* 5. Controls
*------------------------------------------------------------------------------*
rename Age age
gen double age2 = age^2 if !missing(age)
label var age  "Age"
label var age2 "Age squared"

gen byte female = (Sex == 1) if !missing(Sex)       // Sex: 0 = male, 1 = female
label var female "Female"

gen byte urban = (Urban_Rural == 1) if !missing(Urban_Rural)
label var urban "Urban (Urban_Rural = 1)"

rename Education_Level educ
rename Marital_Status  marital
rename Sex             sex

*------------------------------------------------------------------------------*
* 6. Diagnostics by year, then save the individual file
*------------------------------------------------------------------------------*
preserve
    gen byte has_pid      = !missing(pid)
    gen byte tier1        = (pid_source == 1)
    gen byte tier2or3     = inlist(pid_source, 2, 3)
    gen byte ambiguous    = inlist(pid_source, 2, 3) & (dup_pid_wave_season > 0 | dup_pid_wave_annual > 0)
    gen byte employed     = (Activity_Status == 0)
    gen byte agri         = (job == 1)
    gen byte one          = 1
    collapse (sum) rows = one has_pid tier1 tier2or3 ambiguous employed ///
             employed_unclassified agri, by(year)
    gen share_unclassified = employed_unclassified / employed
    gen share_agri_of_employed = agri / employed
    export excel using "$XL01", sheet("lfs_by_year", modify) firstrow(variables)
restore

keep pid pid_str pid_source ID Member_Number Relationship year season census_turn ///
     mix4 province85 job job_alt sector Activity_Status employed_unclassified ///
     dup_pid_wave_season dup_pid_wave_annual weight age age2 sex female educ marital urban ///
     Birth_Year Birth_Month

compress
save "$INTER/lfs_individual.dta", replace

*------------------------------------------------------------------------------*
* 7. Transitions
*------------------------------------------------------------------------------*
* A person is first seen in census turn 1 or 2 (origin) and then again one
* year later in turn 3 or 4 (destination): 1 -> 3 and 2 -> 4.
* Same-season file: origin and destination must be in the same season.
* Annual file: no season rule.

capture program drop make_transitions
program define make_transitions
    version 17
    syntax , SAVING(string) SHEET(string) [SAMEseason]

    use "$INTER/lfs_individual.dta", clear
    drop if missing(pid)

    * Drop weak-ID people who appear twice in the same wave
    if "`sameseason'" == "" {
        drop if inlist(pid_source, 2, 3) & dup_pid_wave_annual > 0
        drop if inlist(pid_source, 2, 3) & dup_pid_wave_season > 0 & !missing(season)
        local key ""
        local keyd ""
    }
    else {
        drop if missing(season)
        drop if inlist(pid_source, 2, 3) & dup_pid_wave_season > 0
        local key "season"
        local keyd "season_dest"
    }

    * ---- origin side (turn 1 or 2) ----
    preserve
        keep if inlist(census_turn, 1, 2)
        duplicates tag pid year `key' census_turn, gen(dup_o)
        drop if dup_o > 0

        gen byte pair_id   = 13 if census_turn == 1
        replace  pair_id   = 24 if census_turn == 2
        gen byte dest_turn = census_turn + 2
        gen int  year_dest = year + 1
        if "`sameseason'" != "" gen byte season_dest = season

        rename year          year_origin
        rename season        season_origin
        rename census_turn   census_turn_origin
        rename mix4          mix4_origin
        rename province85    province85_origin
        rename job           job_origin
        rename job_alt       job_origin_alt
        rename sector        sector_origin
        rename Activity_Status activity_origin
        rename weight        Weight_origin
        rename age           age_origin
        rename age2          age2_origin
        rename sex           sex_origin
        rename female        female_origin
        rename educ          educ_origin
        rename marital       marital_origin
        rename urban         urban_origin

        keep pid pid_str pid_source pair_id dest_turn year_origin year_dest `keyd' season_origin ///
             census_turn_origin mix4_origin province85_origin job_origin job_origin_alt sector_origin activity_origin ///
             Weight_origin age_origin age2_origin sex_origin female_origin educ_origin ///
             marital_origin urban_origin
        tempfile origins
        save `origins', replace
    restore

    * ---- destination side (turn 3 or 4) ----
    keep if inlist(census_turn, 3, 4)
    duplicates tag pid year `key' census_turn, gen(dup_d)
    drop if dup_d > 0

    rename year          year_dest
    rename season        season_dest
    rename census_turn   dest_turn
    rename mix4          mix4_dest
    rename province85    province85_dest
    rename job           job_dest
    rename job_alt       job_dest_alt
    rename sector        sector_dest
    rename Activity_Status activity_dest
    rename weight        Weight_dest
    rename age           age_dest
    rename age2          age2_dest
    rename sex           sex_dest
    rename female        female_dest
    rename educ          educ_dest
    rename marital       marital_dest
    rename urban         urban_dest

    keep pid year_dest season_dest dest_turn mix4_dest province85_dest job_dest job_dest_alt sector_dest ///
         activity_dest Weight_dest age_dest age2_dest sex_dest female_dest educ_dest ///
         marital_dest urban_dest
    isid pid year_dest `keyd' dest_turn

    * ---- put the two sides together ----
    merge 1:1 pid year_dest `keyd' dest_turn using `origins', gen(_merge_tr)
    drop if _merge_tr == 2          // destination without an origin: not a transition

    * Matching rate by origin year (saved to Excel)
    preserve
        gen byte matched = (_merge_tr == 3)
        collapse (count) origin_rows = pid (sum) matched, by(year_origin)
        gen match_rate = matched / origin_rows
        export excel using "$XL01", sheet("`sheet'", modify) firstrow(variables)
    restore

    keep if _merge_tr == 3
    drop _merge_tr

    * Checks (not used to drop people)
    gen byte same_county = (mix4_origin == mix4_dest) if mix4_origin != "" & mix4_dest != ""
    gen byte same_sex    = (sex_origin == sex_dest) if !missing(sex_origin, sex_dest)
    gen byte age_gap_ok  = inrange(age_dest - age_origin, 0, 2) if !missing(age_origin, age_dest)

    * Outcomes (only for people who work in agriculture at the origin)
    make_outcomes

    label var pair_id         "13 = turn 1 to 3; 24 = turn 2 to 4"
    label var same_county     "Same county at origin and destination"
    label var age_gap_ok      "Age gap between origin and destination is 0 to 2 years"

    compress
    save "`saving'", replace
end

make_transitions, saving("$INTER/transitions_same_season.dta") sheet("transitions_same_season") sameseason
make_transitions, saving("$INTER/transitions_annual.dta")      sheet("transitions_annual")

*------------------------------------------------------------------------------*
* 8. A few numbers on the guide sheet
*------------------------------------------------------------------------------*
putexcel set "$XL01", sheet("00_Guide") modify
putexcel A8 = "Raw LFS rows"
putexcel B8 = `n_raw'
putexcel A9 = "Rows without county code"
putexcel B9 = `n_missing_mix4'
putexcel clear

di as result "01 done."
log close step
