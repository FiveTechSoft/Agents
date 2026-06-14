// Whether CCUI_Color emits ANSI colour codes (off unless the REPL turns it on).
STATIC s_lColor := .F.

// Classifies a line of REPL input. Returns a hash with:
//   "type" => "exit"|"clear"|"help"|"init"|"model"|"cost"|"message"|"empty"
//   "text" => the trimmed line, or the command argument for "model"
FUNCTION CCUI_ParseCommand( cLine )
   LOCAL cTrim := AllTrim( hb_CStr( cLine ) )
   LOCAL cLow  := Lower( cTrim )
   DO CASE
   CASE Empty( cTrim )
      RETURN { "type" => "empty", "text" => "" }
   CASE cLow == "/exit" .OR. cLow == "/quit"
      RETURN { "type" => "exit", "text" => cTrim }
   CASE cLow == "/clear"
      RETURN { "type" => "clear", "text" => cTrim }
   CASE cLow == "/help"
      RETURN { "type" => "help", "text" => cTrim }
   CASE cLow == "/init"
      RETURN { "type" => "init", "text" => "" }
   CASE cLow == "/model" .OR. Left( cLow, 7 ) == "/model "
      RETURN { "type" => "model", "text" => AllTrim( SubStr( cTrim, 7 ) ) }
   CASE cLow == "/cost"
      RETURN { "type" => "cost", "text" => "" }
   CASE cLow == "/save" .OR. Left( cLow, 6 ) == "/save "
      RETURN { "type" => "save", "text" => AllTrim( SubStr( cTrim, 6 ) ) }
   CASE cLow == "/load" .OR. Left( cLow, 6 ) == "/load "
      RETURN { "type" => "load", "text" => AllTrim( SubStr( cTrim, 6 ) ) }
   CASE cLow == "/caveman"
      RETURN { "type" => "skill", "text" => "caveman" }
   CASE cLow == "/plan" .OR. Left( cLow, 6 ) == "/plan "
      RETURN { "type" => "plan", "text" => AllTrim( SubStr( cTrim, 6 ) ) }
   CASE cLow == "/run"
      RETURN { "type" => "run", "text" => "" }
   CASE cLow == "/demo"
      RETURN { "type" => "demo", "text" => "" }
   CASE cLow == "/sh" .OR. Left( cLow, 4 ) == "/sh " .OR. ;
        cLow == "/shell" .OR. Left( cLow, 7 ) == "/shell " .OR. ;
        cLow == "/bash" .OR. Left( cLow, 6 ) == "/bash "
      RETURN { "type" => "shx", ;
               "text" => AllTrim( SubStr( cTrim, At( " ", cTrim + " " ) ) ) }
   CASE cLow == "/git" .OR. Left( cLow, 5 ) == "/git "
      RETURN { "type" => "gitx", "text" => AllTrim( SubStr( cTrim, 5 ) ) }
   CASE cLow == "/clone" .OR. Left( cLow, 7 ) == "/clone "
      RETURN { "type" => "clonex", "text" => AllTrim( SubStr( cTrim, 7 ) ) }
   CASE cLow == "/key" .OR. Left( cLow, 5 ) == "/key "
      RETURN { "type" => "keyx", "text" => AllTrim( SubStr( cTrim, 5 ) ) }
   CASE cLow == "/skill" .OR. Left( cLow, 7 ) == "/skill "
      RETURN { "type" => "skillx", "text" => AllTrim( SubStr( cTrim, 7 ) ) }
   CASE cLow == "/tool" .OR. cLow == "/tools"
      RETURN { "type" => "toolx", "text" => "" }
   CASE cLow == "/lean" .OR. Left( cLow, 6 ) == "/lean "
      RETURN { "type" => "lean", "text" => AllTrim( SubStr( cTrim, 6 ) ) }
   CASE cLow == "/provider" .OR. Left( cLow, 10 ) == "/provider "
      RETURN { "type" => "provider", ;
               "text" => AllTrim( SubStr( cTrim, 10 ) ) }
   CASE cLow == "/goal" .OR. Left( cLow, 6 ) == "/goal "
      RETURN { "type" => "goal", "text" => AllTrim( SubStr( cTrim, 6 ) ) }
   CASE cLow == "/tasks" .OR. Left( cLow, 7 ) == "/tasks "
      RETURN { "type" => "tasks", "text" => AllTrim( SubStr( cTrim, 7 ) ) }
   CASE cLow == "/compact" .OR. Left( cLow, 9 ) == "/compact "
      RETURN { "type" => "compact", "text" => AllTrim( SubStr( cTrim, 9 ) ) }
   CASE cLow == "/ctx" .OR. Left( cLow, 5 ) == "/ctx "
      RETURN { "type" => "ctx", "text" => AllTrim( SubStr( cTrim, 5 ) ) }
   CASE cLow == "/loop" .OR. Left( cLow, 6 ) == "/loop "
      RETURN { "type" => "loop", "text" => AllTrim( SubStr( cTrim, 6 ) ) }
   CASE cLow == "/rewind" .OR. Left( cLow, 8 ) == "/rewind "
      RETURN { "type" => "rewind", "text" => AllTrim( SubStr( cTrim, 8 ) ) }
   CASE cLow == "/hook" .OR. Left( cLow, 6 ) == "/hook "
      RETURN { "type" => "hook", "text" => AllTrim( SubStr( cTrim, 6 ) ) }
   CASE cLow == "/btw" .OR. Left( cLow, 5 ) == "/btw "
      // /btw is the mid-turn interrupt classifier in the box (handled by
      // CCPROMPT_Classify); at the cooked prompt or any other path that
      // routes through here, just strip the prefix and treat the rest as
      // an ordinary message to the model.
      RETURN { "type" => "message", ;
               "text" => AllTrim( SubStr( cTrim, 6 ) ) }
   ENDCASE
   RETURN { "type" => "message", "text" => cTrim }

// The instruction sent to the agent by the /init command: it asks the model
// to inspect the project and write a CC.md file.
FUNCTION CCUI_InitPrompt()
   RETURN "Analyse this project and create a CC.md file in the working " + ;
          "directory. Use your tools to explore the repository: its layout, " + ;
          "how it is built and run, and its coding conventions. CC.md " + ;
          "should concisely cover: what the project is, how to build and run " + ;
          "it, the key directories, and the coding conventions to follow. " + ;
          "Keep it short. Write the file with your write tool, then confirm."

// Formats a session usage hash into a human-readable cost report.
// hUsage: { prompt_tokens => N, completion_tokens => N, ... }
// Pricing is approximate (DeepSeek API rates).
FUNCTION CCUI_CostReport( hUsage )
   LOCAL nIn, nOut, nHit, cOut, nCostTotal, nW := 46
   IF ValType( hUsage ) != "H" .OR. Len( hb_HKeys( hUsage ) ) == 0
      RETURN CCUI_Color( "No usage data for this session yet.", "90" ) + Chr(10)
   ENDIF
   nIn  := hb_HGetDef( hUsage, "prompt_tokens", 0 )
   nOut := hb_HGetDef( hUsage, "completion_tokens", 0 )
   nHit := Min( hb_HGetDef( hUsage, "prompt_cache_hit_tokens", 0 ), nIn )
   // DeepSeek pricing: $0.14/M input cache-miss, $0.0028/M input cache-HIT
   // (98% off), $0.28/M output. Agent loops re-send the conversation prefix
   // every step (= cache hits), so billing all input as cache-miss would
   // overstate the session cost several-fold (web-version parity).
   nCostTotal := ( nIn - nHit ) * 0.14 / 1000000 + ;
                 nHit * 0.0028 / 1000000 + nOut * 0.28 / 1000000
   // emerald metrics card, like the GUI's "Metricas de Sesion"
   cOut := CCUI_CardLine( CCUI_Color( "Session cost report", "1" ) + ;
           Space( 8 ) + CCUI_Color( "$" + LTrim( Str( nCostTotal, 10, 4 ) ), "1;97" ), ;
           "card_cost", nW ) + Chr(10)
   cOut += CCUI_CardLine( "", "card_cost", nW ) + Chr(10)
   cOut += CCUI_CardLine( "input (context):     " + ;
           LTrim( Str( nIn ) ) + " tokens", "card_cost", nW ) + Chr(10)
   IF nHit > 0
      cOut += CCUI_CardLine( CCUI_Color( "  cached (98% off):  " + ;
              LTrim( Str( nHit ) ) + " tokens", "2" ), "card_cost", nW ) + Chr(10)
   ENDIF
   cOut += CCUI_CardLine( "output (generated):  " + ;
           LTrim( Str( nOut ) ) + " tokens", "card_cost", nW ) + Chr(10)
   cOut += CCUI_CardLine( CCUI_Color( "total:               " + ;
           LTrim( Str( nIn + nOut ) ) + " tokens", "1" ), "card_cost", nW ) + Chr(10)
   RETURN cOut

