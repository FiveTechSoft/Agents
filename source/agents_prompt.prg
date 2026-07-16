// ccprompt: the persistent bottom input box and the mid-turn message queue.
// This file holds the pure logic; the console I/O (Poll, Redraw, Activate,
// Teardown) is added on top of it.

// The input box occupies the bottom FOUR rows: top frame, input line,
// bottom frame, and a skills status line that lists active skills.
#define AGPROMPT_BOX_ROWS  4

// Wall-clock of the previously processed key, used by paste detection.
STATIC s_nLastKeyMs := 0
// Wall-clock of the previous Esc, used by double-tap detection. Two Escs
// within AGPROMPT_DBLESC_MS milliseconds emit a "rewind" interrupt
// instead of a plain "esc" -- which the REPL turns into a /rewind
// conversation undo. Reset every time a non-Esc key arrives.
STATIC s_nLastEscMs := 0
#define AGPROMPT_DBLESC_MS 600
// Below this many rows there is no room for the box -> fallback mode.
#define AGPROMPT_MIN_ROWS  8

// Builds a fresh prompt state. hSize is an optional { rows, cols } hash; when
// omitted the console is queried with AGCON_Size(). region/editor/queue are
// always present so the pure helpers work without a console. scroll_top is
// the first row of the scroll region (defaults to 1 — meaning "full screen
// scrollable above the box"); pass a larger value to keep a header (e.g.
// the banner) pinned at the top. content_row is the row where the next
// agent output will land; it starts at scroll_top and grows down until the
// box reaches the bottom of the screen, at which point the box pins to the
// bottom and output starts scrolling inside the region.
FUNCTION AGPROMPT_New( hSize, nTopRow )
   LOCAL nRows, nCols
   IF ValType( hSize ) == "H"
      nRows := hSize[ "rows" ]
      nCols := hSize[ "cols" ]
   ELSE
      hSize := AGCON_Size()
      nRows := hSize[ "rows" ]
      nCols := hSize[ "cols" ]
   ENDIF
   nTopRow := iif( ValType( nTopRow ) == "N" .AND. nTopRow >= 1, nTopRow, 1 )
   RETURN { "editor"      => AGIN_New( "" ), ;
            "queue"       => {}, ;
            "interrupt"   => NIL, ;
            "scroll_top"  => nTopRow, ;
            "content_row" => nTopRow, ;
            "region"      => AGPROMPT_Region( nRows, nCols, nTopRow, nTopRow ) }

// Computes the screen layout for a console of nRows x nCols. box_top sits
// at max( nContentRow + 1, nTopRow + 1 ), clamped to nRows - BOX_ROWS + 1
// (the absolute floor). scroll_bottom = box_top - 1. While box_top is
// above the floor the box "follows" the content; once it hits the floor
// the box is pinned to the bottom and the scroll region (scroll_top..
// scroll_bottom) takes over scrolling on overflow. A console shorter
// than AGPROMPT_MIN_ROWS is reported inactive (the caller falls back).
FUNCTION AGPROMPT_Region( nRows, nCols, nContentRow, nTopRow )
   LOCAL nFloor, nBoxTop
   nTopRow := iif( ValType( nTopRow ) == "N" .AND. nTopRow >= 1, nTopRow, 1 )
   nFloor  := nRows - AGPROMPT_BOX_ROWS + 1
   // default nContentRow keeps the box pinned at its floor -- preserves
   // the original layout for callers that don't track content position
   nContentRow := iif( ValType( nContentRow ) == "N" .AND. nContentRow >= 1, ;
                       nContentRow, nFloor - 1 )
   nBoxTop := nContentRow + 1
   IF nBoxTop < nTopRow + 1  ; nBoxTop := nTopRow + 1  ; ENDIF
   IF nBoxTop > nFloor       ; nBoxTop := nFloor       ; ENDIF
   // The scroll region is the FULL band between the pinned header and
   // the floor while the box is still travelling -- output lands below
   // the banner without touching it. Once the box pins to its floor the
   // banner has done its job (the user has seen it) and the region
   // expands UP to row 1 so further content scrolls the banner off the
   // top edge. Without this expansion the banner sits frozen at the top
   // forever, wasting screen rows even after the box is pinned.
   RETURN { "rows"          => nRows, ;
            "cols"          => nCols, ;
            "active"        => ( nRows >= AGPROMPT_MIN_ROWS ), ;
            "scroll_top"    => iif( nBoxTop == nFloor, 1, nTopRow ), ;
            "scroll_bottom" => nFloor - 1, ;
            "box_top"       => nBoxTop, ;
            "pinned"        => ( nBoxTop == nFloor ) }

