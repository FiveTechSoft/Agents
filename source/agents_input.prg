// Raw-mode multi-line input editor for the main prompt. Supports:
// - Single-line editing with cursor keys, Home/End, Delete
// - Input history with Up/Down
// - Multi-line input via Shift+Enter or paste detection
// - Paste detection: rapid keystrokes (<50ms apart) with embedded
//   newlines are buffered as multi-line instead of submitting.

// ── History buffer (persists across calls to AGIN_ReadLine) ──────────────
STATIC s_aHistory := {}          // array of history lines, oldest first
STATIC s_nHistoryMax := 50       // maximum entries kept
STATIC s_nHistoryPos := -1       // -1 = not navigating; 0 = most recent, 1 = older...
STATIC s_cHistoryDraft := ""     // saved draft text when entering history navigation

// Adds a line to the history buffer. Empty lines and exact duplicates of the
// most recent entry are ignored. The buffer never exceeds s_nHistoryMax.
FUNCTION AGIN_HistoryAdd( cText )
   LOCAL cTrim := AllTrim( hb_CStr( cText ) )
   IF Empty( cTrim )
      RETURN NIL
   ENDIF
   // skip if it's the same as the most recent entry
   IF Len( s_aHistory ) > 0 .AND. ATail( s_aHistory ) == cTrim
      RETURN NIL
   ENDIF
   AAdd( s_aHistory, cTrim )
   // trim the oldest when over the limit
   IF Len( s_aHistory ) > s_nHistoryMax
      hb_ADel( s_aHistory, 1, .T. )
   ENDIF
   RETURN NIL

// Resets the navigation position back to "current draft" mode.
FUNCTION AGIN_HistoryReset()
   s_nHistoryPos := -1
   s_cHistoryDraft := ""
   RETURN NIL

// Returns the previous history entry (one step back in time), or NIL when
// there is no more history to go back to. Also saves the current draft on
// the first Up press.
FUNCTION AGIN_HistoryPrev( cCurrentBuf )
   LOCAL nLen := Len( s_aHistory )
   IF nLen == 0
      RETURN NIL
   ENDIF
   IF s_nHistoryPos == -1
      // first Up: save the current draft
      s_cHistoryDraft := hb_CStr( cCurrentBuf )
   ENDIF
   IF s_nHistoryPos < nLen - 1
      s_nHistoryPos++
      RETURN s_aHistory[ nLen - s_nHistoryPos ]
   ENDIF
   // already at the oldest entry
   RETURN NIL

// Returns the next history entry (one step forward toward the present), or
// the saved draft when the bottom is reached.
FUNCTION AGIN_HistoryNext( cCurrentBuf )
   LOCAL nLen := Len( s_aHistory )
   HB_SYMBOL_UNUSED( cCurrentBuf )
   IF s_nHistoryPos <= 0
      // back to draft mode
      s_nHistoryPos := -1
      RETURN s_cHistoryDraft
   ENDIF
   s_nHistoryPos--
   RETURN s_aHistory[ nLen - s_nHistoryPos ]

// Returns the number of history entries currently stored.
FUNCTION AGIN_HistoryCount()
   RETURN Len( s_aHistory )

// Clears all history.
FUNCTION AGIN_HistoryClear()
   s_aHistory := {}
   s_nHistoryPos := -1
   s_cHistoryDraft := ""
   RETURN NIL

// ── Editor state operations ──────────────────────────────────────────────

// A fresh editor state, cursor at the end of the initial text.
// When cInitial is non-empty the text is flagged as a "suggestion" so the
// input box renders it in the suggestion colour and Tab accepts it.
FUNCTION AGIN_New( cInitial )
   LOCAL cText := hb_CStr( cInitial )
   RETURN { "buf" => cText, "cursor" => hb_UTF8Len( cText ), ;
            "suggestion" => iif( !Empty( cText ), cText, "" ) }

// Inserts cChar at the cursor and advances the cursor.
FUNCTION AGIN_Insert( oSt, cChar )
   LOCAL n := oSt[ "cursor" ], cBuf := oSt[ "buf" ]
   oSt[ "buf" ] := hb_UTF8SubStr( cBuf, 1, n ) + cChar + ;
                   hb_UTF8SubStr( cBuf, n + 1, hb_UTF8Len( cBuf ) - n )
   oSt[ "cursor" ] := n + 1
   RETURN oSt

