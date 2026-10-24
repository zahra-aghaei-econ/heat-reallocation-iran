*==============================================================================*
* 28_lpm_person_linkage.do
* Robustness to the person-linkage rule.
*
*   A  Strict sample. The headline M7 regressions (Days35 and HeatDose35, seven outcomes)
*      are repeated on the people whose ID was built from the household member number
*      (pid_source == 1). Everything else (weather, controls, fixed effects, weights,
*      clustering) is unchanged. The member number exists from 1387 onward, so the strict
*      sample leaves out the origin years 1384 and 1385.
*   B  Linkage diagnostics on the headline Days35 sample: share of each ID tier, share of
*      matched pairs with the same sex and a plausible age gap, strict share by origin year.
*   C  Direct validation of the fallback rule. In the years where the member number exists,
*      the one-year same-season transitions are built twice: with the member-number ID
*      (benchmark) and with the relationship-based ID that ignores the member number
*      (pseudo fallback). We count how many benchmark transitions the fallback recovers,
*      how many of those are the wrong person, and whether the labor state agrees.
*
* Output: output/<RUN_NAME>/tables/28_lpm_person_linkage.xlsx
*         output/<RUN_NAME>/results/lpm_linkage_results.dta
*                                   linkage_flow.dta, linkage_tiers.dta, linkage_byyear.dta,
*                                   linkage_validation.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/28_lpm_person_linkage.log", text replace name(step)

global XL28 "$TABLES/28_lpm_person_linkage.xlsx"

prep_lpm_data

