*==============================================================================*
* 30_timeseries_shares.do
* Time series 1384-1403 from the labor force survey (all people aged 15 and over,
* all census turns, weighted with Weight):
*   (a) sector shares among the employed (agriculture, industry, services)
*   (b) the five population shares (agriculture, industry, services,
*       unemployed, inactive)
* Employed people without a sector code (about 2.5 percent from 1401) are shown as a
* separate group, and a second version counts them as services.
*
* This script uses the individual file only. It does not depend on the run settings
* (years or fixed effects), so it always covers all years.
*
* Output: output/<RUN_NAME>/tables/30_timeseries_shares.xlsx
*         output/<RUN_NAME>/graphs/ts_employment_shares.pdf, ts_population_shares.pdf
*         output/<RUN_NAME>/results/timeseries_shares.dta
*
* Reading the graphs: the survey design changed in 1392 and the weights changed
* in 1396-1397, so small jumps in those years can come from the survey, not from the economy.
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/30_timeseries_shares.log", text replace name(step)

global XL30 "$TABLES/30_timeseries_shares.xlsx"

guide_sheet, file("$XL30") title("Time series of sector shares, 1384-1403") lines("Annual: Percent, weighted, people aged 15 and over. pop_* = share of the population (agriculture, industry, services, unemployed, inactive, employed without sector). emp_* = share of the employed, people without sector left out. empalt_* = share of the employed, people without sector counted as services. emp_unclassified = share of the employed with no sector code.|Year_season: Same by year and season.|Rows_by_year: Number of survey rows per year.|Notes: The survey design changed in 1392 and the weights changed in 1396-97. From 1401 about 2.5 percent of the employed have no sector code, probably military jobs.")

use "$INTER/lfs_individual.dta", clear
keep if age >= 15 & !missing(age) & !missing(Activity_Status) & !missing(weight) & weight > 0

* Population shares (they add up to 1 with the unclassified group)
gen double pop_agri = (job == 1)
gen double pop_ind  = (job == 2)
gen double pop_serv = (job == 3)
gen double pop_unemp = (job == 4)
gen double pop_inact = (job == 5)
gen double pop_unclassified = (employed_unclassified == 1)

* Shares among the employed, version 1: unclassified left out
gen double emp_agri = (job == 1) if Activity_Status == 0 & employed_unclassified == 0
gen double emp_ind  = (job == 2) if Activity_Status == 0 & employed_unclassified == 0
gen double emp_serv = (job == 3) if Activity_Status == 0 & employed_unclassified == 0

* Version 2: unclassified counted as services
gen double empalt_agri = (job_alt == 1) if Activity_Status == 0
gen double empalt_ind  = (job_alt == 2) if Activity_Status == 0
gen double empalt_serv = (job_alt == 3) if Activity_Status == 0

* Share of the employed who have no sector
gen double emp_unclassified = employed_unclassified if Activity_Status == 0

* Annual
preserve
    collapse (mean) pop_* emp_* empalt_* [aweight = weight], by(year)
    foreach v of varlist pop_* emp_* empalt_* {
        replace `v' = 100 * `v'
    }
    save "$RESULTS/timeseries_shares.dta", replace
    export excel using "$XL30", sheet("Annual", modify) firstrow(variables)
restore

* By year and season (for checking seasonal patterns)
preserve
    collapse (mean) pop_* emp_* empalt_* [aweight = weight], by(year season)
    foreach v of varlist pop_* emp_* empalt_* {
        replace `v' = 100 * `v'
    }
    export excel using "$XL30", sheet("Year_season", modify) firstrow(variables)
restore

* Unweighted row counts per year (survey size)
preserve
    gen long n_rows = 1
    collapse (sum) n_rows, by(year)
    export excel using "$XL30", sheet("Rows_by_year", modify) firstrow(variables)
restore

*------------------------------------------------------------------------------*
* Graphs
*------------------------------------------------------------------------------*
preserve
    use "$RESULTS/timeseries_shares.dta", clear
    graph set window fontface "Arial"

    twoway (line emp_agri year, lwidth(medthick)) ///
           (line emp_ind  year, lwidth(medthick) lpattern(dash)) ///
           (line emp_serv year, lwidth(medthick) lpattern(shortdash)), ///
        xline(1392, lcolor(gs10) lpattern(dot)) ///
        xline(1396.5, lcolor(gs10) lpattern(dot)) ///
        ytitle("Share of employed (%)", margin(medium)) xtitle("Year") ///
        xlabel(1384(2)1403, angle(45)) ylabel(, grid angle(0)) ///
        legend(order(1 "Agriculture" 2 "Industry" 3 "Services") rows(1) position(6)) ///
        note("Dotted lines: survey design change (1392), weight change (1396-97)." "Employed people with no sector are left out.", size(small)) ///
        graphregion(color(white))
    graph export "$GRAPHS/ts_employment_shares.pdf", replace

    twoway (line pop_agri year, lwidth(medthick)) ///
           (line pop_ind year, lwidth(medthick) lpattern(dash)) ///
           (line pop_serv year, lwidth(medthick) lpattern(shortdash)) ///
           (line pop_unemp year, lwidth(medthick) lpattern(longdash)) ///
           (line pop_inact year, lwidth(medthick) lpattern(dash_dot)), ///
        xline(1392, lcolor(gs10) lpattern(dot)) ///
        xline(1396.5, lcolor(gs10) lpattern(dot)) ///
        ytitle("Share of population aged 15+ (%)", margin(medium)) xtitle("Year") ///
        xlabel(1384(2)1403, angle(45)) ylabel(, grid angle(0)) ///
        legend(order(1 "Agriculture" 2 "Industry" 3 "Services" 4 "Unemployed" 5 "Inactive") rows(1) position(6)) ///
        note("Dotted lines: survey design change (1392), weight change (1396-97)." "Employed people with no sector are not shown.", size(small)) ///
        graphregion(color(white))
    graph export "$GRAPHS/ts_population_shares.pdf", replace
restore


di as result "30 done."
log close step
