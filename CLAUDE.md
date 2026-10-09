# PLC project: ctrlX CORE, ladder rebuild

Ladder (LD) rebuild of the Structured Text project in `~/Dev/Plc`, for a Bosch Rexroth ctrlX CORE (ctrlX PLC Engineering, CODESYS-based). Same design docs, same behaviour.

## Use the `codesys-lad` and `codesys-st` skills

Load the **`codesys-lad`** skill before writing or reviewing any ladder, and the **`codesys-st`** skill (`~/.claude/skills/codesys-st/`) for everything else. codesys-st holds:
- the house rules: the sequence structure, no rising edges, never reading your own outputs, naming conventions;
- the ctrlX library references.

Follow it exactly. The rules in it came from review of real code.

## Motion: use the Motion App commands (`ML_` functions)

For all axis and kinematics motion in this project, use the **Motion App PLC functions (`ML_...`, library `CXA_Motion`)**.

- **Don't use** `CXA_PLCopen` (`MC_*` / `MB_*` function blocks).
- **Don't use** `CXA_MotionInterface` (the AxisInterface / KinematicInterface template).

This overrides the skill's default of PLCopen FBs.

Where to look things up:
- **Command and function reference:** `~/.claude/skills/codesys-st/references/motion/INDEX.md`. Find the command there, then read only that section of the `07-*.md` files, including its "PLC:" part.
- **Behaviour, buffering, states and errors:** `~/.claude/skills/codesys-st/references/motion-essentials.md`.

Remember that `ML_` calls are **one-shot functions, not FBs**, and ladder can't call them. Every `ML_` call lives in an `FB_Ml*` wrapper (ST), which issues the command once per Execute, keeps the `CmdID` and tracks it with `ML_GetCmdState` (via `FB_AxisCmdState`). Never call a motion command every scan. A new command type means a new wrapper.

Check every struct and field name against the reference before using it. Don't guess.

## What is ladder and what stays ST

- **Ladder:** the logic electricians read online: `FB_StateManager`, `FB_DriveSupplyMgr`, `FB_ServoAxisMgr`, `FB_ServoAxisPower`, `FB_ServoMotionSeq`, `PRG_Main`. Ladder files are full ST source with an LD body (`NETWORK ...`), in the codesys-lad rung language.
- **ST:** anything with a loop, interface/method plumbing or `ML_` calls:
  - client plumbing: `I_StateClient`, `FB_StateClient`, `FB_StateRequest`, and `FB_StateClientScan` (the manager's client loop);
  - drive arrays: `FB_DriveStatusScan`, `FB_DriveDcBusCtrl`, `Fn_DriveFeedback`;
  - RT axis status: `FB_AxisRtMap`, `FB_AxisRtRead`, `Fn_RtCopy` (decided: these stay ST);
  - `ML_` wrappers: `FB_MlPower`, `FB_MlReset`, `FB_MlPosAbs`, `FB_MlGearIn`, `FB_MlVelocity`, `FB_MlAbort`, `FB_AxisCmdState`.
- **Motion from ladder goes through the `FB_Ml*` wrappers.** Each one issues its `ML_` command once per Execute and is re-armed when Execute drops (the PLCopen Execute/Done handshake). A ladder sequence drives Execute from its decoded state, so it needs no entry actions for motion.

## Testing

`tests/run.sh` builds, validates, traces and runs every test plan in the scan simulator. `tests/simx.py` extends the skill's `ld_sim` with stubbed sub-FBs and pin expressions. Run it after any change.

## Design docs

The design is in **`design/`**. Start with `design/README.md`, which has the index, the implementation order, the house rules and the open decisions.

- Implement what the docs say. If code needs a decision the docs don't make, ask, and don't invent one.
- The design docs are library-agnostic on purpose. Library choices (such as the `ML_` functions above) belong in the code and here, not in the docs.
- When a design decision changes, update the doc as well as the code. Mark answered questions **Decided** in place, without renumbering.
