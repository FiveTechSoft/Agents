// Streaming, line-buffered markdown-to-ANSI renderer for the assistant's
// reply. The reply arrives as text deltas; this renders each line once it is
// complete, mirroring the SSE parser pattern. It also captures the
// "Suggested next:" marker line. Never throws: unrecognised text is emitted
// unchanged, and with colour off (AGUI_ColorOn() false) markers are stripped
// but no ANSI codes are produced.

// Creates a fresh render state.
FUNCTION AGMD_New()
   RETURN { "buf" => "", "fence" => .F., "suggestion" => "" }

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
      cSplit := AGMD_SplitBulletRun( cLine )
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
// same bullet-run split as AGMD_Feed so a list that arrived without any
// terminating newline still renders one item per line.
FUNCTION AGMD_Flush( oSt )
   LOCAL cOut := "", cSplit, aParts, cPart
   IF Len( oSt[ "buf" ] ) > 0
      cSplit := AGMD_SplitBulletRun( oSt[ "buf" ] )
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
   RETURN cOut

// Returns the captured suggested next prompt, or "".
FUNCTION AGMD_Suggestion( oSt )
   RETURN oSt[ "suggestion" ]

// Renders one line (no trailing newline supplied); the result ends in LF.
STATIC FUNCTION AGMD_RenderLine( oSt, cLine )
   LOCAL cTrim, cRest, nH, cList, nSuggest
   cLine := StrTran( cLine, Chr(13), "" )
   cTrim := AllTrim( cLine )

   // suggested-prompt marker -> captured, never printed.
   // Some models emit it on the same line as the final sentence
   // (no leading newline), so also check for a mid-line occurrence.
   IF Len( cTrim ) >= 15 .AND. Lower( Left( cTrim, 15 ) ) == "suggested next:"
      oSt[ "suggestion" ] := AllTrim( SubStr( cTrim, 16 ) )
      RETURN ""
   ENDIF
   nSuggest := hb_At( "suggested next:", Lower( cTrim ) )
   IF nSuggest > 1
      oSt[ "suggestion" ] := AllTrim( SubStr( cTrim, nSuggest + 15 ) )
      RETURN AllTrim( Left( cTrim, nSuggest - 1 ) ) + Chr(10)
   ENDIF

   // fenced code block toggle (``` optionally followed by a language tag)
   IF Left( cTrim, 3 ) == "```"
      oSt[ "fence" ] := !oSt[ "fence" ]
      RETURN ""
   ENDIF
   IF oSt[ "fence" ]
      RETURN "  " + AGUI_Color( cLine, "90" ) + Chr(10)
   ENDIF

   // blank line
   IF Empty( cTrim )
      RETURN Chr(10)
   ENDIF

   // heading
   nH := AGMD_HeadingLevel( cTrim )
   IF nH > 0
      cRest := AllTrim( SubStr( cTrim, nH + 1 ) )
      RETURN AGUI_Color( cRest, "1" ) + Chr(10)
   ENDIF

   // list item
   cList := AGMD_ListRender( cTrim )
   IF cList != NIL
      RETURN cList + Chr(10)
   ENDIF

   // paragraph
   RETURN AGMD_Inline( cLine ) + Chr(10)

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
