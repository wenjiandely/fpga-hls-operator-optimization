# SPDX-License-Identifier: Apache-2.0
# Usage: vitis_hls -f scripts/run_hls.tcl -tclargs operator stage ?clock_ns?
set root [file normalize [file join [file dirname [info script]] ..]]
set operator [lindex $argv 0]
set stage [lindex $argv 1]
if {$operator ni {sha256 lz4 cholesky} || $stage ni {csim csynth cosim}} {
    error "Usage: -tclargs <sha256|lz4|cholesky> <csim|csynth|cosim> ?clock_ns?"
}
switch $operator {
    sha256 {set period 15.0; set top test_hmac_sha256}
    lz4 {set period 11.0; set top lz4CompressEngineRun}
    cholesky {set period 7.0; set top kernel_cholesky_0}
}
if {[llength $argv] > 2} {set period [lindex $argv 2]}
if {![string is double -strict $period] || $period <= 0} {error "clock_ns must be positive"}
set work [file join $root build $operator]
file mkdir $work
cd $work
open_project -reset project
set_top $top
switch $operator {
    sha256 {
        set test [file join $root security L1 tests hmac sha256]
        set flags "-I\"[file join $root security L1 include]\""
        add_files [file join $test test.cpp] -cflags $flags
        add_files -tb [file join $test test.cpp] -cflags $flags
        add_files -tb [file join $test gld.dat]
        file copy -force [file join $test gld.dat] [file join $work gld.dat]
        set tbargs ""
    }
    lz4 {
        set test [file join $root data_compression L1 tests lz4_compress]
        set flags "-I\"[file join $root data_compression L1 include hw]\""
        add_files [file join $test lz4_compress_test.cpp] -cflags $flags
        add_files -tb [file join $test lz4_compress_test.cpp] -cflags $flags
        add_files -tb [file join $test sample.txt]
        set tbargs "\"[file join $test sample.txt]\" \"[file join $work sample.txt.encoded]\""
    }
    cholesky {
        set lib [file join $root solver L1]
        set test [file join $lib tests cholesky]
        set flags "-DMATRIX_DIM=3 -DMATRIX_LOWER_TRIANGULAR=0 -DSEL_ARCH=0 -D_DATA_PATH=\"[file join $test datas]\""
        foreach inc [list [file join $test complex_fixed_arch0] [file join $test host] [file join $test kernel] $test [file join $lib tests] [file join $lib include] [file join $lib include hw]] {
            append flags " -I\"$inc\""
        }
        add_files [file join $test kernel kernel_cholesky_0.cpp] -cflags $flags
        add_files -tb [file join $test host test_cholesky.cpp] -cflags $flags
        set tbargs ""
    }
}
open_solution -reset solution1 -flow_target vivado
set_part xc7z020-clg484-1
create_clock -period $period
set_clock_uncertainty 10%
if {$stage in {csim cosim}} {csim_design -argv $tbargs}
if {$stage in {csynth cosim}} {csynth_design}
if {$stage eq "cosim"} {cosim_design -rtl verilog -argv $tbargs}
close_project
exit
