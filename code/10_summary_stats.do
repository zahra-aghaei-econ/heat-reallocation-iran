*==============================================================================*
* 10_summary_stats.do
* Summary statistics (thesis Tables 1 and 2).
*   Table 1: all one-year transitions with a known destination and matched weather
*            (people from every labor state at the origin).
*   Table 2: only people who work in agriculture at the origin (the estimation sample).
* All means and standard deviations are weighted with Weight_origin.
* Shares of categories (sex, marital status, urban) are the mean of a 0/1 variable.
*
* Output: output/<RUN_NAME>/tables/10_summary_stats.xlsx
*         output/<RUN_NAME>/results/summary_stats.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/10_summary_stats.log", text replace name(step)

global XL10 "$TABLES/10_summary_stats.xlsx"

load_model_data

* Base sample for Table 1: known destination, valid weight and IDs, run years,
* weather matched with enough valid days.
gen byte base_all = inrange(job_dest, 1, 5) & (Weight_origin > 0) & !missing(Weight_origin) ///
    & !missing(mix_id) & !missing(province_year) & !missing(pair_id) ///
    & inrange(season_origin, 1, 4) & $YEARS_IF & weather_common_sample == 1
gen byte base_agri = base_all & job_origin == 1

quietly count if base_all == 1
local n_all = r(N)
quietly count if base_agri == 1
local n_agri = r(N)
di as result "Table 1 sample: `n_all'   Table 2 sample: `n_agri'"

*------------------------------------------------------------------------------*
* One row per variable
*------------------------------------------------------------------------------*
capture postclose st
postfile st str4 table_id str32 varname str70 label double mean double sd ///
    double min double max long n_obs using "$RESULTS/summary_stats.dta", replace

capture program drop post_stat
program define post_stat
    syntax varname(numeric), TABLE(string) LABEL(string) TOUSE(varname)
    quietly summarize `varlist' [aweight = Weight_origin] if `touse' == 1
    if r(N) > 0 {
        post st ("`table'") ("`varlist'") ("`label'") (r(mean)) (r(sd)) (r(min)) (r(max)) (r(N))
    }
    else {
        post st ("`table'") ("`varlist'") ("`label'") (.) (.) (.) (.) (0)
    }
end

* Weather variables shown in both tables
local wx "days35_10_s0 days37_10_s0 days40_10_s0 heat35_10_s0 rain100_s0"

foreach t in T1 T2 {
    local touse "base_all"
    if "`t'" == "T2" local touse "base_agri"

    * Labor state at the origin and one year later
    if "`t'" == "T1" {
        foreach j in 1 2 3 4 5 {
            gen byte __o`j' = (job_origin == `j') if `touse' == 1
            gen byte __d`j' = (job_dest == `j')   if `touse' == 1
            post_stat __o`j', table("T1") label("Share at origin: state `j'") touse(`touse')
            post_stat __d`j', table("T1") label("Share one year later: state `j'") touse(`touse')
            drop __o`j' __d`j'
        }
    }
    else {
        foreach y in exit_agri productive_exit distress_exit dest2 dest3 dest4 dest5 {
            post_stat `y', table("T2") label("Outcome: `y'") touse(`touse')
        }
    }

    foreach w of local wx {
        local wl : variable label `w'
        post_stat `w', table("`t'") label("Weather: `wl'") touse(`touse')
    }

    post_stat age_origin, table("`t'") label("Age") touse(`touse')

    foreach v in sex_origin marital_origin urban_origin {
        quietly levelsof `v' if `touse' == 1, local(lv)
        foreach c of local lv {
            local lab : label (`v') `c'
            gen byte __cat = (`v' == `c') if `touse' == 1
            post_stat __cat, table("`t'") label("Share: `v' = `c' (`lab')") touse(`touse')
            drop __cat
        }
    }

    * Education is an appendix-only control
    capture confirm variable educ_origin
    if !_rc {
        gen byte __edu_obs = !missing(educ_origin) if `touse' == 1
        post_stat __edu_obs, table("`t'") label("Education observed (appendix control)") touse(`touse')
        drop __edu_obs
        quietly levelsof educ_origin if `touse' == 1, local(lv)
        foreach c of local lv {
            local lab : label (educ_origin) `c'
            gen byte __cat = (educ_origin == `c') if `touse' == 1 & !missing(educ_origin)
            post_stat __cat, table("`t'") label("Share: educ_origin = `c' (`lab')") touse(`touse')
            drop __cat
        }
    }
}
postclose st

*------------------------------------------------------------------------------*
* Excel
*------------------------------------------------------------------------------*
guide_sheet, file("$XL10") title("Summary statistics (Tables 1 and 2)") lines("Table1_all_origin: All transitions with known destination and matched weather. Both the origin state and the state one year later are shown as shares.|Table2_agri_origin: Agriculture workers at the origin (the sample of the main models). Outcomes are 0/1 here, so means are shares.|Sample: Number of observations in each table.|Notes: Means and standard deviations use Weight_origin. Weather is measured in the origin season: Days35 = days with Tmax of 35C or more divided by 10, HeatDose35 = degrees above 35C summed over days divided by 10, rain100 = seasonal rainfall in 100 mm.")

preserve
    use "$RESULTS/summary_stats.dta", clear
    keep if table_id == "T1"
    drop table_id varname
    export excel using "$XL10", sheet("Table1_all_origin", modify) firstrow(variables)
restore
preserve
    use "$RESULTS/summary_stats.dta", clear
    keep if table_id == "T2"
    drop table_id varname
    export excel using "$XL10", sheet("Table2_agri_origin", modify) firstrow(variables)
restore

putexcel set "$XL10", sheet("Sample") modify
putexcel A1 = "Sample sizes"
putexcel A3 = "Table 1 (all origin states)"
putexcel B3 = `n_all'
putexcel A4 = "Table 2 (agriculture at origin)"
putexcel B4 = `n_agri'
putexcel clear

di as result "10 done."
log close step
