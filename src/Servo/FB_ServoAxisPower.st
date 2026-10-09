// FB_ServoAxisPower: one axis of the servo axis manager. Power on/off as a level, the axis
// reset, and the axis's own fault check. FB_ServoAxisMgr has one instance per axis and
// decides when power is wanted and when to reset.
// Design: design/Unit_ServoStation_Design.md §3
FUNCTION_BLOCK FB_ServoAxisPower
VAR_INPUT
    sAxisName       : STRING(15);   // ctrlX MOTION axis name
    iAxis           : INT;          // axis index (GVL_Axes.AX1 / AX2 / VM), added to the abort codes
    bWantPower      : BOOL;         // the machine state wants the axes powered
    bReset          : BOOL;         // reset the axis: issued once while TRUE (machine in Resetting)
END_VAR
VAR_OUTPUT
    bFault          : BOOL;         // the axis has a fault (data invalid, error, power lost, command rejected)
    uiAbortCode     : UINT;         // abort code for the fault, 0 = none
END_VAR
VAR_IN_OUT CONSTANT
    stStatus        : ST_AxisCyclicStatus;  // cyclic status of this axis
END_VAR
VAR
    _bWantAxisPower : BOOL;         // power commanded to this axis
    _bPowerConfirmed: BOOL;         // axis reported PowerOn since power was commanded
    _bCmdRejected   : BOOL;         // a power or reset command was not accepted
    _bFault         : BOOL;
    _uiReasonBase   : UINT;         // abort code base of the fault found
    _uiAbortCode    : UINT;
    _fbPower        : FB_MlPower;
    _fbReset        : FB_MlReset;
END_VAR
VAR CONSTANT
    ABORT_NONE          : UINT := 0;
    ABORT_AXIS_ERROR    : UINT := 200;  // + axis index
    ABORT_POWER_LOST    : UINT := 210;  // + axis index
    ABORT_AXIS_CMD      : UINT := 220;  // + axis index: power/reset command not accepted
    ABORT_AXIS_DATA     : UINT := 230;  // + axis index: cyclic status not valid
END_VAR

// ===== 1. Read status =====
NETWORK Power confirmed
// Set once the axis reports PowerOn after power was commanded (last scan's command);
// dropped when power is switched off. Power lost is only checked after this.
    _bWantAxisPower (_bPowerConfirmed | stStatus.PowerOn) -> _bPowerConfirmed

NETWORK Command rejected
// The wrappers hold their error: power until the next accepted power command, reset while Resetting
    (_fbPower.bError | _fbReset.bError) -> _bCmdRejected

// ===== 2. Faults -> abort code, first matching =====
NETWORK Reason: data invalid
    /stStatus.DataValid -> _uiReasonBase := ABORT_AXIS_DATA

NETWORK Reason: axis error
    stStatus.DataValid stStatus.HasError -> _uiReasonBase := ABORT_AXIS_ERROR

NETWORK Reason: power lost
    stStatus.DataValid /stStatus.HasError _bPowerConfirmed /stStatus.PowerOn -> _uiReasonBase := ABORT_POWER_LOST

NETWORK Reason: command rejected
    stStatus.DataValid /stStatus.HasError (/_bPowerConfirmed | stStatus.PowerOn) _bCmdRejected
        -> _uiReasonBase := ABORT_AXIS_CMD

NETWORK Fault
    (/stStatus.DataValid | stStatus.HasError | _bPowerConfirmed /stStatus.PowerOn | _bCmdRejected) -> _bFault

NETWORK Abort code
    _bFault -> _uiAbortCode := _uiReasonBase + INT_TO_UINT(iAxis)

NETWORK No abort code
    /_bFault -> _uiAbortCode := ABORT_NONE

// ===== 3. Command levels =====
NETWORK Axis power
// Enable only once motion reports the axis ready for power (DC bus up) and it has no error.
// Readiness comes from the motion feedback, not the drive status word, so a test axis works too.
    bWantPower stStatus.PowerReady /stStatus.HasError -> _bWantAxisPower

// ===== 4. Cyclic: sub-FBs, then outputs last =====
NETWORK Power command
// ML_AxsPower is issued once each time the wanted level changes
    -> _fbPower(sAxisName := sAxisName, bSwitchOn := _bWantAxisPower)

NETWORK Reset command
    -> _fbReset(bExecute := bReset, sAxisName := sAxisName)

NETWORK Out bFault
    _bFault -> bFault

NETWORK Out copies
    -> uiAbortCode := _uiAbortCode
END_FUNCTION_BLOCK
