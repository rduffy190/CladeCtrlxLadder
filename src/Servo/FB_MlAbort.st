// FUNCTION_BLOCK: FB_MlAbort
// Stop an axis (ML_AxsAbort) with the Execute/Done handshake, for ladder: issued once when
// bExecute is TRUE, tracked by its CmdID, and re-armed when bExecute is removed. Ends any
// gearing on the axis. Used for halt (normal deceleration) and abort (abort deceleration).
// Library: CXA_Motion

// ===== Declaration =====
FUNCTION_BLOCK FB_MlAbort
VAR_INPUT
    bExecute        : BOOL;         // issue the stop; hold TRUE until Done/Error, remove to re-arm
    sAxisName       : STRING(15);   // ctrlX MOTION axis name
    lrDeceleration  : LREAL;        // latched when the stop is issued
END_VAR
VAR_OUTPUT
    bDone           : BOOL;         // axis stopped (while bExecute)
    bError          : BOOL;         // rejected, aborted or failed (while bExecute)
END_VAR
VAR
    _bIssued        : BOOL;
    _bAccepted      : BOOL;
    _ulCmdID        : ULINT;
    _stCmd          : ML_AxsAbortData;
    _fbCmdState     : FB_AxisCmdState;
END_VAR
VAR CONSTANT
    SOURCE_NAME     : STRING(50) := 'FB_MlAbort';
    NO_JERK_LIMIT   : LREAL := 0.0;
END_VAR

// ===== Implementation =====
IF bExecute AND NOT _bIssued THEN
    _stCmd.In.AxisName     := sAxisName;
    _stCmd.In.Source       := SOURCE_NAME;
    _stCmd.In.Deceleration := lrDeceleration;
    _stCmd.In.JerkDec      := NO_JERK_LIMIT;
    _bAccepted := ML_AxsAbort(Data := _stCmd);
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
