# Product plan — HRL/RBG library (TwinCAT 3)

Status 18 Nov 2026: Phases 1-4 done, Phase 5 safety done, HMI in progress. Not committed.
Owner of commits: Suleman (no co-author line). Tests: 59/59 pass on 3.1.4026.25 (`tools/tc_build_test.ps1`).

| Phase | State | Verified by |
|---|---|---|
| 1 Axis interface + NC axes | done | tests on 7 NC simulation axes (TF5000 trial) |
| 2 Config file | done | 5 tests + real load of HrlConfig.json from the boot folder (one-off) |
| 3 MFR TCP link | done, TCP untested live | codec + Serve tests; socket code build-only (needs TF6310 trial + client) |
| 4 Manual, teach-in, diagnostics | done; taught positions not yet saved to file | 5 tests |
| 5 Safety interface + docs | done (template) | 3 tests; docs/safety/README.md |
| 5 HMI (TE2000) | done: page + GVL_Hmi + FB_HmiBridge | 59/59; Live-View shows live values (18 Nov); buttons not clicked through yet |

Deviations from the plan below: diagnostics use ADSLOGSTR + an active-fault list instead of EventLogger
event classes (those need the XAE type editor); no in-PLC MFR link double (the emulator calls the
interface directly, tests use FB_MfrLinkFake); FB_RackPersist and tools/mfr_client.py not built yet.

## Goal

Turn the demo into a library an integrator can configure instead of program:
wire the hardware, fill one config file, run the guided commissioning, done.
Every phase keeps the existing 37 TcUnit tests green and adds its own.

## Done means (whole product)

- [ ] Same PLC code runs on simulated axes or real NC axes; switched in the config file only.
- [ ] Rack size, axis data, conveyor zones, MFR connection and telegram layout come from `HrlConfig.json`.
- [ ] Real MFR link over TCP/IP with a configurable fixed-length telegram; the in-process emulator stays for tests.
- [ ] Modes: Stop, Manual (jog per axis), Homing, Teach-in (guided), Automatic, with clean mode changes.
- [ ] Every fault is a TwinCAT EventLogger event with cause + remedy text (DE/EN).
- [ ] Safety: PLC-side safety interface (status in, enables out, stop categories) + TwinSAFE template + EN 528 checklist. Marked "not validated".
- [ ] TE2000 HMI: overview, jog/teach, faults, MFR log.
- [ ] Builds headless with 0 errors; all TcUnit tests pass on 3.1.4026.25; README "What is verified" updated.

## Hard limits (stay in README "Honest scope")

Not run on real hardware. Safety is a template, validated per machine by the integrator.
Single-deep, one RBG, one aisle. Beckhoff only.

## Architecture after the change

```
MAIN
 └─ FB_Hrl (root mode node)
     ├─ FB_HrlConfig ........ loads HrlConfig.json once at start (Tc3_JsonXml + file FBs)
     ├─ FB_Rack ............. runtime size from config (arrays sized by max constants)
     ├─ FB_Srm
     │   └─ I_Axis ×3 ....... FB_AxisSim (today's FB_Axis) | FB_AxisNc (Tc2_MC2)
     ├─ FB_ConveyorZone ×n .. bSimulate from config; real I/O via GVL_IO (AT %I*/%Q*)
     ├─ FB_IPoint
     ├─ FB_MfrInterface ..... logic unchanged; telegrams come from I_MfrLink
     │   └─ I_MfrLink ....... FB_MfrLinkLocal (emulator, tests) | FB_MfrLinkTcp (Tc2_TcpIp)
     ├─ FB_TelegramCodec .... ST_Telegram <-> fixed-length ASCII, field layout from config
     ├─ FB_SafetyInterface .. safety status in -> enables / stop request out
     └─ FB_Diag ............. EventLogger wrapper, one event class TC_HRL
```

Rule: the MFR checks, RBG sequence, rack booking and conveyor logic do not change.
New code sits behind interfaces; old blocks get `IMPLEMENTS`, not rewrites.

## Phase 1 — Hardware abstraction (axes + I/O)

Files:
- `Devices/I_Axis.TcIO` (new): `MoveAbs(lrPos):E_CmdResult`, `Halt():E_CmdResult`, `Reset()`, `Jog(bFwd,bBwd)`, props `ActPos`, `ActVelo`, `InPosition`, `Error`, `ErrorId`; `Configure(lrVelo, lrAccel, lrTol)`.
- `Devices/FB_Axis.TcPOU`: add `IMPLEMENTS I_Axis` (keep the name so existing tests stay valid; README calls it the simulated axis). Add `Halt`, `Jog`, props.
- `Devices/FB_AxisNc.TcPOU` (new): `EXTENDS FB_CyclicNode IMPLEMENTS I_Axis`; `stAxis : AXIS_REF` linked to an NC axis; MC_Power, MC_Reset, MC_MoveAbsolute, MC_Halt, MC_Jog, MC_ReadStatus. Same eBusy/eDone/eError contract, ErrorId from the NC.
- `Units/FB_Srm.TcPOU`: axes used through `ipTravel/ipHoist/ipFork : I_Axis`; holds both sim and NC instances, picks by `eAxisKind` (config). Axis data from config instead of the hard-coded block in `OnCyclic`.
- `Io/GVL_IO.TcGVL` (new): `AT %I*` / `AT %Q*` for light barriers, motor contactors, I-point sensors, barcode string.
- `Machine/FB_Hrl.TcPOU`: maps GVL_IO to the zones and I-point when not simulated.
- `HrlRbg.tsproj`: NC task with 3 axes (Travel, Hoist, Fork) in simulation mode, linked to `FB_AxisNc.stAxis` (done through the Automation Interface, not hand-edited XML).
- `Test/FB_AxisNc_Test.TcPOU` (new): MoveAbs reaches target, Halt, fault -> eError, Reset. Runs against NC simulation axes.
- `Test/FB_Srm_Test.TcPOU`: one extra test: a store job on NC axes.

