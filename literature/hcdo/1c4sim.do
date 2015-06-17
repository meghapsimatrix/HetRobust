capture log close
log using 1c4, replace
* 1c4.do - data structure: x1 het on chi errors, R2=.40.
* Replication by jsl: 98.03.21
ts
version 5.0
clear
set more off
    global simnum_ = 1000
    global factor = .97
    global plevel = .05
    global seedmc = 11020760
    use jslhc1
    set seed $seedmc
    di "Iterations beginning."
    ts
    hcmonte 1 105 1c4 25 50 100 250 500 1000
    di "Iterations complete.
    ts
    hcresult 1 1c4 25 50 100 250 500 1000

log close
