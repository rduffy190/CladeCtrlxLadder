// GVL: GVL_IO
// Hardware signals. Map these in the device tree I/O mapping (EtherCAT SoE cyclic data).
{attribute 'qualified_only'}
VAR_GLOBAL CONSTANT
    NUM_DRIVES              : DINT := 2;    // drives in use on the supply (the spare drive 2 is not counted)
    DRIVE_AX1               : DINT := 0;    // drive 0: Ax1, also hosts the supply unit
    DRIVE_AX2               : DINT := 1;    // drive 1: Ax2
END_VAR
VAR_GLOBAL
    // Supply unit (drive-integrated)
    wDI_SupplyStatus        : WORD;                             // AT: S-0-2058 (S-0-1720.0.2) supply unit status word
    wDO_SupplyCtrl          : WORD;                             // MDT: S-0-2057 (S-0-1720.0.1) supply unit control word

    // Drives
    awDI_DriveStatus        : ARRAY[0..NUM_DRIVES - 1] OF WORD;     // AT: drive status word (bits 15/14 readiness, bit 13 fault)
    awDO_DriveDcBusCtrl     : ARRAY[0..NUM_DRIVES - 1] OF WORD;     // MDT: S-0-0240 DC bus power control

    // Drive 2: spare, not used yet. Not part of supply readiness, torque or fault checks.
    wDI_SpareDriveStatus    : WORD;                             // AT: drive 2 status word

    // Fault reset: drive 0 hosts the supply, so the servo axes' reset in Resetting also resets the supply
END_VAR
