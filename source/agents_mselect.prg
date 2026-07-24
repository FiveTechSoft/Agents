// agents_mselect.prg -- Mouse text selection in the transcript viewport.
//
// Click-and-drag highlights text with reverse video.
// Only selected rows are repainted; non-selected rows untouched.
// Strategy: INSERT ESC[7m (reverse video) into the original ANSI line
// at the exact byte positions. This inverts whatever colors are there,
// making the selection visible regardless of original foreground/background.
// Single FWrite per paint for flicker-free operation.

#include "inkey.ch"

// --- state ---
STATIC s_lActive    := .F.
STATIC s_nAnchorRow := 0
STATIC s_nAnchorCol := 1
STATIC s_nCurRow    := 0
STATIC s_nCurCol    := 1

// ---------------------------------------------------------------------------
FUNCTION AGMSEL_OnButton( nType, nRow, nCol )
   LOCAL oPrompt, hReg
   LOCAL nTop, nBot, nCols, nViewport

   oPrompt := AGREPL_BoxPrompt()
   IF oPrompt == NIL .OR. !hb_HHasKey( oPrompt, "region" ) .OR. ;
      ValType( oPrompt[ "region" ] ) != "H"
      RETURN NIL
   ENDIF
   hReg := oPrompt[ "region" ]
   nTop  := hb_HGetDef( hReg, "scroll_top", 1 )
   nBot  := hb_HGetDef( hReg, "scroll_bottom", 1 )
   nCols := hb_HGetDef( hReg, "cols", 80 )
   IF nBot <= nTop
      RETURN NIL
   ENDIF
   nViewport := nBot - nTop + 1

   // --- button DOWN -> start selection ---
   IF nType == 1
      IF nRow >= nTop .AND. nRow <= nBot
         s_lActive    := .T.
         s_nAnchorRow := nRow
         s_nAnchorCol := Max( 1, nCol )
         s_nCurRow    := nRow
         s_nCurCol    := Max( 1, nCol )
         _MSEL_Paint( oPrompt, nTop, nBot, nCols, nViewport )
      ENDIF
      RETURN NIL
   ENDIF

   // --- drag -> extend selection ---
   IF nType == 3 .AND. s_lActive
      IF nRow >= nTop .AND. nRow <= nBot
         nCol := Max( 1, nCol )
         IF ( nRow != s_nCurRow ) .OR. ( nCol != s_nCurCol )
            s_nCurRow := nRow
            s_nCurCol := nCol
            _MSEL_Paint( oPrompt, nTop, nBot, nCols, nViewport )
         ENDIF
      ENDIF
      RETURN NIL
   ENDIF

   // --- button UP -> finish selection, copy to clipboard ---
   IF nType == 2 .AND. s_lActive
      IF nRow >= nTop .AND. nRow <= nBot
         s_nCurRow := nRow
         s_nCurCol := Max( 1, nCol )
      ENDIF

      _MSEL_CopySelection( oPrompt, nTop, nBot, nCols, nViewport )

      // Clean repaint
      _MSEL_PaintClean( oPrompt, nTop, nBot, nCols, nViewport )
      s_lActive    := .F.
      s_nAnchorRow := 0
      s_nAnchorCol := 1
      s_nCurRow    := 0
      s_nCurCol    := 1
      RETURN NIL
   ENDIF

   RETURN NIL

