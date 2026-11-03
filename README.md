# Virtual commissioning of a pallet high-bay warehouse — TwinCAT 3

A storage and retrieval machine (RBG / stacker crane), its rack, the conveyor
pre-zone and the telegram interface to the material flow computer, written in
TwinCAT 3 Structured Text and commissioned **virtually**: every part simulates
its own hardware, so the whole plant runs and is tested on a soft-PLC with no
I/O connected.

It is built on my [node-tree framework](https://github.com/sulemanali5760/twincat3-pickplace-framework)
(cinnamon-style): the plant is a tree of nodes, one `Cyclic()` on the root runs
everything, devices expose commands that return `eBusy / eDone / eError`, and
sequences are a `CASE` over a step manager. The framework is copied unchanged.

### ▶ [Watch the plant run in your browser](https://sulemanali5760.github.io/twincat3-hrl-virtual-commissioning/)

No TwinCAT needed. The page is a JavaScript port of the same logic: the RBG
stores and retrieves pallets, the telegram log shows every order and answer,
and buttons send the faulty telegrams from the interface test or fail the
travel drive mid-job. (Source: `docs/index.html`.)

## What happens, in plain words

1. A pallet arrives on the **in-feed** conveyor and passes the **I-point** (contour and barcode check). It stops on the **transfer station** in front of the aisle.
2. The **material flow computer** (here an emulator) sends a transport order `TORD`: *take LE0042 from the station to place L-07-3*.
3. The PLC checks the order **before anything moves**: sequence number, duplicate order, valid places, RBG free, source holds exactly that pallet, target empty. If one check fails it answers `TERR` with a status code. If all pass it answers `TACK` and starts the RBG.
4. The **RBG** runs its single cycle: travel and hoist to the station together, fork out, lift, fork in, travel to the place still lifted, fork out, lower, fork in. The rack books the pallet out at "lift" and in at "lower", so the PLC always knows where every pallet is.
5. When the fork is back in the middle, the PLC reports `TDON`. The material flow computer must acknowledge with `TACK` within 5 s, otherwise the PLC raises status 30.
6. After every third store, the emulator orders the oldest pallet back out. The station is held free for it, the RBG brings the pallet to the station, and the out-feed takes it away.

Every axis simulates itself with a real speed/acceleration profile, so the times
are realistic: one store or retrieval takes about 25–40 s, a FEM 9.851 double
cycle about 52 s.

## The plant

```
                     rack, left side (20 columns x 8 levels)
   ┌──────────────────────────────────────────────────────────┐
   │ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢                  │
in-feed ─▶ [transfer station] ══ RBG aisle ═══════════════════▶  travel x
out-feed ◀─        ▲            hoist y, telescopic fork z
   │ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢                  │
   └──────────────────────────────────────────────────────────┘
                     rack, right side            320 places, single-deep
```

| Part | Block | What it does |
|---|---|---|
| Rack | `FB_Rack` | Which place holds which load unit; nominal positions from the drawing; **teach-in** of measured positions with a tolerance check (> 20 mm off = check the rack) |
| Axes | `FB_Axis` ×3 | Travel, hoist, fork. Simulated trapezoid velocity profile (v, a), `lrActPos` stands for the laser distance sensor |
| RBG | `FB_Srm` | Single cycle: travel+hoist → fork out → lift → fork in → travel+hoist → fork out → lower → fork in. Books the pallet out of the source and into the target at the exact step |
| Conveyor | `FB_ConveyorZone` | One **standard block** for every zone of the pre-zone — zones differ only in parameters (length, speed, jam time). Accept / deliver handshake, end light barrier, jam detection |
| I-point | `FB_IPoint` | Contour check (overhang, height) and barcode read before a pallet may be stored |
| MFR interface | `FB_MfrInterface` | Telegrams to the material flow computer (WAMAS-like): checks sequence number, duplicate order, valid addresses, RBG free, source holds the ordered load unit, target free → `TACK` or `TERR` with a status code; reports `TDON` and watches the acknowledgement |
| Throughput | `F_TravelTime`, `F_DoubleCycleTime` | Performance proof after FEM 9.851 (double cycle) |
| Demo | `FB_Hrl`, `FB_MfrEmulator`, `MAIN` | The plant as the root node; an emulated MFR feeds pallets, stores them and after every third store retrieves the oldest, so the plant runs by itself |

## Telegram status codes

| Code | Meaning | | Code | Meaning |
|---|---|---|---|---|
| 0 | OK | | 41 | duplicate order |
| 10 | target place occupied | | 42 | invalid address |
| 11 | source place empty | | 43 | RBG busy |
| 20 | contour NIO | | 44 | wrong load unit at source |
| 30 | TDON not acknowledged in time | | 45 | unknown telegram |
| 40 | sequence number out of order | | 50 | RBG fault |

The real telegram layout of a material flow computer is project-specific; this is a typical fixed layout.

## Performance proof (FEM 9.851 double cycle)

Store at P1, travel empty to P2, retrieve there, back to the transfer station.
FEM 9.851 places the reference points at P1 = (1/5 L, 2/3 H) and P2 = (2/3 L, 1/5 H);
the nearest places in this rack are column 4 / level 6 and column 13 / level 2.

| | |
|---|---|
| Rack L × H | 28.6 m × 9.1 m |
| Axes | travel 3.0 m/s, 0.6 m/s² · hoist 1.5 m/s, 0.8 m/s² · fork 0.6 m/s, 0.6 m/s² |
| Pick or deposit (fork out, lift/lower, fork in) | 6.37 s |
| Moves station → P1 → P2 → station | 6.43 s + 9.17 s + 11.27 s |
| **Calculated double cycle** | **52.4 s ≈ 69 double cycles per hour** |

The test `DoubleCycle_MatchesTheFem9851Calculation` runs the same two jobs on the
simulated RBG and requires the measured time to be within 5 % of the calculation.

## Files

Paths relative to `TcProject/HrlRbg/HrlRbgPlc/`.

| Folder | Content |
|---|---|
| `Framework/` | the node-tree framework (unchanged copy) |
| `Rack/` | `FB_Rack`, `ST_SlotAddr`, `ST_Slot`, `GVL_Rack` (geometry) |
| `Devices/` | `FB_Axis`, `FB_ConveyorZone`, `FB_IPoint` |
| `Units/` | `FB_Srm` |
| `Mfr/` | `FB_MfrInterface`, `ST_Telegram`, `GVL_Mfr` |
| `Performance/` | travel-time and double-cycle functions |
| `Machine/` | `FB_Hrl`, `FB_MfrEmulator`, `MAIN` |
| `Test/` | TcUnit suites, `PRG_TEST` |

## Tests

37 unit tests with [TcUnit](https://tcunit.org), in 7 suites. Every test runs its
scenario to the end inside one PLC cycle in simulated time, so the suite finishes
in about a second.

| Suite | What it pins down |
|---|---|
| `FB_Rack_Test` (7) | geometry, teach-in accepted / rejected, booking in and out, no double booking, invalid addresses, next free place |
| `FB_Axis_Test` (5) | arrives in tolerance, trapezoid and triangle move times, drive fault fails the move, reset |
| `FB_ConveyorZone_Test` (4) | runs to the light barrier in the right time, one pallet per zone, delivers, jam |
| `FB_IPoint_Test` (3) | OK, overhang, no read |
| `FB_MfrInterface_Test` (10) | the interface test cases: valid order, wrong sequence, duplicate, target occupied, source empty, wrong load unit, invalid address, busy, TDON + ack timeout, TACK |
| `FB_Srm_Test` (5) | store job, retrieve job, refused job, travel fault mid-job keeps the pallet booked, FEM 9.851 double cycle |
| `FB_TravelTime_Test` (3) | trapezoid, triangle, zero distance |

## Run it

1. Install TcUnit once (download `TcUnit.library` from the [releases page](https://github.com/tcunit/TcUnit/releases), then *PLC → Library Repository → Install*).
2. Open `TcProject/HrlRbg.sln` in TwinCAT XAE, platform *TwinCAT RT (x64)*.
3. Build, *Activate Configuration*, Run. `PRG_TEST` runs after `MAIN`; results appear in the Error List after about a second.
4. Watch the plant: `MAIN.fbPlant.fbSrm` (positions, jobs), `MAIN.fbEmulator` (stored / retrieved), `MAIN.fbPlant.fbRack`.

Built against TwinCAT 3.1.4026.

## Honest scope

- Everything is simulated: axes, light barriers and the material flow computer. Connecting real hardware means setting `bSimulate := FALSE` and mapping the I/O.
- The PROFINET network, the safety program (emergency stop, aisle door per EN 528) and the HMI are not part of this TwinCAT project.
- The FEM 9.851 reference points are taken as P1 = (1/5 L, 2/3 H), P2 = (2/3 L, 1/5 H); check against the standard text before using the numbers for a real acceptance.
