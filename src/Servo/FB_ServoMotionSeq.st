// FB_ServoMotionSeq: servo station motion. Position Ax1/Ax2 to their offsets and the VM to 0,
// gear Ax1/Ax2 to the VM (absolute to set point, 1:1, slave offsets), run the VM at the speed
// command (re-issued on a change), hold/unhold by stopping/restarting the VM, stop by halting
// the VM then the slaves, abort by stopping the VM then the slaves at the abort deceleration.
// Ladder sequence: jumps -> commit -> transitions -> commit -> state decode -> cyclic. There
// are no entry actions: every motion command is an Execute-level wrapper (FB_Ml*) whose
// Execute is the decoded state, so leaving a state drops the trigger and re-arms the command.
// Design: design/Unit_ServoStation_Design.md §4
FUNCTION_BLOCK FB_ServoMotionSeq
VAR_INPUT
    itfClient       : I_StateClient;    // GVL_State.aClients[GVL_State.CLIENT_SERVO_MOTION]
    stMachineState  : ST_MachineState;  // machine state to follow (from the caller: the broadcast, or a sub-manager's state)
    asAxisName      : ARRAY[0..GVL_Axes.LAST_AXIS] OF STRING(15);   // ctrlX MOTION axis names: Ax1, Ax2, VM
    lrSpeedCmd      : LREAL;    // VM velocity in Running; limited by the caller; may change at any time
    lrAx1Offset     : LREAL;    // Ax1 phase offset from the VM (positioning target and gear slave offset)
    lrAx2Offset     : LREAL;    // Ax2 phase offset from the VM (positioning target and gear slave offset)
END_VAR
VAR_OUTPUT
    eSeqState       : E_ServoSeqState;  // current step, for HMI / online view
    uiAbortCode     : UINT;             // abort code currently requested, 0 = none
END_VAR
VAR_IN_OUT CONSTANT
    astStatus       : ARRAY[0..GVL_Axes.LAST_AXIS] OF ST_AxisCyclicStatus;   // cyclic axis status
END_VAR
VAR

    _eSeqState      : E_ServoSeqState;  // the state; eSeqState is only a copy
    _eNextSeqState  : E_ServoSeqState;  // written by jumps/transitions, committed after each section
    _bSqIdle        : BOOL;             // sequence state decoded after the commit: one BOOL per state
    _bSqPositioning : BOOL;
    _bSqGearingIn   : BOOL;
    _bSqSynced      : BOOL;
    _bSqVmRunning   : BOOL;
    _bSqVmSpeedChange : BOOL;
    _bSqVmHalting   : BOOL;
    _bSqUngearing   : BOOL;
    _bSqAbortVm     : BOOL;
    _bSqAbortSlaves : BOOL;

    _bFailedAx1     : BOOL;             // a command of this axis failed (outside the abort steps)
    _bFailedAx2     : BOOL;
    _bFailedVm      : BOOL;
    _bFaultAbortActive : BOOL;
    _bAbort         : BOOL;
    _uiAbortCode    : UINT;
    _bDone          : BOOL;

    // Motion commands: Execute is the decoded state
    _fbAx1Pos       : FB_MlPosAbs;      // Positioning
    _fbAx2Pos       : FB_MlPosAbs;
    _fbVmPos        : FB_MlPosAbs;
    _fbAx1Gear      : FB_MlGearIn;      // GearingIn
    _fbAx2Gear      : FB_MlGearIn;
    _fbVmVel        : FB_MlVelocity;    // VmRunning
    _fbVmHalt       : FB_MlAbort;       // VmHalting, VM_DEC
    _fbAx1Halt      : FB_MlAbort;       // Ungearing, POS_DEC
    _fbAx2Halt      : FB_MlAbort;
    _fbVmAbort      : FB_MlAbort;       // AbortVm, ABORT_DEC
    _fbAx1Abort     : FB_MlAbort;       // AbortSlaves, ABORT_DEC
    _fbAx2Abort     : FB_MlAbort;
    _fbStateReq     : FB_StateRequest;
