*==============================================================================*
* lib_models.do
* Small programs shared by all model do-files (20, 21, 22, ...).
* 00_setup.do runs this file once, so you never run it alone.
*
* What the programs do:
*   prep_lpm_data   open the model-ready data, build the base sample and the outcomes
*   make_sample     one estimation sample for one heat measure (complete cases)
*   get_spec        controls and fixed effects of model M1 ... M8
*   open_results    open the results file (one row per regression and term)
*   run_lpm         run one regression and write its rows to the results file
*   export_wide     write one Excel sheet: rows = model and term, columns = outcomes
*   guide_sheet     write the Guide sheet (run settings and notes)
*==============================================================================*

*------------------------------------------------------------------------------*
* prep_lpm_data
*------------------------------------------------------------------------------*
* Base sample: agriculture at origin, known destination, valid weight and IDs,
* origin year inside the run period. Outcomes are in percentage points (pp_...).
capture program drop prep_lpm_data
program define prep_lpm_data
    version 17
    load_model_data

    gen byte flag_base = (job_origin == 1) & inrange(job_dest, 1, 5) ///
        & (Weight_origin > 0) & !missing(Weight_origin) ///
        & !missing(mix_id) & !missing(province_year) & !missing(pair_id) ///
        & inrange(season_origin, 1, 4) & $YEARS_IF

    * All individual controls must be observed
    gen byte flag_ctrl_ok = !missing(age_origin, age2_origin, sex_origin, marital_origin, urban_origin)

    keep if flag_base

    egen long province_year_season = group(province_year season_origin)
    label var province_year_season "Province x year x origin season"

    global OUTCOMES exit_agri productive_exit distress_exit dest2 dest3 dest4 dest5
    foreach y of global OUTCOMES {
        gen double pp_`y' = 100 * `y'
    }
    label var pp_exit_agri       "Exit from agriculture (pp)"
    label var pp_productive_exit "Productive exit: industry or services (pp)"
    label var pp_distress_exit   "Non-employment exit: unemployed or inactive (pp)"
    label var pp_dest2           "Industry (pp)"
    label var pp_dest3           "Services (pp)"
    label var pp_dest4           "Unemployment (pp)"
    label var pp_dest5           "Inactivity (pp)"

    global SAMPLE_LIST ""
    count
    di as result "Base sample: " r(N)
end

*------------------------------------------------------------------------------*
* make_sample
*------------------------------------------------------------------------------*
* smp_<name> = base sample + matched weather with enough valid days + controls
*              complete + all listed variables observed.
* Option localclim: also needs a usable reference climate (local-climate measures).
capture program drop make_sample
program define make_sample
    version 17
    syntax , NAMe(string) VARs(string) [LOCALclim]

    local wcond "weather_common_sample == 1"
    if "`localclim'" != "" local wcond "weather_localclim_sample == 1"

    capture drop smp_`name'
    gen byte smp_`name' = flag_base & `wcond' & flag_ctrl_ok
    foreach v of local vars {
        replace smp_`name' = 0 if missing(`v')
    }
    label var smp_`name' "Sample: `name'"
    global SAMPLE_LIST "$SAMPLE_LIST `name'"
    quietly count if smp_`name' == 1
    di as result "Sample `name': " r(N)
end