local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain')
make_sample, name(heat35) vars(heat35_10_s0 `rain')
gen byte smp_days35s = (smp_days35 == 1) & (pid_source == 1)
gen byte smp_heat35s = (smp_heat35 == 1) & (pid_source == 1)
label var smp_days35s "Sample: Days35, member-number IDs only"
label var smp_heat35s "Sample: HeatDose35, member-number IDs only"

*------------------------------------------------------------------------------*
* A. Regressions
*------------------------------------------------------------------------------*
open_results, file("$RESULTS/lpm_linkage_results.dta")
foreach y of global OUTCOMES {
    run_lpm, family("Linkage_Days35") panel("1_baseline") model(7) outcome(`y') ///
        wvars("days35_10_s0 `rain'") terms("days35_10_s0") rainterms("`rain'") sample(days35)
    run_lpm, family("Linkage_Days35") panel("2_strict") model(7) outcome(`y') ///
        wvars("days35_10_s0 `rain'") terms("days35_10_s0") rainterms("`rain'") sample(days35s)
    run_lpm, family("Linkage_HeatDose35") panel("1_baseline") model(7) outcome(`y') ///
        wvars("heat35_10_s0 `rain'") terms("heat35_10_s0") rainterms("`rain'") sample(heat35)
    run_lpm, family("Linkage_HeatDose35") panel("2_strict") model(7) outcome(`y') ///
        wvars("heat35_10_s0 `rain'") terms("heat35_10_s0") rainterms("`rain'") sample(heat35s)
}
close_results
export_long, file("$XL28") sheet("Results_long")

*------------------------------------------------------------------------------*
* B. Diagnostics
*------------------------------------------------------------------------------*
* Sample flow of the strict restriction (Days35 sample, before singleton removal)
quietly count if smp_days35 == 1
local nb = r(N)
quietly summarize Weight_origin if smp_days35 == 1
local wb = r(sum)
quietly count if smp_days35s == 1
local ns = r(N)
quietly summarize Weight_origin if smp_days35s == 1
local ws = r(sum)
preserve
    clear
    set obs 3
    gen str60 stage = ""
    gen double n_obs = .
    gen double weighted_n = .
    gen double pct_of_baseline = .
    gen double pct_weighted = .
    replace stage = "Headline Days35 sample" in 1
    replace n_obs = `nb' in 1
    replace weighted_n = `wb' in 1
    replace pct_of_baseline = 100 in 1
    replace pct_weighted = 100 in 1
    replace stage = "Member-number IDs only" in 2
    replace n_obs = `ns' in 2
    replace weighted_n = `ws' in 2
    replace pct_of_baseline = 100 * `ns' / `nb' in 2
    replace pct_weighted = 100 * `ws' / `wb' in 2
    replace stage = "Removed (relationship-based IDs)" in 3
    replace n_obs = `nb' - `ns' in 3
    replace weighted_n = `wb' - `ws' in 3
    replace pct_of_baseline = 100 * (`nb' - `ns') / `nb' in 3
    replace pct_weighted = 100 * (`wb' - `ws') / `wb' in 3
    save "$RESULTS/linkage_flow.dta", replace
    export excel using "$XL28", sheet("Flow", modify) firstrow(variables)
restore

* ID tiers inside the headline sample
tempname ht
tempfile ft
postfile `ht' byte pid_source str40 label long n_obs double share double wshare ///
    double same_sex_pct double age_gap_ok_pct using `ft', replace
forvalues s = 1/3 {
    quietly count if smp_days35 == 1 & pid_source == `s'
    local n = r(N)
    quietly summarize Weight_origin if smp_days35 == 1 & pid_source == `s'
    local w = cond(r(N) > 0, r(sum), 0)
    local ss = .
    local ag = .
    if `n' > 0 {
        quietly count if smp_days35 == 1 & pid_source == `s' & same_sex == 1
        local ss = 100 * r(N) / `n'
        quietly count if smp_days35 == 1 & pid_source == `s' & age_gap_ok == 1
        local ag = 100 * r(N) / `n'
    }
    local lab "Member number"
    if `s' == 2 local lab "Relationship + birth month"
    if `s' == 3 local lab "Relationship only"
    post `ht' (`s') ("`lab'") (`n') (100 * `n' / `nb') (100 * `w' / `wb') (`ss') (`ag')
}
postclose `ht'
preserve
    use `ft', clear
    save "$RESULTS/linkage_tiers.dta", replace
    export excel using "$XL28", sheet("ID_tiers", modify) firstrow(variables)
restore

* Strict share by origin year
preserve
    keep if smp_days35 == 1
    gen byte strict = (pid_source == 1)
    gen byte one = 1
    collapse (sum) n_obs = one n_strict = strict, by(year_origin)
    gen double strict_share = 100 * n_strict / n_obs
    save "$RESULTS/linkage_byyear.dta", replace
    export excel using "$XL28", sheet("By_year", modify) firstrow(variables)
restore

*------------------------------------------------------------------------------*
* C. Direct validation of the relationship-based fallback
*------------------------------------------------------------------------------*
use "$INTER/lfs_individual.dta", clear
keep if inrange(season, 1, 4) & inlist(census_turn, 1, 2, 3, 4)
gen byte job_use = job
if "$UNCLASSIFIED_AS_SERVICES" == "1" replace job_use = job_alt

gen str8  hh = strtrim(ID)
gen str1  sx = string(sex, "%01.0f")           if !missing(sex)
gen str2  byr = string(Birth_Year, "%02.0f")   if !missing(Birth_Year)
gen str2  bm = string(Birth_Month, "%02.0f")   if !missing(Birth_Month)
gen str2  mn = string(Member_Number, "%02.0f") if !missing(Member_Number)
gen str2  rl = string(Relationship, "%02.0f")  if !missing(Relationship)

* Benchmark ID: member-number based (same recipe as step 01, tier 1)
gen str40 mid = ""
replace mid = "M_" + hh + "_" + mn + "_" + byr + "_" + sx if hh != "" & mn != "" & byr != "" & sx != ""
* Pseudo fallback ID: relationship based, member number ignored (tier 2, then tier 3)
gen str50 fid = ""
replace fid = "RMB_" + hh + "_" + rl + "_" + byr + "_" + bm + "_" + sx ///
    if hh != "" & rl != "" & byr != "" & bm != "" & sx != ""
replace fid = "RB_" + hh + "_" + rl + "_" + byr + "_" + sx ///
    if fid == "" & hh != "" & rl != "" & byr != "" & sx != ""
* Same ambiguity rule as in step 01: a weak ID that appears twice in a wave is dropped
duplicates tag fid year season census_turn if fid != "", gen(df)
gen byte amb = (df > 0) if fid != ""
replace amb = 0 if fid != "" & missing(amb)
keep mid fid amb year season census_turn job_use
tempfile W
save `W', replace

* Benchmark transitions (turn 1 -> 3 and 2 -> 4, same season, one year later)
use `W', clear
keep if mid != "" & inlist(census_turn, 1, 2)
duplicates tag mid year season census_turn, gen(d)
drop if d > 0
gen byte dt = census_turn + 2
gen int  y1 = year + 1
gen byte s1 = season
rename year y0
rename season s0
rename census_turn t0
rename job_use job0
keep mid y0 s0 t0 y1 s1 dt job0
tempfile BO
save `BO', replace

use `W', clear
keep if mid != "" & inlist(census_turn, 3, 4)
duplicates tag mid year season census_turn, gen(d)
drop if d > 0
rename year y1
rename season s1
rename census_turn dt
rename job_use job1
keep mid y1 s1 dt job1
isid mid y1 s1 dt
tempfile BD
save `BD', replace

use `BO', clear
merge 1:1 mid y1 s1 dt using `BD', keep(match) nogen
gen byte ag0 = (job0 == 1 & inrange(job1, 1, 5))
keep if inrange(y0, $FIRST_ORIGIN_YEAR, $LAST_ORIGIN_YEAR)
tempfile BENCH
save `BENCH', replace

* Fallback transitions (member number ignored)
use `W', clear
keep if fid != "" & amb == 0
preserve
    keep if inlist(census_turn, 1, 2)
    duplicates tag fid year season census_turn, gen(d)
    drop if d > 0
    gen byte dt = census_turn + 2
    gen int  y1 = year + 1
    gen byte s1 = season
    rename year y0
    rename season s0
    rename census_turn t0
    rename mid mid0
    keep fid mid0 y0 s0 t0 y1 s1 dt
    tempfile FO
    save `FO', replace
restore
keep if inlist(census_turn, 3, 4)
duplicates tag fid year season census_turn, gen(d)
drop if d > 0
rename year y1
rename season s1
rename census_turn dt
rename mid mid1
rename job_use jobf
keep fid mid1 jobf y1 s1 dt
isid fid y1 s1 dt
tempfile FD
save `FD', replace

use `FO', clear
merge 1:1 fid y1 s1 dt using `FD', keep(match) nogen
keep if mid0 != ""
rename mid0 mid
isid mid y0 s0 t0
tempfile FB
save `FB', replace

* Compare
use `BENCH', clear
merge 1:1 mid y0 s0 t0 using `FB', gen(m)
keep if inlist(m, 1, 3)
gen byte rec   = (m == 3)
gen byte ver   = (rec == 1 & mid1 != "")
gen byte exact = (mid1 == mid) if ver == 1
gen byte wrong = (ver == 1 & exact == 0)
gen byte jobok = (jobf == job1) if rec == 1 & !missing(jobf, job1)
gen byte exit1 = (job1 != 1) if ag0 == 1
gen byte exitf = (jobf != 1) if ag0 == 1 & rec == 1 & inrange(jobf, 1, 5)
gen byte exitok = (exit1 == exitf) if ag0 == 1 & rec == 1 & !missing(exit1, exitf)

tempname hv
tempfile fv
postfile `hv' str40 group long bench_n long rec_n long ver_n long exact_n long wrong_n ///
    double rec_pct double exact_pct double wrong_pct double jobok_pct double exitok_pct using `fv', replace
foreach g in all ag {
    local cond ""
    local lab "All benchmark transitions"
    if "`g'" == "ag" {
        local cond "& ag0 == 1"
        local lab "Agriculture-origin transitions"
    }
    quietly count if 1 == 1 `cond'
    local B = r(N)
    quietly count if rec == 1 `cond'
    local R = r(N)
    quietly count if ver == 1 `cond'
    local V = r(N)
    quietly count if exact == 1 `cond'
    local E = r(N)
    quietly count if wrong == 1 `cond'
    local F = r(N)
    quietly summarize jobok if rec == 1 `cond'
    local J = 100 * r(mean)
    local X = .
    if "`g'" == "ag" {
        quietly summarize exitok if rec == 1 & ag0 == 1
        local X = 100 * r(mean)
    }
    post `hv' ("`lab'") (`B') (`R') (`V') (`E') (`F') (100 * `R' / `B') ///
        (100 * `E' / `V') (100 * `F' / `V') (`J') (`X')
}
postclose `hv'
use `fv', clear
save "$RESULTS/linkage_validation.dta", replace
export excel using "$XL28", sheet("Validation", modify) firstrow(variables)
list, noobs

guide_sheet, file("$XL28") title("Person-linkage robustness (28)") lines("Results_long: headline M7 on the baseline sample (panel 1) and on the strict sample with member-number IDs only (panel 2), Days35 and HeatDose35, seven outcomes. Percentage points per ten units of the heat measure.|Flow: size of the strict sample against the headline Days35 sample, before singleton removal.|ID_tiers: share of each ID tier in the headline sample, and the share of matched pairs with the same sex and an age gap of 0 to 2 years (diagnostics only, not used to drop anyone).|By_year: strict share by origin year (the member number exists from 1387 onward).|Validation: in the years with a member number, transitions rebuilt with the relationship-based ID (member number ignored) compared with the member-number benchmark: recovery, exact-person and wrong-person rates, agreement of the labor state.")

di as result "28 done."
log close step
