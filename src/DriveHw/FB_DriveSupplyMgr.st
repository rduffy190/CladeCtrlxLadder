// FB_DriveSupplyMgr: drive hardware station, one drive-integrated supply unit feeding the servo
// drives. Switches the supply to operation when all drives are ready for power, enables DC bus
// power in the drives while the supply is in operation, switches off only when no axis is
// under torque, aborts on supply or drive faults. Faults are cleared by the drive reset of
// drive 0 (which hosts the supply), issued by the servo axis manager in Resetting; this block
// waits for the faults to clear.
// No internal state machine: everything is a level function of the machine state and the
// hardware status. The drive-array loops are FB_DriveStatusScan and FB_DriveDcBusCtrl (ST).
// Design: design/Unit_DriveHardwareStation_Design.md
// Library: CXA_DriveUtil (MB_PowerSupplyDriveIntegrated)
FUNCTION_BLOCK FB_DriveSupplyMgr
VAR_INPUT
    itfClient       : I_StateClient;    // GVL_State.aClients[GVL_State.CLIENT_DRIVE_HW]
    stMachineState  : ST_MachineState;  // machine state to follow (from the caller: the broadcast, or a sub-manager's state)
    wSupplyStatus   : WORD;             // supply unit status word S-0-2058 (S-0-1720.0.2)
END_VAR
VAR_OUTPUT
    bSupplyInOperation : BOOL;          // diag: supply in operation mode (DC bus up)
    bSupplyOff      : BOOL;             // diag: supply mains off
    bAllReadyForPower : BOOL;           // diag: every drive ready for power
    bAnyUnderTorque : BOOL;             // diag: some drive under torque
    bAnyDriveFault  : BOOL;             // diag: some drive faulted
    bSupplyFault    : BOOL;             // diag: supply internal error or supply control error
    uiAbortCode     : UINT;             // abort code currently requested, 0 = none
END_VAR
VAR_IN_OUT
    wSupplyCtrl     : WORD;             // supply unit control word S-0-2057 (S-0-1720.0.1)
    awDriveStatus   : ARRAY[*] OF WORD; // drive status words, one per drive, numbered from 0
    awDriveDcBusCtrl: ARRAY[*] OF WORD; // drive DC bus power control S-0-0240, one per drive
END_VAR
VAR

    _bAllReady      : BOOL;
    _bAnyTorque     : BOOL;
    _bAnyDriveFault : BOOL;
    _uiDriveFaultCode : UINT;           // ABORT_DRIVE_FAULT + index of the first faulted drive
    _bSupplyInOp    : BOOL;
    _bSupplyOff     : BOOL;
    _bSupplyError   : BOOL;             // internal supply unit error
    _bSupplyCtrlError : BOOL;           // supply control FB error (invalid input, mode timeout)

    _bFaultAbortActive : BOOL;          // fault aborts are raised in this state
    _bAbort         : BOOL;
    _uiAbortCode    : UINT;
    _bDone          : BOOL;

    _bWantOn        : BOOL;
    _bSupplyCmd     : BOOL;             // supply to operation (self-holding)
    _bSupplyEnable  : BOOL;
    _eTargetMode    : MB_POWERSUPPLY_TARGET_MODE;

    _fbDriveStatus  : FB_DriveStatusScan;
    _fbSupply       : MB_PowerSupplyDriveIntegrated;
    _fbDcBus        : FB_DriveDcBusCtrl;
    _fbStateReq     : FB_StateRequest;
END_VAR
VAR CONSTANT
    SUPPLY_MODE_TIMEOUT : TIME := T#10S;    // max time per supply mode change (supervised by the FB)
    ABORT_NONE          : UINT := 0;
    ABORT_SUPPLY_CTRL   : UINT := 100;      // supply did not reach its target mode / invalid input
    ABORT_SUPPLY_FAULT  : UINT := 101;      // supply unit internal error
    ABORT_DRIVE_FAULT   : UINT := 110;      // + drive index
END_VAR

// ===== 1. Read status =====
NETWORK Drive status words
// Bits 15/14: ready for power / under torque. Bit 13: fault. The spare drive 2 isn't in the array.
    -> _fbDriveStatus(uiFaultCodeBase := ABORT_DRIVE_FAULT, awDriveStatus := awDriveStatus,
                      bAllReadyForPower => _bAllReady, bAnyUnderTorque => _bAnyTorque,
                      bAnyFault => _bAnyDriveFault, uiFaultCode => _uiDriveFaultCode)

NETWORK Supply in operation
// Supply state from the previous call of the supply FB
    [_fbSupply.ActualMode = MB_POWERSUPPLY_ACTUAL_MODE.OPERATION_MODE] -> _bSupplyInOp

NETWORK Supply off
    [_fbSupply.ActualMode = MB_POWERSUPPLY_ACTUAL_MODE.MAINS_OFF] -> _bSupplyOff

