// FUNCTION_BLOCK: FB_AxisRtMap
// Opens the cyclic axis status RT node (motion/realtime/cyclicStatusData) and reads its memory
// map into stConfig: for every axis in asAxisName, the byte offset of every field in
// GVL_AxisRtMap, plus the map revision. FB_AxisRtRead then reads every axis in one access,
// using stConfig and the same DL_MemUser.
// stConfig.bValid is TRUE only in Ready. On a fault (open, map, or the reader reporting
// bReadFault) the node is closed, stConfig is cleared, and after RETRY_DELAY the node is
// reopened and the map read again. A changed map (axes reconfigured) therefore recovers by
// itself. uiErrorStep / eResult keep the first cause until bEnable is removed.
// Libraries: CXA_Datalayer (DL_MemUser, DL_NODEVALUE), CXA_AutomationCore_fbs
// (comm_datalayer_MemoryMap, comm_datalayer_Variable)

// ===== Declaration =====
FUNCTION_BLOCK FB_AxisRtMap
VAR_INPUT
    bEnable         : BOOL;     // open the node, read the map and keep stConfig valid
    bReadFault      : BOOL;     // the read failed: close, then reopen and reread the map after RETRY_DELAY
    asAxisName      : ARRAY[0..GVL_Axes.LAST_AXIS] OF STRING(15);    // ctrlX MOTION axis names, indexed like GVL_Axes
END_VAR
VAR_OUTPUT
    bReady          : BOOL;     // stConfig is valid
    bError          : BOOL;     // faulted, retrying every RETRY_DELAY
    bAllAxesFound   : BOOL;     // diag: every axis had every field in the map
    uiErrorStep     : UINT;     // diag: first failure: 1 open, 2 get map, 3 the read failed (0 = none)
    eResult         : DL_RESULT;    // diag: Data Layer result of the first failure
    udiVarCount     : UDINT;    // diag: entries in the map
    udiRevision     : UDINT;    // diag: map revision
END_VAR
VAR_IN_OUT
    fbMem           : DL_MemUser;       // shared with FB_AxisRtRead
    stConfig        : ST_AxisRtConfig;  // read configuration for FB_AxisRtRead
END_VAR
VAR
    _uiStep         : UINT;
    _uiLastStep     : UINT;
    _bOpen          : BOOL;             // OpenMemory was called: CloseMemory is due
    _eOpen          : DL_RESULT := DL_RESULT.DL_OK;
    _eGetMap        : DL_RESULT := DL_RESULT.DL_OK;
    _uiErrorStep    : UINT;
    _eResult        : DL_RESULT := DL_RESULT.DL_OK;
    _stConfig       : ST_AxisRtConfig;
    _stCleared      : ST_AxisRtConfig;  // never written: all FALSE / 0
    _bAllAxesFound  : BOOL;

    // Map parsing
    _fbMapNode      : DL_NODEVALUE;
    _fbMemMap       : comm_datalayer_MemoryMap;
    _fbVar          : comm_datalayer_Variable;
    _udiVarCount    : UDINT;
    _udiVar         : UDINT;
    _sName          : STRING(255);
    _sAxis          : STRING(255);
    _sField         : STRING(255);
    _iSep           : INT;
    _udiBitOffset   : UDINT;
    _iAxis          : INT;
    _iField         : INT;

    _fbRetry        : TON;
END_VAR
VAR CONSTANT
    STEP_IDLE       : UINT := 0;    // node closed, config invalid
    STEP_OPEN       : UINT := 1;    // OpenMemory issued on entry
    STEP_GET_MAP    : UINT := 2;    // map read and parsed on entry
    STEP_READY      : UINT := 3;    // config valid, the reader reads
    STEP_FAULT      : UINT := 4;    // node closed, waiting to retry
    ERROR_NONE      : UINT := 0;
    ERROR_OPEN      : UINT := 1;
    ERROR_GET_MAP   : UINT := 2;
    ERROR_READ      : UINT := 3;
    RETRY_DELAY     : TIME := T#1S; // time in Fault before the node is reopened
END_VAR

// ===== Implementation =====
// ===== 1. Jumps =====
IF _uiStep = STEP_OPEN AND _eOpen <> DL_RESULT.DL_OK THEN
    IF _uiErrorStep = ERROR_NONE THEN
        _uiErrorStep := ERROR_OPEN;
        _eResult     := _eOpen;
    END_IF
    _uiStep := STEP_FAULT;
ELSIF _uiStep = STEP_GET_MAP AND _eGetMap <> DL_RESULT.DL_OK THEN
    IF _uiErrorStep = ERROR_NONE THEN
        _uiErrorStep := ERROR_GET_MAP;
        _eResult     := _eGetMap;
    END_IF
    _uiStep := STEP_FAULT;
ELSIF _uiStep = STEP_READY AND bReadFault THEN
    IF _uiErrorStep = ERROR_NONE THEN
        _uiErrorStep := ERROR_READ;
    END_IF
    _uiStep := STEP_FAULT;
END_IF

