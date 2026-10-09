// GVL: GVL_Axes
// Servo station axes: names as configured in ctrlX MOTION, and their cyclic status
// (read from the Data Layer RT node by FB_AxisRtMap / FB_AxisRtRead in PRG_Main).
{attribute 'qualified_only'}
VAR_GLOBAL CONSTANT
    AX1         : INT := 0;     // real servo, drive 0 (also hosts the drive supply)
    AX2         : INT := 1;     // real servo, drive 1
    VM          : INT := 2;     // virtual master
    LAST_AXIS   : INT := 2;
    asAxisName  : ARRAY[0..LAST_AXIS] OF STRING(15) := ['Ax1', 'Ax2', 'VM'];  // set to the ctrlX MOTION axis names
END_VAR
VAR_GLOBAL
    astStatus   : ARRAY[0..LAST_AXIS] OF ST_AxisCyclicStatus;   // RT cyclic status, indexed AX1 / AX2 / VM, written by PRG_Main.fbAxisRtRead
END_VAR
