// FUNCTION: Fn_RtCopy
// Copies one field out of a Data Layer RT buffer, a byte at a time because the buffer is
// packed (LREALs are not aligned). Returns FALSE and copies nothing if a pointer is null or
// the field doesn't lie inside the buffer.

// ===== Declaration =====
FUNCTION Fn_RtCopy : BOOL
VAR_INPUT
    pData       : POINTER TO BYTE;  // start of the RT buffer (from BeginAccess)
    udiDataSize : UDINT;            // buffer size in bytes (from GetSize)
    udiOffset   : UDINT;            // byte offset of the field in the buffer
    pDst        : POINTER TO BYTE;  // destination, e.g. ADR(stX.ActualPos)
    udiSize     : UDINT;            // field size in bytes, e.g. SIZEOF(stX.ActualPos)
END_VAR
VAR
    _pSrc       : POINTER TO BYTE;
    _pDst       : POINTER TO BYTE;
    _udiByte    : UDINT;
END_VAR

// ===== Implementation =====
Fn_RtCopy := pData <> 0 AND pDst <> 0 AND udiOffset + udiSize <= udiDataSize;
IF Fn_RtCopy THEN
    _pSrc := pData + udiOffset;
    _pDst := pDst;
    FOR _udiByte := 1 TO udiSize DO
        _pDst^ := _pSrc^;
        _pSrc := _pSrc + 1;
        _pDst := _pDst + 1;
    END_FOR
END_IF
