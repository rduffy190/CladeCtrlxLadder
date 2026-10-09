// FUNCTION_BLOCK: FB_MlGearIn
// Gear-in with the Execute handshake, for ladder: ML_AxsGearInPos2 is issued once when
// bExecute is TRUE, tracked by its CmdID, and re-armed when bExecute is removed. Removing
// bExecute doesn't end the gearing; a later command on the slave does.
// Gearing is absolute to the master's set point, 1:1, with the slave offset applied by the
// gearing, and synchronises the shortest way (servo design §4).
// Library: CXA_Motion

// ===== Declaration =====
FUNCTION_BLOCK FB_MlGearIn
VAR_INPUT
    bExecute        : BOOL;         // issue the gear-in; remove to re-arm
    sAxisName       : STRING(15);   // slave axis name
    sMasterName     : STRING(15);   // master axis name
    lrSlaveOffset   : LREAL;        // slave phase offset, latched when the command is issued
END_VAR
VAR_OUTPUT
    bError          : BOOL;         // rejected, aborted or failed (while bExecute)
END_VAR
VAR
    _bIssued        : BOOL;
    _bAccepted      : BOOL;
    _ulCmdID        : ULINT;
    _stCmd          : ML_AxsGearInPos2Data;
    _fbCmdState     : FB_AxisCmdState;
END_VAR
VAR CONSTANT
    SOURCE_NAME       : STRING(50) := 'FB_MlGearIn';
    GEAR_RATIO        : DINT := 1;      // 1:1
    MASTER_OFFSET     : LREAL := 0.0;
    MASTER_SYNC_POS   : LREAL := 0.0;
    MASTER_START_DIST : LREAL := 0.0;
    FINE_ADJUST       : LREAL := 0.0;
END_VAR

// ===== Implementation =====
IF bExecute AND NOT _bIssued THEN
    _stCmd.In.AxisName            := sAxisName;
    _stCmd.In.Source              := SOURCE_NAME;
    _stCmd.In.MasterName          := sMasterName;
    _stCmd.In.SyncSource          := ML_SyncSource.SYNC_SETPOINT;
    _stCmd.In.SyncMode            := ML_SyncMode.SYNC_ABSOLUTE;
    _stCmd.In.DynSyncDirection    := ML_DynSyncDirection.SHORTEST_WAY;
    _stCmd.In.MasterSyncPosition  := MASTER_SYNC_POS;
    _stCmd.In.MasterStartDistance := MASTER_START_DIST;
    _stCmd.In.Parameters.MasterOffset     := MASTER_OFFSET;
    _stCmd.In.Parameters.SlaveOffset      := lrSlaveOffset;
    _stCmd.In.Parameters.RatioNumerator   := GEAR_RATIO;
    _stCmd.In.Parameters.RatioDenominator := GEAR_RATIO;
    _stCmd.In.Parameters.FineAdjust       := FINE_ADJUST;
    _stCmd.In.Buffered            := TRUE;
    _bAccepted := ML_AxsGearInPos2(Data := _stCmd);
    _ulCmdID   := _stCmd.Out.CmdID;
    _bIssued   := TRUE;
ELSIF NOT bExecute THEN
    _bIssued   := FALSE;
    _bAccepted := FALSE;
END_IF

_fbCmdState(bActive := _bIssued, sObjName := sAxisName, ulCmdID := _ulCmdID, bAccepted := _bAccepted);

// Outputs
bError := _fbCmdState.bFailed;
