# Source

Ladder rebuild of `~/Dev/Plc` for ctrlX PLC Engineering. **One file is one object in the device tree.**

- **Ladder POUs** (`FB_StateManager`, `FB_DriveSupplyMgr`, `FB_ServoAxisPower`, `FB_ServoAxisMgr`, `FB_ServoMotionSeq`, `PRG_Main`) are full source files: an ST declaration and a ladder body written as `NETWORK`s. The LD editor can't paste text, so these arrive only through the import file.
- **ST objects** use paste format: the markers `// ===== Declaration =====` and `// ===== Implementation =====` show which pane each part goes into. DUT and GVL files paste whole.

| Folder | Ladder | ST | Design doc |
|---|---|---|---|
| `State/` | `FB_StateManager` | `E_MachineState`, `ST_MachineState`, `ST_StateClientData`, `I_StateClient` (methods `Request`, `Report`), `FB_StateClient` (methods `Request`, `Report`, property `Data`, Get only), `FB_StateRequest`, `FB_StateClientScan`, `GVL_State` | `design/Central_State_Management_Design.md` |
| `DriveHw/` | `FB_DriveSupplyMgr` | `ST_DriveFeedback`, `Fn_DriveFeedback`, `FB_DriveStatusScan`, `FB_DriveDcBusCtrl` | `design/Unit_DriveHardwareStation_Design.md` |
| `Servo/` | `FB_ServoAxisPower`, `FB_ServoAxisMgr`, `FB_ServoMotionSeq` | `ST_AxisCyclicStatus`, `GVL_Axes`, `GVL_AxisRtMap`, `ST_AxisRtOffsets`, `ST_AxisRtConfig`, `Fn_RtCopy`, `FB_AxisRtMap`, `FB_AxisRtRead`, `E_ServoSeqState`, `FB_AxisCmdState`, `FB_MlPower`, `FB_MlReset`, `FB_MlPosAbs`, `FB_MlGearIn`, `FB_MlVelocity`, `FB_MlAbort` | `design/Unit_ServoStation_Design.md` |
| `Main/` | `PRG_Main` | `GVL_IO`, `GVL_Hmi` | |

## What changed from the ST version

The behaviour follows the design docs and the ST version. The structure changes where ladder needs it:

- **Loops moved into ST helpers.** The manager's client loop is `FB_StateClientScan`. The drive-word loops are `FB_DriveStatusScan` (ready, torque, fault and the first fault's code) and `FB_DriveDcBusCtrl`. Adding a client or a drive still needs no ladder change.
- **Motion uses Execute-level wrappers.** The ST sequence issued `ML_` commands in its entry actions and tracked CmdIDs itself. In ladder, each command is an `FB_Ml*` instance whose `bExecute` is the decoded sequence state. It issues once, reports `bDone`/`bError`, and re-arms when its state is left. That's the level trigger servo doc §4 describes. `VmSpeedChange` drops the velocity Execute for one scan, so the next `VmRunning` scan re-issues at the new speed. `FB_MlVelocity.bSetpointChanged` replaces the ST speed latch.
- **The axis manager is split per axis.** `FB_ServoAxisPower` (one instance per axis) does the power level, reset and the axis's fault code. `FB_ServoAxisMgr` decides when power is wanted, debounces at-rest, picks the first axis with a fault, and reports done. A rejected power or reset command is held by its wrapper until the next accepted command, instead of being latched until the next Resetting entry. The effect is the same: aborts aren't raised in Resetting, and leaving Resetting needs the axes powered, which needs an accepted power command.
- **Ladder timing.** The step timers restart one scan after a state change (ladder holds IN off on the change scan). The axis manager reads the per-axis fault codes from the previous scan. Both are one scan (milliseconds) against timeouts of seconds.
- **The machine state is broadcast already decoded.** `GVL_State.stMachineState` (`ST_MachineState`) holds `eState` plus one BOOL per state, filled by the manager from its own decode. Units take it as their `stMachineState` input and use contacts like `stMachineState.bAborting`, with no decode networks of their own. They echo `stMachineState.eState`. This replaces the ST version's `eMachineState` input and `GVL_State.eMachineState`.
- **`PRG_Main` wires the manager's outputs straight to `GVL_State`** with `=>` pins, instead of copy lines.

**Paste/create order** (dependencies first): `E_MachineState` → `ST_MachineState` → `ST_StateClientData` → `I_StateClient` → `FB_StateClient` → `FB_StateRequest` → `FB_StateClientScan` → `GVL_State` → everything else via the import.

**Task:** call `PRG_Main` from the cyclic PLC task.

**I/O mapping:** map `GVL_IO` to the SoE cyclic data:
- supply unit: status word S-0-2058 in the AT, control word S-0-2057 in the MDT. The supply unit must be configured for "external activation via field bus".
- drives 0 (Ax1, hosts the supply) and 1 (Ax2): status word in the AT, DC bus power control S-0-0240 in the MDT;
- drive 2 is a spare and isn't used. Only its status word is mapped, for diagnostics.

**Libraries:** `Standard` (TON), `CXA_DriveUtil` (`MB_PowerSupplyDriveIntegrated`), `CXA_Motion` (`ML_` functions), `CXA_Datalayer` (`DL_MemUser`, `DL_NODEVALUE`), `CXA_AutomationCore_fbs` (`comm_datalayer_MemoryMap`, `comm_datalayer_Variable`).

**Motion setup:** as in `~/Dev/Plc/src/README.md`. Set `GVL_Axes.asAxisName`, enable cyclic status data per axis, and set the dynamics constants in `FB_ServoMotionSeq` (`POS_*`, `VM_*`, `ABORT_DEC`, `SPEED_DEADBAND`), which are placeholders.

## Importing

`python3 tools/build_import.py` builds `build/MotionLad_Import.xml` and `build/manual/`, which holds the objects to create by hand (`I_StateClient`, `FB_StateClient`; the converter doesn't do interfaces, methods or properties) and the checklist `build/manual/README.md`. Follow that checklist.

**Check in the LD editor after import:** three pin values are arithmetic expressions, not plain variables. CODESYS accepts expressions on box inputs, but this converter hasn't produced one in an import that was checked on a real install:
- `FB_ServoAxisPower`, network *Abort code*: `_uiReasonBase + INT_TO_UINT(iAxis)`;
- `FB_ServoMotionSeq`, networks *Abort code: Ax1/Ax2/VM*: `ABORT_MOTION_CMD + INT_TO_UINT(GVL_Axes.AX1)` etc.;
- `PRG_Main`, network *Servo station: motion*: `lrAx2Offset := MODULO - GVL_Hmi.lrSlaveOffset`.

## Status

| Part | State |
|---|---|
| All ladder POUs | Built, schema-valid, traced. Logic tested in the scan simulator (`tests/run.sh`: 90 cases). Not imported or compiled in ctrlX PLC Engineering yet. |
| ST helpers and wrappers | Written. Not compiled. The `ML_` field names are the ones the ST project used. |
| RT axis status | Unchanged from the ST project. |
