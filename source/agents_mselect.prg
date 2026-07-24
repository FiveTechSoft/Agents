// agents_mselect.prg -- Mouse text selection in the transcript viewport.
//
// Click-and-drag in the scroll region highlights lines with reverse video.
// On mouse release the selected text is copied to the Windows clipboard.
//
// Modeled after test_mselect.prg which proved this mechanism works.

#include "inkey.ch"

// --- state ---
STATIC s_lActive   := .F.
STATIC s_nAnchorRow := 0
STATIC s_nCurRow   := 0

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
         s_nCurRow    := nRow
         _MSEL_Paint( oPrompt, nTop, nBot, nCols, nViewport )
      ENDIF
      RETURN NIL
   ENDIF

   // --- drag -> extend selection ---
   IF nType == 3 .AND. s_lActive
      IF nRow >= nTop .AND. nRow <= nBot
         s_nCurRow := nRow
         _MSEL_Paint( oPrompt, nTop, nBot, nCols, nViewport )
      ENDIF
      RETURN NIL
   ENDIF

   // --- button UP -> finish selection, copy to clipboard ---
   IF nType == 2 .AND. s_lActive
      IF nRow >= nTop .AND. nRow <= nBot
         s_nCurRow := nRow
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
               cLine := RTrim( _MSEL_StripAnsi( AGSB_GetLine( nBuf ) ) )
               cText += cLine
               nLines++
               IF i < nRowBot
                  cText += Chr(13) + Chr(10)
               ENDIF
            ENDIF
         NEXT
         IF !Empty( cText )
            _MSEL_SetClipboard( cText )
         ENDIF
      ENDIF

      // Repaint without highlight
      _MSEL_RepaintClean( oPrompt, nTop, nBot, nCols, nViewport )
      s_lActive    := .F.
      s_nAnchorRow := 0
      s_nCurRow    := 0
      RETURN NIL
   ENDIF

   RETURN NIL

// ---------------------------------------------------------------------------
// _MSEL_Paint -- repaint affected rows with reverse video highlight.
// ---------------------------------------------------------------------------
STATIC FUNCTION _MSEL_Paint( oPrompt, nTop, nBot, nCols, nViewport )
   LOCAL nTotal, nStart, nEnd, nBuf
   LOCAL nRowTop, nRowBot, nRow, cOut, cClean

   nTotal := AGSB_Count()
   IF nTotal == 0 ; RETURN NIL ; ENDIF
   nEnd   := nTotal - AGSB_ScrollOffset()
   nStart := nEnd - nViewport + 1
   IF nStart < 1 ; nStart := 1 ; ENDIF
   IF nEnd > nTotal ; nEnd := nTotal ; ENDIF

   // First repaint the full viewport clean, then overlay highlight
   _MSEL_RepaintClean( oPrompt, nTop, nBot, nCols, nViewport )

   // Now paint only the selected rows with highlight
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
         ELSE
            cClean := cClean + Space( nCols - Len( cClean ) )
         ENDIF
         cOut += Chr(27) + "[" + LTrim( Str( nRow ) ) + ";1H" + ;
                 Chr(27) + "[2K" + ;
                 Chr(27) + "[7m" + cClean + Chr(27) + "[27m"
      ENDIF
   NEXT
   cOut += AGREPL_BoxCursorSeq()
   FWrite( hb_GetStdOut(), cOut )
   RETURN NIL

// ---------------------------------------------------------------------------
// _MSEL_RepaintClean -- repaint viewport rows from buffer without highlight.
// ---------------------------------------------------------------------------
STATIC FUNCTION _MSEL_RepaintClean( oPrompt, nTop, nBot, nCols, nViewport )
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
         cOut += Chr(27) + "[" + LTrim( Str( nRow ) ) + ";1H" + ;
                 Chr(27) + "[2K" + AGSB_GetLine( nBuf )
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