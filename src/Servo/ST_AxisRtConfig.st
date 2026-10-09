// DUT: ST_AxisRtConfig
// Read configuration for the cyclic axis status RT node, built by FB_AxisRtMap and used by
// FB_AxisRtRead. astAxis is indexed like GVL_Axes (AX1, AX2, VM).
TYPE ST_AxisRtConfig :
STRUCT
    bValid      : BOOL;     // node open and map read: FB_AxisRtRead may read
    udiRevision : UDINT;    // map revision, passed to BeginAccess
    astAxis     : ARRAY[0..GVL_Axes.LAST_AXIS] OF ST_AxisRtOffsets;     // offsets per axis
END_STRUCT
END_TYPE
