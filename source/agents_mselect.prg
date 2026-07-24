// agents_mselect.prg -- Mouse text selection in the transcript viewport.
//
// Click-and-drag in the scroll region highlights lines with reverse video.
// On mouse release the selected text is copied to the Windows clipboard.
//
// Design:
//   State machine: IDLE -> SELECTING -> IDLE
//   Anchor: screen row where the click started.
//   Current: screen row where the mouse currently is (during drag).
//   Selected lines = min(anchor,current) .. max(anchor,current) in screen rows.
//   Each selected screen row maps to a ring-buffer line via the viewport math
//   (same formula as AGPROMPT_ScrollTranscript).
//
// Integration: AGPROMPT_Poll calls AGMSEL_HandleEvent() in its drain loop.
// If a click lands in the transcript region (above the box), selection begins.
// While selecting, each mouse-drag repaints the affected rows with reverse
// video.  On button-up the text is extracted, ANSI-stripped, and sent to the
// clipboard.

#include "inkey.ch"

// --- state ---
STATIC s_lActive   := .F.     // .T. while mouse button is held
STATIC s_nAnchorRow := 0      // screen row where click started (1-based)
STATIC s_nCurRow   := 0      // current screen row during drag

// Minimum column width to copy (strips trailing blanks).
#define MSEL_TRIM_RIGHT  .T.

// ---------------------------------------------------------------------------
// AGMSEL_HandleEvent( oPrompt ) -- called from AGPROMPT_Poll drain loop.
//   Returns .T. when the event was consumed (selection active or finished).
//   Returns .F. when nothing happened (no mouse event pending).
// ---------------------------------------------------------------------------
FUNCTION AGMSEL_HandleEvent( oPrompt )
   LOCAL aEvt, nType, nRow, nCol
   LOCAL hReg, nTop, nBot, nCols
   LOCAL nStart, nEnd, nViewport, nTotal
   LOCAL nLineTop, nLineBot
   LOCAL aSelected := {}, i, cText, cLine, nTrim

   IF oPrompt == NIL .OR. !hb_HHasKey( oPrompt, "region" ) .OR. ;
      ValType( oPrompt[ "region" ] ) != "H"
      RETURN .F.
   ENDIF
   hReg := oPrompt[ "region" ]

   // Read the mouse event stored by _CheckMouseEvent() in agents_console.prg
   aEvt := AGCON_MouseEvent()

   IF aEvt == NIL .OR. ValType( aEvt ) != "A" .OR. Len( aEvt ) < 3
      RETURN .F.
   ENDIF

   nType := aEvt[ 1 ]
   nRow  := aEvt[ 2 ]
   nCol  := aEvt[ 3 ]

   // Only accept left button events (down=1, up=2, drag=3)
   IF nType < 1 .OR. nType > 3
      RETURN .F.
   ENDIF

   // --- identify the scroll viewport ---
   nTop     := hb_HGetDef( hReg, "scroll_top", 1 )
   nBot     := hb_HGetDef( hReg, "scroll_bottom", 1 )
   nCols    := hb_HGetDef( hReg, "cols", 80 )
   IF nBot <= nTop
      RETURN .F.
   ENDIF
   nViewport := nBot - nTop + 1

   // --- click must be inside the scroll region ---
   IF nRow < nTop .OR. nRow > nBot
      // Click outside the viewport: cancel any active selection
      IF s_lActive
         _MSEL_Finish( oPrompt )
      ENDIF
      RETURN .F.
   ENDIF

   DO CASE
   CASE nType == 1  // LEFT BUTTON DOWN -> start selection
      s_lActive     := .T.
      s_nAnchorRow  := nRow
      s_nCurRow     := nRow
      _MSEL_Paint( oPrompt )

   CASE nType == 3  // DRAG -> extend selection
      IF s_lActive
         s_nCurRow := nRow
         _MSEL_Paint( oPrompt )
      ENDIF

   CASE nType == 2  // LEFT BUTTON UP -> finish, copy to clipboard
      IF s_lActive
         s_nCurRow := nRow
         // Extract selected text
         nTotal := AGSB_Count()
         IF nTotal > 0
            nEnd   := nTotal - AGSB_ScrollOffset()
            nStart := nEnd - nViewport + 1
            IF nStart < 1 ; nStart := 1 ; ENDIF
            IF nEnd > nTotal ; nEnd := nTotal ; ENDIF
            // Map screen rows to buffer lines
            nLineTop := nStart + ( Min( s_nAnchorRow, s_nCurRow ) - nTop )
            nLineBot := nStart + ( Max( s_nAnchorRow, s_nCurRow ) - nTop )
            IF nLineTop < 1 ; nLineTop := 1 ; ENDIF
            IF nLineBot > nTotal ; nLineBot := nTotal ; ENDIF
            // Collect lines
            FOR i := nLineTop TO nLineBot
               cLine := AGSB_GetLine( i )
               // Strip ANSI escape sequences for clipboard
               cLine := _MSEL_StripAnsi( cLine )
               // Trim trailing blanks
               IF MSEL_TRIM_RIGHT
                  cLine := RTrim( cLine )
               ENDIF
               AAdd( aSelected, cLine )
            NEXT
         ENDIF
         // Finish selection (repaint without highlight)
         _MSEL_Finish( oPrompt )
         // Copy to clipboard
         IF !Empty( aSelected )
            cText := ""
            FOR i := 1 TO Len( aSelected )
               cText += aSelected[ i ]
               IF i < Len( aSelected )
                  cText += Chr(13) + Chr(10)
               ENDIF
            NEXT
            _MSEL_SetClipboard( cText )
         ENDIF
      ENDIF
   ENDCASE

   RETURN .T.

