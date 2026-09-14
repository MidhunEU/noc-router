# noc-router

![SystemVerilog](https://img.shields.io/badge/SystemVerilog-IEEE%201800-red)
![Sim](https://img.shields.io/badge/tested%20on-Synopsys%20VCS-blue)
![Regression](https://img.shields.io/badge/regression-5%2F5%20passing-brightgreen)

Constrained-random functional verification of a 5-port wormhole NoC mesh router
with virtual channels — pure SystemVerilog, no UVM. Layered testbench,
constrained-random stimulus, concurrent assertions and functional coverage,
all reproducible for free on EDA Playground.

## Highlights

- Parameterized DUT: 5 ports, 2 virtual channels, 8-flit buffers, XY routing,
  per-output round-robin arbitration with wormhole locking and VALID/READY stall-hold
- Layered OOP testbench: generator, driver, monitor, tag-matched scoreboard,
  coverage collector, environment
- 5 constrained-random stimulus modes, including hotspot and backpressure injection
- 5 concurrent assertions + 3 cover properties, bound with `bind` (RTL untouched)
- 5/5 regression runs green, 0 errors across 1720 packets / 11.5k flits

## Architecture

```
Generator -> Driver -> DUT -> Monitor -> Scoreboard
    |                           |
    +--> Scoreboard (expected) +--> Coverage
    sva_checker <--> DUT (bind, RTL untouched)
```

| Block | Role |
|-------|------|
| `Packet` → `HotspotPacket` | Randomized transactions; base → extended inheritance |
| `Generator` | Random, hotspot-to-0, all-to-one, single-flit, long-packet stress |
| `Driver` | Drives all 5 ports via clocking block; injects output backpressure |
| `Monitor` | Samples every accepted output flit |
| `Scoreboard` | Order-independent packet check vs golden flit rebuild, matched by header tag |
| `RouterCoverage` | Coverpoints on src/dest/vc/len plus 3 crosses |
| `sva_checker` | Handshake stability, hold under stall, no-X, legal dest, liveness |

Flit encoding: header `{type[31:30], vc[29], pad[28:27], tag[26:3], dest[2:0]}`,
body/tail `{type[31:30], payload[29:0]}` (bit 29 is payload there, not VC).

## Repository layout

```
design.sv      package → interface → DUT → SVA checker (EDA Design pane)
testbench.sv   9 TB classes → Env → top_tb (EDA Testbench pane)
logs/          trimmed VCS transcripts, one per run
screenshots/   EDA Playground screenshots of the same runs
```

## Getting started

Prerequisites: a free [EDA Playground](https://www.edaplayground.com) account.
Use the **Synopsys VCS** simulator — the free Riviera-PRO build blocks
`rand` / `mailbox` / `covergroup` / `assert`.

1. Paste `design.sv` and `testbench.sv` into the Design and Testbench panes.
2. Compile Options:
   `-timescale=1ns/1ns +vcs+flush+all +warn=all -sverilog +define+ENABLE_SVA`
3. Set Run Options to any row below (Run Time 10 ms) and Run. A passing run prints
   `errors=0 pending_exp=0` with no `[SVA]` errors.

| Run | Options | Sent | Got | Flits | Errors | Time |
|-----|---------|------|-----|-------|--------|------|
| T1 | `+NUM=200 +MODE=0 +STALL=0` | 200 | 200 | 1097 | 0 | 35045ns |
| T2 | `+NUM=20 +MODE=3 +STALL=0` | 20 | 20 | 20 | 0 | 8045ns |
| T3 | `+NUM=300 +MODE=1 +STALL=0` | 300 | 300 | 1622 | 0 | 50045ns |
| T4 | `+NUM=200 +MODE=0 +STALL=1` | 200 | 200 | 1097 | 0 | 35045ns |
| T5 | `+NUM=1000 +MODE=4 +STALL=1` | 1000 | 1000 | 8010 | 0 | 270045ns |

Modes: 0 random · 1 hotspot (to port 0) · 2 all-to-one (to port 2) ·
3 single-flit directed · 4 long-packet stress. Full transcripts in [`logs/`](logs);
[T1 screenshot](screenshots/T1_random200.png) shows a typical passing run.

## Verification notes

Two real DUT bugs were caught by this testbench during development:

1. **VC decode** — BODY/TAIL flits took their VC from payload bit 29, scattering
   one packet across VC FIFOs so it never reassembled. Fixed with a per-input
   `cur_vc` register set by each HEAD.
2. **Stall hold** — re-arbitration while stalled changed `data_out` under
   `valid=1`, dropping a flit per stall. Fixed by freezing `data_out`/`valid`
   until the stall clears.
