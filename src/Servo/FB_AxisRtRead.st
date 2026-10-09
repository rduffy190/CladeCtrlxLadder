// FUNCTION_BLOCK: FB_AxisRtRead
// Reads the cyclic status of every axis from the RT node motion/realtime/cyclicStatusData into
// astStatus, using the offsets in stConfig (built by FB_AxisRtMap). Call one instance every
// scan, after FB_AxisRtMap and with the same DL_MemUser.
// One BeginAccess/EndAccess per scan for all axes: the buffer is locked once, and every axis
// comes from the same buffer snapshot. Axes that aren't complete in the map are skipped.
// An axis without a good read is cleared, so its DataValid is FALSE.
// bError (access failed or a field outside the buffer: the map has probably changed) goes to
// FB_AxisRtMap.bReadFault, which reopens the node and rereads the map.
// Library: CXA_Datalayer (DL_MemUser)

// ===== Declaration =====
FUNCTION_BLOCK FB_AxisRtRead
VAR_OUTPUT
    bValid          : BOOL;         // the buffer was read this scan and every axis found in the map was copied
    bError          : BOOL;         // the read failed although the config is valid: feed to FB_AxisRtMap.bReadFault
    abValid         : ARRAY[0..GVL_Axes.LAST_AXIS] OF BOOL;    // diag: axis read this scan
    abNotInMap      : ARRAY[0..GVL_Axes.LAST_AXIS] OF BOOL;    // diag: axis or some of its fields not in the map (cyclic status enabled? name right?)
    eResult         : DL_RESULT;    // diag: result of this scan's read
END_VAR
VAR_IN_OUT
    fbMem           : DL_MemUser;   // the DL_MemUser opened by FB_AxisRtMap
    astStatus       : ARRAY[0..GVL_Axes.LAST_AXIS] OF ST_AxisCyclicStatus;     // cyclic status per axis, indexed like GVL_Axes
END_VAR
VAR_IN_OUT CONSTANT
    stConfig        : ST_AxisRtConfig;  // from FB_AxisRtMap
END_VAR
VAR
    _bValid         : BOOL;
    _bError         : BOOL;
    _abValid        : ARRAY[0..GVL_Axes.LAST_AXIS] OF BOOL;
    _abNotInMap     : ARRAY[0..GVL_Axes.LAST_AXIS] OF BOOL;
    _bCopyOk        : BOOL;
    _eResult        : DL_RESULT := DL_RESULT.DL_OK;
    _iAxis          : INT;
    _stOfs          : ST_AxisRtOffsets;     // offsets of the axis being copied
    _pData          : POINTER TO BYTE;      // start of the RT buffer, only valid between Begin/EndAccess
    _udiSize        : UDINT;
    _stStatus       : ST_AxisCyclicStatus;  // the axis being copied
    _astStatus      : ARRAY[0..GVL_Axes.LAST_AXIS] OF ST_AxisCyclicStatus;
    _stCleared      : ST_AxisCyclicStatus;  // never written: all FALSE / 0
END_VAR

// ===== Implementation =====
// Start from "nothing read": every axis cleared, so DataValid is FALSE unless copied below
_bValid  := FALSE;
_bError  := FALSE;
_eResult := DL_RESULT.DL_OK;
FOR _iAxis := 0 TO GVL_Axes.LAST_AXIS DO
    _astStatus[_iAxis]  := _stCleared;
    _abValid[_iAxis]    := FALSE;
    _abNotInMap[_iAxis] := stConfig.bValid AND NOT stConfig.astAxis[_iAxis].bComplete;
END_FOR