Check: build 0 errors; all old tests + new pass; a run with `eAxisKind := eNc` stores a pallet.

## Phase 2 — Configuration file

Files:
- `Config/ST_HrlConfig.TcDUT` (new): rack (sides, columns, levels, pitch, offsets, strokes, teach tolerance), axes (kind, velo, accel, tol, timeout ×3), zones (length, speed, jam time, simulate ×n), I-point (simulate), MFR (link kind, IP, port, ack timeout, telegram layout), safety (simulate).
- `Config/FB_HrlConfig.TcPOU` (new): reads `C:\TwinCAT\3.1\Boot\HrlConfig.json` (path parameter), parses with `FB_JsonDomParser`, validates ranges, falls back to built-in defaults (= today's values) and raises a config event on any error.
- `Rack/GVL_Rack.TcGVL`: constants become `cMax*` array bounds (60 columns, 16 levels, 2 sides); live values move to the config.
- `Rack/FB_Rack.TcPOU`: uses config sizes; `IsValid` and `FindFree` check against them.
- `config/HrlConfig.json` + `config/HrlConfig.schema.json` (repo, new): today's plant as the example.
- `Test/FB_HrlConfig_Test.TcPOU` (new): parse a good JSON string, reject out-of-range values, defaults on missing file.

Check: build; tests; a second config (10×4 rack) changes the plant without code changes (test).

## Phase 3 — Real MFR link

Needs: TF6310 TCP/IP installed by Suleman (TcPkg), trial licence.

Files:
- `Mfr/I_MfrLink.TcIO` (new): `Poll(VAR_OUTPUT stIn, bNew)`, `Send(stOut)`, prop `Connected`.
- `Mfr/FB_TelegramCodec.TcPOU` (new): encode/decode fixed-length ASCII; field order, widths and padding from config; checks length and numeric fields (bad frame -> status 45).
- `Mfr/FB_MfrLinkTcp.TcPOU` (new): TCP server or client (config), reconnect, keep-alive `LIFE` telegram, receive buffer with frame start/end chars.
- `Mfr/FB_MfrLinkLocal.TcPOU` (new): in-process queue; `FB_MfrEmulator` talks through it.
- `Mfr/FB_MfrInterface.TcPOU`: unchanged checks; adds `Cyclic` polling of the link and sends replies/outbox through it.
- `Test/FB_TelegramCodec_Test.TcPOU` (new): round trip, wrong length, non-numeric field, custom layout.
- `tools/mfr_client.py` (repo, new): small Python MFR test client for the integrator (not run here).

Check: build; tests (codec + existing interface tests through the local link).
TCP itself is not exercised by the test suite: listed as "verified by build only" unless Suleman runs the client.

## Phase 4 — Operation and commissioning

Files:
- `Units/FB_Srm.TcPOU`: `RunManual` (jog per axis, interlocks: fork must be centred before travel/hoist), `RunHoming` (fork in, then home NC axes / sim to station), `RunStop` (Halt all axes).
- `Commissioning/FB_TeachIn.TcPOU` (new): guided teach: select place -> RBG drives to nominal -> operator jogs -> `Confirm` -> `FB_Rack.Teach`; progress counter; result table.
- `Commissioning/FB_RackPersist.TcPOU` (new): save/load taught positions to `HrlTeach.json`.
- framework `E_OpMode` has no teach mode: teach runs inside Manual (no framework change).
- `Diag/FB_Diag.TcPOU` + event class `TC_HRL` (TwinCAT type system, `.tmc` event class): events for axis fault, jam, ack timeout, config error, teach rejected, safety stop; text DE + EN with remedy.
- `Test/FB_TeachIn_Test`, `Test/FB_ManualMode_Test` (new).

Check: build; tests; mode change during a job stops cleanly (test).

## Phase 5 — Safety template and HMI

Safety (no hardware, template only):
- `Safety/ST_SafetyStatus.TcDUT`, `Safety/FB_SafetyInterface.TcPOU` (new): inputs from the safety PLC (e-stop ok, aisle door closed + locked, safe speed active, STO feedback per drive); outputs: drive enable, door unlock request, stop category request (0/1/2). Automatic only when all OK; door unlock only after RBG standstill.
- `docs/safety/` (new): TwinSAFE group layout (from the installed SafetyTemplate), signal list, EN 528 / ISO 13849 checklist, "what the integrator must do".
- `Test/FB_SafetyInterface_Test.TcPOU` (new): every input drop -> right stop and no restart without reset.

HMI (needs TE2000 installed by Suleman):
- `TcProject/HrlHmi/` TE2000 project: Overview (rack occupancy, RBG position, conveyors), Manual/Teach page, Faults (EventLogger grid), MFR log.
- Created in XAE by Suleman from the HMI template (I give click steps via the twincat-gui-help lookup); I write the page content and symbol bindings.

Check: build; safety tests; HMI: Suleman opens it live, screenshot in README.

## Order and working mode

One lane, phase by phase, in this checkout. Parallel worktrees are not used here:
every phase edits `HrlRbgPlc.plcproj` and `FB_Srm`, so branches would collide.
After each phase: headless build + TcUnit run, then Suleman reviews and commits.

## Needs from Suleman

1. OK to run the headless build + TcUnit runtime run (COM automation) for this repo, every phase.
2. Install TF6310 TCP/IP via TcPkg before Phase 3.
3. Install `TE2000-HMI-Engineering.1.12.762.60.exe` (Downloads) before Phase 5.
4. Renew the 7-day runtime trial licence when it expires (captcha).
