// Line-level diff between two texts, rendered Claude Code style: a header
// "Added N lines, removed M lines" followed by hunks of changed lines with
// 3 lines of context, each line prefixed with a line number and a +/-/space
// marker. Pure: no colour, no I/O -- the display layer colours it.

// Returns the diff text for cOld -> cNew.
FUNCTION CCDIFF_Lines( cOld, cNew )
   LOCAL aOps, op, nAdd := 0, nDel := 0, cHdr
   aOps := CCDIFF_Ops( CCDIFF_Split( cOld ), CCDIFF_Split( cNew ) )
   FOR EACH op IN aOps
      DO CASE
      CASE op[ "t" ] == "add"
         nAdd++
      CASE op[ "t" ] == "del"
         nDel++
      ENDCASE
   NEXT
   cHdr := "Added " + LTrim( Str( nAdd ) ) + " line" + iif( nAdd == 1, "", "s" ) + ;
           ", removed " + LTrim( Str( nDel ) ) + " line" + iif( nDel == 1, "", "s" )
   RETURN cHdr + Chr(10) + CCDIFF_Format( aOps )

// Splits text into a line array, dropping CR. Empty text is zero lines.
STATIC FUNCTION CCDIFF_Split( cText )
   cText := StrTran( hb_CStr( cText ), Chr(13), "" )
   IF Len( cText ) == 0
      RETURN {}
   ENDIF
   RETURN hb_ATokens( cText, Chr(10) )

// Diffs two line arrays via a longest-common-subsequence table; returns an
// array of ops { t => "ctx"|"add"|"del", o => oldLineNo, n => newLineNo, x => text }.
STATIC FUNCTION CCDIFF_Ops( aOld, aNew )
   LOCAL nO := Len( aOld ), nN := Len( aNew ), aC, i, j, aOps := {}
   aC := Array( nO + 1 )
   FOR i := 1 TO nO + 1
      aC[ i ] := Array( nN + 1 )
      AFill( aC[ i ], 0 )
   NEXT
   FOR i := nO TO 1 STEP -1
      FOR j := nN TO 1 STEP -1
         IF aOld[ i ] == aNew[ j ]
            aC[ i ][ j ] := aC[ i + 1 ][ j + 1 ] + 1
         ELSE
            aC[ i ][ j ] := Max( aC[ i + 1 ][ j ], aC[ i ][ j + 1 ] )
         ENDIF
      NEXT
   NEXT
   i := 1
   j := 1
   DO WHILE i <= nO .AND. j <= nN
      IF aOld[ i ] == aNew[ j ]
         AAdd( aOps, { "t" => "ctx", "o" => i, "n" => j, "x" => aOld[ i ] } )
         i++
         j++
      ELSEIF aC[ i + 1 ][ j ] >= aC[ i ][ j + 1 ]
         AAdd( aOps, { "t" => "del", "o" => i, "n" => 0, "x" => aOld[ i ] } )
         i++
      ELSE
         AAdd( aOps, { "t" => "add", "o" => 0, "n" => j, "x" => aNew[ j ] } )
         j++
      ENDIF
   ENDDO
   DO WHILE i <= nO
      AAdd( aOps, { "t" => "del", "o" => i, "n" => 0, "x" => aOld[ i ] } )
      i++
   ENDDO
   DO WHILE j <= nN
      AAdd( aOps, { "t" => "add", "o" => 0, "n" => j, "x" => aNew[ j ] } )
      j++
   ENDDO
   RETURN aOps

// Formats the ops: changed lines plus 3 context lines each side, capped.
STATIC FUNCTION CCDIFF_Format( aOps )
   LOCAL n := Len( aOps ), aShow, i, k, cOut := "", nShown := 0
   LOCAL nCtx := 3, nCap := 60
   IF n == 0
      RETURN "(no changes)"
   ENDIF
   aShow := Array( n )
   AFill( aShow, .F. )
   FOR i := 1 TO n
      IF aOps[ i ][ "t" ] != "ctx"
         FOR k := Max( 1, i - nCtx ) TO Min( n, i + nCtx )
            aShow[ k ] := .T.
         NEXT
      ENDIF
   NEXT
   FOR i := 1 TO n
      IF !aShow[ i ]
         LOOP
      ENDIF
      IF nShown >= nCap
         cOut += "... (diff truncated)" + Chr(10)
         EXIT
      ENDIF
      cOut += CCDIFF_Line( aOps[ i ] ) + Chr(10)
      nShown++
   NEXT
   IF Empty( cOut )
      RETURN "(no changes)"
   ENDIF
   RETURN cOut

// Formats one op: "<6-wide line number> <marker> <text>". Added lines carry
// the new line number, deleted lines the old one, context the new one.
STATIC FUNCTION CCDIFF_Line( op )
   LOCAL nNum, cMark
   DO CASE
   CASE op[ "t" ] == "add"
      nNum := op[ "n" ]
      cMark := "+"
   CASE op[ "t" ] == "del"
      nNum := op[ "o" ]
      cMark := "-"
   OTHERWISE
      nNum := op[ "n" ]
      cMark := " "
   ENDCASE
   RETURN Str( nNum, 6 ) + " " + cMark + " " + op[ "x" ]