// ===== 2. Transitions =====
CASE _uiStep OF
    STEP_IDLE:
        IF bEnable THEN
            _uiStep := STEP_OPEN;
        END_IF

    STEP_OPEN:
        // A failed open has already jumped to Fault
        IF NOT bEnable THEN
            _uiStep := STEP_IDLE;
        ELSE
            _uiStep := STEP_GET_MAP;
        END_IF

    STEP_GET_MAP:
        // A failed map read has already jumped to Fault
        IF NOT bEnable THEN
            _uiStep := STEP_IDLE;
        ELSE
            _uiStep := STEP_READY;
        END_IF

    STEP_READY:
        IF NOT bEnable THEN
            _uiStep := STEP_IDLE;
        END_IF

    STEP_FAULT:
        IF NOT bEnable THEN
            _uiStep := STEP_IDLE;
        ELSIF _fbRetry.Q THEN
            _uiStep := STEP_OPEN;
        END_IF

ELSE
    _uiStep := STEP_FAULT;
END_CASE

// ===== 3. On change =====
IF _uiStep <> _uiLastStep THEN
    // Common: the config is only valid in Ready
    _stConfig.bValid := _uiStep = STEP_READY;

    CASE _uiStep OF
        STEP_IDLE:
            IF _bOpen THEN
                fbMem.CloseMemory();
                _bOpen := FALSE;
            END_IF
            _stConfig    := _stCleared;
            _uiErrorStep := ERROR_NONE;
            _eResult     := DL_RESULT.DL_OK;

        STEP_OPEN:
            _eOpen := fbMem.OpenMemory(GVL_AxisRtMap.NODE_NAME);
            _bOpen := TRUE;     // close even after a failed open, as the Rexroth example does

        STEP_GET_MAP:
            _stConfig := _stCleared;
            _eGetMap  := fbMem.GetMemoryMap(_fbMapNode);
            IF _eGetMap = DL_RESULT.DL_OK THEN
                _fbMemMap.getRootAsMemoryMap(_fbMapNode.GetData(), _fbMapNode.GetSize());
                _udiVarCount := _fbMemMap.getVariablesLength();
                _udiVar := 0;
                // Bounded by the map size: one pass over the entries, in this scan
                WHILE _udiVar < _udiVarCount DO
                    _fbMemMap.getVariables(_udiVar, ADR(_fbVar));
                    _sName := _fbVar.getName();
                    _iSep  := FIND(_sName, GVL_AxisRtMap.NAME_SEPARATOR);
                    IF _iSep > 1 THEN
                        _sAxis        := LEFT(_sName, _iSep - 1);
                        _sField       := MID(_sName, LEN(_sName) - _iSep, _iSep + 1);
                        _udiBitOffset := _fbVar.getBitoffset();
                        FOR _iAxis := 0 TO GVL_Axes.LAST_AXIS DO
                            IF asAxisName[_iAxis] = _sAxis THEN
                                FOR _iField := 0 TO GVL_AxisRtMap.LAST_FIELD DO
                                    IF GVL_AxisRtMap.asFieldName[_iField] = _sField THEN
                                        _stConfig.astAxis[_iAxis].audiOffset[_iField] := _udiBitOffset / GVL_AxisRtMap.BITS_PER_BYTE;
                                        _stConfig.astAxis[_iAxis].abFound[_iField]    := _udiBitOffset MOD GVL_AxisRtMap.BITS_PER_BYTE = 0;
                                    END_IF
                                END_FOR
                            END_IF
                        END_FOR
                    END_IF
                    _udiVar := _udiVar + 1;
                END_WHILE
                _stConfig.udiRevision := _fbMemMap.getRevision();

                // An axis can be read only if every field was found
                _bAllAxesFound := TRUE;
                FOR _iAxis := 0 TO GVL_Axes.LAST_AXIS DO
                    _stConfig.astAxis[_iAxis].bComplete := TRUE;
                    FOR _iField := 0 TO GVL_AxisRtMap.LAST_FIELD DO
                        _stConfig.astAxis[_iAxis].bComplete := _stConfig.astAxis[_iAxis].bComplete
                                                               AND _stConfig.astAxis[_iAxis].abFound[_iField];
                    END_FOR
                    _bAllAxesFound := _bAllAxesFound AND _stConfig.astAxis[_iAxis].bComplete;
                END_FOR
            END_IF

        STEP_FAULT:
            IF _bOpen THEN
                fbMem.CloseMemory();
                _bOpen := FALSE;
            END_IF
            _stConfig := _stCleared;
    END_CASE
    _uiLastStep := _uiStep;
END_IF

// ===== 4. Cyclic =====
_fbRetry(IN := _uiStep = STEP_FAULT, PT := RETRY_DELAY);

// Outputs
stConfig      := _stConfig;
bReady        := _uiStep = STEP_READY;
bError        := _uiErrorStep <> ERROR_NONE AND _uiStep <> STEP_READY;
bAllAxesFound := _bAllAxesFound;
uiErrorStep   := _uiErrorStep;
eResult       := _eResult;
udiVarCount   := _udiVarCount;
udiRevision   := _stConfig.udiRevision;
