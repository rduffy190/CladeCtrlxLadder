// FUNCTION_BLOCK: FB_MlReset
// Axis reset with the Execute/Done handshake, for ladder: ML_AxsReset is issued once when
// bExecute is TRUE and again only after bExecute has been FALSE.
// Library: CXA_Motion

// ===== Declaration =====
FUNCTION_BLOCK FB_MlReset
VAR_INPUT
    bExecute    : BOOL;         // issue the reset; hold TRUE, remove to re-arm
    sAxisName   : STRING(15);   // ctrlX MOTION axis name
END_VAR
VAR_OUTPUT
    bDone       : BOOL;         // the reset was accepted (while bExecute)
    bError      : BOOL;         // the reset was not accepted (while bExecute)
END_VAR
VAR
    _bIssued    : BOOL;
    _bAccepted  : BOOL;
    _stCmd      : ML_AxsResetData;
END_VAR
VAR CONSTANT
    SOURCE_NAME : STRING(50) := 'FB_MlReset';
END_VAR

// ===== Implementation =====
IF bExecute AND NOT _bIssued THEN
    _stCmd.In.AxisName := sAxisName;
    _stCmd.In.Source   := SOURCE_NAME;
    _bAccepted := ML_AxsReset(Data := _stCmd);
    _bIssued   := TRUE;
ELSIF NOT bExecute THEN
    _bIssued   := FALSE;
    _bAccepted := FALSE;
END_IF

// Outputs
bDone  := _bIssued AND _bAccepted;
bError := _bIssued AND NOT _bAccepted;