END_VAR
VAR CONSTANT
    VM_POSITION     : LREAL := 0.0;     // VM start position
    POS_VEL         : LREAL := 90.0;    // start positioning: velocity (units/s)   -- set for the machine
    POS_ACC         : LREAL := 360.0;   // start positioning: acceleration
    POS_DEC         : LREAL := 360.0;   // start positioning and ungearing: deceleration
    VM_ACC          : LREAL := 360.0;   // VM ramp up
    VM_DEC          : LREAL := 360.0;   // VM normal ramp down (hold, stop)
    ABORT_DEC       : LREAL := 1440.0;  // abort deceleration, separate from VM_DEC
    SPEED_DEADBAND  : LREAL := 0.01;    // speed command change that re-issues the VM velocity
    ABORT_NONE      : UINT := 0;
    ABORT_MOTION_CMD: UINT := 300;      // + axis index: motion command rejected, aborted or failed
END_VAR

// ===== 1. Jumps: abort first, then stop =====
NETWORK J1 Abort -> AbortVm
// From any active step: stop the VM first (slaves follow while geared)
    stMachineState.bAborting [_eSeqState <> E_ServoSeqState.Idle] [_eSeqState <> E_ServoSeqState.AbortVm]
        [_eSeqState <> E_ServoSeqState.AbortSlaves]
        -> _eNextSeqState := E_ServoSeqState.AbortVm

NETWORK J2 Stop -> VmHalting
// From any step not already on the stop or abort path: halt the VM, then ungear.
// Machine Stopping and Aborting are exclusive, so this never overrides J1.
    stMachineState.bStopping [_eSeqState <> E_ServoSeqState.Idle] [_eSeqState <> E_ServoSeqState.VmHalting]
        [_eSeqState <> E_ServoSeqState.Ungearing] [_eSeqState <> E_ServoSeqState.AbortVm]
        [_eSeqState <> E_ServoSeqState.AbortSlaves]
        -> _eNextSeqState := E_ServoSeqState.VmHalting

NETWORK Commit jumps
    -> _eSeqState := _eNextSeqState

// ===== 2. Transitions only =====
// The wrappers' Done/Error are from their call at the end of the last scan
NETWORK T Idle -> Positioning
    [_eSeqState = E_ServoSeqState.Idle] stMachineState.bStarting -> _eNextSeqState := E_ServoSeqState.Positioning

NETWORK T Positioning -> GearingIn
    [_eSeqState = E_ServoSeqState.Positioning] _fbAx1Pos.bDone _fbAx2Pos.bDone _fbVmPos.bDone
        -> _eNextSeqState := E_ServoSeqState.GearingIn

NETWORK T GearingIn -> Synced
    [_eSeqState = E_ServoSeqState.GearingIn]
        astStatus[GVL_Axes.AX1].InSynchronization astStatus[GVL_Axes.AX2].InSynchronization
        -> _eNextSeqState := E_ServoSeqState.Synced

NETWORK T Synced -> VmRunning
    [_eSeqState = E_ServoSeqState.Synced] (stMachineState.bRunning | stMachineState.bUnHolding)
        -> _eNextSeqState := E_ServoSeqState.VmRunning

NETWORK T VmRunning -> VmHalting
    [_eSeqState = E_ServoSeqState.VmRunning] stMachineState.bHolding -> _eNextSeqState := E_ServoSeqState.VmHalting

NETWORK T VmRunning -> VmSpeedChange
// The library can't change a running velocity command: drop it for one scan, then re-issue
    [_eSeqState = E_ServoSeqState.VmRunning] /stMachineState.bHolding _fbVmVel.bSetpointChanged
        -> _eNextSeqState := E_ServoSeqState.VmSpeedChange

NETWORK T VmSpeedChange -> VmRunning
// Back to VmRunning next scan: its Execute issues the velocity command at the new speed
    [_eSeqState = E_ServoSeqState.VmSpeedChange] -> _eNextSeqState := E_ServoSeqState.VmRunning

NETWORK T VmHalting -> Ungearing
    [_eSeqState = E_ServoSeqState.VmHalting] _fbVmHalt.bDone stMachineState.bStopping
        -> _eNextSeqState := E_ServoSeqState.Ungearing

NETWORK T VmHalting -> Synced
// Holding: VM stopped, slaves stay geared
    [_eSeqState = E_ServoSeqState.VmHalting] _fbVmHalt.bDone /stMachineState.bStopping
        -> _eNextSeqState := E_ServoSeqState.Synced

NETWORK T Ungearing -> Idle
    [_eSeqState = E_ServoSeqState.Ungearing] _fbAx1Halt.bDone _fbAx2Halt.bDone
        -> _eNextSeqState := E_ServoSeqState.Idle

