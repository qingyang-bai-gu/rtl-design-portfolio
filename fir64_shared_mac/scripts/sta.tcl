# Driven by run_sta.py. No default power numbers are reported without a VCD.
if {[catch {
    read_liberty $::env(FIR_LIBERTY)
    read_verilog build/fir64_mapped.v
    link_design fir64_shared_mac
    read_sdc constraints/fir64.sdc
    # Example pin loads/slews; replace with integration values before evaluation.
    # Capacitance is in the Liberty capacitance unit.
    set_load 0.01 [all_outputs]
    set_input_transition 0.10 [get_ports {s_data* s_valid m_ready}]
    if {[info exists ::env(FIR_SPEF)]} { read_spef $::env(FIR_SPEF) }
    check_setup -verbose > build/timing_constraints.rpt
    report_checks -path_delay min_max -group_path_count 10 -fields {slew cap input_pins nets} > build/timing_paths.rpt
    report_worst_slack -max > build/timing_wns.rpt
    report_tns > build/timing_tns.rpt
    if {[info exists ::env(FIR_VCD)]} {
        read_vcd -scope tb_fir64/dut $::env(FIR_VCD)
        report_activity_annotation > build/power_annotation.rpt
        report_power > build/power.rpt
    }
} message]} {
    puts stderr "FIR_STA_ERROR: $message"
    exit 1
}
exit
