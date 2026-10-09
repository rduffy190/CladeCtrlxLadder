// DUT: E_ServoSeqState
// Internal sequence of FB_ServoMotionSeq (exposed as an output, hence an enum).
{attribute 'qualified_only'}
{attribute 'strict'}
TYPE E_ServoSeqState :
(
    Idle := 0,      // all at standstill, ungeared
    Positioning,    // Ax1 -> offset 1, Ax2 -> offset 2, VM -> 0
    GearingIn,      // Ax1, Ax2 gear in to VM, absolute to set point, 1:1
    Synced,         // geared, VM at standstill
    VmRunning,      // VM velocity at speed command
    VmSpeedChange,  // one scan: re-enter VmRunning to apply a new speed
    VmHalting,      // VM decelerates to standstill
    Ungearing,      // slaves halted, gearing ended
    AbortVm,        // VM stopped at abort deceleration
    AbortSlaves     // slaves stopped at abort deceleration, gearing ended
);
END_TYPE
