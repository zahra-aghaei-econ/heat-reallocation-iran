*==============================================================================*
* 00_setup.do
* Settings used by every other do-file: folders, run settings, small programs.
* You do not run this file alone. master.do runs it first.
*==============================================================================*

version 17
set more off
set varabbrev off

if "$ROOT" == "" {
    di as error "ROOT is empty. Please run master.do (it sets ROOT first)."
    exit 198
}

*------------------------------------------------------------------------------*
* 1. Run settings
*------------------------------------------------------------------------------*
* RUN_NAME comes from master.do. Each run writes to its own output folder,
* so the three runs never overwrite each other.
*
*   run1_old_period_pairFE : old sample (origin 1384-1398), WITH pair fixed effects.
*                            Only used to check that we reproduce the thesis numbers.
*   run2_old_period        : old sample, WITHOUT pair fixed effects.
*   run3_new_period        : new sample (origin 1384-1402), WITHOUT pair fixed effects.

if "$RUN_NAME" == "" global RUN_NAME "run3_new_period"

if "$RUN_NAME" == "run1_old_period_pairFE" {
    global FIRST_ORIGIN_YEAR 1384
    global LAST_ORIGIN_YEAR  1398
    global USE_PAIR_FE       1
}
else if "$RUN_NAME" == "run2_old_period" {
    global FIRST_ORIGIN_YEAR 1384
    global LAST_ORIGIN_YEAR  1398
    global USE_PAIR_FE       0
}
else if "$RUN_NAME" == "run3_new_period" {
    global FIRST_ORIGIN_YEAR 1384
    global LAST_ORIGIN_YEAR  1402
    global USE_PAIR_FE       0
}
else {
    di as error "Unknown RUN_NAME: $RUN_NAME"
    exit 198
}

* Employed people without a sector code (about 2.5 percent from 1401, probably military
* jobs that are not in the ISIC file).
*   1 = they are counted as services (the version reported in the paper; set in master.do)
*   0 = they get no labor-market state and are left out (robustness version)
if "$UNCLASSIFIED_AS_SERVICES" == "" global UNCLASSIFIED_AS_SERVICES 0
* With the switch at 1 the run gets its own output folder (name ends in _svc),
* so the main version is never overwritten.
if "$UNCLASSIFIED_AS_SERVICES" == "1" & strpos("$RUN_NAME", "_svc") == 0 global RUN_NAME "${RUN_NAME}_svc"

* Multinomial logit is slow, so it is switched off in the first round.
if "$RUN_MNL" == "" global RUN_MNL 0

*------------------------------------------------------------------------------*
* 2. Folders and input files
*------------------------------------------------------------------------------*
global CODE   "$ROOT/code"
global DATA   "$ROOT/data"
global INTER  "$ROOT/intermediate"
global LOOKUP "$ROOT/lookups"
global BUILD  "$ROOT/output/data_build"
global OUT    "$ROOT/output/$RUN_NAME"
global TABLES "$OUT/tables"
global RESULTS "$OUT/results"
global GRAPHS "$OUT/graphs"
global LOGS   "$OUT/logs"

* The two raw inputs (put them in the data folder with these names)
global LFS_FILE     "$DATA/lfs.dta"
global WEATHER_FILE "$DATA/weather_daily.dta"

foreach d in "$ROOT/intermediate" "$ROOT/output" "$BUILD" "$OUT" "$TABLES" "$RESULTS" "$GRAPHS" "$LOGS" {
    capture mkdir "`d'"
}

*------------------------------------------------------------------------------*
* 3. Weather settings
*------------------------------------------------------------------------------*
* Fixed reference years for the local climate (before the LFS starts)
global REF_START 1330
global REF_END   1383

* A season is used only if at least 60 percent of its days are observed
global MIN_COVERAGE      0.60
* A county-season needs at least 15 good reference years
global MIN_VALID_REF_YRS 15

*------------------------------------------------------------------------------*
* 4. Sample and model settings
*------------------------------------------------------------------------------*
* Origin years used in the models
global YEARS_IF "inrange(year_origin, $FIRST_ORIGIN_YEAR, $LAST_ORIGIN_YEAR)"