// True when cText is a paste-collapse placeholder of the form
// "[pasted N lines text]".
FUNCTION AGPROMPT_IsPlaceholder( cText )
   LOCAL cTrim := AllTrim( hb_CStr( cText ) )
   RETURN Left( cTrim, 8 ) == "[pasted " .AND. ;
          Right( cTrim, 12 ) == " lines text]"

// Classifies a submitted line. Returns { action, text }:
//   action "empty" -> blank line, ignore
//   action "btw"   -> /btw line, text is the remainder (an interrupt)
//   action "queue" -> a normal message to queue
FUNCTION AGPROMPT_Classify( cLine )
   LOCAL cTrim := hb_CStr( cLine )
   cTrim := StrTran( StrTran( cTrim, Chr(13), "" ), Chr(10), "" )
   cTrim := AllTrim( cTrim )
   IF Empty( cTrim )
      RETURN { "action" => "empty", "text" => "" }
   ENDIF
   IF Lower( cTrim ) == "/btw"
      RETURN { "action" => "btw", "text" => "" }
   ENDIF
   IF Lower( Left( cTrim, 5 ) ) == "/btw "
      RETURN { "action" => "btw", "text" => AllTrim( SubStr( cTrim, 6 ) ) }
   ENDIF
   RETURN { "action" => "queue", "text" => cTrim }

// Appends a message to the FIFO queue.
FUNCTION AGPROMPT_Enqueue( oPrompt, cText )
   AAdd( oPrompt[ "queue" ], hb_CStr( cText ) )
   RETURN oPrompt

// Removes and returns the oldest queued message, or NIL when the queue is
// empty.
FUNCTION AGPROMPT_Dequeue( oPrompt )
   LOCAL cFirst
   IF Empty( oPrompt[ "queue" ] )
      RETURN NIL
   ENDIF
   cFirst := oPrompt[ "queue" ][ 1 ]
   hb_ADel( oPrompt[ "queue" ], 1, .T. )
   RETURN cFirst

// Returns .T. when an interruption (Esc or /btw) is pending.
FUNCTION AGPROMPT_Interrupted( oPrompt )
   RETURN oPrompt[ "interrupt" ] != NIL

// Writes a string straight to stdout, bypassing AGREPL_Out (which strips CR
// and rewrites LF). Needed for absolute cursor positioning.
STATIC FUNCTION AGPROMPT_Raw( cText )
   FWrite( hb_GetStdOut(), cText )
   // Ensure the box paint reaches the terminal immediately. Without this,
   // some PTY/WSL hosts buffer stdout and the user sees a blank prompt
   // line until a later newline/flush.
   AGCON_TTY_FLUSH()
   RETURN NIL

// Forces the dynamic box to pin at the floor immediately. Interactive
// selectors (ask_user, propose_agents) paint above the box and assume a
// stable position right above the floor, so once one of them opens the
// box should stop "travelling" with content. No-op when already pinned.
FUNCTION AGPROMPT_ForcePin( oPrompt )
   LOCAL hSz
   IF oPrompt == NIL ; RETURN oPrompt ; ENDIF
   IF hb_HHasKey( oPrompt, "region" ) .AND. ;
      hb_HGetDef( oPrompt[ "region" ], "pinned", .F. ) == .T.
      RETURN oPrompt
   ENDIF
   hSz := AGCON_Size()
   oPrompt[ "content_row" ] := hSz[ "rows" ] - AGPROMPT_BOX_ROWS
   AGPROMPT_Redraw( oPrompt )
   RETURN oPrompt

