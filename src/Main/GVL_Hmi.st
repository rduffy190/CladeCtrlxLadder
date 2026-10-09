// GVL: GVL_Hmi
// Operator commands from the HMI. All levels: hold TRUE to request.
{attribute 'qualified_only'}
VAR_GLOBAL
    bOnCmd      : BOOL;     // machine on
    bOffCmd     : BOOL;     // machine off
    bStartCmd   : BOOL;     // start production
    bStopCmd    : BOOL;     // controlled stop
    bHoldCmd    : BOOL;     // hold while TRUE
    bAbortCmd   : BOOL;     // operator abort
    bResetCmd   : BOOL;     // reset after abort

    // Servo station
    lrSpeedCmd      : LREAL;    // VM line speed (units/s); limit it here, the unit doesn't clamp
    lrSlaveOffset   : LREAL;    // phase offset: Ax1 at +offset, Ax2 at 360 - offset
END_VAR
