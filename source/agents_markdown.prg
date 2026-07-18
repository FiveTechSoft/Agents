// Streaming, line-buffered markdown-to-ANSI renderer for the assistant's
// reply. The reply arrives as text deltas; this renders each line once it is
// complete, mirroring the SSE parser pattern. It also captures the
// "Suggested next:" marker line. Never throws: unrecognised text is emitted
// unchanged, and with colour off (AGUI_ColorOn() false) markers are stripped
// but no ANSI codes are produced.
//
// Supported blocks: headings, lists, fenced code, **bold** / *italic* / `code`,
// and GitHub-style pipe tables (including models that smash rows onto one
// line with "||" instead of newlines).

// Creates a fresh render state.
FUNCTION AGMD_New()
   RETURN { "buf" => "", "fence" => .F., "suggestion" => "", ;
            "table" => {} }

// Appends a chunk; renders every line completed by a newline. Returns the
// rendered ANSI text for those lines ("" when only a partial line is
// buffered). Defensive against models that emit a list as a single line
// with "- " markers joining items but no real newlines: such a line is
// detected and split into one bullet per virtual line before rendering.
FUNCTION AGMD_Feed( oSt, cChunk )
   LOCAL cOut := "", nNL, cLine, cSplit, aParts, cPart
   oSt[ "buf" ] += hb_CStr( cChunk )
   DO WHILE ( nNL := At( Chr(10), oSt[ "buf" ] ) ) > 0
      cLine := Left( oSt[ "buf" ], nNL - 1 )
      oSt[ "buf" ] := SubStr( oSt[ "buf" ], nNL + 1 )
      cSplit := AGMD_PreSplit( cLine )
      IF Chr(10) $ cSplit
         aParts := hb_ATokens( cSplit, Chr(10) )
         FOR EACH cPart IN aParts
            cOut += AGMD_RenderLine( oSt, cPart )
         NEXT
      ELSE
         cOut += AGMD_RenderLine( oSt, cLine )
      ENDIF
   ENDDO
   RETURN cOut

// Pre-process a physical line: unsmash tables / headings jammed without LF,
// then bullet-run split.
STATIC FUNCTION AGMD_PreSplit( cLine )
   LOCAL c
   c := AGMD_SplitTableRun( cLine )
   c := AGMD_SplitHeadingJam( c )
   c := AGMD_SplitBulletRun( c )
   RETURN c

// Models often emit whole tables as one line:
//   | A | B ||---|---|| a | b |
// Turn "||" row boundaries into real newlines.
STATIC FUNCTION AGMD_SplitTableRun( cLine )
   LOCAL cTrim := AllTrim( cLine )
   IF Empty( cTrim )
      RETURN cLine
   ENDIF
   // Only rewrite when it looks like a pipe table (starts with |, has ---).
   IF !( Left( cTrim, 1 ) == "|" .AND. "---" $ cTrim .AND. "||" $ cTrim )
      // Also split multi-row tables without separator if many || appear.
      IF !( Left( cTrim, 1 ) == "|" .AND. "||" $ cTrim )
         RETURN cLine
      ENDIF
      // Require at least two || to avoid splitting cells with empty middle.
      IF Len( hb_ATokens( cTrim, "||" ) ) < 3
         RETURN cLine
      ENDIF
   ENDIF
   RETURN StrTran( cTrim, "||", "|" + Chr(10) + "|" )

// "text---### Heading" or "text:### Heading" → break before heading / rule.
STATIC FUNCTION AGMD_SplitHeadingJam( cLine )
   LOCAL c := cLine, n, cOut := ""
   // ---###  or ---## 
   DO WHILE ( n := hb_At( "---#", c ) ) > 0
      cOut += Left( c, n - 1 ) + Chr(10) + "---" + Chr(10)
      c := SubStr( c, n + 3 )   // keep leading #
   ENDDO
   c := cOut + c
   cOut := ""
   // jammed "### " not at start (after non-space)
   n := 2
   DO WHILE n <= Len( c ) - 3
      IF SubStr( c, n, 4 ) == "### " .OR. SubStr( c, n, 3 ) == "## " .OR. ;
         SubStr( c, n, 2 ) == "# "
         // only if previous char is not newline and looks like jam
         IF SubStr( c, n - 1, 1 ) != Chr(10) .AND. ;
            SubStr( c, n - 1, 1 ) != " "
            cOut += Left( c, n - 1 ) + Chr(10)
            c := SubStr( c, n )
            n := 2
            LOOP
         ENDIF
      ENDIF
      n++
   ENDDO
   RETURN cOut + c