* People who work in agriculture at the origin and have a known destination
global AG_SAMPLE "job_origin == 1 & !missing(job_dest) & Weight_origin > 0 & !missing(Weight_origin) & $YEARS_IF"

* Fixed effects in the main model: county, province x year, origin season.
* The pair fixed effect (turn 1->3 or 2->4) is added only in run 1.
global FE_LIST "mix_id province_year season_origin"
if $USE_PAIR_FE == 1 global FE_LIST "$FE_LIST pair_id"

*------------------------------------------------------------------------------*
* 5. Small programs
*------------------------------------------------------------------------------*

* make_mix4 builds a 4-character county code: province (2 digits) + county (2 digits)
capture program drop make_mix4
program define make_mix4
    version 17
    syntax , PROVince(name) COUNTy(name) GENerate(name)

    capture drop `generate'
    tempvar pv cv
    gen str20 `pv'   = ""
    gen str20 `cv' = ""

    capture confirm string variable `province'
    if !_rc {
        replace `pv' = strtrim(`province')
    }
    else {
        replace `pv' = string(`province', "%20.0f") if !missing(`province')
    }

    capture confirm string variable `county'
    if !_rc {
        replace `cv' = strtrim(`county')
    }
    else {
        replace `cv' = string(`county', "%20.0f") if !missing(`county')
    }

    replace `pv'   = subinstr(`pv', " ", "", .)
    replace `cv' = subinstr(`cv', " ", "", .)

    * make sure the codes have two digits (keep the leading zero)
    replace `pv'   = string(real(`pv'),   "%02.0f") if `pv'   != "" & real(`pv')   < .
    replace `cv' = string(real(`cv'), "%02.0f") if `cv' != "" & real(`cv') < .

    gen str4 `generate' = `pv' + `cv' if `pv' != "" & `cv' != ""
    label var `generate' "County code (province + county, 4 characters)"
end

* make_outcomes builds the exit outcomes from job_origin and job_dest.
* Outcomes exist only for people who work in agriculture at the origin.
capture program drop make_outcomes
program define make_outcomes
    version 17
    capture drop stay_agri exit_agri productive_exit distress_exit dest1 dest2 dest3 dest4 dest5
    gen byte stay_agri       = (job_dest == 1)        if job_origin == 1 & !missing(job_dest)
    gen byte exit_agri       = (job_dest != 1)        if job_origin == 1 & !missing(job_dest)
    gen byte productive_exit = inlist(job_dest, 2, 3) if job_origin == 1 & !missing(job_dest)
    gen byte distress_exit   = inlist(job_dest, 4, 5) if job_origin == 1 & !missing(job_dest)
    forvalues k = 1/5 {
        gen byte dest`k' = (job_dest == `k') if job_origin == 1 & !missing(job_dest)
    }
    label var stay_agri       "Agriculture at origin: stays in agriculture"
    label var exit_agri       "Agriculture at origin: leaves agriculture"
    label var productive_exit "Agriculture at origin: moves to industry or services"
    label var distress_exit   "Agriculture at origin: becomes unemployed or inactive"
end

* load_model_data opens the model-ready file. If the switch above is 1,
* unclassified employed people are counted as services before the outcomes are built.
capture program drop load_model_data
program define load_model_data
    version 17
    use "$INTER/model_ready.dta", clear
    if "$UNCLASSIFIED_AS_SERVICES" == "1" {
        replace job_origin = job_origin_alt
        replace job_dest   = job_dest_alt
        make_outcomes
        di as result "Unclassified employed people are counted as services."
    }
end

* User-written packages (install them once with install_packages.do)
foreach p in reghdfe ftools {
    capture which `p'
    if _rc {
        di as error "Package `p' is missing. Run install_packages.do once (or: ssc install `p', replace)."
        exit 199
    }
}

* Programs shared by the model do-files
do "$CODE/lib_models.do"

di as result "Setup done. Run: $RUN_NAME   Origin years: $FIRST_ORIGIN_YEAR-$LAST_ORIGIN_YEAR   Pair FE: $USE_PAIR_FE"
