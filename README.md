# 5-Port NoC Router Verification (SystemVerilog)

B.Tech elective project for A8451 SystemVerilog for Verification (R22), done by a
team of 3. We verified a 5-port wormhole NoC router with virtual channels using a
pure SystemVerilog testbench (no UVM): a layered TB, constrained-random stimulus,
SystemVerilog assertions and functional coverage. Everything here runs on
EDA Playground with Synopsys VCS, so anyone can reproduce it.

## Files in this repo

- `design.sv` — package, interface, the router DUT and the SVA checker.
  Paste this into the Design pane on EDA Playground.
- `testbench.sv` — the testbench classes, environment and top.
  Paste this into the Testbench pane.
- `logs/` — simulation transcripts of the 5 regression runs (T1–T5).
- `screenshots/` — EDA Playground screenshots of the same runs.

## Design under test

A 5-port (N/S/E/W/Local) wormhole router: 32-bit flits, 2 virtual channels per
port, 8-flit buffers, destination-port (XY) routing, round-robin arbitration per
output. Once a HEAD flit wins an output, that output stays locked to it until its
TAIL goes through. Stalled outputs hold their flit stable (standard VALID/READY).

| Flit | Encoding |
|------|----------|
| Header | `{type[31:30], vc[29], pad[28:27], tag[26:3], dest[2:0]}` |
| Body / Tail | `{type[31:30], payload[29:0]}` (bit 29 is payload here, not VC) |

## Testbench

```
Generator -> Driver -> DUT -> Monitor -> Scoreboard
    |                           |
    +--> Scoreboard (expected) +--> Coverage
    sva_checker <--> DUT (bind, RTL untouched)
```

The Generator makes constrained-random packets (plain random, hotspot to port 0,
all-to-one, single-flit, and long-packet stress). The Driver drives all 5 input
ports through a clocking block and can inject output backpressure. The Monitor
collects every accepted output flit, and the Scoreboard matches whole packets by
their header tag against a golden rebuild, so packets may arrive in any order.
A covergroup samples every packet descriptor, and the assertion checker is bound
to the DUT without touching the RTL.

Classes: `Packet` (base) → `HotspotPacket` (extends it), `Generator`, `Driver`,
`Monitor`, `Scoreboard`, `RouterCoverage`, `Env`, plus `top_tb` on top.

## How to run

1. On EDA Playground select Testbench+Design = SystemVerilog, simulator = Synopsys VCS.
   (Free Riviera-PRO cannot run this — it blocks `rand`/`mailbox`/`covergroup`/`assert`.)
2. Compile Options: `-timescale=1ns/1ns +vcs+flush+all +warn=all -sverilog +define+ENABLE_SVA`
3. Set Run Options to one of the rows below (Run Time 10 ms) and press Run.
   A run passes when the scoreboard prints `errors=0 pending_exp=0` with no `[SVA]` errors.

## Results (VCS 2025.06)

| Run | Options | Sent | Got | Flits | Errors | Pending | Time |
|-----|---------|------|-----|-------|--------|---------|------|
| T1 | `+NUM=200 +MODE=0 +STALL=0` | 200 | 200 | 1097 | 0 | 0 | 35045ns |
| T2 | `+NUM=20 +MODE=3 +STALL=0` | 20 | 20 | 20 | 0 | 0 | 8045ns |
| T3 | `+NUM=300 +MODE=1 +STALL=0` | 300 | 300 | 1622 | 0 | 0 | 50045ns |
| T4 | `+NUM=200 +MODE=0 +STALL=1` | 200 | 200 | 1097 | 0 | 0 | 35045ns |
| T5 | `+NUM=1000 +MODE=4 +STALL=1` | 1000 | 1000 | 8010 | 0 | 0 | 270045ns |

Modes: 0 random, 1 hotspot (all to port 0), 2 all-to-one (to port 2),
3 single-flit directed, 4 long-packet stress. Transcripts are in `logs/`, and
[T1's screenshot](screenshots/T1_random200.png) shows a typical passing run.

## Bugs we actually found with this testbench

1. **VC decode bug.** BODY/TAIL flits were taking their VC from payload bit 29,
   so flits of one packet landed in different VC FIFOs and packets never
   reassembled (length / wrong-dest / unknown-tag errors). Fixed by remembering
   the VC opened by each HEAD (`cur_vc` per input port).
2. **Stall-hold bug.** While an output was stalled, re-arbitration changed
   `data_out` under `valid=1`, dropping a flit every time. The hold assertion
   caught it; fixed by freezing `data_out`/`valid` until the stall clears.

## Course outcomes (A8451)

| CO | Where it is in this project |
|----|------------------------------|
| A8451.1 Methodology, data types | Layered TB, virtual interface, queues and associative arrays |
| A8451.2 Procedural code, assertions | Clocking blocks, 8 SVA properties bound with `bind` |
| A8451.3 Functional coverage | Covergroup on src/dest/vc/len with 3 crosses |
| A8451.4 OOP | Packet → HotspotPacket inheritance, mailboxes, Env |
| A8451.5 Randomization | `rand` + constraints + inline `with` + `pre_randomize` |

Team split: M1 did the DUT + interface, M2 the TB classes + randomization,
M3 the assertions + coverage + regression runs.