*------------------------------------------------------------------------------*
* get_spec : model M1 ... M11
*------------------------------------------------------------------------------*
*   M1  weather only, no controls, no fixed effects
*   M2  + age, age squared, sex
*   M3  + marital status
*   M4  + urban
*   M5  + origin-year, origin-season (and pair) fixed effects
*   M6  + county fixed effects
*   M7  county + province-by-year + season (and pair)   <- headline model
*   M8  M7 + county-specific linear trends
*   M9  county + province-by-year-by-season (and pair)   <- saturated version of M7
*   M10 M7 with a county intercept before and after a break year (script 36)
*   M11 county-by-season + province-by-year (and pair)   <- not used in the main results
capture program drop get_spec
program define get_spec, rclass
    version 17
    args m
    local pair ""
    if $USE_PAIR_FE == 1 local pair " pair_id"

    local c2 "c.age_origin c.age2_origin i.sex_origin"
    local c3 "`c2' i.marital_origin"
    local c4 "`c3' i.urban_origin"

    if `m' == 1 {
        return local controls ""
        return local absorb ""
    }
    else if `m' == 2 {
        return local controls "`c2'"
        return local absorb ""
    }
    else if `m' == 3 {
        return local controls "`c3'"
        return local absorb ""
    }
    else if `m' == 4 {
        return local controls "`c4'"
        return local absorb ""
    }
    else if `m' == 5 {
        return local controls "`c4'"
        return local absorb "year_origin season_origin`pair'"
    }
    else if `m' == 6 {
        return local controls "`c4'"
        return local absorb "mix_id year_origin season_origin`pair'"
    }
    else if `m' == 7 {
        return local controls "`c4'"
        return local absorb "mix_id province_year season_origin`pair'"
    }
    else if `m' == 8 {
        return local controls "`c4'"
        return local absorb "mix_id province_year season_origin`pair' mix_id#c.year_trend"
    }
    else if `m' == 9 {
        * Saturated: county FE + province x year x season FE (replaces province x year and season)
        return local controls "`c4'"
        return local absorb "mix_id province_year_season`pair'"
    }
    else if `m' == 10 {
        * M7 plus a separate county intercept before and after a break year.
        * Needs the variable post_break (made in script 36).
        return local controls "`c4'"
        return local absorb "mix_id#i.post_break province_year season_origin`pair'"
    }
    else if `m' == 11 {
        * M7 with a county-by-season fixed effect in place of the county and season effects.
        * The heat variable is then compared only with other years of the same county and season.
        return local controls "`c4'"
        return local absorb "mix_id#season_origin province_year`pair'"
    }
    else {
        di as error "Model number must be 1-11."
        exit 198
    }
end

*------------------------------------------------------------------------------*
* open_results / run_lpm
*------------------------------------------------------------------------------*
capture program drop open_results
program define open_results
    version 17
    syntax , FILE(string)
    capture postclose res
    global RES_FILE `"`file'"'
    postfile res str30 run str28 family str28 panel byte model_num str4 model ///
        str24 outcome str32 term str80 term_label str9 kind ///
        double coef double se double tstat double pvalue double ci_lo double ci_hi ///
        long n_used long n_clusters double r2 double r2_within ///
        str40 sample_name str12 status using `"`file'"', replace
end

capture program drop close_results
program define close_results
    capture postclose res
end