NETWORK T AbortVm -> AbortSlaves
// Stopped, or can't be commanded any more (unpowered / in error): move on, never hang
    [_eSeqState = E_ServoSeqState.AbortVm]
        (_fbVmAbort.bDone | _fbVmAbort.bError | /astStatus[GVL_Axes.VM].PowerOn | astStatus[GVL_Axes.VM].HasError)
        -> _eNextSeqState := E_ServoSeqState.AbortSlaves

NETWORK T AbortSlaves -> Idle
    [_eSeqState = E_ServoSeqState.AbortSlaves]
        (_fbAx1Abort.bDone | _fbAx1Abort.bError | /astStatus[GVL_Axes.AX1].PowerOn | astStatus[GVL_Axes.AX1].HasError)
        (_fbAx2Abort.bDone | _fbAx2Abort.bError | /astStatus[GVL_Axes.AX2].PowerOn | astStatus[GVL_Axes.AX2].HasError)
        -> _eNextSeqState := E_ServoSeqState.Idle

NETWORK T Invalid state -> AbortVm
// The CASE ELSE: any value past the last state (e.g. after an online change)
    [_eSeqState > E_ServoSeqState.AbortSlaves] -> _eNextSeqState := E_ServoSeqState.AbortVm

NETWORK Commit transitions
    -> _eSeqState := _eNextSeqState

// ===== State decode: one compare per rung, so later rungs use contacts =====
NETWORK Decode Idle
    [_eSeqState = E_ServoSeqState.Idle] -> _bSqIdle

NETWORK Decode Positioning
    [_eSeqState = E_ServoSeqState.Positioning] -> _bSqPositioning

NETWORK Decode GearingIn
    [_eSeqState = E_ServoSeqState.GearingIn] -> _bSqGearingIn

NETWORK Decode Synced
    [_eSeqState = E_ServoSeqState.Synced] -> _bSqSynced

NETWORK Decode VmRunning
    [_eSeqState = E_ServoSeqState.VmRunning] -> _bSqVmRunning

NETWORK Decode VmSpeedChange
    [_eSeqState = E_ServoSeqState.VmSpeedChange] -> _bSqVmSpeedChange

NETWORK Decode VmHalting
    [_eSeqState = E_ServoSeqState.VmHalting] -> _bSqVmHalting

NETWORK Decode Ungearing
    [_eSeqState = E_ServoSeqState.Ungearing] -> _bSqUngearing

NETWORK Decode AbortVm
    [_eSeqState = E_ServoSeqState.AbortVm] -> _bSqAbortVm

NETWORK Decode AbortSlaves
    [_eSeqState = E_ServoSeqState.AbortSlaves] -> _bSqAbortSlaves

// ===== 4. Cyclic =====
NETWORK Failed Ax1
// Command failures in the abort steps are expected (axes may be unpowered or in error) and
// aren't counted. A wrapper only reports an error while its Execute is on.
    (_fbAx1Pos.bError | _fbAx1Gear.bError | _fbAx1Halt.bError) -> _bFailedAx1

NETWORK Failed Ax2
    (_fbAx2Pos.bError | _fbAx2Gear.bError | _fbAx2Halt.bError) -> _bFailedAx2

NETWORK Failed VM
    (_fbVmPos.bError | _fbVmVel.bError | _fbVmHalt.bError) -> _bFailedVm

NETWORK Fault aborts active
// Not raised while aborting, aborted or resetting
    /stMachineState.bAborting /stMachineState.bAborted /stMachineState.bResetting -> _bFaultAbortActive

NETWORK Abort code: Ax1
    _bFailedAx1 -> _uiAbortCode := ABORT_MOTION_CMD + INT_TO_UINT(GVL_Axes.AX1)

NETWORK Abort code: Ax2
    /_bFailedAx1 _bFailedAx2 -> _uiAbortCode := ABORT_MOTION_CMD + INT_TO_UINT(GVL_Axes.AX2)

NETWORK Abort code: VM
    /_bFailedAx1 /_bFailedAx2 _bFailedVm -> _uiAbortCode := ABORT_MOTION_CMD + INT_TO_UINT(GVL_Axes.VM)

NETWORK Abort code: none
    /_bFailedAx1 /_bFailedAx2 /_bFailedVm -> _uiAbortCode := ABORT_NONE

NETWORK Abort request
    _bFaultAbortActive [_uiAbortCode <> ABORT_NONE] -> _bAbort

