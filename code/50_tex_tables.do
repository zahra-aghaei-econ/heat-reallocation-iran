*==============================================================================*
* 50_tex_tables.do
* LaTeX table fragments and number macros for the paper. No regressions here:
* it reads the result files of earlier steps.
*
* Each table fragment is only the tabular environment (no caption, no label, no notes).
* The paper puts it inside its own table environment:
*     \begin{table}[p] \centering \caption{...} \label{...}
*     \begin{adjustbox}{max width=\linewidth} \input{Tables/headline.tex} \end{adjustbox}
*     \exhibitnote{...}
*     \end{table}
* In a table, every column is one regression.
*
* Needs: step 10 (summary_stats.dta) and step 20 (lpm_main_results.dta).
*
* Output (output/<RUN_NAME>/tex/):
*   headline.tex     columns: exit from agriculture, productive exit, non-employment exit;
*                    industry and services are shown under productive exit, unemployment and
*                    inactivity under non-employment exit; Panel A Days35, Panel B HeatDose35;
*                    rows with the sample mean of the outcome and the coefficient as a percent of it
*   ratio_table.tex  all seven outcomes: sample mean, Days35 coefficient and its percent of the
*                    mean, HeatDose35 coefficient and its percent of the mean
*   numbers.tex      \newcommand macros with the numbers (for example \DaysExitCoef)
* Copy the tex folder to the Tables folder of the LaTeX project.
*==============================================================================*

if "$ROOT" == "" {
    di as error "Run master.do first."
    exit 198
}
capture log close step
log using "$LOGS/50_tex_tables.log", text replace name(step)

global TEX "$OUT/tex"
capture mkdir "$TEX"

local D = char(36)

* Outcome list and macro names
local outs "exit_agri productive_exit distress_exit dest2 dest3 dest4 dest5"
local nm_exit_agri "Exit"
local nm_productive_exit "Prod"
local nm_distress_exit "Nonemp"
local nm_dest2 "Ind"
local nm_dest3 "Serv"
local nm_dest4 "Unemp"
local nm_dest5 "Inact"
local lab_exit_agri "Exit from agriculture"
local lab_productive_exit "Productive exit"
local lab_distress_exit "Non-employment exit"
local lab_dest2 "To industry"
local lab_dest3 "To services"
local lab_dest4 "To unemployment"
local lab_dest5 "To inactivity"
local nm_days35 "Days"
local nm_heat35 "Heat"

*------------------------------------------------------------------------------*
* Read results into locals
*------------------------------------------------------------------------------*
use "$RESULTS/lpm_main_results.dta", clear
local nobs = n_used[1]
foreach m in days35 heat35 {
    foreach y of local outs {
        quietly summarize coef if measure == "`m'" & outcome == "`y'"
        local b_`m'_`y' = r(mean)
        quietly summarize se if measure == "`m'" & outcome == "`y'"
        local se_`m'_`y' = r(mean)
        quietly summarize pvalue if measure == "`m'" & outcome == "`y'"
        local p_`m'_`y' = r(mean)
    }
}

