// FUNCTION_BLOCK: FB_MlPosAbs
// Absolute move with the Execute/Done handshake, for ladder: ML_AxsPosAbs is issued once when
// bExecute is TRUE, tracked by its CmdID, and re-armed when bExecute is removed. Modulo axes
// move the shortest way (the axis default for ML_AxsPosAbs).
// Library: CXA_Motion

// ===== Declaration =====
FUNCTION_BLOCK FB_MlPosAbs
VAR_INPUT
    bExecute        : BOOL;         // issue the move; hold TRUE until Done/Error, remove to re-arm
    sAxisName       : STRING(15);   // ctrlX MOTION axis name
    lrPosition      : LREAL;        // target position
    lrVelocity      : LREAL;        // dynamics, latched when the move is issued
    lrAcceleration  : LREAL;
    lrDeceleration  : LREAL;
END_VAR
VAR_OUTPUT
    bDone           : BOOL;         // move finished (while bExecute)
    bError          : BOOL;         // rejected, aborted or failed (while bExecute)
END_VAR
VAR
    _bIssued        : BOOL;
    _bAccepted      : BOOL;
    _ulCmdID        : ULINT;
    _stCmd          : ML_AxsPosData;
    _fbCmdState     : FB_AxisCmdState;
END_VAR
VAR CONSTANT
    SOURCE_NAME     : STRING(50) := 'FB_MlPosAbs';
    NO_JERK_LIMIT   : LREAL := 0.0;     // jerk 0 on both = no jerk limit (trapezoid)
END_VAR

// ===== Implementation =====
IF bExecute AND NOT _bIssued THEN
    _stCmd.In.AxisName := sAxisName;
    _stCmd.In.Source   := SOURCE_NAME;
    _stCmd.In.Position := lrPosition;
    _stCmd.In.Buffered := TRUE;
    _stCmd.In.DynLimits.Velocity     := lrVelocity;
    _stCmd.In.DynLimits.Acceleration := lrAcceleration;
    _stCmd.In.DynLimits.Deceleration := lrDeceleration;
    _stCmd.In.DynLimits.JerkAcc      := NO_JERK_LIMIT;
    _stCmd.In.DynLimits.JerkDec      := NO_JERK_LIMIT;
    _bAccepted := ML_AxsPosAbs(Data := _stCmd);
    _ulCmdID   := _stCmd.Out.CmdID;
    _bIssued   := TRUE;
ELSIF NOT bExecute THEN
    _bIssued   := FALSE;
    _bAccepted := FALSE;
END_IF

_fbCmdState(bActive := _bIssued, sObjName := sAxisName, ulCmdID := _ulCmdID, bAccepted := _bAccepted);

// Outputs
bDone  := _fbCmdState.bDone;
bError := _fbCmdState.bFailed;
