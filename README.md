# CEP — Constrained-Random Verification of 5-Port NoC Router
  For A8451 - SystemVerilog for Verification
  By K. Abhyuday, N. Midhun, Dileep

## Contents
- `design.sv` — DUT + interface + SVA checkers (paste into EDA Playground `design.sv` pane).
  Sections in order: `router_pkg` → `router_if` → `noc_router` → `sva_checker` (+ `bind`).
- `testbench.sv` — layered OOP TB + top (paste into `testbench.sv` pane).
  Sections: `ObsFlit/Packet/HotspotPacket/Generator/Driver/Monitor/Scoreboard/RouterCoverage/Env` → `top_tb`.
- `logs/` — trimmed VCS transcripts for all 5 runs (scoreboard + SVA + sim report only).
- `screenshots/` — matching EDA Playground screenshots per run.
- `RESULTS_SUMMARY.md` — regression table, bug log, CO mapping.

## Run
1. edaplayground.com → Testbench+Design = SystemVerilog → Simulator = **Synopsys VCS**
   (free Riviera-PRO blocks `rand/mailbox/covergroup/assert` — needs paid license).
2. Compile Options: `-timescale=1ns/1ns +vcs+flush+all +warn=all -sverilog +define+ENABLE_SVA`
   (`ENABLE_SVA` turns on the `bind` checkers; Riviera runs must omit it).
3. Run Options per test (Run Time 10ms):
   - T1 random: `+NUM=200 +MODE=0 +STALL=0`
   - T2 single-flit: `+NUM=20 +MODE=3 +STALL=0`
   - T3 hotspot-to-0: `+NUM=300 +MODE=1 +STALL=0`
   - T4 backpressure: `+NUM=200 +MODE=0 +STALL=1`
   - T5 long stress: `+NUM=1000 +MODE=4 +STALL=1`
4. Pass = `SCOREBOARD: ... errors=0 pending_exp=0`, no `[SVA]` errors.

## Results
All 5 runs PASS, 0 errors — see `RESULTS_SUMMARY.md` for the table, bug log, and CO mapping.
