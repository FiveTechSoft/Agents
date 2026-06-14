// ccselect: the interactive multiple-choice selector used by the ask_user
// tool. This file holds the pure state logic and the raw-key I/O loop. The
// block rendering (AGUI_QuestionBlock) lives in ccui.prg so it can reuse the
// static AGUI_PadCell helper.

// Builds a fresh selector state. aOptions is the list of answer strings; the
// literal "Other" is appended so the user is never boxed in. The cursor
// starts on the first option.
FUNCTION AGSEL_New( cQuestion, aOptions )
   LOCAL aOpts := {}, x
   IF ValType( aOptions ) == "A"
      FOR EACH x IN aOptions
         AAdd( aOpts, hb_CStr( x ) )
      NEXT
   ENDIF
   AAdd( aOpts, "Other" )
   RETURN { "question" => hb_CStr( cQuestion ), ;
            "options"  => aOpts, ;
            "cursor"   => 1 }

// Moves the cursor to nIndex, clamped to 1..Len(options). Returns oSel.
FUNCTION AGSEL_SetCursor( oSel, nIndex )
   LOCAL nMax := Len( oSel[ "options" ] )
   IF nIndex < 1
      nIndex := 1
   ELSEIF nIndex > nMax
      nIndex := nMax
   ENDIF
   oSel[ "cursor" ] := nIndex
   RETURN oSel

// Moves the cursor by nDelta rows, wrapping around the ends so Down on the
// last option lands on the first and Up on the first lands on the last.
// Returns oSel.
FUNCTION AGSEL_Move( oSel, nDelta )
   LOCAL nMax := Len( oSel[ "options" ] )
   LOCAL n := oSel[ "cursor" ] + nDelta
   IF nMax <= 0
      RETURN oSel
   ENDIF
   DO WHILE n < 1
      n += nMax
   ENDDO
   DO WHILE n > nMax
      n -= nMax
   ENDDO
   oSel[ "cursor" ] := n
   RETURN oSel

// Writes bytes straight to stdout, bypassing AGREPL_Out's line rewriting --
// needed for absolute cursor positioning.
STATIC FUNCTION AGSEL_Raw( cText )
   FWrite( hb_GetStdOut(), cText )
   RETURN NIL

// Paints the question block. On a repaint, first moves the cursor up over the
// previous block (question line + one line per option + the tail hint line)
// so the new block overwrites it. Every row is a constant display width
// across repaints -- only the marker and inverse video change -- so no
// explicit clearing is needed.
STATIC FUNCTION AGSEL_Paint( oSel, lRepaint )
   LOCAL cPre := "", oPrompt, hReg, nTop, aLines, i, cOut, nLines
   LOCAL cSep, cLabel
   oPrompt := AGREPL_BoxPrompt()
   IF oPrompt != NIL .AND. ;
      ValType( oPrompt[ "region" ] ) == "H" .AND. ;
      oPrompt[ "region" ][ "active" ] == .T.
      // Box mounted: paint each line at an absolute row so neither LF nor
      // line wrap can push the cursor past scroll_bottom. Include the
      // tool-block separator and " Ask user" label at the top so the user
      // always sees the section header alongside the question.
      // Block layout:
      //   separator
      //   " Ask user"
      //   <blank>
      //   question
      //   <blank>
      //   N options
      //   <blank>
      //   hint
      // -> total height = N + 7
      // Pin the box to the floor so the block has a stable position
      // above it (it would otherwise collide with the still-travelling
      // dynamic box).
      AGPROMPT_ForcePin( oPrompt )
      hReg := oPrompt[ "region" ]
      nLines := Len( oSel[ "options" ] ) + 7
      // anchor the block just above the (now pinned) box
      nTop := hReg[ "box_top" ] - nLines
      IF nTop < 1
         nTop := 1
      ENDIF
      cSep   := AGUI_Color( Replicate( Chr(226)+Chr(148)+Chr(128), ;
                                       hReg[ "cols" ] - 1 ), ;
                            AGUI_Pal( "bash_header" ) )
      cLabel := AGUI_Color( " Ask user", AGUI_Pal( "bash_header" ) )
      aLines := hb_ATokens( AGUI_QuestionBlock( oSel ), Chr(10) )
      // prepend separator + label + blank so they share the same block
      hb_AIns( aLines, 1, cSep, .T. )
      hb_AIns( aLines, 2, cLabel, .T. )
      hb_AIns( aLines, 3, "", .T. )
      cOut := ""
      // First paint: reserve the block's rows by scrolling the region up
      // by blockHeight. This pushes any prior model output up so it
      // remains visible above the block instead of being overwritten.
      IF !lRepaint
         cOut += Chr(27) + "[" + LTrim( Str( hReg[ "scroll_bottom" ] ) ) + ;
                 ";1H" + Replicate( Chr(10), nLines )
      ENDIF
      FOR i := 1 TO nLines
         cOut += Chr(27) + "[" + LTrim( Str( nTop + i - 1 ) ) + ";1H" + ;
                 Chr(27) + "[2K" + ;
                 iif( i <= Len( aLines ), aLines[ i ], "" )
      NEXT
      cOut += AGREPL_BoxCursorSeq()
      AGSEL_Raw( cOut )
      RETURN NIL
   ENDIF
   nLines := Len( oSel[ "options" ] ) + 4
   // No box (cooked mode, tests): keep the original LF-driven layout.
   IF lRepaint
      cPre := Chr(27) + "[" + LTrim( Str( nLines ) ) + "A"
   ENDIF
   AGSEL_Raw( cPre + AGUI_QuestionBlock( oSel ) )
   RETURN NIL

