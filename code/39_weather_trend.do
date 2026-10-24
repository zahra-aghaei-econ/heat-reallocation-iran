*==============================================================================*
* 39_weather_trend.do
* Long-run trend of hot days. For each county and year we count the days with Tmax of
* 35C or more in the cleaned daily file; the figure shows the mean over counties
* (the 10th and 90th percentiles across counties are in the Excel file).
* A county-year is used only if at least 330 days have a valid Tmax.
* Output: output/<RUN_NAME>/graphs/ts_days35_trend.pdf
*         output/<RUN_NAME>/tables/39_weather_trend.xlsx (yearly means)
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/39_weather_trend.log", text replace name(step)

global XL39 "$TABLES/39_weather_trend.xlsx"

use mix4 year d_days35 valid_tmax_day using "$INTER/weather_daily_base_county.dta", clear
collapse (sum) hot_days = d_days35 valid_days = valid_tmax_day, by(mix4 year)
keep if valid_days >= 330
collapse (mean) days35 = hot_days (p10) p10 = hot_days (p90) p90 = hot_days (count) n_counties = hot_days, by(year)
keep if year >= 1340
save "$RESULTS/weather_trend_days35.dta", replace

guide_sheet, file("$XL39") title("Days with Tmax of 35C or more, yearly mean over counties") ///
    lines("Yearly: year, mean number of days per county (days35), 10th and 90th percentile across counties, number of counties used.|Notes: A county-year is used only if at least 330 days have a valid Tmax. Years before 1340 are not shown.")
export excel using "$XL39", sheet("Yearly", modify) firstrow(variables)

twoway (line days35 year, lwidth(medthick) lcolor(maroon)) ///
       (lfit days35 year, lpattern(dash) lcolor(gs6)), ///
    xline(1384, lcolor(gs10) lpattern(dot)) ///
    ytitle("Days per year with Tmax of 35C or more" "(mean over counties)", margin(medium)) xtitle("Year") ///
    xlabel(1340(10)1400, angle(45)) ylabel(40(5)70, grid angle(0)) ///
    legend(order(1 "Mean over counties" 2 "Linear trend") rows(1) position(6) size(small)) ///
    note("Dotted line: first year of the labour force survey sample (1384).", size(small)) ///
    graphregion(color(white))
graph export "$GRAPHS/ts_days35_trend.pdf", replace

di as result "39 done."
log close step