// Returns the sessions directory path (.agents/sessions under the
// working directory, or CCHARBOUR_CONFIG).
FUNCTION CCUI_SessionDir()
   LOCAL cBase := hb_GetEnv( "CCHARBOUR_CONFIG" )
   IF Empty( cBase )
      cBase := hb_cwd() + hb_ps() + ".agents"
   ENDIF
   RETURN cBase + hb_ps() + "sessions"

// Ensures the sessions directory exists. Returns .T. on success.
FUNCTION CCUI_EnsureSessionDir()
   LOCAL cDir := CCUI_SessionDir()
   IF !hb_DirExists( cDir )
      RETURN hb_DirCreate( cDir )
   ENDIF
   RETURN .T.

// Returns the full path for a session name (adds .json extension).
FUNCTION CCUI_SessionPath( cName )
   RETURN CCUI_SessionDir() + hb_ps() + cName + ".json"

// Lists saved session files in the sessions directory.
// Returns an array of { name, path, mtime } hashes, or empty array.
FUNCTION CCUI_SessionList()
   LOCAL cDir := CCUI_SessionDir(), aFiles, aOut := {}, hFile, cName
   IF !hb_DirExists( cDir )
      RETURN aOut
   ENDIF
   aFiles := Directory( cDir + hb_ps() + "*.json" )
   FOR EACH hFile IN aFiles
      cName := hFile[ 1 ]
      IF Right( cName, 5 ) == ".json"
         cName := Left( cName, Len( cName ) - 5 )
      ENDIF
      AAdd( aOut, { "name" => cName, ;
                    "path" => cDir + hb_ps() + hFile[ 1 ], ;
                    "mtime" => hFile[ 3 ] } )
   NEXT
   RETURN aOut

// Formats a list of saved sessions into a human-readable string.
FUNCTION CCUI_SessionListOutput( aSessions )
   LOCAL cOut := "", hS, cTime
   IF Len( aSessions ) == 0
      RETURN CCUI_Color( "No saved sessions found.", "90" ) + Chr(10)
   ENDIF
   cOut := CCUI_Color( "Saved sessions:", "1" ) + Chr(10)
   FOR EACH hS IN aSessions
      // mtime is a DATE; DToC formats it as "yyyy-mm-dd" via SET DATE FORMAT
      // (or the locale default). Prior code did `DToS(d) + " " + d` which
      // tried to concatenate a DATE with a string and crashed with
      // "Argument error" the first time /load was run against a directory
      // that actually contained a saved session.
      cTime := DToC( hS[ "mtime" ] )
      cOut += "  " + hS[ "name" ] + CCUI_Color( "  (" + cTime + ")", "90" ) + Chr(10)
   NEXT
   cOut += CCUI_Color( "Use /load <name> to restore a session.", "90" ) + Chr(10)
   RETURN cOut

// Returns the first line of cText, truncated to nMax characters, with a
// "[<N> chars]" annotation when anything was dropped. nMax defaults to 80.
FUNCTION CCUI_Summarize( cText, nMax )
   LOCAL cFirst, nNL, nLen
   cText := hb_CStr( cText )
   nLen  := Len( cText )
   IF ValType( nMax ) != "N" .OR. nMax <= 0
      nMax := 80
   ENDIF
   nNL := At( Chr(10), cText )
   cFirst := iif( nNL > 0, Left( cText, nNL - 1 ), cText )
   cFirst := StrTran( cFirst, Chr(13), "" )
   IF Len( cFirst ) > nMax
      cFirst := Left( cFirst, nMax )
   ENDIF
   IF Len( cFirst ) < nLen
      RETURN cFirst + " [" + LTrim( Str( nLen ) ) + " chars]"
   ENDIF
   RETURN cFirst

// Maps one agent/SSE event hash to display text ("" when the event is ignored).
// tool_call and tool_result are rendered by the REPL render layer, which has
// the tool-name state they need.
FUNCTION CCUI_RenderEvent( hEv )
   LOCAL cType
   IF ValType( hEv ) != "H" .OR. !hb_HHasKey( hEv, "type" )
      RETURN ""
   ENDIF
   cType := hEv[ "type" ]
   DO CASE
   CASE cType == "text_delta"
      RETURN hb_CStr( hEv[ "text" ] )
   CASE cType == "error"
      // dark-red error card (GUI parity); plain red line when colour is off
      IF CCUI_ColorOn()
         RETURN Chr(10) + CCUI_Card( CCUI_Color( "!! error: " + ;
                hb_CStr( hEv[ "message" ] ), "1;91" ), "card_err" ) + Chr(10)
      ENDIF
      RETURN Chr(10) + CCUI_Color( "!! error: " + hb_CStr( hEv[ "message" ] ), ;
             "31" ) + Chr(10)
   ENDCASE
   RETURN ""

// Builds a Claude Code-style tool label: "Read(src/x.prg)", "Shell(echo hi)".
// The tool name is capitalised; the most relevant argument goes in parentheses.
STATIC FUNCTION CCUI_ToolLabel( cName, cArgsJson )
   LOCAL cProper, xArgs, cArg := ""
   cName := hb_CStr( cName )
   cProper := iif( Empty( cName ), "Tool", ;
                   Upper( Left( cName, 1 ) ) + SubStr( cName, 2 ) )
   xArgs := hb_jsonDecode( hb_CStr( cArgsJson ) )
   IF ValType( xArgs ) == "H"
      DO CASE
      CASE hb_HHasKey( xArgs, "command" )
         cArg := hb_CStr( xArgs[ "command" ] )
      CASE hb_HHasKey( xArgs, "path" )
         cArg := hb_CStr( xArgs[ "path" ] )
      CASE hb_HHasKey( xArgs, "pattern" )
         cArg := hb_CStr( xArgs[ "pattern" ] )
      ENDCASE
   ENDIF
   cArg := StrTran( StrTran( cArg, Chr(13), " " ), Chr(10), " " )
   IF Len( cArg ) > 80
      cArg := Left( cArg, 80 ) + "..."
   ENDIF
   RETURN cProper + "(" + cArg + ")"

// Builds a Claude Code-style result block: the first line prefixed with the
// corner glyph, continuation lines aligned under it, capped at 8 lines.
STATIC FUNCTION CCUI_ResultBlock( cText )
   LOCAL aLines, cOut := "", i, nShow, cLine, cMark, nMax := 50, nWidth
   aLines := hb_ATokens( StrTran( cText, Chr(13), "" ), Chr(10) )
   DO WHILE Len( aLines ) > 1 .AND. Empty( ATail( aLines ) )
      hb_ADel( aLines, Len( aLines ), .T. )
   ENDDO
   nShow := Min( Len( aLines ), nMax )
   // Compute the widest added/removed line so every coloured bar gets
   // padded to the same length; bars of mismatched widths look ragged
   // when stacked. Floor at 110 to keep the default look on small diffs.
   nWidth := 110
   FOR i := 1 TO nShow
      cLine := aLines[ i ]
      cMark := CCUI_DiffMark( cLine )
      IF cMark == "+" .OR. cMark == "-"
         nWidth := Max( nWidth, hb_UTF8Len( cLine ) )
      ENDIF
   NEXT
   FOR i := 1 TO nShow
      cLine := aLines[ i ]
      // colour diff lines: added on a green background, removed on dark red.
      // The line is space-padded first so the background fills the width
      // instead of stopping at the end of the text.
      cMark := CCUI_DiffMark( cLine )
      DO CASE
      CASE cMark == "+"
         cLine := CCUI_Color( CCUI_DiffPad( cLine, nWidth ), "97;42" )
      CASE cMark == "-"
         cLine := CCUI_Color( CCUI_DiffPad( cLine, nWidth ), "97;48;5;52" )
      ENDCASE
      cOut += iif( i == 1, "  " + Chr(226)+Chr(142)+Chr(191) + "  ", "     " ) + cLine
      IF i < nShow
         cOut += Chr(10)
      ENDIF
   NEXT
   IF Len( aLines ) > nMax
      cOut += Chr(10) + "     ... (" + ;
              LTrim( Str( Len( aLines ) - nMax ) ) + " more lines)"
   ENDIF
   RETURN cOut

