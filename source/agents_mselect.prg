// agents_mselect.prg -- Mouse text selection in the transcript viewport.
//
// Click-and-drag highlights text with black-on-white.
// Strategy: RestScreen() restores clean screen, then ANSI escape sequences
// paint the highlight. Two atomic operations = no flickering.
// On mouse release: RestScreen() restores clean, text copied to clipboard.

#include "inkey.ch"

// --- state ---
STATIC s_lActive    := .F.
STATIC s_nAnchorRow := 0
STATIC s_nAnchorCol := 1
STATIC s_nCurRow    := 0
STATIC s_nCurCol    := 1
STATIC s_cSaved     := NIL

// ---------------------------------------------------------------------------
FUNCTION AGMSEL_OnButton( nType, nRow, nCol )
   LOCAL oPrompt, hReg
   LOCAL nTop, nBot, nCols, nViewport
   LOCAL nTotal, nStart, nEnd
   LOCAL nBuf, i, cLine, cText, nLines
   LOCAL nRowTop, nRowBot

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
STATIC FUNCTION _MSEL_ClipLine( cLine, nRow, nRowTop, nRowBot )
   LOCAL nFrom, nTo

   IF nRowTop == nRowBot
      nFrom := Min( s_nAnchorCol, s_nCurCol )
      nTo   := Max( s_nAnchorCol, s_nCurCol )
   ELSEIF nRow == nRowTop
      nFrom := Min( s_nAnchorCol, s_nCurCol )
      nTo   := Max( s_nAnchorCol, s_nCurCol )
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
// _MSEL_Paint -- restore clean screen then paint highlights with ANSI.
// RestScreen is atomic (no flicker), then ANSI writes paint the selection.
// ESC[48;5;15m = white bg (256-color), ESC[30m = black fg, ESC[0m = reset.
// ---------------------------------------------------------------------------
STATIC FUNCTION _MSEL_Paint( oPrompt, nTop, nBot, nCols, nViewport )
   LOCAL nTotal, nStart, nEnd
   LOCAL nRowTop, nRowBot, nRow, cOut, cClean
   LOCAL nFrom, nTo, cLeft, cMid, nLen

   IF s_cSaved == NIL ; RETURN NIL ; ENDIF

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

   // Step 1: restore clean screen (atomic, no flicker)
   RestScreen( nTop, 1, nBot, nCols, s_cSaved )

   // Step 2: paint highlighted rows with ANSI
   cOut := ""
   FOR nRow := nRowTop TO nRowBot
      nBuf := nStart + ( nRow - nTop )
      IF nBuf >= 1 .AND. nBuf <= nTotal
         cClean := _MSEL_StripAnsi( AGSB_GetLine( nBuf ) )
         IF Len( cClean ) > nCols
            cClean := Left( cClean, nCols )
         ENDIF

         // Determine highlight column range
         IF nRowTop == nRowBot
            nFrom := Min( s_nAnchorCol, s_nCurCol )
            nTo   := Max( s_nAnchorCol, s_nCurCol )
         ELSEIF nRow == nRowTop
            nFrom := Min( s_nAnchorCol, s_nCurCol )
            nTo   := Max( s_nAnchorCol, s_nCurCol )
         ELSEIF nRow == nRowBot
            nFrom := 1
            nTo   := Max( s_nAnchorCol, s_nCurCol )
         ELSE
            nFrom := 1
            nTo   := nCols
         ENDIF

         IF nFrom < 1 ; nFrom := 1 ; ENDIF
         IF nTo > Len( cClean ) ; nTo := Len( cClean ) ; ENDIF
         IF nFrom > Len( cClean ) ; nFrom := Len( cClean ) + 1 ; ENDIF

         // Position cursor at this row, write: normal left + highlighted mid
         cOut += Chr(27) + "[" + LTrim( Str( nRow ) ) + ";1H" + Chr(27) + "[2K"
         cLeft := ""
         IF nFrom > 1
            cLeft := Left( cClean, nFrom - 1 )
         ENDIF
         IF nTo >= nFrom
            cMid := SubStr( cClean, nFrom, nTo - nFrom + 1 )
         ELSE
            cMid := ""
         ENDIF
         cOut += cLeft
         IF !Empty( cMid )
            cOut += Chr(27) + "[48;5;15;30m" + cMid + Chr(27) + "[0m"
         ENDIF
      ENDIF
   NEXT
   cOut += AGREPL_BoxCursorSeq()
   FWrite( hb_GetStdOut(), cOut )
   RETURN NIL

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
