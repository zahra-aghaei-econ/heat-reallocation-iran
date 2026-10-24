# Where each table and figure of the paper comes from

All files are written for one run into `output/<RUN_NAME>/` (the paper uses
`output/run3_new_period_svc/`).

* `tex/*.tex`: LaTeX table fragments (only the `tabular`; caption, label and notes are in the
  paper). They are written by `code/50_tex_tables.do` or by the Python scripts in `tools/`,
  which only read the result files in `results/` and run no regression.
* `graphs/*.pdf`: figures, written by the Stata step named in the table.
* `results/*.dta`: all estimates (one row per coefficient) used by the tables.
* `tables/*.xlsx`: one Excel workbook per step with all estimates, sample sizes and a guide sheet.

"Step" is the do-file in `code/` that estimates the numbers; "Writer" is the file that turns
them into the fragment.

## Main text

| Paper exhibit (label) | File | Step | Writer |
|---|---|---|---|
| Sector shares among the employed (`fig:sector_share`) | `ts_employment_shares.pdf` | 30 | 30 |
| Days per year at or above 35C (`fig:weather_trend`) | `ts_days35_trend.pdf` | 39 | 39 |
| Mean days at or above 35C, by county (`fig:map_days35`) | `map_days35_year.pdf` | 61 | 61 |
| Agro-climatic regions (`fig:map_regions`) | `map_regions.pdf` | 61 | 61 |
| Transition matrix, five states (`tab:transition_matrix`) | `transition_matrix.tex` | 11 | `make_tex_tables_b.py` |
| Headline table, Days35 (`tab:headline_days35`) | `headline.tex` | 20 | 50 |
| Coefficients and baseline rates (`tab:ratio`) | `ratio_table.tex` | 10, 20 | 50 |
| Specification progression M1-M8 (`tab:main1_progression`) | `progression.tex` | 21 | `make_tex_tables.py` |
| Preferred against saturated fixed effects (`tab:main_saturated_summary`) | `saturated.tex` | 24 | `make_tex_tables.py` |
| Destination coefficients (`fig:destination_coefficients`) | `coef_main_Days35.pdf`, `coef_main_HeatDose35.pdf` | 24 | 60 |
| Binned scatter (`fig:binscatter`) | `bs_fwl_days35_exit_agri.pdf`, `bs_fwl_heat35_exit_agri.pdf` | 35 | 35 |
| All origin states (`tab:allorigin_matrix`) | `allorigin.tex` | 25 | `make_tex_tables_b.py` |
| One-SD comparison (`tab:standardized_compare`) | `standardized.tex` | 10, 20 | `make_tex_tables.py` |
| Heat thresholds (`tab:main_threshold_compact`) | `thresholds.tex` | 22 | `make_tex_tables.py` |
| Heat relative to local climatology (`tab:main3_mechanism`) | `mechanism.tex` | 22 | `make_tex_tables.py` |
| Above and below the county-season norm (`tab:asymmetry`) | `asymmetry.tex` | 33 | `make_tex_tables.py` |
| Heat-by-period interactions (`tab:periods`) | `periods.tex` | 38 | `make_tex_tables.py` |
| Periods, Days35 (`fig:periods`) | `coef_periods1390_Days35.pdf`, `coef_periods1397_Days35.pdf` | 38 | 60 |
| Each origin year, Days35 (`fig:years`) | `coef_years_Days35.pdf` | 38 | 60 |
| Agro-climatic regions (`tab:regions`) | `regions.tex` | 31 | `make_tex_tables.py` |
| County-level share, annual against seasonal (`tab:cty_main`) | `cty_main.tex` | 46 | `make_tex_tables_d.py` |
| Controlled comparison (`tab:cty_controlled`) | `cty_controlled.tex` | 46 | `make_tex_tables_d.py` |

## Appendix