// Activates the pinned box: sets the VT scroll region to
// rows nTopRow..scroll_bottom so agent output scrolls only inside that
// window. nTopRow defaults to 1 (full screen scrollable above the box);
// pass a larger value to keep a header (e.g. the banner) pinned at the
// top -- the cursor is then parked at nTopRow, so the first agent
// output lands right under the header instead of at the bottom.
// No-op when the region is inactive (small console / fallback).
FUNCTION AGPROMPT_Activate( oPrompt, nTopRow )
   LOCAL hSz, hReg
   hSz := AGCON_Size()
   nTopRow := iif( ValType( nTopRow ) == "N" .AND. nTopRow >= 1 .AND. ;
                   nTopRow < hSz[ "rows" ] - AGPROMPT_BOX_ROWS, nTopRow, 1 )
   oPrompt[ "scroll_top" ]  := nTopRow
   oPrompt[ "content_row" ] := nTopRow
   oPrompt[ "region" ] := AGPROMPT_Region( hSz[ "rows" ], hSz[ "cols" ], ;
                                           nTopRow, nTopRow )
   hReg := oPrompt[ "region" ]
   IF !hReg[ "active" ]
      RETURN oPrompt
   ENDIF
   // Force raw TTY (no echo, char-at-a-time) so typed keys reach AGCON
   // under WSL/Windows Terminal. Safe no-op on Windows.
   AGCON_RawMode( .T. )
   // park the cursor at the top of the scroll region and save it as the
   // initial output anchor; the box sits one row below until the content
   // grows enough to push it down to the floor
   AGPROMPT_Raw( Chr(27) + "[" + LTrim( Str( nTopRow ) ) + ";1H" )
   AGPROMPT_Raw( Chr(27) + "[s" )
   // arm the scroll region too so an early burst that overshoots the
   // dynamic box position scrolls cleanly into the box's eventual floor
   AGPROMPT_Raw( Chr(27) + "[" + LTrim( Str( nTopRow ) ) + ";" + ;
                 LTrim( Str( hReg[ "scroll_bottom" ] ) ) + "r" )
   AGPROMPT_Redraw( oPrompt )
   RETURN oPrompt

// Restores the terminal: clears the scroll region (full screen scrollable
// again), wipes the box rows so they do not bleed into the shell prompt,
// then parks the cursor on the row where the box used to start. The
// following shell prompt continues from there, right under the agent's
// last visible output.
FUNCTION AGPROMPT_Teardown( oPrompt )
   LOCAL hReg := oPrompt[ "region" ]
   IF !hReg[ "active" ]
      RETURN oPrompt
   ENDIF
   // reset scroll region to the whole screen
   AGPROMPT_Raw( Chr(27) + "[r" )
   // erase the rows the box occupied (top frame + input line + bottom
   // frame + status line). ESC[<row>;1H + ESC[2K for each row.
   AGPROMPT_Raw( Chr(27) + "[" + LTrim( Str( hReg[ "box_top" ] ) ) + ";1H" )
   AGPROMPT_Raw( Chr(27) + "[2K" + Chr(10) + Chr(27) + "[2K" + Chr(10) + ;
                 Chr(27) + "[2K" + Chr(10) + Chr(27) + "[2K" )
   // move the cursor to the first box row so the shell prompt comes back
   // exactly where the agent's last visible output ended
   AGPROMPT_Raw( Chr(27) + "[" + LTrim( Str( hReg[ "box_top" ] ) ) + ";1H" )
   AGCON_RawMode( .F. )
   RETURN oPrompt

