// ccpropose: the multi-row proposal selector used by the propose_agents
// tool. Pure state + raw-key I/O loop; the block rendering lives in
// CCUI_ProposeBlock (ccui.prg) so it can reuse CCUI_Color and the palette.

// Builds a fresh selector state from a list of {agent_type, prompt}
// proposals. All proposals start marked as accepted; the user toggles
// off any they want to drop. Cursor starts on the first row.
FUNCTION CCPROPOSE_New( aProposals )
   LOCAL aItems := {}, h, cType, cPrompt
   IF ValType( aProposals ) == "A"
      FOR EACH h IN aProposals
         IF ValType( h ) == "H"
            cType := hb_HGetDef( h, "agent_type", "explore" )
            IF !( cType == "explore" .OR. cType == "general" )
               cType := "explore"
            ENDIF
            cPrompt := hb_CStr( hb_HGetDef( h, "prompt", "" ) )
            IF !Empty( cPrompt )
               AAdd( aItems, { "type" => cType, ;
                               "prompt" => cPrompt, ;
                               "accepted" => .T. } )
            ENDIF
         ENDIF
      NEXT
   ENDIF
   RETURN { "items" => aItems, "cursor" => 1 }

// Moves the cursor by nDelta rows, wrapping around (consistent with CCSEL).
FUNCTION CCPROPOSE_Move( oSel, nDelta )
   LOCAL nMax := Len( oSel[ "items" ] )
   LOCAL n
   IF nMax <= 0
      RETURN oSel
   ENDIF
   n := oSel[ "cursor" ] + nDelta
   DO WHILE n < 1
      n += nMax
   ENDDO
   DO WHILE n > nMax
      n -= nMax
   ENDDO
   oSel[ "cursor" ] := n
   RETURN oSel

// Toggles accepted on the highlighted row.
FUNCTION CCPROPOSE_Toggle( oSel )
   IF !Empty( oSel[ "items" ] )
      oSel[ "items" ][ oSel[ "cursor" ] ][ "accepted" ] := ;
         !oSel[ "items" ][ oSel[ "cursor" ] ][ "accepted" ]
   ENDIF
   RETURN oSel

// Returns an array of the {type, prompt} hashes the user accepted (in
// original order, only the ones still marked accepted).
FUNCTION CCPROPOSE_Accepted( oSel )
   LOCAL aOut := {}, h
   FOR EACH h IN oSel[ "items" ]
      IF h[ "accepted" ]
         AAdd( aOut, { "agent_type" => h[ "type" ], "prompt" => h[ "prompt" ] } )
      ENDIF
   NEXT
   RETURN aOut

// Writes bytes to stdout, bypassing CCREPL_Out's line rewriting.
STATIC FUNCTION CCPROPOSE_Raw( cText )
   FWrite( hb_GetStdOut(), cText )
   RETURN NIL

// Paints the proposal block. With the box mounted, it sits in absolute
// rows at the bottom of the scroll region (just like CCSEL_Paint).
STATIC FUNCTION CCPROPOSE_Paint( oSel, lRepaint )
   LOCAL nLines, cPre := "", oPrompt, hReg, nTop, aLines, i, cOut, nCols
   LOCAL cSep, cLabel
   oPrompt := CCREPL_BoxPrompt()
   nCols := CCREPL_Cols()
   IF oPrompt != NIL .AND. ;
      ValType( oPrompt[ "region" ] ) == "H" .AND. ;
      oPrompt[ "region" ][ "active" ] == .T.
      // Pin the box first so the selector has a stable anchor.
      CCPROMPT_ForcePin( oPrompt )
      hReg := oPrompt[ "region" ]
      cSep := CCUI_Color( Replicate( Chr(226)+Chr(148)+Chr(128), ;
                                     hReg[ "cols" ] - 1 ), ;
                          CCUI_Pal( "bash_header" ) )
      cLabel := CCUI_Color( " Propose agents", CCUI_Pal( "bash_header" ) )
      aLines := hb_ATokens( CCUI_ProposeBlock( oSel ), Chr(10) )
      hb_AIns( aLines, 1, cSep, .T. )
      hb_AIns( aLines, 2, cLabel, .T. )
      hb_AIns( aLines, 3, "", .T. )
      nLines := Len( aLines )
      // anchor the block just above the (now pinned) box
      nTop := hReg[ "box_top" ] - nLines
      IF nTop < 1
         nTop := 1
      ENDIF
      cOut := ""
      // first paint: scroll the region up by nLines so prior output stays
      // visible above the block
      IF !lRepaint
         cOut += Chr(27) + "[" + LTrim( Str( hReg[ "scroll_bottom" ] ) ) + ;
                 ";1H" + Replicate( Chr(10), nLines )
      ENDIF
      FOR i := 1 TO nLines
         cOut += Chr(27) + "[" + LTrim( Str( nTop + i - 1 ) ) + ";1H" + ;
                 Chr(27) + "[2K" + ;
                 iif( i <= Len( aLines ), aLines[ i ], "" )
      NEXT
      cOut += CCREPL_BoxCursorSeq()
      CCPROPOSE_Raw( cOut )
      RETURN NIL
   ENDIF
   // No box (cooked / tests): LF-driven layout, relative repaint
   nLines := Len( oSel[ "items" ] ) + 5
   IF lRepaint
      cPre := Chr(27) + "[" + LTrim( Str( nLines ) ) + "A"
   ENDIF
   CCPROPOSE_Raw( cPre + CCUI_ProposeBlock( oSel ) )
   HB_SYMBOL_UNUSED( nCols )
   RETURN NIL

// Runs the proposal selector interactively. Returns the array of accepted
// proposals (possibly empty if the user rejected all but confirmed), or
// NIL if the user cancelled with Esc. With no console it auto-accepts
// every proposal so non-interactive runs do not stall.
FUNCTION CCPROPOSE_Run( oSel )
   LOCAL nKey, lDone := .F., lCancel := .F.
   IF !CCCON_HasConsole()
      RETURN CCPROPOSE_Accepted( oSel )
   ENDIF
   IF Empty( oSel[ "items" ] )
      RETURN {}
   ENDIF
   CCPROPOSE_Paint( oSel, .F. )
   DO WHILE !lDone
      DO WHILE !CCCON_KeyPending()
         hb_idleSleep( 0.02 )
      ENDDO
      nKey := CCCON_ReadKey()
      DO CASE
      CASE nKey == -9                       // Up
         CCPROPOSE_Move( oSel, -1 )
      CASE nKey == -10                      // Down
         CCPROPOSE_Move( oSel, 1 )
      CASE nKey == 32                       // Space -> toggle current row
         CCPROPOSE_Toggle( oSel )
      CASE nKey == 65 .OR. nKey == 97       // A / a -> accept all
         AEval( oSel[ "items" ], {| h | h[ "accepted" ] := .T. } )
      CASE nKey == 78 .OR. nKey == 110      // N / n -> reject all
         AEval( oSel[ "items" ], {| h | h[ "accepted" ] := .F. } )
      CASE nKey == -1                       // Enter -> confirm
         lDone := .T.
      CASE nKey == -13                      // Esc -> cancel
         lCancel := .T.
         lDone := .T.
      ENDCASE
      IF !lDone
         CCPROPOSE_Paint( oSel, .T. )
      ENDIF
   ENDDO
   IF lCancel
      RETURN NIL
   ENDIF
   RETURN CCPROPOSE_Accepted( oSel )
