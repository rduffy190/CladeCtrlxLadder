// DUT: ST_AxisRtOffsets
// Where one axis's cyclic status fields are in the RT buffer, filled by FB_AxisRtMap from the
// node's memory map. Indexed by GVL_AxisRtMap.F_*.
TYPE ST_AxisRtOffsets :
STRUCT
    bComplete   : BOOL;     // every field was found in the map: the axis can be read
    audiOffset  : ARRAY[0..GVL_AxisRtMap.LAST_FIELD] OF UDINT;  // byte offset of each field in the buffer
    abFound     : ARRAY[0..GVL_AxisRtMap.LAST_FIELD] OF BOOL;   // diag: field found on a byte boundary
END_STRUCT
END_TYPE
