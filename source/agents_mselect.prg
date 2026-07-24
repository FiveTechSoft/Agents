// agents_mselect.prg -- Mouse text selection in the transcript viewport.
//
// Click-and-drag in the scroll region highlights text with black-on-white.
// First line: from click column to end of line.
// Middle lines: full lines.
// Last line: from start of line to current mouse column.
// On mouse release the selected text is copied to the Windows clipboard.
// Uses SaveScreen()/RestScreen() to eliminate flickering.

#include "inkey.ch"

// --- state ---
STATIC s_lActive    := .F.
STATIC s_nAnchorRow := 0
STATIC s_nAnchorCol := 1    // column where mouse was clicked
STATIC s_nCurRow    := 0
STATIC s_nCurCol    := 1    // current mouse column
STATIC s_cSaved     := NIL  // saved screen snapshot for flicker-free repaint

// ---------------------------------------------------------------------------
// AGMSEL_OnButton( nType, nRow, nCol ) -- called from _MapRaw in
// agents_console.prg when K_LBUTTONDOWN / K_MOUSEMOVE / K_LBUTTONUP fires.
//   nType: 1=down, 2=up, 3=drag
//   nRow, nCol: 1-based screen coordinates from MRow()/MCol().
// ---------------------------------------------------------------------------
FUNCTION AGMSEL_OnButton( nType, nRow, nCol )
   LOCAL oPrompt, hReg
   LOCAL nTop, nBot, nCols, nViewport
   LOCAL nTotal, nStart, nEnd
   LOCAL nBuf, i, cLine, cText, nLines
   LOCAL nRowTop, nRowBot
   LOCAL lNeedPaint

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
         s_cSaved     := SaveScreen( nTop, 1, nBot, nCols )
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
         lNeedPaint := ( nRow != s_nCurRow ) .OR. ( nCol != s_nCurCol )
         IF lNeedPaint
            IF s_cSaved != NIL
               RestScreen( nTop, 1, nBot, nCols, s_cSaved )
            ENDIF
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

      // Extract selected text from ring buffer
      nTotal := AGSB_Count()
      IF nTotal > 0
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
      ENDIF

      // Restore clean screen
      IF s_cSaved != NIL
         RestScreen( nTop, 1, nBot, nCols, s_cSaved )
      ENDIF
      s_cSaved     := NIL
      s_lActive    := .F.
      s_nAnchorRow := 0
      s_nAnchorCol := 1
      s_nCurRow    := 0
      s_nCurCol    := 1
      RETURN NIL
   ENDIF

   RETURN NIL

// ---------------------------------------------------------------------------
// _MSEL_ClipLine -- clip a single line for selection/extraction.
//   nRow    = screen row being processed
//   nRowTop = topmost selected row
//   nRowBot = bottommost selected row
//
// First row: from anchor column to current column.
// Middle rows: full line.
// Last row: from start to current column.
// Single row: from anchor column to current column.
// ---------------------------------------------------------------------------
STATIC FUNCTION _MSEL_ClipLine( cLine, nRow, nRowTop, nRowBot )
   LOCAL nFrom, nTo

   IF nRowTop == nRowBot
      // Single row: anchor col to cur col
      nFrom := Min( s_nAnchorCol, s_nCurCol )
      nTo   := Max( s_nAnchorCol, s_nCurCol )
   ELSEIF nRow == nRowTop
      // First row: anchor col to cur col
      nFrom := Min( s_nAnchorCol, s_nCurCol )
      nTo   := Max( s_nAnchorCol, s_nCurCol )
   ELSEIF nRow == nRowBot
      // Last row: start to cur col
      nFrom := 1
      nTo   := Max( s_nAnchorCol, s_nCurCol )
   ELSE
      // Middle row: full line
      RETURN RTrim( cLine )
   ENDIF

   IF nFrom < 1 ; nFrom := 1 ; ENDIF
   IF nTo > Len( cLine ) ; nTo := Len( cLine ) ; ENDIF
   IF nTo < nFrom
      RETURN ""
   ENDIF
   RETURN RTrim( SubStr( cLine, nFrom, nTo - nFrom + 1 ) )

