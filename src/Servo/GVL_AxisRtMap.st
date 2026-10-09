// GVL: GVL_AxisRtMap
// Field table for the cyclic axis status RT node. FB_AxisRtMap looks each map entry
// '<axis>/<field>' up here; the F_* index is where its byte offset is stored in
// ST_AxisRtOffsets.audiOffset, and FB_AxisRtRead copies by the same index.
// Keep F_* and asFieldName in step: asFieldName[F_X] is the map name of field X.
{attribute 'qualified_only'}
VAR_GLOBAL CONSTANT
    NODE_NAME           : STRING(255) := 'motion/realtime/cyclicStatusData';   // RT node
    NAME_SEPARATOR      : STRING(1) := '/';     // map names are '<axis>/<field>'
    BITS_PER_BYTE       : UDINT := 8;           // map offsets are in bits

    F_ACTUAL_POS            : INT := 0;
    F_ACTUAL_VEL            : INT := 1;
    F_ACTUAL_TRQ            : INT := 2;
    F_ACTUAL_TRQ_PERCENT    : INT := 3;
    F_DEVICE_ERROR_CODE     : INT := 4;
    F_PLC_OPEN_STATE        : INT := 5;
    F_DRIVE_STATUS_WORD     : INT := 6;
    F_DATA_VALID            : INT := 7;
    F_HOMED                 : INT := 8;
    F_STANDSTILL            : INT := 9;
    F_POWER_READY           : INT := 10;
    F_POWER_ON              : INT := 11;
    F_HAS_ERROR             : INT := 12;
    F_HAS_WARNING           : INT := 13;
    F_AXIS_FOLLOW_COMMAND   : INT := 14;
    F_IN_POSITION           : INT := 15;
    F_IN_VELOCITY           : INT := 16;
    F_IN_TORQUE             : INT := 17;
    F_IN_SYNCHRONIZATION    : INT := 18;
    F_OVERRIDE_IS_ZERO      : INT := 19;
    F_TORQUE_CTRL_POS_VEL_LIM : INT := 20;
    F_TORQUE_CTRL_NEG_VEL_LIM : INT := 21;
    F_IN_SYNC_WINDOW        : INT := 22;
    LAST_FIELD              : INT := 22;

    asFieldName : ARRAY[0..LAST_FIELD] OF STRING(31) := [
        'ActualPos', 'ActualVel', 'ActualTRQ', 'ActualTRQPercent',
        'DeviceErrorCode', 'PlcOpenState', 'DriveStatusWord',
        'DataValid', 'Homed', 'Standstill', 'PowerReady', 'PowerOn', 'HasError', 'HasWarning',
        'AxisFollowCommand', 'InPosition', 'InVelocity', 'InTorque', 'InSynchronization',
        'OverrideIsZero', 'TorqueCtrlPosVelLim', 'TorqueCtrlNegVelLim', 'InSyncWindow'];
END_VAR
