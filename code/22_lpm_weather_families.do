*==============================================================================*
* 22_lpm_weather_families.do
* Other ways to measure heat, all at the headline model M7 and at M8 (county trends).
* Each measure is entered alone with the rain controls, except where two terms
* belong together (for example GDD and HDD).
*
*   F2  agronomic GDD / HDD (sine method), lagged one season (A) or two seasons (B)
*   F7  the same with the daily mean temperature (robustness)
*   F4  local climate: days above the local P90, and Tmean anomaly (linear + square)
*   F5  flexible form: Tmax bins (20-25C is the omitted bin), and quadratic Tmean
*   F6  thresholds and percentiles: Days37, Days40, HeatDose37, HeatDose40,
*       HDD35 (Tmean), CountP80, CountP95, DoseP80, DoseP90, DoseP95
*
* Which models to run: set MODELS_22 in master.do before the steps, for example
*     global MODELS_22 "7"      (default; headline model only)
*     global MODELS_22 "8"      (county trends only; slower)
* The file names carry the models, so the two runs do not overwrite each other.
*
* Output: output/<RUN_NAME>/tables/22_lpm_weather_families_M7.xlsx
*         output/<RUN_NAME>/results/lpm_families_M7_results.dta
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/22_lpm_weather_families.log", text replace name(step)

if "$MODELS_22" == "" global MODELS_22 "7"
local tag = "M" + subinstr("$MODELS_22", " ", "", .)
global XL22 "$TABLES/22_lpm_weather_families_`tag'.xlsx"

prep_lpm_data

* Quick test: set PILOT_22 to 1 in master.do to run only one outcome (exit from
* agriculture). The log then shows how many seconds each regression takes.
if "$PILOT_22" == "1" global OUTCOMES exit_agri

local rain "rain100_s0 rain100_sq_s0"
local rainlag "rain100_s0 rain100_sq_s0 rain100_lag13"

* Labels for the table rows (only variables that have no clear label yet)
label var bin_tmax_le20_s0   "Days with Tmax up to 20C in the season, /10"
label var bin_tmax_25_30_s0  "Days with Tmax 25-30C in the season, /10"
label var bin_tmax_30_35_s0  "Days with Tmax 30-35C in the season, /10"
label var bin_tmax_35_40_s0  "Days with Tmax 35-40C in the season, /10"
label var bin_tmax_gt40_s0   "Days with Tmax above 40C in the season, /10"
label var tmean_s0           "Mean temperature of the season (C)"
label var tmean_sq_s0        "Squared mean temperature of the season"
label var countp80_10_s0     "Days above the local P80 of Tmax, /10"
label var countp95_10_s0     "Days above the local P95 of Tmax, /10"
label var dosep80_10_s0      "Sum of Tmax above the local P80, /10"
label var dosep95_10_s0      "Sum of Tmax above the local P95, /10"