IF stConfig.bValid THEN
    // BeginAccess locks the buffer against other users, so EndAccess always follows,
    // with only the copy in between.
    _eResult := fbMem.BeginAccess(Data => _pData, Revision := stConfig.udiRevision);
    IF _eResult = DL_RESULT.DL_OK THEN
        fbMem.GetSize(SizeBytes => _udiSize);
        _bValid := TRUE;
        FOR _iAxis := 0 TO GVL_Axes.LAST_AXIS DO
            IF stConfig.astAxis[_iAxis].bComplete THEN
                _stOfs := stConfig.astAxis[_iAxis];
                // Every field is copied; any copy outside the buffer fails this axis and the read
                _bCopyOk := TRUE;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_DATA_VALID],              pDst := ADR(_stStatus.DataValid),           udiSize := SIZEOF(_stStatus.DataValid)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_HOMED],                   pDst := ADR(_stStatus.Homed),               udiSize := SIZEOF(_stStatus.Homed)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_STANDSTILL],              pDst := ADR(_stStatus.Standstill),          udiSize := SIZEOF(_stStatus.Standstill)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_POWER_READY],             pDst := ADR(_stStatus.PowerReady),          udiSize := SIZEOF(_stStatus.PowerReady)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_POWER_ON],                pDst := ADR(_stStatus.PowerOn),             udiSize := SIZEOF(_stStatus.PowerOn)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_HAS_ERROR],               pDst := ADR(_stStatus.HasError),            udiSize := SIZEOF(_stStatus.HasError)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_HAS_WARNING],             pDst := ADR(_stStatus.HasWarning),          udiSize := SIZEOF(_stStatus.HasWarning)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_AXIS_FOLLOW_COMMAND],     pDst := ADR(_stStatus.AxisFollowCommand),   udiSize := SIZEOF(_stStatus.AxisFollowCommand)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_IN_POSITION],             pDst := ADR(_stStatus.InPosition),          udiSize := SIZEOF(_stStatus.InPosition)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_IN_VELOCITY],             pDst := ADR(_stStatus.InVelocity),          udiSize := SIZEOF(_stStatus.InVelocity)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_IN_TORQUE],               pDst := ADR(_stStatus.InTorque),            udiSize := SIZEOF(_stStatus.InTorque)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_IN_SYNC_WINDOW],          pDst := ADR(_stStatus.InSyncWindow),        udiSize := SIZEOF(_stStatus.InSyncWindow)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_IN_SYNCHRONIZATION],      pDst := ADR(_stStatus.InSynchronization),   udiSize := SIZEOF(_stStatus.InSynchronization)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_OVERRIDE_IS_ZERO],        pDst := ADR(_stStatus.OverrideIsZero),      udiSize := SIZEOF(_stStatus.OverrideIsZero)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_TORQUE_CTRL_POS_VEL_LIM], pDst := ADR(_stStatus.TorqueCtrlPosVelLim), udiSize := SIZEOF(_stStatus.TorqueCtrlPosVelLim)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_TORQUE_CTRL_NEG_VEL_LIM], pDst := ADR(_stStatus.TorqueCtrlNegVelLim), udiSize := SIZEOF(_stStatus.TorqueCtrlNegVelLim)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_ACTUAL_POS],              pDst := ADR(_stStatus.ActualPos),           udiSize := SIZEOF(_stStatus.ActualPos)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_ACTUAL_VEL],              pDst := ADR(_stStatus.ActualVel),           udiSize := SIZEOF(_stStatus.ActualVel)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_ACTUAL_TRQ],              pDst := ADR(_stStatus.ActualTRQ),           udiSize := SIZEOF(_stStatus.ActualTRQ)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_ACTUAL_TRQ_PERCENT],      pDst := ADR(_stStatus.ActualTRQPercent),    udiSize := SIZEOF(_stStatus.ActualTRQPercent)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_DRIVE_STATUS_WORD],       pDst := ADR(_stStatus.DriveStatusWord),     udiSize := SIZEOF(_stStatus.DriveStatusWord)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_DEVICE_ERROR_CODE],       pDst := ADR(_stStatus.DeviceErrorCode),     udiSize := SIZEOF(_stStatus.DeviceErrorCode)) AND _bCopyOk;
                _bCopyOk := Fn_RtCopy(pData := _pData, udiDataSize := _udiSize, udiOffset := _stOfs.audiOffset[GVL_AxisRtMap.F_PLC_OPEN_STATE],          pDst := ADR(_stStatus.PlcOpenState),        udiSize := SIZEOF(_stStatus.PlcOpenState)) AND _bCopyOk;
                IF _bCopyOk THEN
                    _astStatus[_iAxis] := _stStatus;
                    _abValid[_iAxis]   := TRUE;
                ELSE
                    _bValid  := FALSE;
                    _eResult := DL_RESULT.DL_SIZE_MISMATCH;     // a field lies outside the buffer
                END_IF
            END_IF
        END_FOR
    END_IF
    fbMem.EndAccess();
    _bError := NOT _bValid;
END_IF

// Outputs
astStatus  := _astStatus;
bValid     := _bValid;
bError     := _bError;
abValid    := _abValid;
abNotInMap := _abNotInMap;
eResult    := _eResult;