// When a line starts with a bullet marker AND contains 3+ further inline
// marker occurrences (with or without a leading space), the model
// concatenated a list into one line without newlines. Split it so each
// item becomes its own virtual line, preserving the marker on every
// line. Returns the original cLine when no split is needed.
STATIC FUNCTION AGMD_SplitBulletRun( cLine )
   LOCAL cMark := "", aParts, i, cResult, nStart
   IF Left( cLine, 2 ) == "- "
      cMark := "- "
   ELSEIF Left( cLine, 2 ) == "* "
      cMark := "* "
   ELSEIF Left( cLine, 2 ) == "+ "
      cMark := "+ "
   ENDIF
   IF Empty( cMark )
      RETURN cLine
   ENDIF
   // hb_ATokens("- a- b- c", "- ") returns { "", "a", "b", "c" }; require
   // 4+ tokens (so at least 3 inline items) to avoid splitting a regular
   // single bullet that happens to contain "- " inside its text
   aParts := hb_ATokens( cLine, cMark )
   IF Len( aParts ) < 4
      RETURN cLine
   ENDIF
   nStart := iif( Empty( aParts[ 1 ] ), 2, 1 )
   cResult := cMark + aParts[ nStart ]
   FOR i := nStart + 1 TO Len( aParts )
      cResult += Chr(10) + cMark + aParts[ i ]
   NEXT
   RETURN cResult

// Renders any buffered partial line (call at end of stream). Applies the
// same pre-splits as AGMD_Feed so a list/table that arrived without any
// terminating newline still renders one item per line.
FUNCTION AGMD_Flush( oSt )
   LOCAL cOut := "", cSplit, aParts, cPart
   IF Len( oSt[ "buf" ] ) > 0
      cSplit := AGMD_PreSplit( oSt[ "buf" ] )
      oSt[ "buf" ] := ""
      IF Chr(10) $ cSplit
         aParts := hb_ATokens( cSplit, Chr(10) )
         FOR EACH cPart IN aParts
            cOut += AGMD_RenderLine( oSt, cPart )
         NEXT
      ELSE
         cOut := AGMD_RenderLine( oSt, cSplit )
      ENDIF
   ENDIF
   // Flush any open pipe table.
   cOut += AGMD_TableFlush( oSt )
   RETURN cOut

// Returns the captured suggested next prompt, or "".
FUNCTION AGMD_Suggestion( oSt )
   RETURN oSt[ "suggestion" ]