// Deletes the character before the cursor; moves the cursor back. No-op at 0.
FUNCTION AGIN_Backspace( oSt )
   LOCAL n := oSt[ "cursor" ], cBuf := oSt[ "buf" ]
   IF n > 0
      oSt[ "buf" ] := hb_UTF8SubStr( cBuf, 1, n - 1 ) + ;
                      hb_UTF8SubStr( cBuf, n + 1, hb_UTF8Len( cBuf ) - n )
      oSt[ "cursor" ] := n - 1
   ENDIF
   RETURN oSt

// Deletes the character at the cursor. No-op at the end.
FUNCTION AGIN_Delete( oSt )
   LOCAL n := oSt[ "cursor" ], cBuf := oSt[ "buf" ], nLen := hb_UTF8Len( oSt[ "buf" ] )
   IF n < nLen
      oSt[ "buf" ] := hb_UTF8SubStr( cBuf, 1, n ) + ;
                      hb_UTF8SubStr( cBuf, n + 2, nLen - n - 1 )
   ENDIF
   RETURN oSt

// Cursor movement, all clamped to [0, len].
FUNCTION AGIN_Left( oSt )
   IF oSt[ "cursor" ] > 0
      oSt[ "cursor" ] := oSt[ "cursor" ] - 1
   ENDIF
   RETURN oSt

FUNCTION AGIN_Right( oSt )
   IF oSt[ "cursor" ] < hb_UTF8Len( oSt[ "buf" ] )
      oSt[ "cursor" ] := oSt[ "cursor" ] + 1
   ENDIF
   RETURN oSt

FUNCTION AGIN_Home( oSt )
   oSt[ "cursor" ] := 0
   RETURN oSt

FUNCTION AGIN_End( oSt )
   oSt[ "cursor" ] := hb_UTF8Len( oSt[ "buf" ] )
   RETURN oSt

// Returns { "text" => <slice that fits nWidth columns>, "col" => <cursor
// column within the slice> }. When the buffer fits, the slice is the whole
// buffer. When it is wider, it scrolls so the cursor stays visible.
// For multi-line buffers, shows the LAST line (like a typical REPL).
FUNCTION AGIN_Window( oSt, nWidth )
   LOCAL cBuf := oSt[ "buf" ], nLen := hb_UTF8Len( cBuf ), nCur := oSt[ "cursor" ]
   LOCAL nNL, cLastLine, nLastLineLen, nOffset, nScr
   // Count newlines to get the last line
   nNL := RAt( Chr(10), cBuf )
   IF nNL > 0
      cLastLine := hb_UTF8SubStr( cBuf, nNL + 1, nLen - nNL )
   ELSE
      cLastLine := cBuf
   ENDIF
   nLastLineLen := hb_UTF8Len( cLastLine )
   // For cursor positioning within the window, compute the cursor's
   // offset relative to the start of the last line.
   nOffset := iif( nNL > 0, nCur - nNL, nCur )
   IF nOffset < 0
      nOffset := 0
   ENDIF
   IF nLastLineLen <= nWidth
      RETURN { "text" => cLastLine, "col" => nOffset, "lines" => AGIN_LineCount( cBuf ) }
   ENDIF
   // scroll the last line if it exceeds the width
   nScr := iif( nOffset > nWidth, nOffset - nWidth, 0 )
   RETURN { "text" => hb_UTF8SubStr( cLastLine, nScr + 1, nWidth ), ;
            "col" => nOffset - nScr, "lines" => AGIN_LineCount( cBuf ) }

// Returns the number of lines in a buffer (1 for no newlines).
// Counts Chr(10) bytes directly: a newline byte (0x0A) can never occur
// inside a multi-byte UTF-8 sequence, so this is exact and runs in O(n) --
// the old per-character hb_UTF8SubStr scan was O(n^2) and lagged the editor
// as the line grew.
FUNCTION AGIN_LineCount( cBuf )
   RETURN 1 + ( Len( cBuf ) - Len( StrTran( cBuf, Chr(10), "" ) ) )

