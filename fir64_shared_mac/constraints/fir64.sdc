# Demonstration pre-layout constraints. Values are assumptions, not achieved Fmax.
# Units: use a Liberty whose time unit is 1 ns. run_sta.py checks this assumption.
create_clock -name sample_clk -period $::env(FIR_SAMPLE_PERIOD_NS) [get_ports sample_clk]
create_clock -name proc_clk -period $::env(FIR_PROC_PERIOD_NS) [get_ports proc_clk]
set_clock_uncertainty 0.10 [all_clocks]
set_input_delay -clock sample_clk -max 1.0 [get_ports {s_data* s_valid}]
set_input_delay -clock sample_clk -min 0.0 [get_ports {s_data* s_valid}]
set_output_delay -clock sample_clk -max 1.0 [get_ports s_ready]
set_output_delay -clock sample_clk -min 0.0 [get_ports s_ready]
set_input_delay -clock proc_clk -max 1.0 [get_ports m_ready]
set_input_delay -clock proc_clk -min 0.0 [get_ports m_ready]
set_output_delay -clock proc_clk -max 1.0 [get_ports {m_data* m_acc* m_valid}]
set_output_delay -clock proc_clk -min 0.0 [get_ports {m_data* m_acc* m_valid}]
set_false_path -from [get_ports arst_n]
# CDC endpoints use two-stage synchronizers. This exception is for functional
# pre-layout STA ONLY. It does not constrain Gray-bus routing/skew. See docs/cdc.md.
set_clock_groups -asynchronous -group [get_clocks sample_clk] -group [get_clocks proc_clk]