NETWORK Done
// Starting, Holding: Synced. UnHolding: VM running at the commanded speed.
// Stopping, Aborting: back in Idle. Every other state: no motion work.
    ( (stMachineState.bStarting | stMachineState.bHolding) _bSqSynced
    | stMachineState.bUnHolding _bSqVmRunning astStatus[GVL_Axes.VM].InVelocity
    | (stMachineState.bStopping | stMachineState.bAborting) _bSqIdle
    | /stMachineState.bStarting /stMachineState.bHolding /stMachineState.bUnHolding /stMachineState.bStopping /stMachineState.bAborting )
        -> _bDone

NETWORK Positioning Ax1
// Absolute moves, shortest way on the modulo axes
    -> _fbAx1Pos(bExecute := _bSqPositioning, sAxisName := asAxisName[GVL_Axes.AX1], lrPosition := lrAx1Offset,
                 lrVelocity := POS_VEL, lrAcceleration := POS_ACC, lrDeceleration := POS_DEC)

NETWORK Positioning Ax2
    -> _fbAx2Pos(bExecute := _bSqPositioning, sAxisName := asAxisName[GVL_Axes.AX2], lrPosition := lrAx2Offset,
                 lrVelocity := POS_VEL, lrAcceleration := POS_ACC, lrDeceleration := POS_DEC)

NETWORK Positioning VM
    -> _fbVmPos(bExecute := _bSqPositioning, sAxisName := asAxisName[GVL_Axes.VM], lrPosition := VM_POSITION,
                lrVelocity := POS_VEL, lrAcceleration := POS_ACC, lrDeceleration := POS_DEC)

NETWORK Gear in Ax1
// Absolute to the VM set point: slave = VM x 1 + slave offset, synchronised the shortest way
    -> _fbAx1Gear(bExecute := _bSqGearingIn, sAxisName := asAxisName[GVL_Axes.AX1],
                  sMasterName := asAxisName[GVL_Axes.VM], lrSlaveOffset := lrAx1Offset)

NETWORK Gear in Ax2
    -> _fbAx2Gear(bExecute := _bSqGearingIn, sAxisName := asAxisName[GVL_Axes.AX2],
                  sMasterName := asAxisName[GVL_Axes.VM], lrSlaveOffset := lrAx2Offset)

NETWORK VM velocity
// Unbuffered, so a re-issued speed replaces the running command without stopping the VM
    -> _fbVmVel(bExecute := _bSqVmRunning, sAxisName := asAxisName[GVL_Axes.VM], lrVelocity := lrSpeedCmd,
                lrAcceleration := VM_ACC, lrDeceleration := VM_DEC, lrDeadband := SPEED_DEADBAND)

NETWORK VM halt
    -> _fbVmHalt(bExecute := _bSqVmHalting, sAxisName := asAxisName[GVL_Axes.VM], lrDeceleration := VM_DEC)

NETWORK Ungear Ax1
// Slaves are already at zero speed with the VM: cancelling the gearing brings them to standstill
    -> _fbAx1Halt(bExecute := _bSqUngearing, sAxisName := asAxisName[GVL_Axes.AX1], lrDeceleration := POS_DEC)

NETWORK Ungear Ax2
    -> _fbAx2Halt(bExecute := _bSqUngearing, sAxisName := asAxisName[GVL_Axes.AX2], lrDeceleration := POS_DEC)

NETWORK Abort VM
// Slaves follow the VM down while still geared
    -> _fbVmAbort(bExecute := _bSqAbortVm, sAxisName := asAxisName[GVL_Axes.VM], lrDeceleration := ABORT_DEC)

NETWORK Abort Ax1
    -> _fbAx1Abort(bExecute := _bSqAbortSlaves, sAxisName := asAxisName[GVL_Axes.AX1], lrDeceleration := ABORT_DEC)

NETWORK Abort Ax2
    -> _fbAx2Abort(bExecute := _bSqAbortSlaves, sAxisName := asAxisName[GVL_Axes.AX2], lrDeceleration := ABORT_DEC)

NETWORK State client
    -> _fbStateReq(itfClient := itfClient, bAbort := _bAbort, uiAbortCode := _uiAbortCode,
                   eStateEcho := stMachineState.eState, bDone := _bDone)

NETWORK Out copies
    -> eSeqState := _eSeqState, uiAbortCode := _uiAbortCode
END_FUNCTION_BLOCK