// Pads a diff line with trailing spaces so its background colour fills the
// row (a coloured diff bar spans the line rather than stopping at the text).
// nWidth is the target visual width; a line already at or over it is
// returned unchanged. nWidth defaults to 110 (the original fixed width).
FUNCTION CCUI_DiffPad( cLine, nWidth )
   LOCAL nLen := hb_UTF8Len( hb_CStr( cLine ) )
   IF ValType( nWidth ) != "N" .OR. nWidth < 1
      nWidth := 110
   ENDIF
   RETURN iif( nLen < nWidth, cLine + Space( nWidth - nLen ), cLine )

// The Claude Code-style tool-call line: an accent dot, then Tool(args). The
// dot is accent-coloured; the label is left in the default foreground.
FUNCTION CCUI_ToolCallLine( cName, cArgsJson )
   RETURN Chr(10) + ;
          CCUI_Color( Chr(226)+Chr(143)+Chr(186), CCUI_Pal( "accent" ) ) + ;
          "  " + CCUI_ToolLabel( cName, cArgsJson ) + Chr(10)

// True when any line of cText is diff-formatted (per CCUI_DiffMark).
STATIC FUNCTION CCUI_HasDiff( cText )
   LOCAL cLine
   FOR EACH cLine IN hb_ATokens( cText, Chr(10) )
      IF !Empty( CCUI_DiffMark( cLine ) )
         RETURN .T.
      ENDIF
   NEXT
   RETURN .F.

// Renders the block printed under a tool call. Diff-formatted content keeps
// the coloured diff block; otherwise a compact tool-aware one-line summary.
// Result ends in LF.
FUNCTION CCUI_ResultSummary( cToolName, cContent )
   LOCAL cClean, aLines, nLines, cFirst, cSum
   cToolName := Lower( hb_CStr( cToolName ) )
   cContent  := hb_CStr( cContent )
   cClean    := StrTran( cContent, Chr(13), "" )

   IF CCUI_HasDiff( cClean )
      RETURN CCUI_Color( CCUI_ResultBlock( cContent ), CCUI_Pal( "dim" ) ) + Chr(10)
   ENDIF

   IF Left( cClean, 6 ) == "Error:"
      cSum := CCUI_Summarize( cClean, 200 )
   ELSE
      aLines := hb_ATokens( cClean, Chr(10) )
      DO WHILE Len( aLines ) > 1 .AND. Empty( ATail( aLines ) )
         hb_ADel( aLines, Len( aLines ), .T. )
      ENDDO
      nLines := Len( aLines )
      cFirst := Left( iif( nLines > 0, aLines[ 1 ], "" ), 120 )
      DO CASE
      CASE cToolName == "read"
         cSum := "Read " + LTrim( Str( nLines ) ) + " lines"
      CASE cToolName == "write" .OR. cToolName == "edit"
         cSum := cFirst
      CASE cToolName == "glob"
         cSum := iif( Left( cFirst, 11 ) == "No matches ", cFirst, ;
                      "Listed " + LTrim( Str( nLines ) ) + " files" )
      CASE cToolName == "grep"
         cSum := iif( Left( cFirst, 11 ) == "No matches ", cFirst, ;
                      "Found " + LTrim( Str( nLines ) ) + " matches" )
      CASE cToolName == "shell"
         cSum := iif( nLines > 1, ;
                      cFirst + " (" + LTrim( Str( nLines ) ) + " lines)", cFirst )
      OTHERWISE
         cSum := LTrim( Str( nLines ) ) + " lines"
      ENDCASE
   ENDIF

   RETURN CCUI_Color( "     " + cSum, CCUI_Pal( "dim" ) ) + Chr(10)

// Detects a diff line ("<6-wide number> <+|-|space> <text>"); returns the
// marker "+" or "-", or "" when the line is not a diff line.
STATIC FUNCTION CCUI_DiffMark( cLine )
   LOCAL cM, cNum, i
   IF Len( cLine ) < 9
      RETURN ""
   ENDIF
   cM := SubStr( cLine, 8, 1 )
   IF !( cM == "+" .OR. cM == "-" )
      RETURN ""
   ENDIF
   IF !( SubStr( cLine, 7, 1 ) == " " .AND. SubStr( cLine, 9, 1 ) == " " )
      RETURN ""
   ENDIF
   cNum := SubStr( cLine, 1, 6 )
   FOR i := 1 TO 6
      IF !( IsDigit( SubStr( cNum, i, 1 ) ) .OR. SubStr( cNum, i, 1 ) == " " )
         RETURN ""
      ENDIF
   NEXT
   RETURN cM

// Enables or disables ANSI colour output. Off by default; the REPL turns it on
// from the settings "color" key. Only enable it on a VT-capable terminal.
FUNCTION CCUI_SetColor( lOn )
   s_lColor := ( lOn == .T. )
   RETURN NIL

// Wraps text in an ANSI SGR colour code when colour is enabled, otherwise
// returns the text unchanged. cSGR is the code, e.g. "36" (cyan), "90" (grey),
// "31" (red), "1;36" (bold cyan), "33" (yellow).
FUNCTION CCUI_Color( cText, cSGR )
   IF !s_lColor
      RETURN cText
   ENDIF
   RETURN Chr(27) + "[" + cSGR + "m" + cText + Chr(27) + "[0m"

// Returns .T. when ANSI output (colour and cursor control) is enabled.
FUNCTION CCUI_ColorOn()
   RETURN s_lColor

// The Claude Code-style colour palette: maps a name to an ANSI SGR code so
// the codes live in one place. Unknown names return "0" (reset).
FUNCTION CCUI_Pal( cName )
   DO CASE
   CASE cName == "accent"     ; RETURN "38;2;217;119;87"   // Claude Code coral
   CASE cName == "dim"        ; RETURN "90"         // grey borders / secondary
   CASE cName == "bold"       ; RETURN "1"
   CASE cName == "error"      ; RETURN "31"
   CASE cName == "tool"       ; RETURN "1;36"       // bright cyan tool label
   CASE cName == "warn"       ; RETURN "33"
   CASE cName == "diff_add"   ; RETURN "42"
   CASE cName == "diff_del"   ; RETURN "48;5;52"
   CASE cName == "suggestion" ; RETURN "2;38;2;180;255;180"
   CASE cName == "invert"     ; RETURN "7"          // inverse video
   CASE cName == "user"       ; RETURN "97"         // bright white user echo
   CASE cName == "bash_header"  ; RETURN "38;2;128;160;230"   // cyan-violet header
   CASE cName == "bash_command" ; RETURN "92"                  // bright green command
   CASE cName == "bash_explain" ; RETURN "2;97"                // soft (faint) bright white
   // GUI-card background tints (AgenticAI / Agents web cards, truecolor).
   // A touch brighter than the web's gray-800: terminals sit on pure black,
   // so the same RGB reads darker than on the web's gray-900 page.
   CASE cName == "card"       ; RETURN "48;2;52;64;84"    // reply bubble (slate)
   CASE cName == "card_think" ; RETURN "48;2;66;56;94"    // reasoning glass box (purple)
   CASE cName == "card_err"   ; RETURN "48;2;92;40;40"    // error card (dark red)
   CASE cName == "card_cost"  ; RETURN "48;2;26;72;56"    // cost metrics card (emerald)
   CASE cName == "card_warn"  ; RETURN "48;2;92;72;28"    // confirmation card (amber)
   CASE cName == "card_user"  ; RETURN "48;2;37;99;235"   // user bubble (blue-600)
   CASE cName == "card_goal"  ; RETURN "48;2;62;56;124"   // goal card (indigo)
   CASE cName == "card_ctx"   ; RETURN "48;2;92;52;30"    // context-critical (orange)
   CASE cName == "card_tool"  ; RETURN "48;2;38;47;60"    // tool actions panel (faint)
   ENDCASE
   RETURN "0"