// Renders one line (no trailing newline supplied); the result ends in LF.
STATIC FUNCTION AGMD_RenderLine( oSt, cLine )
   LOCAL cTrim, cRest, nH, cList, nSuggest, aCells, cTab
   cLine := StrTran( cLine, Chr(13), "" )
   cTrim := AllTrim( cLine )

   // suggested-prompt marker -> captured, never printed.
   // Some models emit it on the same line as the final sentence
   // (no leading newline), so also check for a mid-line occurrence.
   IF Len( cTrim ) >= 15 .AND. Lower( Left( cTrim, 15 ) ) == "suggested next:"
      oSt[ "suggestion" ] := AllTrim( SubStr( cTrim, 16 ) )
      RETURN AGMD_TableFlush( oSt )
   ENDIF
   nSuggest := hb_At( "suggested next:", Lower( cTrim ) )
   IF nSuggest > 1
      oSt[ "suggestion" ] := AllTrim( SubStr( cTrim, nSuggest + 15 ) )
      RETURN AGMD_TableFlush( oSt ) + ;
             AllTrim( Left( cTrim, nSuggest - 1 ) ) + Chr(10)
   ENDIF

   // fenced code block toggle (``` optionally followed by a language tag)
   IF Left( cTrim, 3 ) == "```"
      cTab := AGMD_TableFlush( oSt )
      oSt[ "fence" ] := !oSt[ "fence" ]
      RETURN cTab
   ENDIF
   IF oSt[ "fence" ]
      RETURN "  " + AGUI_Color( cLine, "90" ) + Chr(10)
   ENDIF

   // blank line
   IF Empty( cTrim )
      RETURN AGMD_TableFlush( oSt ) + Chr(10)
   ENDIF

   // pipe table row (including separator |---|)
   aCells := AGMD_ParseTableRow( cTrim )
   IF aCells != NIL
      AAdd( oSt[ "table" ], aCells )
      RETURN ""
   ENDIF
   // Leaving table mode: flush buffered rows first.
   cTab := AGMD_TableFlush( oSt )

   // horizontal rule
   IF AGMD_IsRule( cTrim )
      RETURN cTab + AGUI_Color( Replicate( Chr(226)+Chr(148)+Chr(128), ;
             Min( 40, AGREPL_Cols() - 4 ) ), "90" ) + Chr(10)
   ENDIF

   // heading
   nH := AGMD_HeadingLevel( cTrim )
   IF nH > 0
      cRest := AllTrim( SubStr( cTrim, nH + 1 ) )
      RETURN cTab + AGUI_Color( cRest, "1" ) + Chr(10)
   ENDIF

   // list item
   cList := AGMD_ListRender( cTrim )
   IF cList != NIL
      RETURN cTab + cList + Chr(10)
   ENDIF

   // paragraph
   RETURN cTab + AGMD_Inline( cLine ) + Chr(10)

// True for --- / *** / ___ rules (3+ of the same char).
STATIC FUNCTION AGMD_IsRule( cTrim )
   LOCAL c0, i
   IF Len( cTrim ) < 3
      RETURN .F.
   ENDIF
   c0 := Left( cTrim, 1 )
   IF !( c0 == "-" .OR. c0 == "*" .OR. c0 == "_" )
      RETURN .F.
   ENDIF
   FOR i := 1 TO Len( cTrim )
      IF SubStr( cTrim, i, 1 ) != c0 .AND. SubStr( cTrim, i, 1 ) != " "
         RETURN .F.
      ENDIF
   NEXT
   RETURN .T.

// Returns the heading level 1..6 for a "# " .. "###### " line, else 0.
STATIC FUNCTION AGMD_HeadingLevel( cTrim )
   LOCAL n := 0
   DO WHILE SubStr( cTrim, n + 1, 1 ) == "#"
      n++
   ENDDO
   IF n >= 1 .AND. n <= 6 .AND. SubStr( cTrim, n + 1, 1 ) == " "
      RETURN n
   ENDIF
   RETURN 0

// Parses a GFM table row into an array of cell strings, or NIL if not a row.
// Separator rows become { "---", "---", ... } markers.
STATIC FUNCTION AGMD_ParseTableRow( cTrim )
   LOCAL aRaw, aCells := {}, c, i, lSep := .T., cCell
   IF Left( cTrim, 1 ) != "|" .AND. Right( cTrim, 1 ) != "|"
      // also allow rows that only start with |
      IF Left( cTrim, 1 ) != "|"
         RETURN NIL
      ENDIF
   ENDIF
   IF Left( cTrim, 1 ) != "|"
      RETURN NIL
   ENDIF
   // Must have at least two pipes.
   IF hb_At( "|", SubStr( cTrim, 2 ) ) == 0
      RETURN NIL
   ENDIF
   aRaw := hb_ATokens( cTrim, "|" )
   // hb_ATokens("| a | b |", "|") → { "", " a ", " b ", "" }
   FOR i := 1 TO Len( aRaw )
      c := aRaw[ i ]
      // skip empty edge pieces from leading/trailing |
      IF i == 1 .AND. Empty( AllTrim( c ) )
         LOOP
      ENDIF
      IF i == Len( aRaw ) .AND. Empty( AllTrim( c ) )
         LOOP
      ENDIF
      cCell := AllTrim( c )
      AAdd( aCells, cCell )
      // separator cell: only dashes, colons, spaces
      IF !AGMD_IsSepCell( cCell )
         lSep := .F.
      ENDIF
   NEXT
   IF Len( aCells ) == 0
      RETURN NIL
   ENDIF
   // Pure separator row → mark specially so flush can skip it as body.
   IF lSep
      RETURN { "___SEP___" }
   ENDIF
   RETURN aCells

