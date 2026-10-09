// FUNCTION_BLOCK: FB_MlVelocity
// Velocity move with the Execute handshake, for ladder: ML_AxsVelocity is issued once when
// bExecute is TRUE (unbuffered, so it replaces a running command without stopping the axis),
// tracked by its CmdID, and re-armed when bExecute is removed.
// The chosen library can't change a running velocity command, so bSetpointChanged reports when
// lrVelocity has moved more than lrDeadband from the issued speed. The caller then drops
// bExecute for one scan (VmSpeedChange) and the next Execute issues the new speed.
// Library: CXA_Motion

// ===== Declaration =====
FUNCTION_BLOCK FB_MlVelocity
VAR_INPUT
    bExecute        : BOOL;         // issue the velocity move; remove to re-arm
    sAxisName       : STRING(15);   // ctrlX MOTION axis name
    lrVelocity      : LREAL;        // velocity, latched when the command is issued
    lrAcceleration  : LREAL;
    lrDeceleration  : LREAL;
    lrDeadband      : LREAL;        // change of lrVelocity that sets bSetpointChanged
END_VAR
VAR_OUTPUT
    bError          : BOOL;         // rejected, aborted or failed (while bExecute)
    bSetpointChanged: BOOL;         // lrVelocity differs from the issued velocity by more than lrDeadband
END_VAR
VAR
    _bIssued        : BOOL;
    _bAccepted      : BOOL;
    _ulCmdID        : ULINT;
    _lrIssuedVel    : LREAL;        // velocity of the command issued
    _stCmd          : ML_AxsVelData;
    _fbCmdState     : FB_AxisCmdState;
END_VAR
VAR CONSTANT
    SOURCE_NAME     : STRING(50) := 'FB_MlVelocity';
    NO_JERK_LIMIT   : LREAL := 0.0;
END_VAR

// ===== Implementation =====
IF bExecute AND NOT _bIssued THEN
    _lrIssuedVel := lrVelocity;
    _stCmd.In.AxisName     := sAxisName;
    _stCmd.In.Source       := SOURCE_NAME;
    _stCmd.In.Velocity     := _lrIssuedVel;
    _stCmd.In.DriveVelMode := FALSE;
    _stCmd.In.Buffered     := FALSE;
    _stCmd.In.DynLimits.Velocity     := ABS(_lrIssuedVel);
    _stCmd.In.DynLimits.Acceleration := lrAcceleration;
    _stCmd.In.DynLimits.Deceleration := lrDeceleration;
    _stCmd.In.DynLimits.JerkAcc      := NO_JERK_LIMIT;
    _stCmd.In.DynLimits.JerkDec      := NO_JERK_LIMIT;
    _bAccepted := ML_AxsVelocity(Data := _stCmd);
    _ulCmdID   := _stCmd.Out.CmdID;
    _bIssued   := TRUE;
ELSIF NOT bExecute THEN
    _bIssued   := FALSE;
    _bAccepted := FALSE;
END_IF

_fbCmdState(bActive := _bIssued, sObjName := sAxisName, ulCmdID := _ulCmdID, bAccepted := _bAccepted);

// Outputs
bError           := _fbCmdState.bFailed;
bSetpointChanged := _bIssued AND ABS(lrVelocity - _lrIssuedVel) > lrDeadband;