// Visible column width of a string: ANSI CSI sequences are skipped and
// UTF-8 continuation bytes are not counted (close enough for card padding).
FUNCTION CCUI_VisLen( cText )
   LOCAL n := 0, i := 1, nLen, c
   cText := hb_CStr( cText )
   nLen  := Len( cText )
   DO WHILE i <= nLen
      c := SubStr( cText, i, 1 )
      IF c == Chr(27) .AND. SubStr( cText, i + 1, 1 ) == "["
         i += 2
         DO WHILE i <= nLen
            c := SubStr( cText, i, 1 )
            i++
            IF c >= "@" .AND. c <= "~" ; EXIT ; ENDIF
         ENDDO
      ELSE
         IF hb_BCode( c ) < 0x80 .OR. hb_BCode( c ) >= 0xC0
            n++
         ENDIF
         i++
      ENDIF
   ENDDO
   RETURN n

// Paints one line as a GUI-style card row: two columns of inner padding,
// the background tint cBgPal padded out to nWidth columns. Embedded SGR
// resets (markdown bold/code spans) re-apply the background so the card
// colour never "leaks away" mid-line. Plain text when colour is off.
FUNCTION CCUI_CardLine( cLine, cBgPal, nWidth )
   LOCAL cBg, nVis
   cLine := hb_CStr( cLine )
   IF !CCUI_ColorOn()
      RETURN "  " + cLine
   ENDIF
   IF ValType( nWidth ) != "N" .OR. nWidth < 20
      nWidth := 80
   ENDIF
   cBg   := Chr(27) + "[" + CCUI_Pal( cBgPal ) + "m"
   cLine := "  " + cLine + "  "
   nVis  := CCUI_VisLen( cLine )
   IF nVis < nWidth
      cLine += Space( nWidth - nVis )
   ENDIF
   cLine := StrTran( cLine, Chr(27) + "[0m", Chr(27) + "[0m" + cBg )
   RETURN cBg + cLine + Chr(27) + "[0m"

// Paints a whole (possibly multi-line) block as a card, one row per line.
// Returns the block without a trailing LF.
FUNCTION CCUI_Card( cText, cBgPal, nWidth )
   LOCAL aLines := hb_ATokens( StrTran( hb_CStr( cText ), Chr(13), "" ), Chr(10) )
   LOCAL cOut := "", i
   FOR i := 1 TO Len( aLines )
      cOut += CCUI_CardLine( aLines[ i ], cBgPal, nWidth ) + ;
              iif( i < Len( aLines ), Chr(10), "" )
   NEXT
   RETURN cOut

// Emits an ANSI control sequence (e.g. "1A" = cursor up one line,
// "1G" = move to column 1) when ANSI output is enabled, else "".
FUNCTION CCUI_VT( cSeq )
   IF !s_lColor
      RETURN ""
   ENDIF
   RETURN Chr(27) + "[" + cSeq

// The VT sequence that wipes the terminal: ESC[3J clears scrollback,
// ESC[2J clears the visible screen, ESC[H homes the cursor. Returned
// unconditionally; callers decide whether the terminal can accept it.
FUNCTION CCUI_ClearScreenSeq()
   RETURN Chr(27) + "[3J" + Chr(27) + "[2J" + Chr(27) + "[H"

// The system message seeded into every conversation. When a CC.md file is
// present in the working directory its contents are appended as project
// instructions, so the agent honours per-project conventions. When a
// memory.md file is present it is appended as the agent's persisted memory.
FUNCTION CCUI_SystemPrompt()
   LOCAL cBase, cProj, cMem
   // lean mode: minimal prompt for token-saving sessions
   IF CCREPL_LeanMode()
      RETURN "You are Agents, a terminal coding assistant on " + OS() + ;
             " in " + hb_cwd() + ". Be very concise. End every reply with " + ;
             "'Suggested next: <short prompt>'."
   ENDIF
   cBase := "You are Agents, a terminal coding assistant. " + ;
            "You have tools to read, write and edit files, search with glob and " + ;
            "grep, and run shell commands. Use them to help the user with coding " + ;
            "tasks. Be concise. " + ;
            "You are running on " + OS() + ", and the current working " + ;
            "directory is " + hb_cwd() + ". Relative paths resolve against " + ;
            "that directory — use relative paths, or absolute paths under it; " + ;
            "never invent absolute paths to other locations. Use shell " + ;
            "commands and conventions appropriate to this operating system. " + ;
            "End every reply with a final line in the exact form " + ;
            "'Suggested next: <a short prompt the user might send next>'." + ;
            Chr(10) + Chr(10) + ;
            "Formatting rules: when you list more than 3 items, put each " + ;
            "item on its own line with a leading '- ' bullet (real " + ;
            "newlines, not commas). When emphasising a number or " + ;
            "identifier with **, leave a space before and after the " + ;
            "delimiter (write 'all **57** files' not 'all**57**files') so " + ;
            "the surrounding spaces survive. Never collapse a list of " + ;
            "paths or names into a single comma-less line." + Chr(10) + Chr(10) + ;
            "Subagent dispatch rules: think first about whether delegation " + ;
            "actually helps. For a one-line answer, a single file edit, or " + ;
            "a conversational reply, do the work in the main thread. For a " + ;
            "single self-contained subtask too heavy to inline, call " + ;
            "dispatch_agent directly. For two or more independent subtasks, " + ;
            "ALWAYS call propose_agents FIRST and wait for the user's " + ;
            "approval -- the user reviews the list, may drop items, and " + ;
            "confirms; only then iterate over the returned JSON and call " + ;
            "dispatch_agent once per approved item." + Chr(10) + Chr(10) + ;
            "IMPORTANT — narrate your actions. Immediately before EVERY tool " + ;
            "call that runs a shell command, or that otherwise does something " + ;
            "non-obvious, you MUST first write one or two short sentences. " + ;
            "Each narration MUST state BOTH: (1) what you are about to do, and " + ;
            "(2) WHY — the reason or goal behind it, not just the action. A " + ;
            "narration that gives only the action is incomplete and not " + ;
            "acceptable. For example, write 'Listing the build directory to " + ;
            "confirm hbmk2 produced the binary.' — NOT 'Listing the build " + ;
            "directory.' This narration is required even though your replies " + ;
            "are otherwise concise — it is not optional. Only skip it for " + ;
            "trivial, self-evident actions such as reading a single named file."
   cProj := CCUI_ProjectContext()
   IF !Empty( cProj )
      cBase += Chr(10) + Chr(10) + ;
         "The following project instructions come from the CC.md file in " + ;
         "the working directory. Treat them as authoritative and follow them:" + ;
         Chr(10) + Chr(10) + cProj
   ENDIF
   cMem := CCUI_MemoryContext()
   IF !Empty( cMem )
      cBase += Chr(10) + Chr(10) + ;
         "The following is your own memory, persisted from previous sessions " + ;
         "in this project. Use it, and keep it current with the memory tool:" + ;
         Chr(10) + Chr(10) + cMem
   ENDIF
   cBase += CCUI_SkillsContext()
   RETURN cBase

// Lists the skills found under .agents/skills/ so the model knows what is
// available without loading every body up front. The model picks one with
// the use_skill tool; that call returns the full body. Returns "" when no
// skills are present so the system prompt stays unchanged.
FUNCTION CCUI_SkillsContext()
   LOCAL aSkills := CCSKILL_List(), hSkill, cOut
   IF Empty( aSkills )
      RETURN ""
   ENDIF
   cOut := Chr(10) + Chr(10) + ;
      "Project skills are available under .agents/skills/. Each is a " + ;
      "checklist or set of instructions you may activate when its " + ;
      "description matches the task. Activate one with the use_skill tool " + ;
      "(the body is returned to you); use it only when it clearly applies — " + ;
      "do not invoke a skill for trivial edits or simple questions." + ;
      Chr(10) + Chr(10) + "Available skills:" + Chr(10)
   FOR EACH hSkill IN aSkills
      cOut += "- " + hSkill[ "name" ] + ": " + hSkill[ "description" ] + Chr(10)
   NEXT
   RETURN cOut

// Reads project instructions from a CC.md file in the current directory.
// Returns "" when the file is absent or empty.
FUNCTION CCUI_ProjectContext()
   LOCAL cText := ""
   IF File( "CC.md" )
      cText := hb_MemoRead( "CC.md" )
   ENDIF
   RETURN AllTrim( hb_CStr( cText ) )

