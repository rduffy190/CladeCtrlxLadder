// FUNCTION_BLOCK: FB_AxisCmdState
// Tracks one issued ML_ motion command by its CmdID using ML_GetCmdState.
// ML_ commands are one-shot functions: they are issued once (on state entry) and this block
// follows the command afterwards. Call it every scan.
// Library: CXA_Motion

// ===== Declaration =====
FUNCTION_BLOCK FB_AxisCmdState
VAR_INPUT
    bActive     : BOOL;         // a command is being tracked for this axis
    sObjName    : STRING(15);   // axis name
    ulCmdID     : ULINT;        // CmdID returned when the command was issued
    bAccepted   : BOOL;         // the ML_ call returned TRUE (command added to the axis)
END_VAR
VAR_OUTPUT
    bDone       : BOOL;         // command state DONE
    bFailed     : BOOL;         // rejected, aborted by another command, or state query error
    sState      : STRING(50);   // diag: command state as reported
END_VAR
VAR
    _stQuery    : ML_GetCmdStateData;
    _bQueryOk   : BOOL;
    _bDone      : BOOL;
    _bFailed    : BOOL;
END_VAR
VAR CONSTANT
    CMD_DONE    : STRING(50) := 'DONE';
    CMD_ABORTED : STRING(50) := 'ABORTED';
END_VAR

// ===== Implementation =====
IF bActive AND bAccepted THEN
    _stQuery.In.ObjName := sObjName;
    _stQuery.In.CmdID   := ulCmdID;
    _bQueryOk := ML_GetCmdState(Data := _stQuery);
    _bDone    := _bQueryOk AND NOT _stQuery.Out.Error AND _stQuery.Out.State = CMD_DONE;
    _bFailed  := NOT _bQueryOk OR _stQuery.Out.Error OR _stQuery.Out.State = CMD_ABORTED;
ELSE
    // Inactive: nothing to report. Active but rejected: failed straight away.
    _stQuery.Out.State := '';
    _bDone   := FALSE;
    _bFailed := bActive AND NOT bAccepted;
END_IF

// Outputs
bDone   := _bDone;
bFailed := _bFailed;
sState  := _stQuery.Out.State;