STATIC FUNCTION AGMD_IsSepCell( c )
   LOCAL i, ch
   IF Empty( c )
      RETURN .T.
   ENDIF
   FOR i := 1 TO Len( c )
      ch := SubStr( c, i, 1 )
      IF !( ch == "-" .OR. ch == ":" .OR. ch == " " )
         RETURN .F.
      ENDIF
   NEXT
   RETURN .T.

// Format and emit the buffered table; clear the buffer. "" if empty.
STATIC FUNCTION AGMD_TableFlush( oSt )
   LOCAL aTab, aRows := {}, aWidths := {}, aRow, i, j, nCols := 0
   LOCAL cOut := "", cLine, cCell, nW, nMaxW, nPad, cSep
   IF !hb_HHasKey( oSt, "table" ) .OR. Len( oSt[ "table" ] ) == 0
      RETURN ""
   ENDIF
   aTab := oSt[ "table" ]
   oSt[ "table" ] := {}
   // Drop separator-only rows; keep data rows (first is usually header).
   FOR i := 1 TO Len( aTab )
      IF Len( aTab[ i ] ) == 1 .AND. aTab[ i ][ 1 ] == "___SEP___"
         LOOP
      ENDIF
      AAdd( aRows, aTab[ i ] )
      IF Len( aTab[ i ] ) > nCols
         nCols := Len( aTab[ i ] )
      ENDIF
   NEXT
   IF Len( aRows ) == 0 .OR. nCols == 0
      RETURN ""
   ENDIF
   // Pad short rows; measure column widths (UTF-8 visual via AGUI_VisLen).
   FOR i := 1 TO nCols
      AAdd( aWidths, 1 )
   NEXT
   FOR i := 1 TO Len( aRows )
      DO WHILE Len( aRows[ i ] ) < nCols
         AAdd( aRows[ i ], "" )
      ENDDO
      FOR j := 1 TO nCols
         nW := AGUI_VisLen( AGMD_StripInline( aRows[ i ][ j ] ) )
         IF nW > aWidths[ j ]
            aWidths[ j ] := nW
         ENDIF
      NEXT
   NEXT
   // Cap total width to terminal (~ cols - 4); shrink widest columns.
   nMaxW := Max( 40, AGREPL_Cols() - 6 )
   AGMD_FitWidths( @aWidths, nMaxW )
   // Header row (bold) + underline + body.
   cOut += AGMD_TableFormatRow( aRows[ 1 ], aWidths, .T. ) + Chr(10)
   cSep := "  "
   FOR j := 1 TO nCols
      cSep += Replicate( "-", aWidths[ j ] )
      IF j < nCols
         cSep += "  "
      ENDIF
   NEXT
   cOut += AGUI_Color( cSep, "90" ) + Chr(10)
   FOR i := 2 TO Len( aRows )
      cOut += AGMD_TableFormatRow( aRows[ i ], aWidths, .F. ) + Chr(10)
   NEXT
   RETURN cOut + Chr(10)

// Shrink column widths so Sum(w) + gaps fits nMax.
STATIC FUNCTION AGMD_FitWidths( aWidths, nMax )
   LOCAL nSum, nGaps, nExtra, j, nWiden
   nGaps := ( Len( aWidths ) - 1 ) * 2 + 2
   DO WHILE .T.
      nSum := 0
      FOR j := 1 TO Len( aWidths )
         nSum += aWidths[ j ]
      NEXT
      IF nSum + nGaps <= nMax
         EXIT
      ENDIF
      // Shrink the widest column by 1 until it fits or all are tiny.
      nWiden := 1
      FOR j := 2 TO Len( aWidths )
         IF aWidths[ j ] > aWidths[ nWiden ]
            nWiden := j
         ENDIF
      NEXT
      IF aWidths[ nWiden ] <= 4
         EXIT
      ENDIF
      aWidths[ nWiden ] := aWidths[ nWiden ] - 1
   ENDDO
   RETURN NIL

