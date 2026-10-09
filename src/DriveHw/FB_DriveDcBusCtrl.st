// FUNCTION_BLOCK: FB_DriveDcBusCtrl
// Sets or clears "DC bus power" (S-0-0240 bit 0) in the control word of every drive on the
// supply. Kept in ST because it loops over the drive array. The other bits are left alone.
// Design: design/Unit_DriveHardwareStation_Design.md §7

// ===== Declaration =====
FUNCTION_BLOCK FB_DriveDcBusCtrl
VAR_INPUT
    bDcBusPower         : BOOL;     // DC bus power to every drive (while the supply is in operation)
END_VAR
VAR_IN_OUT
    awDriveDcBusCtrl    : ARRAY[*] OF WORD; // drive DC bus power control S-0-0240, one per drive
END_VAR
VAR
    _iDrive             : DINT;
END_VAR
VAR CONSTANT
    MASK_DC_BUS_POWER   : WORD := 16#0001;  // S-0-0240 bit 0: DC bus power enabled
END_VAR

// ===== Implementation =====
FOR _iDrive := LOWER_BOUND(awDriveDcBusCtrl, 1) TO UPPER_BOUND(awDriveDcBusCtrl, 1) DO
    IF bDcBusPower THEN
        awDriveDcBusCtrl[_iDrive] := awDriveDcBusCtrl[_iDrive] OR MASK_DC_BUS_POWER;
    ELSE
        awDriveDcBusCtrl[_iDrive] := awDriveDcBusCtrl[_iDrive] AND NOT MASK_DC_BUS_POWER;
    END_IF
END_FOR