*------------------------------------------------------------------------------*
* Samples (each family uses its own complete cases, the same for M7 and M8)
*------------------------------------------------------------------------------*
make_sample, name(gdd_sine) vars(gdd8_32_sine_s1 hdd32_sine_s1 gdd8_32_sine_s2 hdd32_sine_s2 `rainlag')
make_sample, name(gdd_tmean) vars(gdd8_32_tmean_s1 hdd32_tmean_s1 gdd8_32_tmean_s2 hdd32_tmean_s2 `rainlag')
make_sample, name(countp90) vars(countp90_10_s0 `rain') localclim
make_sample, name(anom) vars(anom_tmean_s0 anom_tmean_sq_s0 `rain') localclim
make_sample, name(bins) vars(bin_tmax_le20_s0 bin_tmax_20_25_s0 bin_tmax_25_30_s0 bin_tmax_30_35_s0 bin_tmax_35_40_s0 bin_tmax_gt40_s0 `rain')
make_sample, name(tmean) vars(tmean_s0 tmean_sq_s0 `rain')
make_sample, name(days3740) vars(days37_10_s0 days40_10_s0 `rain')
make_sample, name(heat3740) vars(heat37_10_s0 heat40_10_s0 `rain')
make_sample, name(hdd35tmean) vars(hdd35_tmean_10_s0 `rain')
make_sample, name(pctile) vars(countp80_10_s0 countp95_10_s0 dosep80_10_s0 dosep90_10_s0 dosep95_10_s0 `rain') localclim

open_results, file("$RESULTS/lpm_families_`tag'_results.dta")

foreach y of global OUTCOMES {
    foreach m of global MODELS_22 {

        * F2: sine GDD/HDD, one-season lag (A) and two-season lag (B)
        run_lpm, family("F2_GDD_sine") panel("A_lag1season") model(`m') outcome(`y') ///
            wvars("gdd8_32_sine_s1 hdd32_sine_s1 `rainlag'") terms("gdd8_32_sine_s1 hdd32_sine_s1") ///
            rainterms("`rainlag'") sample(gdd_sine)
        run_lpm, family("F2_GDD_sine") panel("B_lag2seasons") model(`m') outcome(`y') ///
            wvars("gdd8_32_sine_s2 hdd32_sine_s2 `rainlag'") terms("gdd8_32_sine_s2 hdd32_sine_s2") ///
            rainterms("`rainlag'") sample(gdd_sine)

        * F7: same with Tmean
        run_lpm, family("F7_GDD_tmean") panel("A_lag1season") model(`m') outcome(`y') ///
            wvars("gdd8_32_tmean_s1 hdd32_tmean_s1 `rainlag'") terms("gdd8_32_tmean_s1 hdd32_tmean_s1") ///
            rainterms("`rainlag'") sample(gdd_tmean)
        run_lpm, family("F7_GDD_tmean") panel("B_lag2seasons") model(`m') outcome(`y') ///
            wvars("gdd8_32_tmean_s2 hdd32_tmean_s2 `rainlag'") terms("gdd8_32_tmean_s2 hdd32_tmean_s2") ///
            rainterms("`rainlag'") sample(gdd_tmean)

        * F4: local climate
        run_lpm, family("F4_LocalClimate") panel("A_CountP90") model(`m') outcome(`y') ///
            wvars("countp90_10_s0 `rain'") terms("countp90_10_s0") rainterms("`rain'") sample(countp90)
        run_lpm, family("F4_LocalClimate") panel("B_Anomaly") model(`m') outcome(`y') ///
            wvars("anom_tmean_s0 anom_tmean_sq_s0 `rain'") terms("anom_tmean_s0 anom_tmean_sq_s0") ///
            rainterms("`rain'") sample(anom)

        * F5: flexible form (bin 20-25C is the omitted bin)
        run_lpm, family("F5_FlexibleForm") panel("A_TmaxBins") model(`m') outcome(`y') ///
            wvars("bin_tmax_le20_s0 bin_tmax_25_30_s0 bin_tmax_30_35_s0 bin_tmax_35_40_s0 bin_tmax_gt40_s0 `rain'") ///
            terms("bin_tmax_le20_s0 bin_tmax_25_30_s0 bin_tmax_30_35_s0 bin_tmax_35_40_s0 bin_tmax_gt40_s0") ///
            rainterms("`rain'") sample(bins)
        run_lpm, family("F5_FlexibleForm") panel("B_QuadTmean") model(`m') outcome(`y') ///
            wvars("tmean_s0 tmean_sq_s0 `rain'") terms("tmean_s0 tmean_sq_s0") ///
            rainterms("`rain'") sample(tmean)

        * F6: thresholds and percentiles, one measure at a time
        local names "Days37 Days40 HeatDose37 HeatDose40 HDD35_Tmean CountP80 CountP95 DoseP80 DoseP90 DoseP95"
        local vars  "days37_10_s0 days40_10_s0 heat37_10_s0 heat40_10_s0 hdd35_tmean_10_s0 countp80_10_s0 countp95_10_s0 dosep80_10_s0 dosep90_10_s0 dosep95_10_s0"
        local samps "days3740 days3740 heat3740 heat3740 hdd35tmean pctile pctile pctile pctile pctile"
        forvalues i = 1/10 {
            local nm : word `i' of `names'
            local vr : word `i' of `vars'
            local sp : word `i' of `samps'
            run_lpm, family("F6_Thresholds") panel("`nm'") model(`m') outcome(`y') ///
                wvars("`vr' `rain'") terms("`vr'") rainterms("`rain'") sample(`sp')
        }
    }
}
close_results

*------------------------------------------------------------------------------*
* Excel
*------------------------------------------------------------------------------*
guide_sheet, file("$XL22") title("Other heat measures (models chosen by MODELS_22, default M7)") lines("F2_GDD_sine: Growing degree days (8-32C) and harmful degree days above 32C, sine method, lagged one season (panel A) or two seasons (panel B). Rain and last years rain are controls.|F7_GDD_tmean: Same as F2 but built from the daily mean temperature.|F4_LocalClimate: Days above the local 90th percentile of Tmax (A) and Tmean anomaly with its square (B). Only counties with a usable 1330-1383 reference climate.|F5_FlexibleForm: Tmax bins in tens of days (A; 20-25C is the omitted bin) and quadratic seasonal mean temperature (B).|F6_Thresholds: Ten single-measure checks (Days37, Days40, HeatDose37, HeatDose40, HDD35 Tmean, CountP80, CountP95, DoseP80, DoseP90, DoseP95).|All_long: Every regression, one row per term.|Samples: Sample sizes. Each family uses its own complete cases.|Models: M7 county + province-by-year + season FE (headline). M8 adds county-specific linear trends.")
foreach f in F2_GDD_sine F7_GDD_tmean F4_LocalClimate F5_FlexibleForm F6_Thresholds {
    export_wide, file("$XL22") sheet("`f'") family("`f'")
}
export_long, file("$XL22") sheet("All_long")
export_samples, file("$XL22") sheet("Samples")

di as result "22 done."
log close step