// ---------------------------------------------------------------------------
// _MSEL_CopySelection -- extract selected text and copy to clipboard.
// ---------------------------------------------------------------------------
STATIC FUNCTION _MSEL_CopySelection( oPrompt, nTop, nBot, nCols, nViewport )
   LOCAL nTotal, nStart, nEnd
   LOCAL nRowTop, nRowBot, i, nBuf, cLine, cText, nLines

   nTotal := AGSB_Count()
   IF nTotal == 0 ; RETURN NIL ; ENDIF
   nEnd   := nTotal - AGSB_ScrollOffset()
   nStart := nEnd - nViewport + 1
   IF nStart < 1 ; nStart := 1 ; ENDIF
   IF nEnd > nTotal ; nEnd := nTotal ; ENDIF

   nRowTop := Min( s_nAnchorRow, s_nCurRow )
   nRowBot := Max( s_nAnchorRow, s_nCurRow )
   IF nRowTop < nTop ; nRowTop := nTop ; ENDIF
   IF nRowBot > nBot ; nRowBot := nBot ; ENDIF

   cText := ""
   nLines := 0
   FOR i := nRowTop TO nRowBot
      nBuf := nStart + ( i - nTop )
      IF nBuf >= 1 .AND. nBuf <= nTotal
         cLine := _MSEL_StripAnsi( AGSB_GetLine( nBuf ) )
         cLine := _MSEL_ClipLine( cLine, i, nRowTop, nRowBot )
         IF !Empty( cLine )
            IF nLines > 0
               cText += Chr(13) + Chr(10)
            ENDIF
            cText += cLine
            nLines++
         ENDIF
      ENDIF
   NEXT
   IF !Empty( cText )
      _MSEL_SetClipboard( cText )
   ENDIF
   RETURN NIL

// ---------------------------------------------------------------------------
STATIC FUNCTION _MSEL_ClipLine( cLine, nRow, nRowTop, nRowBot )
   LOCAL nFrom, nTo

   IF nRowTop == nRowBot
      nFrom := Min( s_nAnchorCol, s_nCurCol )
      nTo   := Max( s_nAnchorCol, s_nCurCol )
   ELSEIF nRow == nRowTop
      nFrom := Min( s_nAnchorCol, s_nCurCol )
      nTo   := Len( cLine )
   ELSEIF nRow == nRowBot
      nFrom := 1
      nTo   := Max( s_nAnchorCol, s_nCurCol )
   ELSE
      RETURN RTrim( cLine )
   ENDIF

   IF nFrom < 1 ; nFrom := 1 ; ENDIF
   IF nTo > Len( cLine ) ; nTo := Len( cLine ) ; ENDIF
   IF nTo < nFrom
      RETURN ""
   ENDIF
   RETURN RTrim( SubStr( cLine, nFrom, nTo - nFrom + 1 ) )

