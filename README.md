# TPU-Style Systolic Array Accelerator

An 8×8 weight-stationary **systolic array** matrix-multiply accelerator written in SystemVerilog, inspired by the Google TPU architecture.

## Architecture

| Module | File | Description |
|---|---|---|
| `general_pkg` / `PE` | `PE.sv` | Processing Element: signed INT8 MAC with 32-bit accumulator; modes `HOLD` / `LOAD` / `COMPUTE` |
| `PE_Cluster` | `PE_Cluster.sv` | N×N grid of PEs (activations flow right, partial sums and weights flow down) |
| `Systolic_Arr` | `Systolic_Arr.sv` | Wraps the cluster with input skew / output de-skew delay lines and a `result_valid` pipeline |
| `Simple_RAM`, `Weight_Buffer`, activation / result buffers | `Memory.sv` | Synchronous 1R1W SRAMs; double-buffered activation memory (`act_swap`) |
| `Sequencer` | `Sequencer.sv` | Control FSM: `IDLE → LOAD (N cycles) → STREAM (M cycles) → DRAIN → DONE` |

- Parameterizable array size `N` (default 8), INT8 activations/weights, INT32 accumulation
- Weights are pre-loaded row by row, then activation vectors are streamed through the array
- Host interface: `start`, `input_vector_count`, base addresses, `busy` / `done`

## Verification

Self-checking testbenches in `TPU.srcs/sim_1/new/`:
- `tb_systolic_arr.sv` – array datapath vs. golden matrix multiply
- `tb_memory.sv` – buffer read/write behaviour
- `tb_sequencer.sv` – full end-to-end flow (memory + sequencer + array)

## Running

1. Open `TPU.xpr` in AMD Vivado.
2. In the Tcl console: `source scripts/add_sim_sources.tcl` (adds the testbenches and sets `tb_sequencer` as top).
3. Run Behavioral Simulation.

**Tools:** SystemVerilog, AMD Vivado (XSim)