* One regression. Rows are written for every term in terms() (kind = exposure)
* and rainterms() (kind = control). Failed or dropped terms are written with status.
capture program drop run_lpm
program define run_lpm
    version 17
    syntax , FAMily(string) PANel(string) Model(integer) OUTcome(string) ///
        WVars(string) TERMs(string) SAMple(string) [RAINterms(string) EXTRA(string) JTEST(string) ///
        JNAME(string) JLABel(string)]
    if "`jname'"  == "" local jname "equal_coefficients_F"
    if "`jlabel'" == "" local jlabel "Test that the coefficients are equal (F)"

    get_spec `model'
    local ctrl   "`r(controls)'"
    local absorb "`r(absorb)'"
    if "`absorb'" == "" {
        local absopt "noabsorb"
    }
    else {
        local absopt "absorb(`absorb')"
    }

    timer clear 91
    timer on 91
    capture quietly reghdfe pp_`outcome' `wvars' `ctrl' `extra' ///
        if smp_`sample' == 1 [pweight = Weight_origin], `absopt' vce(cluster mix_id)
    local rc = _rc
    timer off 91
    quietly timer list 91
    local secs = r(t91)

    * If you press Break, stop the whole run (and keep what was already written).
    if `rc' == 1 {
        capture postclose res
        di as error "Stopped by the user (Break). Results so far are saved in $RES_FILE"
        exit 1
    }
    di as text "  [`family' | `panel' | M`model' | `outcome']  rc=`rc'  seconds=" %7.1f `secs'

    * Optional joint test, for example: jtest(x_r1 = x_r2 = x_r3). One row, kind = test.
    if `rc' == 0 & "`jtest'" != "" {
        capture quietly test `jtest'
        if _rc == 0 {
            post res ("$RUN_NAME") ("`family'") ("`panel'") (`model') ("M`model'") ///
                ("`outcome'") ("`jname'") ("`jlabel'") ("test") ///
                (r(F)) (.) (.) (r(p)) (.) (.) (e(N)) (e(N_clust)) (e(r2)) (.) ("`sample'") ("ok")
        }
    }

    foreach kind in exposure control {
        local list "`terms'"
        if "`kind'" == "control" local list "`rainterms'"
        foreach v of local list {
            local lbl ""
            capture local lbl : variable label `v'
            if "`lbl'" == "" local lbl "`v'"
            if `rc' != 0 {
                post res ("$RUN_NAME") ("`family'") ("`panel'") (`model') ("M`model'") ///
                    ("`outcome'") ("`v'") ("`lbl'") ("`kind'") ///
                    (.) (.) (.) (.) (.) (.) (.) (.) (.) (.) ("`sample'") ("failed")
                continue
            }
            local b  = .
            local se = .
            capture local b  = _b[`v']
            capture local se = _se[`v']
            if missing(`b') | missing(`se') | `se' <= 0 {
                post res ("$RUN_NAME") ("`family'") ("`panel'") (`model') ("M`model'") ///
                    ("`outcome'") ("`v'") ("`lbl'") ("`kind'") ///
                    (.) (.) (.) (.) (.) (.) (e(N)) (e(N_clust)) (e(r2)) (.) ("`sample'") ("omitted")
                continue
            }
            local df = e(df_r)
            local t  = `b' / `se'
            local p  = 2 * ttail(`df', abs(`t'))
            local tc = invttail(`df', 0.025)
            local rw = .
            capture local rw = e(r2_within)
            post res ("$RUN_NAME") ("`family'") ("`panel'") (`model') ("M`model'") ///
                ("`outcome'") ("`v'") ("`lbl'") ("`kind'") ///
                (`b') (`se') (`t') (`p') (`=`b'-`tc'*`se'') (`=`b'+`tc'*`se'') ///
                (e(N)) (e(N_clust)) (e(r2)) (`rw') ("`sample'") ("ok")
        }
    }
end

*------------------------------------------------------------------------------*
* export_wide : one sheet, rows = panel/model/term, columns = outcomes
*------------------------------------------------------------------------------*
* Each estimate is followed by a row with its standard error in parentheses.
capture program drop export_wide
program define export_wide
    version 17
    syntax , FILE(string) SHEet(string) FAMily(string) [KIND(string)]
    if "`kind'" == "" local kind "exposure"

    preserve
        use "$RES_FILE", clear
        keep if family == "`family'" & kind == "`kind'"
        if _N == 0 {
            di as error "export_wide: no rows for family `family'"
            restore
            exit 0
        }
        gen str12 star = cond(pvalue < 0.01, "***", cond(pvalue < 0.05, "**", cond(pvalue < 0.10, "*", "")))
        gen str30 c1 = cond(missing(coef), status, string(coef, "%9.3f") + star)
        replace c1 = "p = " + string(pvalue, "%6.4f") if kind == "test" & !missing(pvalue)
        gen str30 c2 = cond(missing(se), "", "(" + string(se, "%9.3f") + ")")
        bysort panel model_num term: egen long N = max(n_used)
        keep panel model_num model term term_label outcome c1 c2 N sample_name
        reshape long c, i(panel model_num model term term_label outcome N sample_name) j(row)
        reshape wide c, i(panel model_num model term term_label N sample_name row) j(outcome) string
        foreach y in exit_agri productive_exit distress_exit dest2 dest3 dest4 dest5 {
            capture rename c`y' `y'
        }
        replace N = . if row == 2
        replace model = "" if row == 2
        replace term_label = "" if row == 2
        replace sample_name = "" if row == 2
        sort panel model_num term row
        drop model_num row
        capture order panel model term term_label exit_agri productive_exit distress_exit ///
            dest2 dest3 dest4 dest5 N sample_name
        capture rename dest2 Industry
        capture rename dest3 Services
        capture rename dest4 Unemployment
        capture rename dest5 Inactivity
        capture rename exit_agri Exit_agriculture
        capture rename productive_exit Productive_exit
        capture rename distress_exit Nonemployment_exit
        export excel using `"`file'"', sheet("`sheet'", modify) firstrow(variables)
    restore
end

*------------------------------------------------------------------------------*
* export_long : the full results file as one sheet
*------------------------------------------------------------------------------*
capture program drop export_long
program define export_long
    version 17
    syntax , FILE(string) SHEet(string)
    preserve
        use "$RES_FILE", clear
        drop model_num
        export excel using `"`file'"', sheet("`sheet'", modify) firstrow(variables)
    restore
end

*------------------------------------------------------------------------------*
* export_samples : sample sizes of every sample made with make_sample
*------------------------------------------------------------------------------*
capture program drop export_samples
program define export_samples
    version 17
    syntax , FILE(string) SHEet(string)
    tempname h
    tempfile sf
    postfile `h' str30 sample_name long n_obs double weighted_n double exit_rate_pct using `sf', replace
    foreach s of global SAMPLE_LIST {
        quietly count if smp_`s' == 1
        local n = r(N)
        quietly summarize Weight_origin if smp_`s' == 1
        local wn = r(sum)
        quietly summarize exit_agri [aw = Weight_origin] if smp_`s' == 1
        local ex = 100 * r(mean)
        post `h' ("`s'") (`n') (`wn') (`ex')
    }
    postclose `h'
    preserve
        use `sf', clear
        export excel using `"`file'"', sheet("`sheet'", modify) firstrow(variables)
    restore
end

*------------------------------------------------------------------------------*
* guide_sheet : first sheet of every workbook
*------------------------------------------------------------------------------*
* title: name of the table file; lines: sheet descriptions, separated by "|"
capture program drop guide_sheet
program define guide_sheet
    version 17
    syntax , FILE(string) TITLE(string) LINES(string)
    putexcel set `"`file'"', sheet("00_Guide") replace
    putexcel A1 = "`title'"
    putexcel A3 = "Run"
    putexcel B3 = "$RUN_NAME"
    putexcel A4 = "Origin years"
    putexcel B4 = "$FIRST_ORIGIN_YEAR to $LAST_ORIGIN_YEAR"
    putexcel A5 = "Pair fixed effect in the models (1 = yes)"
    putexcel B5 = $USE_PAIR_FE
    putexcel A6 = "Unclassified employed counted as services (1 = yes)"
    putexcel B6 = $UNCLASSIFIED_AS_SERVICES
    putexcel A7 = "Outcomes"
    putexcel B7 = "Percentage points (0-100). Sample: agriculture workers at the origin, destination one year later in the same season."
    putexcel A8 = "Weights and clusters"
    putexcel B8 = "Weight_origin (pweight); standard errors clustered by county. Stars: * p<0.10, ** p<0.05, *** p<0.01."
    putexcel A10 = "Sheet"
    putexcel B10 = "What it shows"
    local r = 11
    local rest `"`lines'"'
    while `"`rest'"' != "" {
        gettoken one rest : rest, parse("|")
        if `"`one'"' == "|" continue
        local sh = strtrim(substr(`"`one'"', 1, strpos(`"`one'"', ":") - 1))
        local ds = strtrim(substr(`"`one'"', strpos(`"`one'"', ":") + 1, .))
        putexcel A`r' = `"`sh'"'
        putexcel B`r' = `"`ds'"'
        local ++r
    }
    putexcel clear
end

*------------------------------------------------------------------------------*
* add_region : agro-climatic region of the county (6 regions)
*------------------------------------------------------------------------------*
* The crosswalk lives in the lookups folder (336 counties, no microdata).
* Regions: 1 Caspian rice, 2 Highland cereal, 3 Plateau cereal and orchard,
*          4 Khorasan saffron and wheat, 5 Warm lowland wheat, 6 Hot arid date belt.
capture program drop add_region
program define add_region
    version 17
    tempfile cw
    preserve
        use "$LOOKUP/agro_region_crosswalk_1385.dta", clear
        keep mix4 agro_region agro_region_name
        rename mix4 mix4_origin
        save `cw'
    restore
    merge m:1 mix4_origin using `cw', keep(master match) nogen
    quietly count if missing(agro_region)
    if r(N) > 0 di as error "add_region: " r(N) " observations have no region."
    label define region_lbl 1 "Caspian rice" 2 "Highland cereal" 3 "Plateau cereal and orchard" ///
        4 "Khorasan saffron and wheat" 5 "Warm lowland wheat" 6 "Hot arid date belt", replace
    label values agro_region region_lbl
end

*------------------------------------------------------------------------------*
* fig_coef : dot-and-whisker plot of coefficients (one row per outcome)
*------------------------------------------------------------------------------*
* file   : a results dataset made by run_lpm
* series : conditions (Stata "if" expressions on the results variables), separated by |
* labels : legend text for each series, separated by |
* Each series gets its own colour and marker. 95 percent confidence intervals.
capture program drop fig_coef
program define fig_coef
    version 17
    syntax , FILE(string) OUT(string) XTITle(string) SERIES(string) LABels(string)

    capture confirm file `"`file'"'
    if _rc {
        di as error "fig_coef: results file not found: `file'  (figure skipped)"
        exit 0
    }

    * split the series and the labels
    * series are written without quotes, for example  family=Days35,model=7 | family=Days35,model=9
    * keys: family, panel, model (the model number), outcome, term
    local K = 0
    local rest "`series'"
    while "`rest'" != "" {
        gettoken one rest : rest, parse("|")
        if "`one'" == "|" continue
        local ++K
        local one = subinstr("`one'", ",", " ", .)
        local cond`K' ""
        local sep ""
        foreach kv of local one {
            local pos = strpos("`kv'", "=")
            local key = substr("`kv'", 1, `pos' - 1)
            local val = substr("`kv'", `pos' + 1, .)
            if "`key'" == "model" {
                local cond`K' `"`cond`K''`sep'model_num == `val'"'
            }
            else {
                local cond`K' `"`cond`K''`sep'`key' == "`val'""'
            }
            local sep " & "
        }
    }
    local rest `"`labels'"'
    local j = 0
    while `"`rest'"' != "" {
        gettoken one rest : rest, parse("|")
        if `"`one'"' == "|" continue
        local ++j
        local lab`j' = strtrim(`"`one'"')
    }

    local pal1 "31 95 139"
    local pal2 "179 90 31"
    local pal3 "46 125 50"
    local pal4 "123 31 162"
    local pal5 "120 120 120"
    local pal6 "200 160 0"
    local sym1 "O"
    local sym2 "S"
    local sym3 "D"
    local sym4 "T"
    local sym5 "X"
    local sym6 "+"

    tempfile stack
    preserve
        clear
        save `stack', emptyok replace
        forvalues i = 1/`K' {
            use `"`file'"', clear
            keep if kind == "exposure" & status == "ok"
            keep if `cond`i''
            gen byte s = `i'
            append using `stack'
            save `stack', replace
        }
        use `stack', clear
        if _N == 0 {
            di as error "fig_coef: no rows to plot for `out'"
            restore
            exit 0
        }
        gen byte ypos = .
        replace ypos = 7 if outcome == "exit_agri"
        replace ypos = 6 if outcome == "productive_exit"
        replace ypos = 5 if outcome == "distress_exit"
        replace ypos = 4 if outcome == "dest2"
        replace ypos = 3 if outcome == "dest3"
        replace ypos = 2 if outcome == "dest4"
        replace ypos = 1 if outcome == "dest5"
        gen double yy = ypos + ((`K' + 1) / 2 - s) * 0.2

        local plots ""
        local leg ""
        forvalues i = 1/`K' {
            local plots `"`plots' (rcap ci_lo ci_hi yy if s == `i', horizontal lcolor("`pal`i''") lwidth(thin)) (scatter yy coef if s == `i', msymbol(`sym`i'') mcolor("`pal`i''") msize(small))"'
            local leg `"`leg' `=2*`i'' "`lab`i''""'
        }
        twoway `plots', ///
            ylabel(7 "Total exit" 6 "Productive exit" 5 "Non-employment exit" 4 "Industry" ///
                   3 "Services" 2 "Unemployment" 1 "Inactivity", angle(0) noticks nogrid labsize(small)) ///
            yscale(range(0.4 7.6) noline) ytitle("") ///
            xline(0, lcolor(gs8) lwidth(thin)) xtitle(`"`xtitle'"', size(small)) ///
            legend(order(`leg') rows(1) position(6) size(small) region(lstyle(none))) ///
            graphregion(color(white)) plotregion(margin(small))
        graph export `"`out'"', replace
    restore
end