// Reads the agent's persisted memory from memory.md in the current directory.
// Returns "" when the file is absent or empty.
FUNCTION CCUI_MemoryContext()
   LOCAL cText := ""
   IF File( "memory.md" )
      cText := hb_MemoRead( "memory.md" )
   ENDIF
   RETURN AllTrim( hb_CStr( cText ) )

// Returns a UTF-8 box-drawing glyph by name, built from raw bytes so the
// source file's encoding does not matter.
FUNCTION CCUI_Glyph( cName )
   DO CASE
   CASE cName == "tl"
      RETURN Chr(226)+Chr(148)+Chr(140)   // ┌
   CASE cName == "tr"
      RETURN Chr(226)+Chr(148)+Chr(144)   // ┐
   CASE cName == "bl"
      RETURN Chr(226)+Chr(148)+Chr(148)   // └
   CASE cName == "br"
      RETURN Chr(226)+Chr(148)+Chr(152)   // ┘
   CASE cName == "h"
      RETURN Chr(226)+Chr(148)+Chr(128)   // ─
   CASE cName == "v"
      RETURN Chr(226)+Chr(148)+Chr(130)   // │
   ENDCASE
   RETURN " "

// Pads cText to nWidth display columns, counting UTF-8 characters (not bytes).
// cAlign is "L" (default), "C" (centre) or "R" (right). Over-long text is cut.
STATIC FUNCTION CCUI_PadCell( cText, nWidth, cAlign )
   LOCAL nLen, nPad, nLeft
   cText := hb_CStr( cText )
   nLen  := hb_UTF8Len( cText )
   IF nLen > nWidth
      cText := hb_UTF8SubStr( cText, 1, nWidth )
      nLen  := nWidth
   ENDIF
   nPad := nWidth - nLen
   DO CASE
   CASE cAlign == "C"
      nLeft := Int( nPad / 2 )
      RETURN Space( nLeft ) + cText + Space( nPad - nLeft )
   CASE cAlign == "R"
      RETURN Space( nPad ) + cText
   ENDCASE
   RETURN cText + Space( nPad )

// The Agents version string.
// RELEASE CHECKLIST — on every release bump this string together with the
// version in releasenotes.md and the Releases section of README.md, then
// tag the commit v<x.y.z>. All four must stay in sync.
FUNCTION CCUI_Version()
   RETURN "0.8.28"

// The pool of short usage tips shown on the banner and at the idle prompt.
FUNCTION CCUI_Tips()
   RETURN { ;
      "Use /clear to start fresh when switching topics", ;
      "Press Esc to interrupt the agent mid-turn", ;
      "Type /btw <note> to add context without interrupting", ;
      "/init writes a CC.md so the agent learns project conventions", ;
      "/cost shows token usage and estimated spend", ;
      "/save and /load keep conversations across sessions", ;
      "Edit per-tool permissions in .agents/settings.json" }

// Returns the tip at a 1-based index, wrapping modulo the pool length so any
// integer -- including 0 and values past the end -- maps to a valid tip.
FUNCTION CCUI_TipAt( nIndex )
   LOCAL aTips := CCUI_Tips()
   LOCAL nMod  := ( nIndex - 1 ) % Len( aTips )
   IF nMod < 0
      nMod += Len( aTips )
   ENDIF
   RETURN aTips[ nMod + 1 ]

// Formats one tip as a dim-coloured "Tip: <text>" line ending in LF.
FUNCTION CCUI_TipLine( cTip )
   RETURN CCUI_Color( "Tip: " + hb_CStr( cTip ), CCUI_Pal( "dim" ) ) + Chr(10)

// Returns the first non-empty, trimmed line of cText (CR stripped). When no
// such line exists, returns cFallback. Used for the banner's "What's new".
FUNCTION CCUI_ReleaseTagline( cText, cFallback )
   LOCAL cLine
   FOR EACH cLine IN hb_ATokens( hb_CStr( cText ), Chr(10) )
      cLine := AllTrim( StrTran( cLine, Chr(13), "" ) )
      IF !Empty( cLine )
         RETURN cLine
      ENDIF
   NEXT
   RETURN hb_CStr( cFallback )

// The "What's new" line for the banner: the first line of releasenotes.md,
// looked up beside the executable first, then in the working directory. When
// the file is absent or empty, falls back to "Agents v<version>".
FUNCTION CCUI_WhatsNew()
   LOCAL cFallback := "Agents v" + CCUI_Version()
   LOCAL cPath := hb_DirBase() + "releasenotes.md"
   IF !hb_FileExists( cPath )
      cPath := "releasenotes.md"
   ENDIF
   IF hb_FileExists( cPath )
      RETURN CCUI_ReleaseTagline( hb_MemoRead( cPath ), cFallback )
   ENDIF
   RETURN cFallback

// Builds a banner cell: text, alignment ("L"/"C"/"R"), and an SGR code ("" = none).
FUNCTION CCUI_Cell( cText, cAlign, cSGR )
   RETURN { "text" => hb_CStr( cText ), ;
            "align" => iif( Empty( cAlign ), "L", cAlign ), ;
            "sgr" => hb_CStr( cSGR ), ;
            "raw" => .F. }

// A cell whose text already carries its own ANSI escapes and padding;
// the panel row renders it verbatim and skips PadCell + Color wrapping.
FUNCTION CCUI_CellRaw( cText )
   RETURN { "text" => hb_CStr( cText ), ;
            "align" => "L", "sgr" => "", "raw" => .T. }

// Renders one cell to nWidth display columns, padded then colour-wrapped.
// Raw cells are emitted as-is (they carry their own colour and padding).
STATIC FUNCTION CCUI_PanelRow( hCell, nWidth )
   LOCAL cCell
   IF hb_HHasKey( hCell, "raw" ) .AND. hCell[ "raw" ] == .T.
      RETURN hCell[ "text" ]
   ENDIF
   cCell := CCUI_PadCell( hCell[ "text" ], nWidth, hCell[ "align" ] )
   IF !Empty( hCell[ "sgr" ] )
      cCell := CCUI_Color( cCell, hCell[ "sgr" ] )
   ENDIF
   RETURN cCell

// Renders one logo row with a per-character magenta -> violet gradient
// (24-bit true colour). Spaces are emitted unchanged; the line is padded
// to nPanelW with normal spaces so the row sits centred in the banner
// panel. When colour is off the gradient is skipped -- only padding.
FUNCTION CCUI_LogoGradientRow( cLine, nPanelW )
   LOCAL i, n, c, t, r, g, b
   LOCAL nLogo := hb_UTF8Len( cLine )
   LOCAL nLeftPad, nRightPad, cOut
   IF nPanelW < nLogo  ; nPanelW := nLogo  ; ENDIF
   nLeftPad  := Int( ( nPanelW - nLogo ) / 2 )
   nRightPad := nPanelW - nLogo - nLeftPad
   cOut := Space( nLeftPad )
   IF !CCUI_ColorOn()
      RETURN cOut + cLine + Space( nRightPad )
   ENDIF
   n := nLogo
   FOR i := 1 TO n
      c := hb_UTF8SubStr( cLine, i, 1 )
      IF c == " "
         cOut += c
      ELSE
         // linear interpolation: column 0 -> (240,171,252) fuchsia-300;
         // last column -> (124,58,237) violet-600
         t := iif( n > 1, ( i - 1 ) / ( n - 1.0 ), 0 )
         r := 240 - Round( 116 * t, 0 )
         g := 171 - Round( 113 * t, 0 )
         b := 252 - Round(  15 * t, 0 )
         cOut += Chr(27) + "[38;2;" + LTrim( Str( r ) ) + ";" + ;
                                       LTrim( Str( g ) ) + ";" + ;
                                       LTrim( Str( b ) ) + "m" + c
      ENDIF
   NEXT
   cOut += Chr(27) + "[0m" + Space( nRightPad )
   RETURN cOut

