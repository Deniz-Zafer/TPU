# Vivado Tcl Console'da calistir:  source <proje_klasoru>/scripts/add_sim_sources.tcl
# sim_1'e testbench'leri ekler ve varsayilan simulasyon top'unu tb_layers yapar.
set proj_dir [file normalize [file join [file dirname [info script]] ..]]
add_files -fileset sim_1 [list \
    $proj_dir/TPU.srcs/sim_1/new/tb_systolic_arr.sv \
    $proj_dir/TPU.srcs/sim_1/new/tb_memory.sv \
    $proj_dir/TPU.srcs/sim_1/new/tb_sequencer.sv \
    $proj_dir/TPU.srcs/sim_1/new/tb_tiling.sv \
    $proj_dir/TPU.srcs/sim_1/new/tb_core.sv \
    $proj_dir/TPU.srcs/sim_1/new/tb_post_processor.sv \
    $proj_dir/TPU.srcs/sim_1/new/tb_layers.sv]
set_property top tb_layers [get_filesets sim_1]
update_compile_order -fileset sim_1
# Digerlerini calistirmak icin: set_property top <tb_systolic_arr | tb_memory | tb_sequencer | tb_tiling | tb_core | tb_post_processor> [get_filesets sim_1]