// ---------------------------------------------------------------------------
// _MSEL_Paint -- paint selected rows with black-on-white highlight.
// ---------------------------------------------------------------------------
STATIC FUNCTION _MSEL_Paint( oPrompt, nTop, nBot, nCols, nViewport )
   LOCAL nTotal, nStart, nEnd, nBuf
   LOCAL nRowTop, nRowBot, nRow, cOut, cClean
   LOCAL nFrom, nTo, cLeft, cMid

   nTotal := AGSB_Count()
   IF nTotal == 0 ; RETURN NIL ; ENDIF
   nEnd   := nTotal - AGSB_ScrollOffset()
   nStart := nEnd - nViewport + 1
   IF nStart < 1 ; nStart := 1 ; ENDIF
   IF nEnd > nTotal ; nEnd := nTotal ; ENDIF

   // Determine selected row range
   nRowTop := Min( s_nAnchorRow, s_nCurRow )
   nRowBot := Max( s_nAnchorRow, s_nCurRow )
   IF nRowTop < nTop ; nRowTop := nTop ; ENDIF
   IF nRowBot > nBot ; nRowBot := nBot ; ENDIF

   cOut := ""
   FOR nRow := nRowTop TO nRowBot
      nBuf := nStart + ( nRow - nTop )
      IF nBuf >= 1 .AND. nBuf <= nTotal
         cClean := _MSEL_StripAnsi( AGSB_GetLine( nBuf ) )
         IF Len( cClean ) > nCols
            cClean := Left( cClean, nCols )
         ENDIF

         // Determine highlight column range for this row
         IF nRowTop == nRowBot
            // Single row: anchor col to cur col
            nFrom := Min( s_nAnchorCol, s_nCurCol )
            nTo   := Max( s_nAnchorCol, s_nCurCol )
         ELSEIF nRow == nRowTop
            // First row: anchor col to cur col
            nFrom := Min( s_nAnchorCol, s_nCurCol )
            nTo   := Max( s_nAnchorCol, s_nCurCol )
         ELSEIF nRow == nRowBot
            // Last row: start to cur col
            nFrom := 1
            nTo   := Max( s_nAnchorCol, s_nCurCol )
         ELSE
            // Middle row: full line
            nFrom := 1
            nTo   := Len( cClean )
         ENDIF

         IF nFrom < 1 ; nFrom := 1 ; ENDIF
         IF nTo > Len( cClean ) ; nTo := Len( cClean ) ; ENDIF

         // Build line: left (normal) + mid (highlighted) + right fill
         cLeft := ""
         IF nFrom > 1
            cLeft := Left( cClean, nFrom - 1 )
         ENDIF
         IF nTo >= nFrom
            cMid := SubStr( cClean, nFrom, nTo - nFrom + 1 )
         ELSE
            cMid := ""
         ENDIF
         // Pad to fill entire row width
         cMid := PadR( cMid, nCols - Len( cLeft ) )

         cOut += Chr(27) + "[" + LTrim( Str( nRow ) ) + ";1H" + ;
                 Chr(27) + "[2K" + cLeft + ;
                 Chr(27) + "[47;30m" + cMid + Chr(27) + "[0m"
      ENDIF
   NEXT
   cOut += AGREPL_BoxCursorSeq()
   FWrite( hb_GetStdOut(), cOut )
   RETURN NIL

// ---------------------------------------------------------------------------
// _MSEL_StripAnsi -- remove ANSI escape sequences from a string.
// ---------------------------------------------------------------------------
STATIC FUNCTION _MSEL_StripAnsi( cText )
   LOCAL cOut := "", i, cCh, lEsc := .F., lCSI := .F.
   IF ValType( cText ) != "C" .OR. Empty( cText )
      RETURN ""
   ENDIF
   FOR i := 1 TO Len( cText )
      cCh := SubStr( cText, i, 1 )
      IF lCSI
         IF Asc( cCh ) >= 64 .AND. Asc( cCh ) <= 126
            lCSI := .F.
            lEsc := .F.
         ENDIF
      ELSEIF lEsc
         IF cCh == "["
            lCSI := .T.
         ELSE
            lEsc := .F.
         ENDIF
      ELSEIF Asc( cCh ) == 27
         lEsc := .T.
      ELSE
         cOut += cCh
      ENDIF
   NEXT
   RETURN cOut

// ---------------------------------------------------------------------------
// _MSEL_SetClipboard -- copy text to the Windows clipboard via C helper.
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