// Redraws the box on the bottom three rows: top frame, the editor line, the
// bottom frame. Recomputes the region from a fresh AGCON_Size() so a resize
// is picked up -- the scroll margin is re-emitted too, otherwise a grown
// terminal would scroll output in the old, smaller region. The cursor is
// left on the input line at the editing column, so the visible terminal
// cursor sits inside the box where the user types. The output anchor (the
// ESC[s slot, owned by AGREPL_Out) is deliberately not touched here.
FUNCTION AGPROMPT_Redraw( oPrompt )
   LOCAL hReg, hW, hSz, aBadges, nTopRow, nContentRow, nOldBoxTop, i, cWipe
   LOCAL nWriteStart, nWriteEnd, nWipeEnd, lTrailingLF
   hSz := AGCON_Size()
   nTopRow     := hb_HGetDef( oPrompt, "scroll_top",  1 )
   nContentRow := hb_HGetDef( oPrompt, "content_row", nTopRow )
   nOldBoxTop  := hb_HGetDef( oPrompt, "last_box_top", 0 )
   oPrompt[ "region" ] := AGPROMPT_Region( hSz[ "rows" ], hSz[ "cols" ], ;
                                           nContentRow, nTopRow )
   hReg := oPrompt[ "region" ]
   IF !hReg[ "active" ]
      RETURN oPrompt
   ENDIF
   hW := AGIN_Window( oPrompt[ "editor" ], AGUI_InputInnerWidth() )
   // When the box has moved DOWN since the last paint (dynamic mode),
   // wipe every row that was OLD box frame and is NOT (a) about to be
   // overwritten by the new box paint and (b) NOT a row that just
   // received content from the last AGREPL_Out write. Rule of thumb:
   //   wipe = [ oldBoxTop .. min(oldBoxTop+3, newBoxTop-1) ]
   //          minus the just-written rows.
   // The just-written rows are [ write_start .. content_row ] for chunks
   // that do NOT end in LF (cursor lands on the last written text row),
   // and [ write_start .. content_row - 1 ] for chunks that DO end in LF
   // (the final CRLF advances cursor onto a blank row). Skipping that
   // single trailing row is what lets the wipe catch a stale old-box top
   // frame when multiple LF-bearing writes pile up between paints.
   IF nOldBoxTop > 0 .AND. nOldBoxTop < hReg[ "box_top" ]
      nWriteStart := hb_HGetDef( oPrompt, "last_write_start", nContentRow )
      lTrailingLF := hb_HGetDef( oPrompt, "last_write_trailing_lf", .T. )
      nWriteEnd   := iif( lTrailingLF, nContentRow - 1, nContentRow )
      nWipeEnd    := Min( nOldBoxTop + 3, hReg[ "box_top" ] - 1 )
      cWipe := ""
      FOR i := nOldBoxTop TO nWipeEnd
         IF i < nWriteStart .OR. i > nWriteEnd
            cWipe += Chr(27) + "[" + LTrim( Str( i ) ) + ";1H" + Chr(27) + "[2K"
         ENDIF
      NEXT
      IF !Empty( cWipe )
         AGPROMPT_Raw( cWipe )
      ENDIF
   ENDIF
   oPrompt[ "last_box_top" ] := hReg[ "box_top" ]
   // combine plan-mode and active skills into one status-line badge list
   aBadges := AGSKILL_Active()
   IF AGREPL_PlanMode()
      hb_AIns( aBadges, 1, "plan-mode", .T. )
   ENDIF
   IF AGREPL_LeanMode()
      hb_AIns( aBadges, 1, "lean", .T. )
   ENDIF
   IF AGREPL_HasGoal()
      hb_AIns( aBadges, 1, "goal", .T. )
   ENDIF
   // wipe the four rows above the box's new position so the previous
   // frame does not bleed when the box moves down a row; only needed
   // while the box is still travelling (not yet pinned).
   IF !hReg[ "pinned" ] .AND. hReg[ "box_top" ] >= nTopRow + 1
      // do not wipe -- pre-existing agent output may live in those rows.
      // The box will be painted on top by the writes below.
   ENDIF
   // Position each box row with an absolute CUP (ESC[<row>;1H) instead of
   // chaining CRLFs between rows. CRLFs at the bottom of the terminal
   // scroll the screen up -- which is how a single Esc-triggered Redraw
   // ends up stacking 10 leftover top frames when the box sits near the
   // last row: the box paint itself rolls the screen up by one row, the
   // old top frame survives at the row just above the new one, and the
   // next Redraw repeats. Absolute jumps never advance past the last
   // visible row, so no scroll fires.
   AGPROMPT_Raw( ;
      Chr(27) + "[" + LTrim( Str( hReg[ "scroll_top" ] ) ) + ";" + ;
                     LTrim( Str( hReg[ "scroll_bottom" ] ) ) + "r" + ;
      Chr(27) + "[" + LTrim( Str( hReg[ "box_top" ] ) ) + ";1H" + ;
      Chr(27) + "[2K" + AGUI_FrameTop() + ;
      Chr(27) + "[" + LTrim( Str( hReg[ "box_top" ] + 1 ) ) + ";1H" + ;
      Chr(27) + "[2K" + ;
      iif( AGIN_HasSuggestion( oPrompt[ "editor" ] ), ;
          AGUI_InputBoxSuggestion( hW[ "text" ] ), ;
          AGUI_InputBoxLine( hW[ "text" ] ) ) + ;
      Chr(27) + "[" + LTrim( Str( hReg[ "box_top" ] + 2 ) ) + ";1H" + ;
      Chr(27) + "[2K" + AGUI_FrameBottom() + ;
      Chr(27) + "[" + LTrim( Str( hReg[ "box_top" ] + 3 ) ) + ";1H" + ;
      Chr(27) + "[2K" + AGUI_SkillsStatusLine( aBadges, hReg[ "cols" ] ) + ;
      Chr(27) + "[" + LTrim( Str( hReg[ "box_top" ] + 1 ) ) + ";" + ;
              LTrim( Str( 3 + hW[ "col" ] ) ) + "H" )
   RETURN oPrompt