// Encodes a Unicode codepoint (BMP) as a UTF-8 character string.
FUNCTION AGIN_Utf8Chr( n )
   DO CASE
   CASE n < 128
      RETURN Chr( n )
   CASE n < 2048
      RETURN Chr( hb_bitOr( 192, hb_bitShift( n, -6 ) ) ) + ;
             Chr( hb_bitOr( 128, hb_bitAnd( n, 63 ) ) )
   OTHERWISE
      RETURN Chr( hb_bitOr( 224, hb_bitShift( n, -12 ) ) ) + ;
             Chr( hb_bitOr( 128, hb_bitAnd( hb_bitShift( n, -6 ), 63 ) ) ) + ;
             Chr( hb_bitOr( 128, hb_bitAnd( n, 63 ) ) )
   ENDCASE
   RETURN ""

// Returns .T. when the editor state has an active (unaccepted) suggestion.
FUNCTION AGIN_HasSuggestion( oSt )
   RETURN ValType( oSt ) == "H" .AND. hb_HHasKey( oSt, "suggestion" ) .AND. ;
          !Empty( oSt[ "suggestion" ] )

// Clears the suggestion flag so the buffer renders in normal colour.
FUNCTION AGIN_ClearSuggestion( oSt )
   oSt[ "suggestion" ] := ""
   RETURN NIL