// Joins a left and a right column of cells row-for-row into finished banner
// lines: left cell, a dim vertical divider with a space each side, right cell.
// The shorter column is padded with blank cells so both reach equal height.
FUNCTION CCUI_BannerJoin( aLeft, aRight, nLeftW, nRightW )
   LOCAL aOut := {}, nRows, i, hL, hR
   LOCAL hBlank := CCUI_Cell( "", "L", "" )
   LOCAL cDiv := " " + CCUI_Color( CCUI_Glyph( "v" ), CCUI_Pal( "dim" ) ) + " "
   nRows := Max( Len( aLeft ), Len( aRight ) )
   FOR i := 1 TO nRows
      hL := iif( i <= Len( aLeft ),  aLeft[ i ],  hBlank )
      hR := iif( i <= Len( aRight ), aRight[ i ], hBlank )
      AAdd( aOut, CCUI_PanelRow( hL, nLeftW ) + cDiv + CCUI_PanelRow( hR, nRightW ) )
   NEXT
   RETURN aOut

// Renders a CCSEL selector state to a printable block: a "●" bullet and the
// question, then one numbered row per option. The row at the cursor is marked
// with a "❯" arrow and inverse video; other rows get two leading spaces.
// Each line ends in LF. Pure -- no console I/O.
FUNCTION CCUI_QuestionBlock( oSel )
   LOCAL cOut, i, aOpts := oSel[ "options" ], cRow
   LOCAL cBullet := Chr(226) + Chr(151) + Chr(143)   // U+25CF ●
   LOCAL cArrow  := Chr(226) + Chr(157) + Chr(175)   // U+276F ❯
   cOut := CCUI_Color( cBullet, CCUI_Pal( "accent" ) ) + " " + ;
           CCUI_Color( oSel[ "question" ], CCUI_Pal( "bold" ) ) + ;
           Chr(10) + Chr(10)   // blank line between question and options
   FOR i := 1 TO Len( aOpts )
      cRow := iif( i == oSel[ "cursor" ], cArrow + " ", "  " ) + ;
              LTrim( Str( i ) ) + ". " + aOpts[ i ]
      IF i == oSel[ "cursor" ]
         cRow := CCUI_Color( cRow, CCUI_Pal( "invert" ) )
      ENDIF
      cOut += cRow + Chr(10)
   NEXT
   cOut += Chr(10)   // blank line between options and the hint tail
   cOut += CCUI_Color( "  Esc to cancel " + Chr(194) + Chr(183) + ;
                       " Tab to amend " + Chr(194) + Chr(183) + ;
                       " ctrl+e to explain", CCUI_Pal( "dim" ) ) + Chr(10)
   RETURN cOut

// Renders a todo list to a printable block: a "Todos:" header, then one line
// per item -- a status glyph and the item text. completed = "√" (dim),
// in_progress = "■" (accent), pending = "□". Each line ends in LF. Pure.
FUNCTION CCUI_TodoBlock( aTodos )
   LOCAL cOut := CCUI_Color( "Todos:", CCUI_Pal( "bold" ) ) + Chr(10)
   LOCAL hItem, cGlyph, cLabel, lBlocked
   LOCAL cDone := Chr(226) + Chr(136) + Chr(154)   // U+221A √
   LOCAL cProg := Chr(226) + Chr(150) + Chr(160)   // U+25A0 ■
   LOCAL cPend := Chr(226) + Chr(150) + Chr(161)   // U+25A1 □
   LOCAL cLink := Chr(226) + Chr(134) + Chr(179)   // U+21B3 ↳
   FOR EACH hItem IN aTodos
      // present-continuous label takes over while an item is in_progress
      cLabel := hItem[ "text" ]
      IF hItem[ "status" ] == "in_progress" .AND. ;
         hb_HHasKey( hItem, "active_form" ) .AND. ;
         !Empty( hItem[ "active_form" ] )
         cLabel := hItem[ "active_form" ]
      ENDIF
      lBlocked := CCTODO_IsBlocked( hItem, aTodos ) .AND. ;
                  hItem[ "status" ] != "completed"
      DO CASE
      CASE hItem[ "status" ] == "completed"
         cGlyph := CCUI_Color( cDone, CCUI_Pal( "dim" ) )
      CASE hItem[ "status" ] == "in_progress"
         cGlyph := CCUI_Color( cProg, CCUI_Pal( "accent" ) )
      OTHERWISE
         cGlyph := iif( lBlocked, CCUI_Color( cLink, CCUI_Pal( "dim" ) ), ;
                                   cPend )
      ENDCASE
      IF lBlocked
         // indent blocked items and dim them so the dependency is visible
         cOut += "    " + cGlyph + " " + ;
                 CCUI_Color( cLabel + " (blocked)", CCUI_Pal( "dim" ) ) + ;
                 Chr(10)
      ELSE
         cOut += "  " + cGlyph + " " + cLabel + Chr(10)
      ENDIF
   NEXT
   RETURN cOut

// Builds the two-panel startup banner inside one rounded box, 99 columns wide
// (matching the input frame). Left panel: a "Welcome back" line, the six-row
// block "AG" logo, the name+version and the model. Right panel: a "Tips for
// getting started" list and a "What's new" line from releasenotes.md. The
// shorter panel is blank-padded to equal height. Returns the banner ending in LF.
FUNCTION CCUI_Banner( cModel, cCwd, cUser )
   // Adapts to the current terminal width: nInner is the inside width of
   // the rounded frame (so total banner = nInner + 4). Clamped to keep
   // the logo readable on narrow terminals and contained on wide ones.
   LOCAL nCols := CCREPL_Cols() - 2   // leave 1 col margin per side
   LOCAL nInner, nLeftW, nRightW
   LOCAL cH := CCUI_Glyph( "h" ), cV, cName, aLogo, aLeft, aRight, aRows, cOut, i
   IF nCols < 80   ; nCols := 80    ; ENDIF
   IF nCols > 200  ; nCols := 200   ; ENDIF
   nInner  := nCols - 4
   // Split: left ~48% / divider 3 cols / right takes the rest.
   nLeftW  := Int( ( nInner - 3 ) * 0.48 )
   IF nLeftW < 32   ; nLeftW := 32  ; ENDIF
   nRightW := nInner - 3 - nLeftW
   IF nRightW < 32  ; nRightW := 32 ; nLeftW := nInner - 3 - nRightW ; ENDIF

   cModel := hb_CStr( cModel )
   cCwd   := hb_CStr( cCwd )
   cName  := AllTrim( hb_CStr( cUser ) )
   IF Empty( cName )
      cName := AllTrim( hb_CStr( hb_GetEnv( "USER" ) ) )
   ENDIF
   cV := CCUI_Color( CCUI_Glyph( "v" ), CCUI_Pal( "dim" ) )

   // the "AG" logo, six rows of block-drawing glyphs
   // Gradient-text logo — 6 identical rows, centred, per-char magenta-violet.
   aLogo := { ;
      "A g e n t s", ;
      "A g e n t s", ;
      "A g e n t s", ;
      "A g e n t s", ;
      "A g e n t s", ;
      "A g e n t s" }

   // left panel: welcome, logo (6, per-char magenta->violet gradient),
   // name+version, model
   aLeft := {}
   AAdd( aLeft, CCUI_Cell( iif( Empty( cName ), "Welcome back!", ;
                                "Welcome back, " + cName + "!" ), "C", "" ) )
   FOR i := 1 TO 6
      AAdd( aLeft, CCUI_CellRaw( CCUI_LogoGradientRow( aLogo[ i ], nLeftW ) ) )
   NEXT
   AAdd( aLeft, CCUI_Cell( "Agents  v" + CCUI_Version(), "C", CCUI_Pal( "accent" ) ) )
   AAdd( aLeft, CCUI_Cell( "model: " + cModel, "C", "" ) )

   // right panel: tips list, divider, what's new (9 rows, matching the left)
   aRight := {}
   AAdd( aRight, CCUI_Cell( "Tips for getting started", "L", CCUI_Pal( "bold" ) ) )
   AAdd( aRight, CCUI_Cell( "", "L", "" ) )
   AAdd( aRight, CCUI_Cell( "Type a request to begin", "L", "" ) )
   AAdd( aRight, CCUI_Cell( "Run /help to list commands", "L", "" ) )
   AAdd( aRight, CCUI_Cell( "Tip: " + ;
         CCUI_TipAt( Int( hb_Random( Len( CCUI_Tips() ) ) ) + 1 ), "L", "" ) )
   AAdd( aRight, CCUI_Cell( Replicate( cH, nRightW ), "L", CCUI_Pal( "dim" ) ) )
   AAdd( aRight, CCUI_Cell( "What's new", "L", CCUI_Pal( "bold" ) ) )
   AAdd( aRight, CCUI_Cell( CCUI_WhatsNew(), "L", CCUI_Pal( "dim" ) ) )
   AAdd( aRight, CCUI_Cell( "cwd: " + cCwd, "L", CCUI_Pal( "dim" ) ) )

   aRows := CCUI_BannerJoin( aLeft, aRight, nLeftW, nRightW )

   cOut := CCUI_Color( CCUI_Glyph( "tl" ) + Replicate( cH, nInner + 2 ) + ;
           CCUI_Glyph( "tr" ), CCUI_Pal( "dim" ) ) + Chr(10)
   FOR i := 1 TO Len( aRows )
      cOut += cV + " " + aRows[ i ] + " " + cV + Chr(10)
   NEXT
   cOut += CCUI_Color( CCUI_Glyph( "bl" ) + Replicate( cH, nInner + 2 ) + ;
           CCUI_Glyph( "br" ), CCUI_Pal( "dim" ) ) + Chr(10)
   RETURN cOut

