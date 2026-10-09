// FB_ServoAxisMgr: servo station axis manager. Axis power on/off from the machine state,
// torque-free at the end of Aborting, fault detection -> abort request, reset of every axis
// on entry to Resetting. No sequence of its own: everything is a level function of the
// machine state and the axis status. Each axis is an FB_ServoAxisPower.
// Design: design/Unit_ServoStation_Design.md §3
FUNCTION_BLOCK FB_ServoAxisMgr
VAR_INPUT
    itfClient       : I_StateClient;    // GVL_State.aClients[GVL_State.CLIENT_SERVO_AXES]
    stMachineState  : ST_MachineState;  // machine state to follow (from the caller: the broadcast, or a sub-manager's state)
    asAxisName      : ARRAY[0..GVL_Axes.LAST_AXIS] OF STRING(15);    // ctrlX MOTION axis names: Ax1, Ax2, VM
END_VAR
VAR_OUTPUT
    bAllPowered     : BOOL;     // diag: all axes powered
    bAllOff         : BOOL;     // diag: all axes torque-free
    bAllAtRest      : BOOL;     // diag: all axes at rest (debounced)
    bAnyError       : BOOL;     // diag: some axis has an error
    uiAbortCode     : UINT;     // abort code currently requested, 0 = none
END_VAR
VAR_IN_OUT CONSTANT
    astStatus       : ARRAY[0..GVL_Axes.LAST_AXIS] OF ST_AxisCyclicStatus;   // cyclic axis status
END_VAR
VAR

    _bAllPowered    : BOOL;
    _bAllOff        : BOOL;
    _bAllAtRestNow  : BOOL;             // undebounced
    _bAnyError      : BOOL;

    _bFaultAbortActive : BOOL;
    _bAbort         : BOOL;
    _uiAbortCode    : UINT;
    _bDone          : BOOL;
    _bWantPower     : BOOL;             // machine-level power want (before per-axis conditions)

    _fbRestDebounce : TON;
    _fbAx1          : FB_ServoAxisPower;
    _fbAx2          : FB_ServoAxisPower;
    _fbVm           : FB_ServoAxisPower;
    _fbStateReq     : FB_StateRequest;
END_VAR
VAR CONSTANT
    REST_DEBOUNCE   : TIME := T#100MS;  // all axes must be at rest this long before going torque-free
    ABORT_NONE      : UINT := 0;
END_VAR

// ===== 1. Read status =====
NETWORK All powered
    astStatus[GVL_Axes.AX1].PowerOn astStatus[GVL_Axes.AX2].PowerOn astStatus[GVL_Axes.VM].PowerOn
        -> _bAllPowered

NETWORK All torque-free
    /astStatus[GVL_Axes.AX1].PowerOn /astStatus[GVL_Axes.AX2].PowerOn /astStatus[GVL_Axes.VM].PowerOn
        -> _bAllOff

NETWORK All at rest
// At rest: standstill, disabled or in error (an axis in error is stopped by its drive)
    (astStatus[GVL_Axes.AX1].Standstill | /astStatus[GVL_Axes.AX1].PowerOn | astStatus[GVL_Axes.AX1].HasError)
    (astStatus[GVL_Axes.AX2].Standstill | /astStatus[GVL_Axes.AX2].PowerOn | astStatus[GVL_Axes.AX2].HasError)
    (astStatus[GVL_Axes.VM].Standstill | /astStatus[GVL_Axes.VM].PowerOn | astStatus[GVL_Axes.VM].HasError)
        -> _bAllAtRestNow

NETWORK Any error
    (astStatus[GVL_Axes.AX1].HasError | astStatus[GVL_Axes.AX2].HasError | astStatus[GVL_Axes.VM].HasError)
        -> _bAnyError

// ===== 2. Faults -> abort request =====
NETWORK Fault aborts active
// Not raised while aborting, aborted or resetting, so a fault can't block its own reset
    /stMachineState.bAborting /stMachineState.bAborted /stMachineState.bResetting -> _bFaultAbortActive

NETWORK Abort code: Ax1
// First axis with a fault, in axis order. The axis blocks' results are from the last scan.
    _fbAx1.bFault -> _uiAbortCode := _fbAx1.uiAbortCode

NETWORK Abort code: Ax2
    /_fbAx1.bFault _fbAx2.bFault -> _uiAbortCode := _fbAx2.uiAbortCode

NETWORK Abort code: VM
    /_fbAx1.bFault /_fbAx2.bFault _fbVm.bFault -> _uiAbortCode := _fbVm.uiAbortCode

NETWORK Abort code: none
    /_fbAx1.bFault /_fbAx2.bFault /_fbVm.bFault -> _uiAbortCode := ABORT_NONE

NETWORK Abort request
    _bFaultAbortActive [_uiAbortCode <> ABORT_NONE] -> _bAbort

// ===== 3. Done for the current machine state =====
NETWORK Done
// Off, Aborting, Aborted: all torque-free (Aborting: before the supply goes off).
// TurningOn, Resetting: all powered, no error. Every other state: stay powered, nothing to do.
    ( (stMachineState.bOff | stMachineState.bAborted | stMachineState.bAborting) _bAllOff
    | (stMachineState.bTurningOn | stMachineState.bResetting) _bAllPowered /_bAnyError
    | /stMachineState.bOff /stMachineState.bAborted /stMachineState.bAborting /stMachineState.bTurningOn /stMachineState.bResetting )
        -> _bDone

// ===== 4. Command levels =====
NETWORK Want power
// Powered in every state except Off and Aborted; in Aborting only until all axes are at rest
    /stMachineState.bOff /stMachineState.bAborted (/stMachineState.bAborting | /_fbRestDebounce.Q) -> _bWantPower

// ===== 5. Cyclic: sub-FBs, then outputs last =====
NETWORK Rest debounce
    _bAllAtRestNow _fbRestDebounce(PT := REST_DEBOUNCE)

NETWORK Axis Ax1
// Any fault aborts, so Resetting always follows one: every axis is reset, whatever the cause.
// Drive 0 (Ax1) hosts the drive supply, so its reset also clears supply errors.
    -> _fbAx1(sAxisName := asAxisName[GVL_Axes.AX1], iAxis := GVL_Axes.AX1, bWantPower := _bWantPower,
              bReset := stMachineState.bResetting, stStatus := astStatus[GVL_Axes.AX1])

NETWORK Axis Ax2
    -> _fbAx2(sAxisName := asAxisName[GVL_Axes.AX2], iAxis := GVL_Axes.AX2, bWantPower := _bWantPower,
              bReset := stMachineState.bResetting, stStatus := astStatus[GVL_Axes.AX2])

NETWORK Axis VM
    -> _fbVm(sAxisName := asAxisName[GVL_Axes.VM], iAxis := GVL_Axes.VM, bWantPower := _bWantPower,
             bReset := stMachineState.bResetting, stStatus := astStatus[GVL_Axes.VM])

NETWORK State client
    -> _fbStateReq(itfClient := itfClient, bAbort := _bAbort, uiAbortCode := _uiAbortCode,
                   eStateEcho := stMachineState.eState, bDone := _bDone)

NETWORK Out bAllPowered
    _bAllPowered -> bAllPowered

NETWORK Out bAllOff
    _bAllOff -> bAllOff

NETWORK Out bAllAtRest
    _fbRestDebounce.Q -> bAllAtRest

NETWORK Out bAnyError
    _bAnyError -> bAnyError

NETWORK Out copies
    -> uiAbortCode := _uiAbortCode
END_FUNCTION_BLOCK