// Reads a free-text answer. When oPrompt (the active box prompt) is mounted
// the input lands in the box editor itself, so the user types where they
// would normally type their next message; otherwise it falls back to the
// inline prompt below the options. Used by Other and by Tab-amend.
STATIC FUNCTION AGSEL_ReadFreeText( cInitial, oPrompt )
   LOCAL oEd, nKey, cBuf
   IF oPrompt == NIL .OR. !oPrompt[ "region" ][ "active" ]
      // no box -> the old inline editor
      RETURN AGSEL_ReadOther( cInitial )
   ENDIF
   // pre-fill the box editor with the suggestion text and redraw so the
   // user sees it inside the prompt box; Enter submits, Esc cancels
   cInitial := iif( ValType( cInitial ) == "C", cInitial, "" )
   oEd := oPrompt[ "editor" ] := AGIN_New( "" )
   oEd[ "buf" ] := cInitial
   oEd[ "cursor" ] := hb_UTF8Len( cInitial )
   AGPROMPT_Redraw( oPrompt )
   DO WHILE .T.
      DO WHILE !AGCON_KeyPending()
         hb_idleSleep( 0.02 )
      ENDDO
      nKey := AGCON_ReadKey()
      DO CASE
      CASE nKey == -1                          // Enter -> submit
         cBuf := AllTrim( oEd[ "buf" ] )
         oPrompt[ "editor" ] := AGIN_New( "" )
         AGPROMPT_Redraw( oPrompt )
         RETURN cBuf
      CASE nKey == -13                         // Esc -> cancel
         oPrompt[ "editor" ] := AGIN_New( "" )
         AGPROMPT_Redraw( oPrompt )
         RETURN ""
      CASE nKey == -2 ; AGIN_Backspace( oEd )
      CASE nKey == -3 ; AGIN_Left( oEd )
      CASE nKey == -4 ; AGIN_Right( oEd )
      CASE nKey == -5 ; AGIN_Home( oEd )
      CASE nKey == -6 ; AGIN_End( oEd )
      CASE nKey == -7 ; AGIN_Delete( oEd )
      CASE nKey == -11 ; AGIN_Insert( oEd, Chr(10) )
      CASE nKey > 0   ; AGIN_Insert( oEd, AGIN_Utf8Chr( nKey ) )
      ENDCASE
      AGPROMPT_Redraw( oPrompt )
   ENDDO
   RETURN ""

// Reads a free-text answer for the "Other" option, or for Tab-amend with
// cInitial pre-filled. Prints a prompt with the buffer (so the user sees
// the pre-fill), then collects printable characters until Enter or Esc.
// Backspace deletes the last char.
STATIC FUNCTION AGSEL_ReadOther( cInitial )
   LOCAL cBuf, nKey
   cBuf := iif( ValType( cInitial ) == "C", cInitial, "" )
   AGSEL_Raw( Chr(10) + "Edit and press Enter to confirm: " + cBuf )
   DO WHILE .T.
      DO WHILE !AGCON_KeyPending()
         hb_idleSleep( 0.02 )
      ENDDO
      nKey := AGCON_ReadKey()
      DO CASE
      CASE nKey == -1 .OR. nKey == -13      // Enter or Esc -> confirm
         EXIT
      CASE nKey == -2                       // Backspace
         IF !Empty( cBuf )
            cBuf := hb_UTF8SubStr( cBuf, 1, hb_UTF8Len( cBuf ) - 1 )
            AGSEL_Raw( Chr(8) + " " + Chr(8) )
         ENDIF
      CASE nKey > 0                         // a printable character
         cBuf += AGIN_Utf8Chr( nKey )
         AGSEL_Raw( AGIN_Utf8Chr( nKey ) )
      ENDCASE
   ENDDO
   AGSEL_Raw( Chr(10) )
   RETURN AllTrim( cBuf )