// ---------------------------------------------------------------------------
// _MSEL_Paint -- repaint only the selected rows with highlight overlay.
//
// For each selected row, we INSERT two ANSI escape codes into the
// original ring buffer line:
//   ESC[7m   before the first selected character (reverse video on)
//   ESC[27m  after the last selected character  (reverse video off)
//
// Reverse video inverts fg/bg, so the selection is visible regardless
// of the original color scheme. Non-selected rows are NOT touched.
// ---------------------------------------------------------------------------
STATIC FUNCTION _MSEL_Paint( oPrompt, nTop, nBot, nCols, nViewport )
   LOCAL nTotal, nStart, nEnd
   LOCAL nRowTop, nRowBot, nRow, cOut, nBuf
   LOCAL nFrom, nTo, cOrig, aMap, nByteFrom, nByteTo

   nTotal := AGSB_Count()
   IF nTotal == 0 ; RETURN NIL ; ENDIF
   nEnd   := nTotal - AGSB_ScrollOffset()
   nStart := nEnd - nViewport + 1
   IF nStart < 1 ; nStart := 1 ; ENDIF
   IF nEnd > nTotal ; nEnd := nTotal ; ENDIF

   nRowTop := Min( s_nAnchorRow, s_nCurRow )
   nRowBot := Max( s_nAnchorRow, s_nCurRow )
   IF nRowTop < nTop ; nRowTop := nTop ; ENDIF
   IF nRowBot > nBot ; nRowBot := nBot ; ENDIF

   cOut := ""
   FOR nRow := nRowTop TO nRowBot
      nBuf := nStart + ( nRow - nTop )
      IF nBuf >= 1 .AND. nBuf <= nTotal
         cOrig := AGSB_GetLine( nBuf )
         IF Empty( cOrig )
            LOOP
         ENDIF

         // Determine highlight column range for this row (1-based visual cols)
         IF nRowTop == nRowBot
            nFrom := Min( s_nAnchorCol, s_nCurCol )
            nTo   := Max( s_nAnchorCol, s_nCurCol )
         ELSEIF nRow == nRowTop
            nFrom := Min( s_nAnchorCol, s_nCurCol )
            nTo   := nCols
         ELSEIF nRow == nRowBot
            nFrom := 1
            nTo   := Max( s_nAnchorCol, s_nCurCol )
         ELSE
            nFrom := 1
            nTo   := nCols
         ENDIF

         IF nFrom < 1 ; nFrom := 1 ; ENDIF

         // Map visual columns to byte positions in the original ANSI line
         aMap := _MSEL_MapColumns( cOrig )

         // Clamp nTo to actual line width
         IF Len( aMap ) > 0
            IF nTo > Len( aMap )
               nTo := Len( aMap )
            ENDIF
         ELSE
            cOut += Chr(27) + "[" + LTrim( Str( nRow ) ) + ";1H" + ;
                    Chr(27) + "[2K" + cOrig
            LOOP
         ENDIF

         IF nTo < nFrom
            cOut += Chr(27) + "[" + LTrim( Str( nRow ) ) + ";1H" + ;
                    Chr(27) + "[2K" + cOrig
            LOOP
         ENDIF

         // Byte positions in the original string
         nByteFrom := aMap[ nFrom ]
         nByteTo   := aMap[ nTo ]

         // Position cursor, clear line, insert reverse-video markers
         cOut += Chr(27) + "[" + LTrim( Str( nRow ) ) + ";1H" + Chr(27) + "[2K"
         cOut += Left( cOrig, nByteFrom - 1 )
         cOut += Chr(27) + "[7m"
         cOut += SubStr( cOrig, nByteFrom, nByteTo - nByteFrom + 1 )
         cOut += Chr(27) + "[27m"
         cOut += SubStr( cOrig, nByteTo + 1 )
      ENDIF
   NEXT
   FWrite( hb_GetStdOut(), cOut )
   RETURN NIL

// ---------------------------------------------------------------------------
// _MSEL_MapColumns -- parse an ANSI string and return an array mapping
// 1-based visual column -> 1-based byte position in the original string.
// All escape sequences (CSI and non-CSI) are skipped.
// ---------------------------------------------------------------------------
STATIC FUNCTION _MSEL_MapColumns( cText )
   LOCAL aMap := {}, i, cCh, nVis := 0
   LOCAL nState := 0   // 0=normal, 1=ESC seen, 2=CSI param, 3=OSC param
   IF ValType( cText ) != "C" .OR. Empty( cText )
      RETURN aMap
   ENDIF
   FOR i := 1 TO Len( cText )
      cCh := SubStr( cText, i, 1 )
      DO CASE
      CASE nState == 0
         IF Asc( cCh ) == 27
            nState := 1        // ESC seen, wait for type char
         ELSE
            nVis++
            IF nVis <= 200
               AAdd( aMap, i )
            ENDIF
         ENDIF
      CASE nState == 1
         // Character after ESC determines the sequence type
         IF cCh == "["
            nState := 2        // CSI: ESC[ ... final_byte
         ELSEIF cCh == "]"
            nState := 3        // OSC: ESC] ... ST or BEL
         ELSE
            nState := 0        // Two-byte sequence (ESC X), back to normal
         ENDIF
      CASE nState == 2
         // CSI: consume until final byte (0x40-0x7E)
         IF Asc( cCh ) >= 64 .AND. Asc( cCh ) <= 126
            nState := 0
         ENDIF
      CASE nState == 3
         // OSC: consume until ST (ESC\) or BEL (0x07)
         IF Asc( cCh ) == 7        // BEL
            nState := 0
         ELSEIF Asc( cCh ) == 27   // ESC -- might be start of ST
            // Check if next byte is '\' (but we can't peek, so mark ESC)
            // We'll handle ESC\ in state 4
            nState := 4
         ENDIF
      CASE nState == 4
         // After ESC inside OSC: if '\', end OSC; otherwise restart
         IF cCh == "\"
            nState := 0        // ST found: ESC\
         ELSE
            // ESC followed by something else inside OSC -- treat as new ESC
            IF Asc( cCh ) == 27
               nState := 1
            ELSEIF cCh == "["
               nState := 2
            ELSEIF cCh == "]"
               nState := 3
            ELSE
               nState := 0
            ENDIF
         ENDIF
      ENDCASE
   NEXT
   RETURN aMap

