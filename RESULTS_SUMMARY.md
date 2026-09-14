# CEP Results Summary — 5-Port NoC Router (VCS 2025.06, +define+ENABLE_SVA)

## Regression
| ID | Run Options | exp | got | flits | errors | pending | Time | Status |
|----|-------------|-----|-----|-------|--------|---------|------|--------|
| T1 | +NUM=200 +MODE=0 +STALL=0 | 200 | 200 | 1097 | 0 | 0 | 35045ns | PASS random |
| T2 | +NUM=20 +MODE=3 +STALL=0 | 20 | 20 | 20 | 0 | 0 | 8045ns | PASS single-flit directed |
| T3 | +NUM=300 +MODE=1 +STALL=0 | 300 | 300 | 1622 | 0 | 0 | 50045ns | PASS hotspot-to-0 |
| T4 | +NUM=200 +MODE=0 +STALL=1 | 200 | 200 | 1097 | 0 | 0 | 35045ns | PASS backpressure |
| T5 | +NUM=1000 +MODE=4 +STALL=1 | 1000 | 1000 | 8010 | 0 | 0 | 270045ns | PASS long stress |

- SVA HEAD→TAIL covers per output: T1 35/49/35/35/24; T3 266 on out[0] (hotspot); T5 214/196/226/191/173.
- `SV-LCM-PPWI` notes in logs are harmless (duplicate compilation-unit import).

## Bugs found and fixed
1. VC-decode: BODY/TAIL took VC from payload bit[29] → flits scattered across VCs → len/wrong-dest/unknown-tag errors. Fix: `cur_vc[i]` per input, HEAD sets it, BODY follows.
2. STALL-HOLD: re-arbitration under `!ready` changed `data_out` while `valid=1` → hold-check fail + 1-flit loss. Fix: freeze `data_out/valid` while stalled.

## CO mapping
- A8451.1: layered TB, virtual interface, queues/associative arrays
- A8451.2: interface clocking blocks + 8 SVAs via `bind`
- A8451.3: covergroup over src/dest/vc/len + 3 crosses
- A8451.4: Packet → HotspotPacket inheritance, mailboxes, Env
- A8451.5: `rand` + constraints + inline `with` + `pre_randomize`
