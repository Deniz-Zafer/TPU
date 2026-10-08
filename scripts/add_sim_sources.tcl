# Vivado Tcl Console'da calistir:  source <proje_klasoru>/scripts/add_sim_sources.tcl
# sim_1'e testbench'leri ekler ve varsayilan simulasyon top'unu tb_sequencer yapar.
set proj_dir [file normalize [file join [file dirname [info script]] ..]]
add_files -fileset sim_1 [list \
    $proj_dir/TPU.srcs/sim_1/new/tb_systolic_arr.sv \
    $proj_dir/TPU.srcs/sim_1/new/tb_memory.sv \
    $proj_dir/TPU.srcs/sim_1/new/tb_sequencer.sv]
set_property top tb_sequencer [get_filesets sim_1]
update_compile_order -fileset sim_1
# Digerlerini calistirmak icin: set_property top tb_systolic_arr [get_filesets sim_1]  (ya da tb_memory)