// NOTE: requires AGUI_ColorOn() (VT enabled) — the editor positions the cursor
// with AGUI_VT sequences; without VT the sentinel path is taken instead.
// Reads one line (possibly multi-line) through the raw-mode input box.
// cInitial pre-fills the buffer (the suggested next prompt).
// Returns the typed string, or NIL on Ctrl-C / end of input.
// Returns the sentinel hash { "no_console" => .T. } when there is no
// interactive console, so the caller can fall back to a cooked reader.
// Multi-line input:
//   - Shift+Enter inserts a newline (Chr(10)) without submitting.
//   - A rapid sequence of keystrokes (<50ms apart) is treated as a paste;
//     any Enter in the paste inserts a newline instead of submitting.
//   - A plain Enter submits the full buffer (single or multi-line).
FUNCTION AGIN_ReadLine( cInitial )
   LOCAL oSt, nKey, hW, cResult := NIL, lDone := .F., cHistoryLine
   LOCAL nNow, nLastTime := 0, lPaste := .F., nLines

   // the box editor needs VT cursor control; without it (no console, or a
   // console that rejected virtual-terminal mode) fall back to the cooked
   // reader via the sentinel.
   IF !AGUI_ColorOn() .OR. !AGCON_RawMode( .T. )
      RETURN { "no_console" => .T. }
   ENDIF

   // when a suggestion is provided, pre-fill the buffer.
   // do NOT add the suggestion to history — it is a machine-generated prompt,
   // not user input. Only explicit user submits go into history.
   oSt := AGIN_New( hb_CStr( cInitial ) )
   AGIN_HistoryReset()

   // draw the box: top border, prompt line, bottom border, hint; then move
   // the cursor up onto the prompt line (hint -> bottom -> prompt = up 2).
   hW := AGIN_Window( oSt, AGUI_InputInnerWidth() )
   AGREPL_Out( Chr(10) + AGUI_FrameTop() + Chr(10) + ;
               iif( AGIN_HasSuggestion( oSt ), ;
                   AGUI_InputBoxSuggestion( hW[ "text" ] ), ;
                   AGUI_InputBoxLine( hW[ "text" ] ) ) + Chr(10) + ;
               AGUI_FrameBottom() + Chr(10) + ;
               AGUI_InputHint( hW[ "lines" ] ) + AGUI_VT( "2A" ) )

   DO WHILE !lDone
      // place the terminal cursor at the editing column: column 1 is the
      // left border, then a space, then "> " -> text starts at column 5.
      hW := AGIN_Window( oSt, AGUI_InputInnerWidth() )
      AGREPL_Out( AGUI_VT( "1G" ) + ;
                  AGUI_VT( LTrim( Str( 3 + hW[ "col" ] ) ) + "G" ) )
      nKey := AGCON_ReadKey()
      // paste detection: if keys arrive faster than 50ms apart, it's a paste
      nNow := hb_MilliSeconds()
      lPaste := ( nLastTime > 0 .AND. ( nNow - nLastTime ) < 50 )
      nLastTime := nNow
      DO CASE
      CASE nKey == 0 .OR. nKey == -8
         cResult := NIL
         AGIN_HistoryReset()
         lDone := .T.
      CASE nKey == -1
         // Enter: in paste mode insert newline; otherwise submit
         IF lPaste
            AGIN_Insert( oSt, Chr(10) )
         ELSE
            AGIN_ClearSuggestion( oSt )
            AGIN_HistoryAdd( oSt[ "buf" ] )
            cResult := oSt[ "buf" ]
            AGIN_HistoryReset()
            lDone := .T.
         ENDIF
      CASE nKey == -11
         // Shift+Enter: always insert newline, never submit
         AGIN_ClearSuggestion( oSt )
         AGIN_Insert( oSt, Chr(10) )
      CASE nKey == -12
         // Tab: accept the suggestion — keep the buffer, switch to normal colour
         AGIN_ClearSuggestion( oSt )
         oSt[ "cursor" ] := hb_UTF8Len( oSt[ "buf" ] )
      CASE nKey == -2
         // Backspace on a suggestion cancels it; otherwise normal backspace
         IF AGIN_HasSuggestion( oSt )
            AGIN_ClearSuggestion( oSt )
            oSt[ "buf" ] := ""
            oSt[ "cursor" ] := 0
         ELSE
            AGIN_Backspace( oSt )
         ENDIF
      CASE nKey == -3
         AGIN_Left( oSt )
      CASE nKey == -4
         AGIN_Right( oSt )
      CASE nKey == -5
         AGIN_Home( oSt )
      CASE nKey == -6
         AGIN_End( oSt )
      CASE nKey == -7
         // Delete on a suggestion cancels it; otherwise normal delete
         IF AGIN_HasSuggestion( oSt )
            AGIN_ClearSuggestion( oSt )
            oSt[ "buf" ] := ""
            oSt[ "cursor" ] := 0
         ELSE
            AGIN_Delete( oSt )
         ENDIF
      CASE nKey == -9
         // Up: navigate to previous history entry
         AGIN_ClearSuggestion( oSt )
         cHistoryLine := AGIN_HistoryPrev( oSt[ "buf" ] )
         IF cHistoryLine != NIL
            oSt[ "buf" ] := cHistoryLine
            oSt[ "cursor" ] := hb_UTF8Len( cHistoryLine )
         ENDIF
      CASE nKey == -10
         // Down: navigate to next history entry or back to draft
         AGIN_ClearSuggestion( oSt )
         cHistoryLine := AGIN_HistoryNext( oSt[ "buf" ] )
         IF cHistoryLine != NIL
            oSt[ "buf" ] := cHistoryLine
            oSt[ "cursor" ] := hb_UTF8Len( cHistoryLine )
         ENDIF
      CASE nKey > 0
         // Any printable char: if a suggestion is active, replace it
         IF AGIN_HasSuggestion( oSt )
            AGIN_ClearSuggestion( oSt )
            oSt[ "buf" ] := ""
            oSt[ "cursor" ] := 0
         ENDIF
         AGIN_Insert( oSt, AGCON_PrintableText( nKey ) )
      // nKey == -99 (an unmapped key) matches no case above and is ignored
      ENDCASE
      // redraw the prompt line in place; update hint if line count changed
      hW := AGIN_Window( oSt, AGUI_InputInnerWidth() )
      nLines := hW[ "lines" ]
      AGREPL_Out( AGUI_VT( "1G" ) + ;
                  iif( AGIN_HasSuggestion( oSt ), ;
                      AGUI_InputBoxSuggestion( hW[ "text" ] ), ;
                      AGUI_InputBoxLine( hW[ "text" ] ) ) + ;
                  AGUI_VT( "2B" ) + AGUI_VT( "1G" ) + ;
                  AGUI_InputHint( nLines ) + AGUI_VT( "2A" ) )
   ENDDO

   AGCON_RawMode( .F. )
   // step the cursor below the box (prompt -> bottom -> hint -> next line)
   AGREPL_Out( AGUI_VT( "2B" ) + Chr(10) )
   RETURN cResult
