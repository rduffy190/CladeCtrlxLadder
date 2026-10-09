// FUNCTION_BLOCK: FB_MlPower
// Axis power as a level for ladder: issues ML_AxsPower once each time bSwitchOn changes.
// ML_ commands are one-shot functions, so this block remembers the level it last sent.
// Library: CXA_Motion

// ===== Declaration =====
FUNCTION_BLOCK FB_MlPower
VAR_INPUT
    sAxisName   : STRING(15);   // ctrlX MOTION axis name
    bSwitchOn   : BOOL;         // wanted power level
END_VAR
VAR_OUTPUT
    bError      : BOOL;         // the last power command was not accepted; cleared by the next accepted one
END_VAR
VAR
    _bSent      : BOOL;         // power level last commanded
    _bRejected  : BOOL;
    _stCmd      : ML_AxsPowerData;
END_VAR
VAR CONSTANT
    SOURCE_NAME : STRING(50) := 'FB_MlPower';
END_VAR

// ===== Implementation =====
IF bSwitchOn <> _bSent THEN
    _stCmd.In.AxisName := sAxisName;
    _stCmd.In.Source   := SOURCE_NAME;
    _stCmd.In.SwitchOn := bSwitchOn;
    _bRejected := NOT ML_AxsPower(Data := _stCmd);
    _bSent     := bSwitchOn;
END_IF

// Outputs
bError := _bRejected;