use "$RESULTS/summary_stats.dta", clear
keep if table_id == "T2"
foreach y of local outs {
    quietly summarize mean if varname == "`y'"
    local mean_`y' = 100 * r(mean)
}

* Text of each cell, the standard error, and the coefficient as a percent of the mean
foreach m in days35 heat35 {
    foreach y of local outs {
        local s ""
        if `p_`m'_`y'' < 0.10 local s "^{*}"
        if `p_`m'_`y'' < 0.05 local s "^{**}"
        if `p_`m'_`y'' < 0.01 local s "^{***}"
        local bt = trim(string(round(`b_`m'_`y'', 0.001), "%9.3f"))
        local st = trim(string(`se_`m'_`y'', "%9.3f"))
        local cell_`m'_`y' "`D'`bt'`s'`D'"
        local sec_`m'_`y'  "(`st')"
        local pct_`m'_`y' = trim(string(100 * `b_`m'_`y'' / `mean_`y'', "%9.1f"))
    }
}
foreach y of local outs {
    local mt_`y' = trim(string(`mean_`y'', "%9.2f"))
}
local ntxt = trim(string(`nobs', "%12.0fc"))
local ntxt = subinstr("`ntxt'", ",", "{,}", .)

*------------------------------------------------------------------------------*
* headline.tex
*------------------------------------------------------------------------------*
tempname fh
file open `fh' using "$TEX/headline.tex", write text replace
file write `fh' "\begin{tabular}{lccc}" _n
file write `fh' "\toprule" _n
file write `fh' " & (1) & (2) & (3) \\" _n
file write `fh' " & Exit from & Productive & Non-employment \\" _n
file write `fh' " & agriculture & exit & exit \\" _n
file write `fh' "\midrule" _n

local pan = 0
foreach m in days35 heat35 {
    local ++pan
    if "`m'" == "days35" {
        file write `fh' "\multicolumn{4}{l}{\textit{Panel A. Days35 /10}} \\" _n
    }
    else {
        file write `fh' "\multicolumn{4}{l}{\textit{Panel B. HeatDose35 /10}} \\" _n
    }
    file write `fh' "Heat coefficient & `cell_`m'_exit_agri' & `cell_`m'_productive_exit' & `cell_`m'_distress_exit' \\" _n
    file write `fh' " & `sec_`m'_exit_agri' & `sec_`m'_productive_exit' & `sec_`m'_distress_exit' \\" _n
    file write `fh' "\quad of which: industry &  & `cell_`m'_dest2' &  \\" _n
    file write `fh' " &  & `sec_`m'_dest2' &  \\" _n
    file write `fh' "\quad of which: services &  & `cell_`m'_dest3' &  \\" _n
    file write `fh' " &  & `sec_`m'_dest3' &  \\" _n
    file write `fh' "\quad of which: unemployment &  &  & `cell_`m'_dest4' \\" _n
    file write `fh' " &  &  & `sec_`m'_dest4' \\" _n
    file write `fh' "\quad of which: inactivity &  &  & `cell_`m'_dest5' \\" _n
    file write `fh' " &  &  & `sec_`m'_dest5' \\" _n
    file write `fh' "Mean of the outcome (\%) & `mt_exit_agri' & `mt_productive_exit' & `mt_distress_exit' \\" _n
    file write `fh' "Coefficient as \% of the mean & `pct_`m'_exit_agri' & `pct_`m'_productive_exit' & `pct_`m'_distress_exit' \\" _n
    if `pan' == 1 file write `fh' "\midrule" _n
}
file write `fh' "\midrule" _n
file write `fh' "County fixed effects & Yes & Yes & Yes \\" _n
file write `fh' "Province\(\times\)year fixed effects & Yes & Yes & Yes \\" _n
file write `fh' "Season fixed effects & Yes & Yes & Yes \\" _n
file write `fh' "Individual controls & Yes & Yes & Yes \\" _n
file write `fh' "\midrule" _n
file write `fh' "\(N\) & `ntxt' & `ntxt' & `ntxt' \\" _n
file write `fh' "\bottomrule" _n
file write `fh' "\end{tabular}" _n
file close `fh'

*------------------------------------------------------------------------------*
* ratio_table.tex
*------------------------------------------------------------------------------*
file open `fh' using "$TEX/ratio_table.tex", write text replace
file write `fh' "\begin{tabular}{lccccc}" _n
file write `fh' "\toprule" _n
file write `fh' " & Mean of & \multicolumn{2}{c}{Days35 /10} & \multicolumn{2}{c}{HeatDose35 /10} \\" _n
file write `fh' "\cmidrule(lr){3-4}\cmidrule(lr){5-6}" _n
file write `fh' "Outcome & outcome (\%) & Coefficient & \% of mean & Coefficient & \% of mean \\" _n
file write `fh' "\midrule" _n
foreach y of local outs {
    local pre ""
    if inlist("`y'", "dest2", "dest3", "dest4", "dest5") local pre "\quad "
    file write `fh' "`pre'`lab_`y'' & `mt_`y'' & `cell_days35_`y'' & `pct_days35_`y'' & `cell_heat35_`y'' & `pct_heat35_`y'' \\" _n
    file write `fh' " &  & `sec_days35_`y'' &  & `sec_heat35_`y'' &  \\" _n
    if "`y'" == "distress_exit" file write `fh' "\addlinespace" _n
}
file write `fh' "\midrule" _n
file write `fh' "\(N\) & `ntxt' & \multicolumn{2}{c}{`ntxt'} & \multicolumn{2}{c}{`ntxt'} \\" _n
file write `fh' "\bottomrule" _n
file write `fh' "\end{tabular}" _n
file close `fh'

*------------------------------------------------------------------------------*
* numbers.tex : macros for numbers in the text
*   \DaysExitCoef (coefficient), \DaysExitSe, \DaysExitPct (percent of mean),
*   \MeanExit (mean of the outcome, percent), \NObs
*------------------------------------------------------------------------------*
file open `fh' using "$TEX/numbers.tex", write text replace
file write `fh' "% Written by 50_tex_tables.do (run $RUN_NAME). Do not edit by hand." _n
file write `fh' "\newcommand{\NObs}{`ntxt'}" _n
local BS = char(92)
foreach y of local outs {
    local mname "Mean`nm_`y''"
    file write `fh' "`BS'newcommand{`BS'`mname'}{`mt_`y''}" _n
    foreach m in days35 heat35 {
        local bt = trim(string(round(`b_`m'_`y'', 0.001), "%9.3f"))
        local st = trim(string(`se_`m'_`y'', "%9.3f"))
        local pt = trim(string(`p_`m'_`y'', "%9.3f"))
        local base "`nm_`m''`nm_`y''"
        file write `fh' "`BS'newcommand{`BS'`base'Coef}{`bt'}" _n
        file write `fh' "`BS'newcommand{`BS'`base'Se}{`st'}" _n
        file write `fh' "`BS'newcommand{`BS'`base'P}{`pt'}" _n
        file write `fh' "`BS'newcommand{`BS'`base'Pct}{`pct_`m'_`y''}" _n
    }
}
file close `fh'

di as result "50 done. Files are in $TEX"
log close step
