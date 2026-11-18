# Safety concept (template, not validated)

**This project contains no safety function.** The PLC program is standard code. Emergency stop, aisle
door and safe drive stops belong in a safety controller (for Beckhoff: TwinSAFE logic) and must be designed,
validated and documented for each machine by the integrator. What this repository provides is the
standard-PLC side: how the program follows the safety controller, and a checklist of what is still open.

## Split of responsibilities

| Function | Where | In this repo |
|---|---|---|
| Emergency stop, stop category per risk assessment | safety controller | no (template signals only) |
| Aisle access door: monitoring and guard locking | safety controller | no |
| Safe Torque Off / safe stops of the RBG drives | safety controller + drives | no |
| Drive enable and automatic only while the safety status is OK | standard PLC | `FB_SafetyInterface` |
| No automatic restart: acknowledge after every safety drop | standard PLC (plus safety controller) | `FB_SafetyInterface` |
| Door unlock request only at standstill | standard PLC requests, safety controller decides | `FB_SafetyInterface` |
| Stop mode while safety is not OK | standard PLC | `MAIN` |

## Signals (safety controller -> standard PLC)

Map the TwinSAFE group outputs to `MAIN.fbPlant.stSafety` (`ST_SafetyStatus`):

| Bit | Meaning |
|---|---|
| `bSafetyRun` | safety program running, no group error |
| `bEStopOk` | all emergency stops released |
| `bDoorClosed` | aisle access door closed |
| `bDoorLocked` | aisle access door guard-locked |
| `bStoOk` | drives not in Safe Torque Off |

Standard PLC -> safety controller: `MAIN.fbPlant.bDoorUnlockReq`.
HMI -> standard PLC: `MAIN.fbPlant.bSafetyReset` (acknowledge), `MAIN.fbPlant.bDoorRequest`.

`safety.simulate` in `HrlConfig.json` makes every bit count as OK for the bench. It must be `false` on a
real machine.

## TwinSAFE starting point

TwinCAT 3.1.4026 installs TwinSAFE project templates under
`C:\Program Files (x86)\Beckhoff\TwinCAT\3.1\Components\Base\SafetyTemplate\Templates\1.2.0.0\`
(hardware safety PLC with graphical editor, and TwinCAT Safety PLC with Safety C). Create the safety project
from one of them in XAE; this repository does not ship one, because it depends on the safety hardware.

## Checklist for the integrator (not complete, not legal advice)

- [ ] Risk assessment for the actual machine (EN ISO 12100); required performance levels per function.
- [ ] Apply the product standard for storage and retrieval machines (EN 528) and the safety-related
      control system standard (EN ISO 13849-1/-2) to the actual design.
- [ ] Choose the stop category for emergency stop and door opening from the risk assessment.
- [ ] Design the safety controller logic and the safe drive functions; validate them (EN ISO 13849-2).
- [ ] Map the signals above; set `safety.simulate` to `false`; test every drop and the restart lock on the machine.
- [ ] Document the validation and the residual risks; include them in the CE technical file.

Tests of the standard-PLC side: `FB_SafetyInterface_Test` (power-up lock, every bit drop, acknowledge,
door unlock at standstill).