NETWORK Supply internal error
    _fbSupply.PowerSupplyError -> _bSupplyError

NETWORK Supply control error
    _fbSupply.Error -> _bSupplyCtrlError

// ===== 2. Faults -> abort request =====
NETWORK Fault aborts active
// Not raised while aborting, aborted or resetting: a fault that is still present must not
// block the reset that clears it. A fault that survives the reset leaves this client not
// done, and the manager's Resetting timeout aborts again.
    /stMachineState.bAborting /stMachineState.bAborted /stMachineState.bResetting -> _bFaultAbortActive

NETWORK Abort code: supply fault
// Highest priority. Also covers a supply that drops out after it was on.
    _bSupplyError -> _uiAbortCode := ABORT_SUPPLY_FAULT

NETWORK Abort code: drive fault
    /_bSupplyError _bAnyDriveFault -> _uiAbortCode := _uiDriveFaultCode

NETWORK Abort code: supply control
// The supply didn't reach its target mode in time (in practice only power-on)
    /_bSupplyError /_bAnyDriveFault _bSupplyCtrlError -> _uiAbortCode := ABORT_SUPPLY_CTRL

NETWORK Abort code: none
    /_bSupplyError /_bAnyDriveFault /_bSupplyCtrlError -> _uiAbortCode := ABORT_NONE

NETWORK Abort request
    _bFaultAbortActive [_uiAbortCode <> ABORT_NONE] -> _bAbort

// ===== 3. Done for the current machine state =====
NETWORK Done
// Off: supply off. TurningOn: in operation. Aborting: no torque and supply off.
// Resetting: no faults and in operation. Every other state: nothing to do.
    ( stMachineState.bOff /_bSupplyCmd _bSupplyOff
    | stMachineState.bTurningOn _bSupplyInOp
    | stMachineState.bAborting /_bAnyTorque /_bSupplyCmd _bSupplyOff
    | stMachineState.bResetting /_bSupplyError /_bSupplyCtrlError /_bAnyDriveFault _bSupplyInOp
    | /stMachineState.bOff /stMachineState.bTurningOn /stMachineState.bAborting /stMachineState.bResetting )
        -> _bDone

// ===== 4. Command levels =====
NETWORK Want on
// The supply is off in Off, Aborting and Aborted, and on in every other state
    /stMachineState.bOff /stMachineState.bAborted /stMachineState.bAborting -> _bWantOn

NETWORK Supply command
// Switch on only when every drive is ready, then hold; never switch off under torque
    (_bWantOn (_bSupplyCmd | _bAllReady) | _bSupplyCmd _bAnyTorque) -> _bSupplyCmd

NETWORK Target mode: operation
    _bSupplyCmd -> _eTargetMode := MB_POWERSUPPLY_TARGET_MODE.OPERATION_MODE

NETWORK Target mode: mains off
    /_bSupplyCmd -> _eTargetMode := MB_POWERSUPPLY_TARGET_MODE.MAINS_OFF_NO_DISCHARGE

NETWORK Supply enable
// Keep the FB enabled until the supply is really off. In Resetting, a supply control error
// holds Enable off, which is the documented way to clear the FB's error.
    (_bSupplyCmd | /_bSupplyOff) (/stMachineState.bResetting | /_bSupplyCtrlError) -> _bSupplyEnable

// ===== 5. Cyclic: sub-FBs, then outputs last =====
NETWORK Supply unit
    -> _fbSupply(Enable := _bSupplyEnable, TargetMode := _eTargetMode, Timeout := SUPPLY_MODE_TIMEOUT,
                 InProcStatus := wSupplyStatus, OutProcCtrl := wSupplyCtrl)

NETWORK DC bus power
// DC bus power to every drive while the supply is in operation
    -> _fbDcBus(bDcBusPower := _bSupplyInOp, awDriveDcBusCtrl := awDriveDcBusCtrl)

NETWORK State client
    -> _fbStateReq(itfClient := itfClient, bAbort := _bAbort, uiAbortCode := _uiAbortCode,
                   eStateEcho := stMachineState.eState, bDone := _bDone)

NETWORK Out bSupplyInOperation
    _bSupplyInOp -> bSupplyInOperation

NETWORK Out bSupplyOff
    _bSupplyOff -> bSupplyOff

NETWORK Out bAllReadyForPower
    _bAllReady -> bAllReadyForPower

NETWORK Out bAnyUnderTorque
    _bAnyTorque -> bAnyUnderTorque

NETWORK Out bAnyDriveFault
    _bAnyDriveFault -> bAnyDriveFault

NETWORK Out bSupplyFault
    (_bSupplyError | _bSupplyCtrlError) -> bSupplyFault

NETWORK Out copies
    -> uiAbortCode := _uiAbortCode
END_FUNCTION_BLOCK
