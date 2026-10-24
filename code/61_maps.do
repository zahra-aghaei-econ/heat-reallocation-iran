*==============================================================================*
* 61_maps.do
* Maps of the 1385 counties (needs Stata 15 or newer; uses spshape2dta and grmap,
* both built into Stata).
*   map_days35_year.pdf    mean number of days per year with Tmax of 35C or more.
*                          Counties with no such day are grey.
*   map_rain_year.pdf      mean yearly rainfall (mm)
*   map_regions.pdf        the six agro-climatic regions
*   map_coef_<measure>_<outcome>.pdf   region-level effect of heat (from script 31,
*                          separate regression for each region)
* The weather maps use the origin years that are in the estimation sample.
*
* Boundary file: data/shapefile1385/geo2_ir2006.shp (1385 boundaries, IPUMS
* International). IMPORTANT: the county numbers inside the IPUMS file are NOT the survey
* (LFS) county codes. The polygons were matched to the official 1385 county codes of the
* Statistical Centre (GEO85) by county name, one by one, and the result is saved in
* lookups/map_polygon_to_lfs_code_1385.dta (polygon key shp_key -> LFS code mix4).
* A check with the weather data supports the match: neighbouring polygons have similar
* days above 35C (correlation 0.93 with the new match, 0.75 with the direct codes).
* Things to know:
*   - The polygon "Tafresh, Ashtian" covers two county codes (0003 and 0002);
*     the two counties are pooled for the map.
*   - The polygon "Qeshm, Abumusa" covers codes 2204 and 2201; pooled for the map.
*   - Nazarabad (2315) has no polygon of its own. The lake (key 8888) is not a county.
*
* Output: output/<RUN_NAME>/graphs/map_*.pdf, tables/61_map_data.xlsx
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/61_maps.log", text replace name(step)

capture confirm file "$DATA/shapefile1385/geo2_ir2006.shp"
if _rc {
    di as error "Boundary file not found: $DATA/shapefile1385/geo2_ir2006.shp  (maps skipped)"
    log close step
    exit 0
}

* grmap must be activated once on each computer (no internet needed); harmless if already done
capture grmap, activate

global XL61 "$TABLES/61_map_data.xlsx"

*------------------------------------------------------------------------------*
* 1. Origin years of the estimation sample
*------------------------------------------------------------------------------*
prep_lpm_data
local rain "rain100_s0 rain100_sq_s0"
make_sample, name(days35) vars(days35_10_s0 `rain')
quietly levelsof year_origin if smp_days35 == 1, local(yrs)
local ylist = subinstr(trim("`yrs'"), " ", ",", .)
di as result "Origin years in the sample: `yrs'"

*------------------------------------------------------------------------------*
* 2. County weather data: mean days and rain per year
*------------------------------------------------------------------------------*
use "$INTER/weather_county_season.dta", clear
quietly xtset, clear     // the weather file is declared as a panel; maps need no panel setting
keep if inlist(year, `ylist') & weather_valid_s0 == 1
replace mix4 = "0003" if mix4 == "0002"
replace mix4 = "2204" if mix4 == "2201"
collapse (mean) days35_10_s0 rain100_s0, by(mix4 season)
collapse (sum) days35_10_s0 rain100_s0, by(mix4)
gen double days_year = 10 * days35_10_s0
gen double rain_year = 100 * rain100_s0
keep mix4 days_year rain_year
tempfile wx
save `wx'

* Region of each county
use "$LOOKUP/agro_region_crosswalk_1385.dta", clear
keep mix4 agro_region
tempfile reg
save `reg'

* Region effects from script 31 (if it has been run)
tempfile regcoef
local have_coef = 0
capture confirm file "$RESULTS/lpm_regions_results.dta"
if !_rc {
    use "$RESULTS/lpm_regions_results.dta", clear
    keep if kind == "exposure" & status == "ok" & substr(panel, 1, 17) == "B_separate_region"
    gen byte agro_region = real(substr(panel, 18, 1))
    gen str12 measure = cond(family == "Regions_Days35", "days35", "heat35")
    keep agro_region measure outcome coef pvalue
    save `regcoef'
    local have_coef = 1
}

*------------------------------------------------------------------------------*
* 3. Polygons
*------------------------------------------------------------------------------*
capture mkdir "$INTER/map"
* spshape2dta saves into the current folder, and grmap looks for the coordinate file
* there too, so we work inside the map folder until the end of this script.
local cwd61 "`c(pwd)'"
quietly cd "$INTER/map"
spshape2dta "$DATA/shapefile1385/geo2_ir2006.shp", saving(map1385) replace
use "map1385.dta", clear
gen str4 shp_key = substr(PARENT, 2, 2) + substr(string(real(SUBP2006), "%04.0f"), 3, 2)
merge 1:1 shp_key using "$LOOKUP/map_polygon_to_lfs_code_1385.dta", keepusing(mix4) keep(master match) nogenerate
merge 1:1 mix4 using `wx', keep(master match) nogen
merge 1:1 mix4 using `reg', keep(master match) nogen
label define region_lbl 1 "Caspian rice" 2 "Highland cereal" 3 "Plateau cereal and orchard" ///
    4 "Khorasan saffron and wheat" 5 "Warm lowland wheat" 6 "Hot arid date belt", replace
label values agro_region region_lbl
capture quietly xtset, clear
save "map1385_data.dta", replace

preserve
    drop _ID _CX _CY
    capture drop ADMIN_NAME
    export excel using "$XL61", sheet("County_map_data") firstrow(variables) replace
restore

*------------------------------------------------------------------------------*
* 4. Weather maps
*------------------------------------------------------------------------------*
* Days with Tmax >= 35C: zero-day counties are grey, the others get 5 groups
use "map1385_data.dta", clear
quietly count if days_year == 0
di as result "Counties with no day of 35C or more: " r(N)
_pctile days_year if days_year > 0, p(20 40 60 80)
local b1 = round(r(r1))
local b2 = round(r(r2))
local b3 = round(r(r3))
local b4 = round(r(r4))
quietly summarize days_year if days_year > 0
local bmax = ceil(r(max)) + 1
* round numbers in the legend; make the breaks strictly increasing
if `b1' < 1 local b1 = 1
if `b2' <= `b1' local b2 = `b1' + 1
if `b3' <= `b2' local b3 = `b2' + 1
if `b4' <= `b3' local b4 = `b3' + 1
if `bmax' <= `b4' local bmax = `b4' + 1
capture noisily grmap days_year, clmethod(custom) clbreaks(-1 0 `b1' `b2' `b3' `b4' `bmax') ///
    fcolor("217 217 217" "255 255 178" "254 217 118" "254 178 76" "253 141 60" "227 26 28") ///
    ocolor(gs8 ..) osize(vthin ..) ndfcolor("198 219 239") ///
    legend(position(8) size(small)) legtitle("Days per year")