// Non-blocking: drains every pending key into the editor, then redraws the
// box. On Enter the buffer is classified; on Esc an interrupt is recorded.
// Returns an action string: "none", "queued", or "interrupt".
//
// Paste detection: keystrokes arriving < 50ms apart are treated as a paste
// burst. Enter inside a paste burst inserts a newline instead of submitting.
// After the burst, if the buffer ended up multi-line and the burst flagged
// itself, the buffer is collapsed to a "[pasted N lines text]" placeholder
// and the real content is stashed in oPrompt[ "paste" ]; submitting the
// placeholder swaps the real content back in transparently.
FUNCTION AGPROMPT_Poll( oPrompt )
   LOCAL oEd := oPrompt[ "editor" ], nKey, hC, cAction := "none", lDrained := .F.
   LOCAL cHist, nNow, lBurst := .F., nLines, cSubmit, cPlaceholder, nNext
   DO WHILE AGCON_KeyPending()
      lDrained := .T.
      nKey := AGCON_ReadKey()
      // Safety: never treat raw CR/LF as printable insert
      IF nKey == 13 .OR. nKey == 10
         nKey := -1
      ENDIF
      nNow := hb_milliseconds()
      IF s_nLastKeyMs > 0 .AND. ( nNow - s_nLastKeyMs ) < 50
         lBurst := .T.
      ENDIF
      s_nLastKeyMs := nNow
      // any non-Esc key cancels a pending first-Esc -- double-tap must
      // be back-to-back, not Esc+other+Esc many seconds later
      IF nKey != -13 .AND. s_nLastEscMs > 0
         s_nLastEscMs := 0
      ENDIF
      // when a suggestion is active, the next key either accepts it (Tab/Enter)
      // or cancels it (any edit). Tab/Backspace/Delete are handled here in full;
      // Enter and printable keys clear the suggestion flag (and buffer for
      // printable) then fall through to the main DO CASE below.
      IF AGIN_HasSuggestion( oEd )
         DO CASE
         CASE nKey == -12                    // Tab: accept the suggestion text
            AGIN_ClearSuggestion( oEd )
            oEd[ "cursor" ] := hb_UTF8Len( oEd[ "buf" ] )
            lDrained := .T.
            LOOP
         CASE nKey == -1                     // Enter: submit the suggestion
            AGIN_ClearSuggestion( oEd )
         CASE nKey == -2 .OR. nKey == -7     // Backspace/Delete: cancel
            AGIN_ClearSuggestion( oEd )
            oEd[ "buf" ] := ""
            oEd[ "cursor" ] := 0
            lDrained := .T.
            LOOP
         CASE nKey > 0 .OR. nKey == -11 .OR. nKey == -9 .OR. nKey == -10
            AGIN_ClearSuggestion( oEd )
            oEd[ "buf" ] := ""
            oEd[ "cursor" ] := 0
         ENDCASE
      ENDIF
      DO CASE
      CASE nKey == -13                       // Esc -> interrupt, no message
         // Double-tap detection: a second Esc within AGPROMPT_DBLESC_MS ms
         // becomes "rewind" instead of plain "esc". The REPL converts
         // that into a /rewind conversation undo at the idle prompt.
         IF s_nLastEscMs > 0 .AND. ;
            ( hb_milliseconds() - s_nLastEscMs ) <= AGPROMPT_DBLESC_MS
            oPrompt[ "interrupt" ] := { "kind" => "rewind", "text" => "" }
            s_nLastEscMs := 0
         ELSE
            oPrompt[ "interrupt" ] := { "kind" => "esc", "text" => "" }
            s_nLastEscMs := hb_milliseconds()
         ENDIF
         cAction := "interrupt"
      CASE nKey == -1                        // Enter -> classify the buffer
         // expand a paste placeholder back to its real content before
         // classifying, so /btw or commands inside the paste still work
         cSubmit := oEd[ "buf" ]
         IF hb_HHasKey( oPrompt, "paste" ) .AND. ;
            !Empty( oPrompt[ "paste" ] ) .AND. ;
            AGPROMPT_IsPlaceholder( cSubmit )
            cSubmit := oPrompt[ "paste" ]
         ENDIF
         hC := AGPROMPT_Classify( cSubmit )
         DO CASE
         CASE hC[ "action" ] == "empty"
            // ignore
         CASE hC[ "action" ] == "btw"
            oPrompt[ "interrupt" ] := { "kind" => "btw", "text" => hC[ "text" ] }
            cAction := "interrupt"
            AGIN_HistoryAdd( hC[ "text" ] )
         OTHERWISE
            AGPROMPT_Enqueue( oPrompt, hC[ "text" ] )
            cAction := "queued"
            AGIN_HistoryAdd( hC[ "text" ] )
         ENDCASE
         AGIN_HistoryReset()
         IF hb_HHasKey( oPrompt, "paste" )
            hb_HDel( oPrompt, "paste" )
         ENDIF
         oPrompt[ "editor" ] := AGIN_New( "" )
         oEd := oPrompt[ "editor" ]
      CASE nKey == -2                          // Backspace
         // Backspace on a paste placeholder clears the paste entirely
         IF hb_HHasKey( oPrompt, "paste" ) .AND. ;
            AGPROMPT_IsPlaceholder( oEd[ "buf" ] )
            hb_HDel( oPrompt, "paste" )
            oEd[ "buf" ] := ""
            oEd[ "cursor" ] := 0
         ELSE
            AGIN_Backspace( oEd )
         ENDIF
      CASE nKey == -3 ; AGIN_Left( oEd )
      CASE nKey == -4 ; AGIN_Right( oEd )
      CASE nKey == -5 ; AGIN_Home( oEd )
      CASE nKey == -6 ; AGIN_End( oEd )
      CASE nKey == -7 ; AGIN_Delete( oEd )
      CASE nKey == -9                          // Up -> previous history entry
         cHist := AGIN_HistoryPrev( oEd[ "buf" ] )
         IF cHist != NIL
            oEd[ "buf" ] := cHist
            oEd[ "cursor" ] := hb_UTF8Len( cHist )
         ENDIF
      CASE nKey == -10                         // Down -> next history entry
         cHist := AGIN_HistoryNext( oEd[ "buf" ] )
         IF cHist != NIL
            oEd[ "buf" ] := cHist
            oEd[ "cursor" ] := hb_UTF8Len( cHist )
         ENDIF
      CASE nKey == -11 ; AGIN_Insert( oEd, Chr(10) )   // Shift+Enter -> newline
      CASE nKey > 0 ; AGIN_Insert( oEd, AGCON_PrintableText( nKey ) )
      // other keys (Tab, Ctrl+C, unmapped) are ignored mid-prompt
      ENDCASE
      // Repaint after every key so the user sees input immediately.
      // (Batching at the end failed to run under some WSL drain paths.)
      IF nKey != -1 .OR. cAction == "none"
         AGPROMPT_Redraw( oPrompt )
      ENDIF
      IF cAction == "interrupt"
         EXIT   // stop draining once an interrupt is seen
      ENDIF
      // After Enter queued a message, stop draining so the REPL can run it
      IF cAction == "queued"
         // Ensure the box shows empty after submit (Enter path may skip
         // the per-key redraw when nKey == -1).
         AGPROMPT_Redraw( oPrompt )
         EXIT
      ENDIF
   ENDDO
   // post-burst paste collapse: after the burst ends, if the editor buffer
   // has newlines AND the burst flagged itself as a paste, stash the real
   // content and show a tidy "[pasted N lines text]" placeholder instead.
   IF lDrained .AND. lBurst .AND. ;
      !hb_HHasKey( oPrompt, "paste" ) .AND. ;
      Chr(10) $ oEd[ "buf" ] .AND. !AGPROMPT_IsPlaceholder( oEd[ "buf" ] )
      nLines := Len( hb_ATokens( oEd[ "buf" ], Chr(10) ) )
      oPrompt[ "paste" ] := oEd[ "buf" ]
      cPlaceholder := "[pasted " + LTrim( Str( nLines ) ) + " lines text]"
      oEd[ "buf" ] := cPlaceholder
      oEd[ "cursor" ] := hb_UTF8Len( cPlaceholder )
   ENDIF
   // only redraw when a key actually changed something -- an idle poll loop
   // must not repaint 50x/second
   IF lDrained
      AGPROMPT_Redraw( oPrompt )
   ENDIF
   RETURN cAction
