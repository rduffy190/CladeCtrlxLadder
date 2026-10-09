// DUT: ST_AxisCyclicStatus
// Cyclic axis status from ctrlX MOTION (Motion App §6.2.7), read by FB_AxisRtRead from the
// Data Layer RT node motion/realtime/cyclicStatusData. Fields are copied one by one using the
// byte offsets FB_AxisRtMap reads from the node's map, so the field order here doesn't matter.
// Field names match the RT map names. ActualSafeMode is in the map but not used.
// Cyclic status must be enabled per axis
// (motion/axs/<name>/cfg/functions/cyclic-status-data/remanent).
TYPE ST_AxisCyclicStatus :
STRUCT
    // Status bits
    DataValid           : BOOL;     // cyclic data is valid
    Homed               : BOOL;     // axis is referenced
    Standstill          : BOOL;     // axis does not move (within standstill window)
    PowerReady          : BOOL;     // drive is ready for power up
    PowerOn             : BOOL;     // axis has power and is actively controlled
    HasError            : BOOL;     // error pending at the axis
    HasWarning          : BOOL;     // warning pending at the axis
    AxisFollowCommand   : BOOL;     // axis follows the control's command values
    InPosition          : BOOL;     // at target position
    InVelocity          : BOOL;     // at target velocity
    InTorque            : BOOL;     // at target torque
    InSyncWindow        : BOOL;     // slave/master command difference within the InSync window
    InSynchronization   : BOOL;     // slave follows its master and has reached the master command value
    OverrideIsZero      : BOOL;     // velocity override is zero
    TorqueCtrlPosVelLim : BOOL;     // torque control, positive velocity limit reached
    TorqueCtrlNegVelLim : BOOL;     // torque control, negative velocity limit reached
    // Actual values
    ActualPos           : LREAL;    // actual position
    ActualVel           : LREAL;    // actual velocity
    ActualTRQ           : LREAL;    // actual torque
    ActualTRQPercent    : LREAL;    // actual torque in % of rated torque (S-0-0533)
    DriveStatusWord     : WORD;     // drive status word (bit 15 power section ready, bit 13 fault)
    DeviceErrorCode     : UDINT;    // drive diagnostic number (16#FFFFFFFF with no drive connected)
    // State machine
    PlcOpenState        : UDINT;    // PLCopen state (values not documented; not used)
END_STRUCT
END_TYPE