// The top border of the input frame — a plain horizontal rule with no
// corner glyphs, matching the open-edge look requested by the user.
FUNCTION CCUI_FrameTop()
   LOCAL nFill := CCUI_InputInnerWidth() + 2
   RETURN CCUI_Color( Replicate( CCUI_Glyph( "h" ), nFill ), CCUI_Pal( "dim" ) )

// The bottom border of the input frame. Same width as the top.
FUNCTION CCUI_FrameBottom()
   LOCAL nFill := CCUI_InputInnerWidth() + 2
   RETURN CCUI_Color( Replicate( CCUI_Glyph( "h" ), nFill ), CCUI_Pal( "dim" ) )

// The dim hint line shown beneath the input frame.
// nLines (optional) shows the line count for multi-line input.
FUNCTION CCUI_InputHint( nLines )
   LOCAL cSuffix := ""
   IF ValType( nLines ) == "N" .AND. nLines > 1
      cSuffix := "  " + Chr(226)+Chr(128)+Chr(162) + "  " + LTrim( Str( nLines ) ) + " lines"
   ENDIF
   RETURN CCUI_Color( "  /help for commands" + cSuffix + ;
          "  " + Chr(226)+Chr(128)+Chr(162) + "  /exit to quit", CCUI_Pal( "dim" ) )

// The text-column width available inside the input box. Adapts to the
// current terminal width (CCREPL_Cols) minus a one-column safety margin
// (to avoid auto-wrap on the right edge) minus 6 cols of overhead
// (2 borders + 2 inside spaces + the "> " prompt). Clamped to [70, 200].
FUNCTION CCUI_InputInnerWidth()
   LOCAL nCols := CCREPL_Cols() - 1
   IF nCols < 76 ; nCols := 76 ; ENDIF
   IF nCols > 200 ; nCols := 200 ; ENDIF
   RETURN nCols - 3   // "> " (2 chars) + 1 char right margin

// Renders the propose_agents selector body: a short intro line, one row per
// proposal with a checkbox / index / type / truncated prompt, and a hint
// tail. The caller (CCPROPOSE_Paint) wraps it with the rule + header band.
FUNCTION CCUI_ProposeBlock( oSel )
   LOCAL cOut := "", i, aItems := oSel[ "items" ], cRow, cBox, cType, cPrompt
   LOCAL cCheck := Chr(226) + Chr(156) + Chr(147)   // U+2713 ✓ check
   LOCAL cPend  := Chr(194) + Chr(183)              // U+00B7 · middle dot
   LOCAL cArrow := Chr(226) + Chr(157) + Chr(175)   // U+276F ❯
   LOCAL nMax
   // dynamic max prompt length: terminal width minus the row prefix
   // ("❯ [✓] NN. <type   > ") and a 3-char ellipsis budget
   nMax := CCREPL_Cols() - 22
   IF nMax < 30
      nMax := 30
   ENDIF
   cOut += "  " + CCUI_Color( ;
      "The agent suggests these subagents. Toggle with Space, " + ;
      "confirm with Enter.", CCUI_Pal( "dim" ) ) + Chr(10)
   cOut += Chr(10)
   FOR i := 1 TO Len( aItems )
      cBox := iif( aItems[ i ][ "accepted" ], ;
                   CCUI_Color( "[" + cCheck + "]", CCUI_Pal( "accent" ) ), ;
                   CCUI_Color( "[" + cPend + "]", CCUI_Pal( "dim" ) ) )
      cType := PadR( aItems[ i ][ "type" ], 8 )
      cPrompt := aItems[ i ][ "prompt" ]
      IF hb_UTF8Len( cPrompt ) > nMax
         cPrompt := hb_UTF8SubStr( cPrompt, 1, nMax - 3 ) + "..."
      ENDIF
      cRow := iif( i == oSel[ "cursor" ], cArrow + " ", "  " ) + cBox + " " + ;
              LTrim( Str( i ) ) + ". " + cType + " " + cPrompt
      IF i == oSel[ "cursor" ]
         cRow := CCUI_Color( cRow, CCUI_Pal( "invert" ) )
      ENDIF
      cOut += cRow + Chr(10)
   NEXT
   cOut += Chr(10)
   cOut += CCUI_Color( "  Space toggle " + Chr(194)+Chr(183) + ;
                       " A accept all " + Chr(194)+Chr(183) + ;
                       " N reject all " + Chr(194)+Chr(183) + ;
                       " Enter confirm " + Chr(194)+Chr(183) + ;
                       " Esc cancel", CCUI_Pal( "dim" ) ) + Chr(10)
   RETURN cOut

// The status line painted just below the input box. Lists the active skills
// as bracketed tags ("[name1] [name2]"). nCols is the terminal width, used to
// pad the line so it overwrites any leftover text from a previous redraw.
// Blank (just spaces) when no skill is active, so the row is visually hidden.
FUNCTION CCUI_SkillsStatusLine( aActive, nCols )
   LOCAL cLine := "", cName
   IF ValType( aActive ) == "A" .AND. Len( aActive ) > 0
      FOR EACH cName IN aActive
         cLine += "[" + hb_CStr( cName ) + "] "
      NEXT
      cLine := RTrim( cLine )
   ENDIF
   // pad to nCols-1: filling the very last column triggers auto-wrap and
   // scrolls the screen up one row, which would corrupt the layout
   cLine := PadR( cLine, Max( 1, nCols - 1 ) )
   RETURN CCUI_Color( cLine, CCUI_Pal( "accent" ) )

// Renders the multi-line block used for every tool call: a cyan-violet rule
// the full terminal width, the tool's display label ("Bash command", "Edit",
// "Read", ...) on its own line, a blank, then the tool's primary content
// (the command / path / pattern) in green, then the model's narration on a
// Tool content without the old separator bar — just command + explanation,
// indented 3 spaces. Used with the new bullet-based tool header.
FUNCTION CCUI_ToolContentBlock( cArgsJson, cExplain, nCols )
   LOCAL cContent, cLine, cOut := ""
   IF ValType( nCols ) != "N" .OR. nCols < 20
      nCols := 100
   ENDIF
   cContent := CCUI_ToolContent( cArgsJson )
   FOR EACH cLine IN hb_ATokens( hb_CStr( cContent ), Chr(10) )
      cOut += CCUI_Color( "   " + cLine, CCUI_Pal( "bash_command" ) ) + Chr(10)
   NEXT
   IF !Empty( cExplain )
      FOR EACH cLine IN hb_ATokens( hb_CStr( cExplain ), Chr(10) )
         cOut += CCUI_Color( "   " + cLine, CCUI_Pal( "bash_explain" ) ) + Chr(10)
      NEXT
   ENDIF
   RETURN cOut