STATIC FUNCTION AGMD_TableFormatRow( aCells, aWidths, lHeader )
   LOCAL cLine := "  ", j, cCell, nVis, nPad
   FOR j := 1 TO Len( aWidths )
      cCell := AGMD_Inline( hb_CStr( aCells[ j ] ) )
      // Truncate plain text if still too wide (approx via strip).
      IF AGUI_VisLen( AGMD_StripInline( aCells[ j ] ) ) > aWidths[ j ]
         cCell := AGUI_Color( ;
            hb_UTF8SubStr( AGMD_StripInline( aCells[ j ] ), 1, ;
               Max( 1, aWidths[ j ] - 1 ) ) + "...", ;
            iif( lHeader, "1", "0" ) )
      ELSEIF lHeader
         cCell := AGUI_Color( AGMD_StripInline( aCells[ j ] ), "1" )
      ENDIF
      nVis := AGUI_VisLen( AGMD_StripInline( ;
         iif( lHeader, AGMD_StripInline( aCells[ j ] ), aCells[ j ] ) ) )
      // Recompute visual of rendered (ANSI ignored by VisLen).
      nVis := AGUI_VisLen( cCell )
      IF nVis > aWidths[ j ]
         nPad := 0
      ELSE
         nPad := aWidths[ j ] - nVis
      ENDIF
      cLine += cCell + Space( nPad )
      IF j < Len( aWidths )
         cLine += "  "
      ENDIF
   NEXT
   RETURN cLine

// Strip ** ` * markers for width measurement (rough).
STATIC FUNCTION AGMD_StripInline( cText )
   cText := hb_CStr( cText )
   cText := StrTran( cText, "**", "" )
   cText := StrTran( cText, "`", "" )
   cText := StrTran( cText, "*", "" )
   RETURN cText

// Renders a bullet ("- ", "* ", "+ ") or numbered ("<digits>. ") list item,
// or NIL when the line is not a list item.
STATIC FUNCTION AGMD_ListRender( cTrim )
   LOCAL cMark := Left( cTrim, 2 ), nDot := 0, i, c
   LOCAL cBullet := Chr(226)+Chr(128)+Chr(162)   // U+2022 bullet
   IF cMark == "- " .OR. cMark == "* " .OR. cMark == "+ "
      RETURN "  " + AGUI_Color( cBullet, "90" ) + " " + ;
             AGMD_Inline( SubStr( cTrim, 3 ) )
   ENDIF
   FOR i := 1 TO Len( cTrim )
      c := SubStr( cTrim, i, 1 )
      IF IsDigit( c )
         LOOP
      ENDIF
      IF c == "." .AND. i > 1 .AND. SubStr( cTrim, i + 1, 1 ) == " "
         nDot := i
      ENDIF
      EXIT
   NEXT
   IF nDot > 0
      RETURN "  " + AGUI_Color( Left( cTrim, nDot ), "90" ) + " " + ;
             AGMD_Inline( SubStr( cTrim, nDot + 2 ) )
   ENDIF
   RETURN NIL

// Applies inline formatting: **bold**, `code`, *italic*. Order matters:
// ** before * so a bold pair is not split by the italic pass.
STATIC FUNCTION AGMD_Inline( cText )
   cText := AGMD_Span( cText, "**", "1" )
   cText := AGMD_Span( cText, "`", "96" )
   cText := AGMD_Span( cText, "*", "3" )
   RETURN cText

// Wraps every cDelim..cDelim span in cText with the ANSI colour cSGR.
// An unmatched trailing delimiter is left as literal text.
STATIC FUNCTION AGMD_Span( cText, cDelim, cSGR )
   LOCAL nDL := Len( cDelim ), nOpen, nClose, cResult := ""
   LOCAL cInner, cBefore
   DO WHILE ( nOpen := At( cDelim, cText ) ) > 0
      nClose := At( cDelim, SubStr( cText, nOpen + nDL ) )
      IF nClose == 0
         EXIT
      ENDIF
      cBefore := Left( cText, nOpen - 1 )
      cInner  := SubStr( cText, nOpen + nDL, nClose - 1 )
      cResult += cBefore + AGUI_Color( cInner, cSGR )
      cText := SubStr( cText, nOpen + nDL + nClose - 1 + nDL )
   ENDDO
   RETURN cResult + cText
