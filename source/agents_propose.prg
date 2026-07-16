// ccpropose: the multi-row proposal selector used by the propose_agents
// tool. Pure state + raw-key I/O loop; the block rendering lives in
// AGUI_ProposeBlock (ccui.prg) so it can reuse AGUI_Color and the palette.

// Builds a fresh selector state from a list of {agent_type, prompt}
// proposals. All proposals start marked as accepted; the user toggles
// off any they want to drop. Cursor starts on the first row.
FUNCTION AGPROPOSE_New( aProposals )
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

// Moves the cursor by nDelta rows, wrapping around (consistent with AGSEL).
FUNCTION AGPROPOSE_Move( oSel, nDelta )
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
FUNCTION AGPROPOSE_Toggle( oSel )
   IF !Empty( oSel[ "items" ] )
      oSel[ "items" ][ oSel[ "cursor" ] ][ "accepted" ] := ;
         !oSel[ "items" ][ oSel[ "cursor" ] ][ "accepted" ]
   ENDIF
   RETURN oSel

// Returns an array of the {type, prompt} hashes the user accepted (in
// original order, only the ones still marked accepted).
FUNCTION AGPROPOSE_Accepted( oSel )
   LOCAL aOut := {}, h
   FOR EACH h IN oSel[ "items" ]
      IF h[ "accepted" ]
         AAdd( aOut, { "agent_type" => h[ "type" ], "prompt" => h[ "prompt" ] } )
      ENDIF
   NEXT
   RETURN aOut

// Writes bytes to stdout, bypassing AGREPL_Out's line rewriting.
STATIC FUNCTION AGPROPOSE_Raw( cText )
   FWrite( hb_GetStdOut(), cText )
   RETURN NIL

// Paints the proposal block. With the box mounted, it sits in absolute
// rows at the bottom of the scroll region (just like AGSEL_Paint).
STATIC FUNCTION AGPROPOSE_Paint( oSel, lRepaint )
   LOCAL nLines, cPre := "", oPrompt, hReg, nTop, aLines, i, cOut, nCols
   LOCAL cSep, cLabel
   oPrompt := AGREPL_BoxPrompt()
   nCols := AGREPL_Cols()
   IF oPrompt != NIL .AND. ;
      ValType( oPrompt[ "region" ] ) == "H" .AND. ;
      oPrompt[ "region" ][ "active" ] == .T.
      // Pin the box first so the selector has a stable anchor.
      AGPROMPT_ForcePin( oPrompt )
      hReg := oPrompt[ "region" ]
      cSep := AGUI_Color( Replicate( Chr(226)+Chr(148)+Chr(128), ;
                                     hReg[ "cols" ] - 1 ), ;
                          AGUI_Pal( "bash_header" ) )
      cLabel := AGUI_Color( " Propose agents", AGUI_Pal( "bash_header" ) )
      aLines := hb_ATokens( AGUI_ProposeBlock( oSel ), Chr(10) )
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
      cOut += AGREPL_BoxCursorSeq()
      AGPROPOSE_Raw( cOut )
      RETURN NIL
   ENDIF
   // No box (cooked / tests): LF-driven layout, relative repaint
   nLines := Len( oSel[ "items" ] ) + 5
   IF lRepaint
      cPre := Chr(27) + "[" + LTrim( Str( nLines ) ) + "A"
   ENDIF
   AGPROPOSE_Raw( cPre + AGUI_ProposeBlock( oSel ) )
   HB_SYMBOL_UNUSED( nCols )
   RETURN NIL

// Runs the proposal selector interactively. Returns the array of accepted
// proposals (possibly empty if the user rejected all but confirmed), or
// NIL if the user cancelled with Esc. With no console it auto-accepts
// every proposal so non-interactive runs do not stall.
FUNCTION AGPROPOSE_Run( oSel )
   LOCAL nKey, lDone := .F., lCancel := .F.
   IF !AGCON_HasConsole()
      RETURN AGPROPOSE_Accepted( oSel )
   ENDIF
   IF Empty( oSel[ "items" ] )
      RETURN {}
   ENDIF
   AGPROPOSE_Paint( oSel, .F. )
   DO WHILE !lDone
      DO WHILE !AGCON_KeyPending()
         hb_idleSleep( 0.02 )
      ENDDO
      nKey := AGCON_ReadKey()
      DO CASE
      CASE nKey == -9                       // Up
         AGPROPOSE_Move( oSel, -1 )
      CASE nKey == -10                      // Down
         AGPROPOSE_Move( oSel, 1 )
      CASE nKey == 32                       // Space -> toggle current row
         AGPROPOSE_Toggle( oSel )
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
         AGPROPOSE_Paint( oSel, .T. )
      ENDIF
   ENDDO
   IF lCancel
      RETURN NIL
   ENDIF
   RETURN AGPROPOSE_Accepted( oSel )
