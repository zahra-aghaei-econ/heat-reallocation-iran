# Reference results (to check a reproduction)

Run `run3_new_period` with `UNCLASSIFIED_AS_SERVICES 1`, so the output folder is
`output/run3_new_period_svc`. Origin years 1384-1402, no transition-pair fixed effects.
These numbers were produced on the author's computer (Stata MP 17) in October 2026. A new run
with the same two data files should give the same numbers up to the last digit shown.

## Sample (step 11, `results/desc_sample_flow.dta`)

| Step | Rows |
|---|---|
| All transition rows (all origin states) | 2,926,088 |
| Agriculture at origin, known destination, positive weight | 324,046 |
| Valid geography and time, origin year inside the run period | 323,897 |
| Matched to county-season weather = Days35 estimation sample | 322,262 |
| Days35 sample with education observed | 223,483 |

Counties (clusters): 336.

## Headline model M7 (step 20, `results/lpm_main_results.dta`)

Linear probability model; outcome in percentage points (0/100); heat per ten days (Days35) or
per ten degree-days (HeatDose35); county, province-by-year and season fixed effects; age, age
squared, sex, marital status, rural origin, seasonal rain and its square; weight `Weight_origin`;
standard errors clustered by county. N = 322,262.

| Outcome | Days35 coef. | SE | HeatDose35 coef. | SE |
|---|---|---|---|---|
| Exit from agriculture | 0.6615 | 0.0919 | 0.0834 | 0.0138 |
| Productive exit (industry or services) | 0.0934 | 0.0554 | 0.0143 | 0.0071 |
| Non-employment exit (unemployed or inactive) | 0.5681 | 0.0727 | 0.0691 | 0.0122 |
| To industry | 0.0165 | 0.0466 | 0.0010 | 0.0057 |
| To services | 0.0769 | 0.0349 | 0.0133 | 0.0051 |
| To unemployment | 0.1724 | 0.0258 | 0.0218 | 0.0044 |
| To inactivity | 0.3957 | 0.0663 | 0.0473 | 0.0107 |

## Saturated fixed effects M9 (step 24, `results/lpm_saturated_results.dta`)

County and province-by-year-by-season fixed effects, otherwise as M7.

| Outcome | Days35 coef. | SE | HeatDose35 coef. | SE |
|---|---|---|---|---|
| Exit from agriculture | 0.2916 | 0.1409 | 0.0349 | 0.0207 |
| Non-employment exit | 0.4016 | 0.1161 | 0.0379 | 0.0168 |

## Specification ladder, exit from agriculture (step 21, `results/lpm_ladder_results.dta`)

| Model | M1 | M2 | M3 | M4 | M5 | M6 | M7 | M8 |
|---|---|---|---|---|---|---|---|---|
| Days35 | -0.142 | 0.037 | 0.033 | 0.041 | 0.298 | 0.668 | 0.661 | 0.654 |
| HeatDose35 | -0.033 | -0.015 | -0.015 | -0.012 | 0.013 | 0.080 | 0.083 | 0.083 |