| Paper exhibit (label) | File | Step | Writer |
|---|---|---|---|
| Sample construction (`tab:appx_sampleflow`) | `sampleflow.tex` | 11 | `make_tex_tables_b.py` |
| Weather statistics (`tab:appx_weatherstats`) | `weatherstats.tex` | 11 | `make_tex_tables_b.py` |
| Weather correlations (`tab:appx_correlations`) | `weathercorr.tex` | 11 | `make_tex_tables_b.py` |
| Sample composition by year (`tab:sample_composition`) | `samplecomp.tex` | 11 | `make_tex_tables_b.py` |
| Person-ID tiers (`tab:linkage_tiers`) | `linkage_tiers.tex` | 28 | `make_tex_tables_d.py` |
| Strict linkage sample (`tab:linkage`) | `linkage.tex` | 28 | `make_tex_tables_d.py` |
| Validation of the fallback ID (`tab:linkage_validation`) | `linkage_validation.tex` | 28 | `make_tex_tables_d.py` |
| SD by origin sample (`tab:allorigin_sd`) | `allorigin_sd.tex` | 25 | `make_tex_tables_b.py` |
| Exit from each origin state (`tab:allorigin_exit_raw`) | `allorigin_exit.tex` | 25 | `make_tex_tables_b.py` |
| Unemployed origin, urban and rural (`tab:unemp_rural`) | `unemp_rural.tex` | 27 | `make_tex_tables_c.py` |
| Exposure timing and threshold (`tab:appx_timing`) | `timing.tex` | 26 | `make_tex_tables_c.py` |
| Rainfall controls, M7 and M8 (`tab:appx_rainrobust`, `tab:appx_rainrobust_m8`) | `rainrobust.tex`, `rainrobust_m8.tex` | 26 | `make_tex_tables_c.py` |
| Education-observed sample (`tab:appx_education`) | `education.tex` | 23 | `make_tex_tables_c.py` |
| Fitted values outside [0,100] (`tab:fittedrange`) | `fittedrange.tex` | 26 | `make_tex_tables_c.py` |
| Periods and years, HeatDose35 (`fig:app_periods`, `fig:app_years`) | `coef_periods1390_HeatDose35.pdf`, `coef_periods1397_HeatDose35.pdf`, `coef_years_HeatDose35.pdf` | 38 | 60 |
| Spatial inference (`tab:spatial_se`, `tab:spatial_ci`) | `spatial_se.tex`, `spatial_ci.tex` | 29 | `make_tex_tables_d.py` |
| Panel non-continuation and IPW (`tab:attr_*`, `tab:ipw_days35`, `tab:ipw_heat35`) | `attr_byyear.tex`, `attr_weather.tex`, `attr_het.tex`, `attr_propensity.tex`, `attr_weights.tex`, `attr_balance.tex`, `ipw_days35.tex`, `ipw_heat35.tex` | 42 | `make_tex_tables_d.py` |
| Balance of predetermined characteristics (`tab:balance`) | `balance.tex` | 45 | `make_tex_tables_d.py` |
| Residual heat variation (`tab:idvar`) | `idvar.tex` | 44 | `make_tex_tables_d.py` |
| Heterogeneity (`tab:het_tests`, `tab:het_slopes`) | `het_tests.tex`, `het_slopes.tex` | 43 | `make_tex_tables_d.py` |
| County-level ladder, all shares, robustness (`tab:cty_ladder`, `tab:cty_allshares`, `tab:cty_robust`) | `cty_ladder.tex`, `cty_allshares.tex`, `cty_robust.tex` | 46 | `make_tex_tables_d.py` |
| Numbers quoted in the text | `numbers.tex`, `numbers_extra.tex`, `numbers_b.tex`, `numbers_c.tex`, `numbers_d.tex` | several | 50 and `tools/` |

## Not in the paper (figures folder and checks only)

| Content | File | Step |
|---|---|---|
| Binned scatter plots for the other outcomes | `bs_fwl_<measure>_<outcome>.pdf` | 35 |
| Regional effect maps | `map_coef_<measure>_<outcome>.pdf` | 31 (estimates), 61 (maps) |
| Mean yearly rainfall map | `map_rain_year.pdf` | 61 |
| Population shares (five states) | `ts_population_shares.pdf` | 30 |
| Heat above and below the county mean and the county-season mean, with added-variable plots | `asym_<cm or cs>_<measure>_<outcome>.pdf`, `tables/47_asymmetry_county_normal.xlsx` | 47 |
| Other heat measures, asinh, county breaks, raw exit rates, sanctions-period split | Excel workbooks in `tables/` | 22, 34, 36, 37, 32 |
| Data and weather checks | Excel workbooks in `tables/` and `output/data_build/` | 40, 41, 01-03 |
| Province crop-area check of the regions (needs an outside Excel file) | `output/region_check/` | `tools/province_crop_check.py` |