// ---------------------------------------------------------------------------
// _MSEL_PaintClean -- full repaint of viewport from ring buffer, no highlight.
// ---------------------------------------------------------------------------
STATIC FUNCTION _MSEL_PaintClean( oPrompt, nTop, nBot, nCols, nViewport )
   LOCAL nTotal, nStart, nEnd, nBuf, nRow, cOut

   nTotal := AGSB_Count()
   IF nTotal == 0 ; RETURN NIL ; ENDIF
   nEnd   := nTotal - AGSB_ScrollOffset()
   nStart := nEnd - nViewport + 1
   IF nStart < 1 ; nStart := 1 ; ENDIF
   IF nEnd > nTotal ; nEnd := nTotal ; ENDIF

   cOut := ""
   FOR nRow := nTop TO nBot
      nBuf := nStart + ( nRow - nTop )
      IF nBuf >= 1 .AND. nBuf <= nTotal
         cOut += Chr(27) + "[" + LTrim( Str( nRow ) ) + ";1H" + Chr(27) + "[2K" + ;
                 AGSB_GetLine( nBuf )
      ENDIF
   NEXT
   cOut += AGREPL_BoxCursorSeq()
   FWrite( hb_GetStdOut(), cOut )
   RETURN NIL

// ---------------------------------------------------------------------------
STATIC FUNCTION _MSEL_StripAnsi( cText )
   LOCAL cOut := "", i, cCh
   LOCAL nState := 0   // 0=normal, 1=ESC seen, 2=CSI param, 3=OSC param, 4=OSC ESC
   IF ValType( cText ) != "C" .OR. Empty( cText )
      RETURN ""
   ENDIF
   FOR i := 1 TO Len( cText )
      cCh := SubStr( cText, i, 1 )
      DO CASE
      CASE nState == 0
         IF Asc( cCh ) == 27
            nState := 1
         ELSE
            cOut += cCh
         ENDIF
      CASE nState == 1
         IF cCh == "["
            nState := 2
         ELSEIF cCh == "]"
            nState := 3
         ELSE
            nState := 0
         ENDIF
      CASE nState == 2
         IF Asc( cCh ) >= 64 .AND. Asc( cCh ) <= 126
            nState := 0
         ENDIF
      CASE nState == 3
         IF Asc( cCh ) == 7
            nState := 0
         ELSEIF Asc( cCh ) == 27
            nState := 4
         ENDIF
      CASE nState == 4
         IF cCh == "\"
            nState := 0
         ELSEIF Asc( cCh ) == 27
            nState := 1
         ELSEIF cCh == "["
            nState := 2
         ELSEIF cCh == "]"
            nState := 3
         ELSE
            nState := 0
         ENDIF
      ENDCASE
   NEXT
   RETURN cOut

// ---------------------------------------------------------------------------
STATIC FUNCTION _MSEL_SetClipboard( cText )
   LOCAL lOk := .F.
   IF ValType( cText ) != "C" .OR. Empty( cText )
      RETURN .F.
   ENDIF
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      lOk := AGCON_SETCLIP( cText )
   RECOVER
      lOk := .F.
   END SEQUENCE
   RETURN lOk