// Runs the selector interactively and returns the chosen answer string.
// Up/Down move the highlight, a digit key (1-9) jumps to and selects, Enter
// confirms, Tab amends (drops into the editor pre-filled with the current
// option), Esc cancels (returns ""), Ctrl+E asks the model for an
// explanation (returns the sentinel "__AGSEL_EXPLAIN__"). Choosing "Other"
// drops to a free-text prompt. With no console (piped input) it cannot
// prompt, so it returns the first option as a default.
FUNCTION AGSEL_Run( oSel )
   LOCAL nKey, cAnswer, lDone := .F., lCancel := .F., lExplain := .F.
   LOCAL lAmend := .F., oPrompt, oBoxEd, lBoxEdit, hC
   oPrompt := AGREPL_BoxPrompt()
   IF !AGCON_HasConsole()
      RETURN oSel[ "options" ][ 1 ]
   ENDIF
   AGSEL_Paint( oSel, .F. )
   DO WHILE !lDone
      DO WHILE !AGCON_KeyPending()
         hb_idleSleep( 0.02 )
      ENDDO
      nKey := AGCON_ReadKey()
      // route to the box editor when the box is mounted and the key is an
      // editing keystroke (printable / backspace / delete / cursor / line
      // edit). Selector-only keys (Up, Down, digits, Tab, Esc, Ctrl+E)
      // remain with the selector. Enter is shared: if the box buffer is
      // non-empty it submits the box line and cancels the selector;
      // otherwise it confirms the highlighted option.
      lBoxEdit := .F.
      IF oPrompt != NIL
         oBoxEd := oPrompt[ "editor" ]
         DO CASE
         CASE nKey > 0 .AND. nKey != 0          // printable -> insert
            AGIN_Insert( oBoxEd, AGIN_Utf8Chr( nKey ) )
            lBoxEdit := .T.
         CASE nKey == -2                        // Backspace
            AGIN_Backspace( oBoxEd )
            lBoxEdit := .T.
         CASE nKey == -3                        // Left
            AGIN_Left( oBoxEd )
            lBoxEdit := .T.
         CASE nKey == -4                        // Right
            AGIN_Right( oBoxEd )
            lBoxEdit := .T.
         CASE nKey == -5                        // Home
            AGIN_Home( oBoxEd )
            lBoxEdit := .T.
         CASE nKey == -6                        // End
            AGIN_End( oBoxEd )
            lBoxEdit := .T.
         CASE nKey == -7                        // Delete
            AGIN_Delete( oBoxEd )
            lBoxEdit := .T.
         CASE nKey == -11                       // Shift+Enter -> newline
            AGIN_Insert( oBoxEd, Chr(10) )
            lBoxEdit := .T.
         ENDCASE
      ENDIF
      IF lBoxEdit
         AGPROMPT_Redraw( oPrompt )
         LOOP
      ENDIF
      DO CASE
      CASE nKey == -9                       // Up
         AGSEL_Move( oSel, -1 )
      CASE nKey == -10                      // Down
         AGSEL_Move( oSel, 1 )
      CASE nKey >= 49 .AND. nKey <= 57      // digit 1-9 -> jump and select;
         // AGSEL_SetCursor clamps a digit past the last option to the last
         AGSEL_SetCursor( oSel, nKey - 48 )
         lDone := .T.
      CASE nKey == -1                       // Enter
         IF oPrompt != NIL .AND. ;
            !Empty( AllTrim( oPrompt[ "editor" ][ "buf" ] ) )
            // user typed in the box and pressed Enter: submit that line
            // instead of confirming the selector. /exit/quit ends the
            // session immediately; everything else queues for the next
            // turn and the selector returns cancelled.
            IF Lower( AllTrim( oPrompt[ "editor" ][ "buf" ] ) ) == "/exit" .OR. ;
               Lower( AllTrim( oPrompt[ "editor" ][ "buf" ] ) ) == "/quit"
               __QUIT()
            ENDIF
            hC := AGPROMPT_Classify( oPrompt[ "editor" ][ "buf" ] )
            DO CASE
            CASE hC[ "action" ] == "btw"
               // mid-question /btw: record the interrupt and cancel the
               // selector. The agent loop picks the interrupt up at the
               // next iteration boundary and processes its text as the
               // next user message.
               oPrompt[ "interrupt" ] := { "kind" => "btw", ;
                                           "text" => hC[ "text" ] }
               AGIN_HistoryAdd( oPrompt[ "editor" ][ "buf" ] )
            CASE hC[ "action" ] != "empty"
               AGPROMPT_Enqueue( oPrompt, hC[ "text" ] )
               AGIN_HistoryAdd( hC[ "text" ] )
            ENDCASE
            AGIN_HistoryReset()
            oPrompt[ "editor" ] := AGIN_New( "" )
            AGPROMPT_Redraw( oPrompt )
            lCancel := .T.
         ENDIF
         lDone := .T.
      CASE nKey == -12                      // Tab -> amend the highlight
         lAmend := .T.
         lDone := .T.
      CASE nKey == -13                      // Esc -> cancel
         lCancel := .T.
         lDone := .T.
      CASE nKey == -14                      // Ctrl+E -> ask for explanation
         lExplain := .T.
         lDone := .T.
      ENDCASE
      IF !lDone
         AGSEL_Paint( oSel, .T. )
      ENDIF
   ENDDO
   IF lCancel
      RETURN ""
   ENDIF
   IF lExplain
      RETURN "__AGSEL_EXPLAIN__"
   ENDIF
   cAnswer := oSel[ "options" ][ oSel[ "cursor" ] ]
   IF lAmend .OR. cAnswer == "Other"
      cAnswer := AGSEL_ReadFreeText( ;
         iif( lAmend, cAnswer, "" ), oPrompt )
   ENDIF
   RETURN cAnswer