// soft-white line. Every line is plain (no border) and indented three
// spaces to match Claude Code's tool-call style.
FUNCTION CCUI_ToolBlock( cHeader, cContent, cExplain, nCols )
   LOCAL cOut, cLine
   IF ValType( nCols ) != "N" .OR. nCols < 20
      nCols := 100
   ENDIF
   // Unicode box-drawings ─ is 0xE2 0x94 0x80
   cOut := Chr(10) + ;
           CCUI_Color( Replicate( Chr(226)+Chr(148)+Chr(128), nCols - 1 ), ;
                       CCUI_Pal( "bash_header" ) ) + Chr(10) + ;
           CCUI_Color( " " + hb_CStr( cHeader ), CCUI_Pal( "bash_header" ) ) + ;
           Chr(10)
   // only add the spacer line when there is content or an explanation to
   // separate from the header -- ask_user uses an empty content block and
   // wants the QuestionBlock to land right under the label
   IF !Empty( cContent ) .OR. !Empty( cExplain )
      cOut += Chr(10)
   ENDIF
   FOR EACH cLine IN hb_ATokens( hb_CStr( cContent ), Chr(10) )
      cOut += CCUI_Color( "   " + cLine, CCUI_Pal( "bash_command" ) ) + Chr(10)
   NEXT
   IF !Empty( cExplain )
      FOR EACH cLine IN hb_ATokens( AllTrim( hb_CStr( cExplain ) ), Chr(10) )
         IF !Empty( cLine )
            cOut += CCUI_Color( "   " + cLine, ;
                                CCUI_Pal( "bash_explain" ) ) + Chr(10)
         ENDIF
      NEXT
   ENDIF
   RETURN cOut

// Maps a tool name to the header text used in CCUI_ToolBlock. "shell" is
// special-cased to "Bash command" since users recognise that label from
// Claude Code; every other tool name is capitalised and underscores become
// spaces ("github_read" -> "Github read").
FUNCTION CCUI_ToolHeader( cName )
   LOCAL cLow := Lower( hb_CStr( cName ) )
   IF cLow == "shell"
      RETURN "Bash command"
   ENDIF
   cLow := StrTran( cLow, "_", " " )
   RETURN Upper( Left( cLow, 1 ) ) + SubStr( cLow, 2 )

// Extracts the "main" argument from a tool's JSON args -- the thing the
// user wants to see in full inside the tool block. The first key found,
// in priority order: command, path, pattern, url, query, text, name,
// content. Falls back to the raw JSON when none match.
FUNCTION CCUI_ToolContent( cArgsJson )
   LOCAL xArgs, aKeys, cKey
   xArgs := hb_jsonDecode( hb_CStr( cArgsJson ) )
   IF ValType( xArgs ) != "H"
      RETURN hb_CStr( cArgsJson )
   ENDIF
   aKeys := { "command", "path", "pattern", "url", "query", ;
              "text", "name", "content" }
   FOR EACH cKey IN aKeys
      IF hb_HHasKey( xArgs, cKey )
         RETURN hb_CStr( xArgs[ cKey ] )
      ENDIF
   NEXT
   RETURN hb_jsonEncode( xArgs )

// One framed input-box prompt line with the text rendered in the suggestion
// (light-green) colour.
FUNCTION CCUI_InputBoxSuggestion( cText )
   RETURN CCUI_Color( "> ", "1;36" ) + ;
          CCUI_Color( CCUI_PadCell( hb_CStr( cText ), CCUI_InputInnerWidth(), "L" ), ;
                     CCUI_Pal( "suggestion" ) )

// One input-box prompt line: the "> " prompt and cText, no side borders.
FUNCTION CCUI_InputBoxLine( cText )
   RETURN CCUI_Color( "> ", "1;36" ) + ;
          CCUI_PadCell( hb_CStr( cText ), CCUI_InputInnerWidth(), "L" )

// Prompt shown when the user presses Esc to pause tool execution.
// Options: Enter=continue, c=skip remaining tools, a=abort turn.
FUNCTION CCUI_PausePrompt()
   LOCAL cOut := Chr(10)
   cOut += CCUI_Color( CCUI_Glyph( "tl" ) + Replicate( CCUI_Glyph( "h" ), 42 ) + ;
                       CCUI_Glyph( "tr" ), CCUI_Pal( "warn" ) ) + Chr(10)
   cOut += CCUI_Color( CCUI_Glyph( "v" ), CCUI_Pal( "warn" ) ) + ;
           "  " + CCUI_Color( "[PAUSED]", "1;33" ) + ;
           "  Next tool paused by Esc" + ;
           CCUI_Color( "  " + CCUI_Glyph( "v" ), CCUI_Pal( "warn" ) ) + Chr(10)
   cOut += CCUI_Color( CCUI_Glyph( "v" ), CCUI_Pal( "warn" ) ) + ;
           "  Enter=run tool   c=skip all   a=abort turn" + ;
           CCUI_Color( "  " + CCUI_Glyph( "v" ), CCUI_Pal( "warn" ) ) + Chr(10)
   cOut += CCUI_Color( CCUI_Glyph( "bl" ) + Replicate( CCUI_Glyph( "h" ), 42 ) + ;
                       CCUI_Glyph( "br" ), CCUI_Pal( "warn" ) ) + Chr(10)
   cOut += CCUI_Color( "> ", "1;36" )
   RETURN cOut

// The text shown by the /help command.
FUNCTION CCUI_Help()
   RETURN "Commands:" + Chr(10) + ;
          "  /help          show this help" + Chr(10) + ;
          "  /init          analyse the project and write CC.md" + Chr(10) + ;
          "  /model [name]  show the model, or switch to <name>" + Chr(10) + ;
          "  /cost          show token usage and estimated cost" + Chr(10) + ;
          "  /save [name]   save the conversation" + Chr(10) + ;
          "  /load [name]   load a saved conversation" + Chr(10) + ;
          "  /clear         reset the conversation" + Chr(10) + ;
          "  /caveman       activate the caveman skill (terse replies)" + Chr(10) + ;
          "  /plan [tarea]  generate a 3-6 step plan card (web Agents style)" + Chr(10) + ;
          "  /plan add|del|done|edit <n>  edit the plan steps" + Chr(10) + ;
          "  /run           execute the plan step by step (pauses on questions)" + Chr(10) + ;
          "  /demo          showcase the card UI with sample content (no API)" + Chr(10) + ;
          "  /sh <cmd>      run a shell command directly (also /shell /bash)" + Chr(10) + ;
          "  /git [args]    git passthrough (default: status); /clone <repo>" + Chr(10) + ;
          "  /key <secret>  save the API key (alias of /provider key)" + Chr(10) + ;
          "  /skill [name]  list skills as a card, or toggle one on/off" + Chr(10) + ;
          "  /tool          tools registry card (red mutating / green read-only)" + Chr(10) + ;
          "  /plan mode     enter plan mode (lock write/edit/shell)" + Chr(10) + ;
          "  /plan accept   approve the plan, unlock and proceed" + Chr(10) + ;
          "  /plan cancel   drop the plan and exit plan mode" + Chr(10) + ;
          "  /lean          enter lean mode (trim system prompt, save tokens)" + Chr(10) + ;
          "  /lean off      restore the full system prompt" + Chr(10) + ;
          "  /provider      show / switch backend (deepseek/glm/moonshot/openai)" + Chr(10) + ;
          "  /provider key  store the API key for the current backend" + Chr(10) + ;
          "  /goal          show the current goal" + Chr(10) + ;
          "  /goal <text>   set a goal -- keep working until the condition is met" + Chr(10) + ;
          "  /goal stop     stop the auto-continue loop without dropping the goal" + Chr(10) + ;
          "  /goal clear    drop the goal" + Chr(10) + ;
          "  /tasks         list background subagent tasks (dispatch_agent_background)" + Chr(10) + ;
          "  /tasks view <id>  show full record for one task" + Chr(10) + ;
          "  /tasks kill <id>  request cancellation of a running task" + Chr(10) + ;
          "  /tasks clear   drop finished/failed/cancelled tasks from the list" + Chr(10) + ;
          "  /compact       summarise old turns to free up context" + Chr(10) + ;
          "  /ctx           show model context window size and usage" + Chr(10) + ;
          "  /ctx <N>       set context window to N tokens (affects /compact)" + Chr(10) + ;
          "  /ctx auto      reset to auto-detected from the model" + Chr(10) + ;
          "  /loop <int> <p>  re-run prompt <p> every <int> (e.g. 5m, 30s, 1h)" + Chr(10) + ;
          "  /loop status   show the active loop (if any)" + Chr(10) + ;
          "  /loop stop     stop the active loop" + Chr(10) + ;
          "  /rewind        undo the last conversation turn (double-tap Esc)" + Chr(10) + ;
          "  /rewind <N>    undo the last N turns" + Chr(10) + ;
          "  /btw <text>    interrupt the running turn; answer <text> next" + Chr(10) + ;
          "  /exit          quit (alias: /quit)" + Chr(10) + ;
          "Type anything else to talk to the assistant."
