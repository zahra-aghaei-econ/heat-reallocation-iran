*==============================================================================*
* install_packages.do
* Installs the user-written Stata packages used by the code. Run it once on a new
* computer (needs internet). Everything else is built into Stata 17.
*==============================================================================*

ssc install ftools, replace
ssc install reghdfe, replace

* Build the compiled parts of ftools and reghdfe (harmless if already done)
capture noisily ftools, compile
capture noisily reghdfe, compile

* The maps (step 61) use grmap, which is built into Stata but must be activated once
capture noisily grmap, activate

which reghdfe
which ftools
di as result "Packages are ready."