// ---------------------------------------------------------------------------
// _MSEL_Paint -- repaint only the affected rows with reverse video.
// ---------------------------------------------------------------------------
STATIC FUNCTION _MSEL_Paint( oPrompt )
   LOCAL hReg, nTop, nBot, nCols
   LOCAL nViewport, nTotal, nStart, nEnd
   LOCAL nRowStart, nRowEnd, nRow
   LOCAL j, cLine, cOut, cLineClean

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
   nTotal := AGSB_Count()
   IF nTotal == 0
      RETURN NIL
   ENDIF
   nEnd   := nTotal - AGSB_ScrollOffset()
   nStart := nEnd - nViewport + 1
   IF nStart < 1 ; nStart := 1 ; ENDIF
   IF nEnd > nTotal ; nEnd := nTotal ; ENDIF

   // Determine which screen rows to repaint (the union of old and new)
   nRowStart := Min( s_nAnchorRow, s_nCurRow )
   nRowEnd   := Max( s_nAnchorRow, s_nCurRow )
   IF nRowStart < nTop ; nRowStart := nTop ; ENDIF
   IF nRowEnd > nBot   ; nRowEnd := nBot ; ENDIF

   cOut := ""
   FOR nRow := nRowStart TO nRowEnd
      j := nStart + ( nRow - nTop )
      IF j >= 1 .AND. j <= nTotal
         cLine := AGSB_GetLine( j )
         // Strip ANSI for clean repaint, then apply reverse video
         cLineClean := _MSEL_StripAnsi( cLine )
         // Pad/truncate to viewport width
         IF Len( cLineClean ) > nCols
            cLineClean := Left( cLineClean, nCols )
         ELSE
            cLineClean := cLineClean + Space( nCols - Len( cLineClean ) )
         ENDIF
         cOut += Chr(27) + "[" + LTrim( Str( nRow ) ) + ";1H" + ;
                 Chr(27) + "[2K" + ;
                 Chr(27) + "[7m" + cLineClean + Chr(27) + "[27m"
      ENDIF
   NEXT
   cOut += AGREPL_BoxCursorSeq()
   FWrite( hb_GetStdOut(), cOut )
   RETURN NIL

// ---------------------------------------------------------------------------
// _MSEL_Finish -- repaint the affected rows WITHOUT highlight and reset state.
// ---------------------------------------------------------------------------
STATIC FUNCTION _MSEL_Finish( oPrompt )
   LOCAL hReg, nTop, nBot, nCols
   LOCAL nViewport, nTotal, nStart, nEnd
   LOCAL nRowStart, nRowEnd, nRow
   LOCAL j, cLine, cOut

   IF oPrompt == NIL .OR. !hb_HHasKey( oPrompt, "region" ) .OR. ;
      ValType( oPrompt[ "region" ] ) != "H"
      s_lActive := .F.
      RETURN NIL
   ENDIF
   hReg := oPrompt[ "region" ]
   nTop  := hb_HGetDef( hReg, "scroll_top", 1 )
   nBot  := hb_HGetDef( hReg, "scroll_bottom", 1 )
   nCols := hb_HGetDef( hReg, "cols", 80 )
   IF nBot <= nTop
      s_lActive := .F.
      RETURN NIL
   ENDIF
   nViewport := nBot - nTop + 1
   nTotal := AGSB_Count()
   IF nTotal == 0
      s_lActive := .F.
      RETURN NIL
   ENDIF
   nEnd   := nTotal - AGSB_ScrollOffset()
   nStart := nEnd - nViewport + 1
   IF nStart < 1 ; nStart := 1 ; ENDIF
   IF nEnd > nTotal ; nEnd := nTotal ; ENDIF

   nRowStart := Min( s_nAnchorRow, s_nCurRow )
   nRowEnd   := Max( s_nAnchorRow, s_nCurRow )
   IF nRowStart < nTop ; nRowStart := nTop ; ENDIF
   IF nRowEnd > nBot   ; nRowEnd := nBot ; ENDIF

   cOut := ""
   FOR nRow := nRowStart TO nRowEnd
      j := nStart + ( nRow - nTop )
      IF j >= 1 .AND. j <= nTotal
         cLine := AGSB_GetLine( j )
         // Repaint from buffer (includes original ANSI escapes)
         cOut += Chr(27) + "[" + LTrim( Str( nRow ) ) + ";1H" + ;
                 Chr(27) + "[2K" + cLine
      ENDIF
   NEXT
   cOut += AGREPL_BoxCursorSeq()
   FWrite( hb_GetStdOut(), cOut )

   s_lActive    := .F.
   s_nAnchorRow := 0
   s_nCurRow    := 0
   RETURN NIL

// ---------------------------------------------------------------------------
// _MSEL_StripAnsi -- remove ANSI escape sequences from a string.
// Matches ESC[ ... letter/tilde (CSI sequences) and ESC] ... BEL/ST (OSC).
// ---------------------------------------------------------------------------
STATIC FUNCTION _MSEL_StripAnsi( cText )
   LOCAL cResult := "", i, cCh, lEsc := .F., lCSI := .F.
   IF ValType( cText ) != "C" .OR. Empty( cText )
      RETURN ""
   ENDIF
   i := 1
   DO WHILE i <= Len( cText )
      cCh := SubStr( cText, i, 1 )
      IF lCSI
         // Inside CSI sequence: skip until final byte (0x40..0x7E)
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
      ELSEIF Asc( cCh ) == 27  // ESC
         lEsc := .T.
      ELSE
         cResult += cCh
      ENDIF
      i++
   ENDDO
   RETURN cResult

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