if _rc == 0 {
    graph export "$GRAPHS/map_days35_year.pdf", replace
}
else {
    di as error "Map map_days35_year failed (see message above); continuing."
}

_pctile rain_year, p(17 33 50 67 83)
local r1 = round(r(r1))
local r2 = round(r(r2))
local r3 = round(r(r3))
local r4 = round(r(r4))
local r5 = round(r(r5))
quietly summarize rain_year
local rmin = floor(r(min)) - 1
local rmax = ceil(r(max)) + 1
if `r1' <= `rmin' local r1 = `rmin' + 1
if `r2' <= `r1' local r2 = `r1' + 1
if `r3' <= `r2' local r3 = `r2' + 1
if `r4' <= `r3' local r4 = `r3' + 1
if `r5' <= `r4' local r5 = `r4' + 1
if `rmax' <= `r5' local rmax = `r5' + 1
capture noisily grmap rain_year, clmethod(custom) clbreaks(`rmin' `r1' `r2' `r3' `r4' `r5' `rmax') ///
    fcolor(Blues) ocolor(gs8 ..) osize(vthin ..) ndfcolor("198 219 239") ///
    legend(position(8) size(small)) legtitle("Rain, mm per year")
if _rc == 0 {
    graph export "$GRAPHS/map_rain_year.pdf", replace
}
else {
    di as error "Map map_rain_year failed (see message above); continuing."
}

capture noisily grmap agro_region, clmethod(unique) ///
    fcolor("66 146 198" "158 202 225" "254 217 118" "253 141 60" "161 217 155" "189 0 38") ///
    ocolor(gs8 ..) osize(vthin ..) ndfcolor("198 219 239") ///
    legend(position(8) size(small))
if _rc == 0 {
    graph export "$GRAPHS/map_regions.pdf", replace
}
else {
    di as error "Map map_regions failed (see message above); continuing."
}

*------------------------------------------------------------------------------*
* 5. Region-level effects of heat
*------------------------------------------------------------------------------*
if `have_coef' == 1 {
    tempfile one
    foreach m in days35 heat35 {
        foreach y in exit_agri productive_exit distress_exit dest2 dest3 dest4 dest5 {
            use `regcoef', clear
            keep if measure == "`m'" & outcome == "`y'"
            rename coef coef_reg
            keep agro_region coef_reg
            save `one', replace

            use "map1385_data.dta", clear
            merge m:1 agro_region using `one', keep(master match) nogen
            quietly summarize coef_reg
            local cmin = floor(100 * r(min)) / 100 - 0.01
            local cmax = ceil(100 * r(max)) / 100 + 0.01
            local cstep = (`cmax' - `cmin') / 5
            local c1 = round(`cmin' + 1 * `cstep', 0.01)
            local c2 = round(`cmin' + 2 * `cstep', 0.01)
            local c3 = round(`cmin' + 3 * `cstep', 0.01)
            local c4 = round(`cmin' + 4 * `cstep', 0.01)
            local ok = (`c1' > `cmin') & (`c2' > `c1') & (`c3' > `c2') & (`c4' > `c3') & (`cmax' > `c4')
            if `ok' == 1 {
                capture noisily grmap coef_reg, clmethod(custom) clbreaks(`cmin' `c1' `c2' `c3' `c4' `cmax') ///
                    fcolor(Reds) ocolor(gs8 ..) osize(vthin ..) ndfcolor("198 219 239") ///
                    legend(position(8) size(small)) legtitle("Effect (pp)")
            }
            else {
                capture noisily grmap coef_reg, clmethod(eqint) clnumber(5) fcolor(Reds) ///
                    ocolor(gs8 ..) osize(vthin ..) ndfcolor("198 219 239") ///
                    legend(position(8) size(small)) legtitle("Effect (pp)")
            }
            if _rc == 0 graph export "$GRAPHS/map_coef_`m'_`y'.pdf", replace
        }
    }
}
else {
    di as text "Region coefficient maps skipped: run script 31 first."
}

quietly cd "`cwd61'"
di as result "61 done."
log close step
