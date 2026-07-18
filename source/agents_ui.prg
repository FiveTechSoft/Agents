// Whether AGUI_Color emits ANSI colour codes (off unless the REPL turns it on).
STATIC s_lColor := .F.

// Classifies a line of REPL input. Returns a hash with:
//   "type" => "exit"|"clear"|"help"|"init"|"model"|"cost"|"message"|"empty"
//   "text" => the trimmed line, or the command argument for "model"
FUNCTION AGUI_ParseCommand( cLine )
   LOCAL cTrim := hb_CStr( cLine )
   LOCAL cLow
   // Normalize: drop CR/LF/TAB and UTF-8 BOM so "/help" from the box or
   // paste always matches (AllTrim alone does not strip Chr(13)).
   cTrim := StrTran( cTrim, Chr(13), "" )
   cTrim := StrTran( cTrim, Chr(10), "" )
   cTrim := StrTran( cTrim, Chr(9), " " )
   IF Left( cTrim, 3 ) == Chr(239) + Chr(187) + Chr(191)
      cTrim := SubStr( cTrim, 4 )
   ENDIF
   cTrim := AllTrim( cTrim )
   cLow  := Lower( cTrim )
   DO CASE
   CASE Empty( cTrim )
      RETURN { "type" => "empty", "text" => "" }
   // /exit, /quit, /bye (+ bare exit/quit/bye). Same action: leave the REPL.
   CASE cLow == "/exit" .OR. Left( cLow, 6 ) == "/exit " .OR. ;
        cLow == "/quit" .OR. Left( cLow, 6 ) == "/quit " .OR. ;
        cLow == "/bye"  .OR. Left( cLow, 5 ) == "/bye "  .OR. ;
        cLow == "exit"  .OR. cLow == "quit" .OR. cLow == "bye"
      RETURN { "type" => "exit", "text" => cTrim }
   CASE cLow == "/clear"
      RETURN { "type" => "clear", "text" => cTrim }
   // /help, /help ..., help, ?
   CASE cLow == "/help" .OR. Left( cLow, 6 ) == "/help " .OR. ;
        cLow == "help" .OR. cLow == "?"
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
   CASE cLow == "/demo" .OR. Left( cLow, 6 ) == "/demo " .OR. cLow == "demo"
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
      // AGPROMPT_Classify); at the cooked prompt or any other path that
      // routes through here, just strip the prefix and treat the rest as
      // an ordinary message to the model.
      RETURN { "type" => "message", ;
               "text" => AllTrim( SubStr( cTrim, 6 ) ) }
   ENDCASE
   RETURN { "type" => "message", "text" => cTrim }

// The instruction sent to the agent by the /init command: it asks the model
// to inspect the project and write a CC.md file.
FUNCTION AGUI_InitPrompt()
   RETURN "Analyse this project and create a CC.md file in the working " + ;
          "directory. Use your tools to explore the repository: its layout, " + ;
          "how it is built and run, and its coding conventions. CC.md " + ;
          "should concisely cover: what the project is, how to build and run " + ;
          "it, the key directories, and the coding conventions to follow. " + ;
          "Keep it short. Write the file with your write tool, then confirm."

// Formats a session usage hash into a human-readable cost report.
// hUsage: { prompt_tokens => N, completion_tokens => N, ... }
// Pricing is approximate (DeepSeek API rates).
FUNCTION AGUI_CostReport( hUsage )
   LOCAL nIn, nOut, nHit, cOut, nCostTotal, nW := 46
   IF ValType( hUsage ) != "H" .OR. Len( hb_HKeys( hUsage ) ) == 0
      RETURN AGUI_Color( "No usage data for this session yet.", "90" ) + Chr(10)
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
   cOut := AGUI_CardLine( AGUI_Color( "Session cost report", "1" ) + ;
           Space( 8 ) + AGUI_Color( "$" + LTrim( Str( nCostTotal, 10, 4 ) ), "1;97" ), ;
           "card_cost", nW ) + Chr(10)
   cOut += AGUI_CardLine( "", "card_cost", nW ) + Chr(10)
   cOut += AGUI_CardLine( "input (context):     " + ;
           LTrim( Str( nIn ) ) + " tokens", "card_cost", nW ) + Chr(10)
   IF nHit > 0
      cOut += AGUI_CardLine( AGUI_Color( "  cached (98% off):  " + ;
              LTrim( Str( nHit ) ) + " tokens", "2" ), "card_cost", nW ) + Chr(10)
   ENDIF
   cOut += AGUI_CardLine( "output (generated):  " + ;
           LTrim( Str( nOut ) ) + " tokens", "card_cost", nW ) + Chr(10)
   cOut += AGUI_CardLine( AGUI_Color( "total:               " + ;
           LTrim( Str( nIn + nOut ) ) + " tokens", "1" ), "card_cost", nW ) + Chr(10)
   RETURN cOut

// Returns the sessions directory path (.agents/sessions under the
// working directory, or AGENTS_CONFIG).
FUNCTION AGUI_SessionDir()
   LOCAL cBase := hb_GetEnv( "AGENTS_CONFIG" )
   IF Empty( cBase )
      cBase := hb_cwd() + hb_ps() + ".agents"
   ENDIF
   RETURN cBase + hb_ps() + "sessions"

// Ensures the sessions directory exists. Returns .T. on success.
FUNCTION AGUI_EnsureSessionDir()
   LOCAL cDir := AGUI_SessionDir()
   IF !hb_DirExists( cDir )
      RETURN hb_DirCreate( cDir )
   ENDIF
   RETURN .T.

// Returns the full path for a session name (adds .json extension).
FUNCTION AGUI_SessionPath( cName )
   RETURN AGUI_SessionDir() + hb_ps() + cName + ".json"

// Lists saved session files in the sessions directory.
// Returns an array of { name, path, mtime } hashes, or empty array.
FUNCTION AGUI_SessionList()
   LOCAL cDir := AGUI_SessionDir(), aFiles, aOut := {}, hFile, cName
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
FUNCTION AGUI_SessionListOutput( aSessions )
   LOCAL cOut := "", hS, cTime
   IF Len( aSessions ) == 0
      RETURN AGUI_Color( "No saved sessions found.", "90" ) + Chr(10)
   ENDIF
   cOut := AGUI_Color( "Saved sessions:", "1" ) + Chr(10)
   FOR EACH hS IN aSessions
      // mtime is a DATE; DToC formats it as "yyyy-mm-dd" via SET DATE FORMAT
      // (or the locale default). Prior code did `DToS(d) + " " + d` which
      // tried to concatenate a DATE with a string and crashed with
      // "Argument error" the first time /load was run against a directory
      // that actually contained a saved session.
      cTime := DToC( hS[ "mtime" ] )
      cOut += "  " + hS[ "name" ] + AGUI_Color( "  (" + cTime + ")", "90" ) + Chr(10)
   NEXT
   cOut += AGUI_Color( "Use /load <name> to restore a session.", "90" ) + Chr(10)
   RETURN cOut

// Returns the first line of cText, truncated to nMax characters, with a
// "[<N> chars]" annotation when anything was dropped. nMax defaults to 80.
FUNCTION AGUI_Summarize( cText, nMax )
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
FUNCTION AGUI_RenderEvent( hEv )
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
      IF AGUI_ColorOn()
         RETURN Chr(10) + AGUI_Card( AGUI_Color( "!! error: " + ;
                hb_CStr( hEv[ "message" ] ), "1;91" ), "card_err" ) + Chr(10)
      ENDIF
      RETURN Chr(10) + AGUI_Color( "!! error: " + hb_CStr( hEv[ "message" ] ), ;
             "31" ) + Chr(10)
   ENDCASE
   RETURN ""

// Builds a Claude Code-style tool label: "Read(src/x.prg)", "Shell(echo hi)".
// The tool name is capitalised; the most relevant argument goes in parentheses.
STATIC FUNCTION AGUI_ToolLabel( cName, cArgsJson )
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

// Grok-style diff / result block: full-width green/red bars with line
// numbers (no corner glyph clutter). Matches grok3/grok5 screenshots.
STATIC FUNCTION AGUI_ResultBlock( cText )
   LOCAL aLines, cOut := "", i, nShow, cLine, cMark, nMax := 80, nWidth
   aLines := hb_ATokens( StrTran( cText, Chr(13), "" ), Chr(10) )
   DO WHILE Len( aLines ) > 1 .AND. Empty( ATail( aLines ) )
      hb_ADel( aLines, Len( aLines ), .T. )
   ENDDO
   nShow := Min( Len( aLines ), nMax )
   nWidth := Max( 60, AGREPL_Cols() - 2 )
   FOR i := 1 TO nShow
      cLine := aLines[ i ]
      cMark := AGUI_DiffMark( cLine )
      IF cMark == "+" .OR. cMark == "-"
         nWidth := Max( nWidth, hb_UTF8Len( cLine ) + 2 )
      ENDIF
   NEXT
   FOR i := 1 TO nShow
      cLine := aLines[ i ]
      cMark := AGUI_DiffMark( cLine )
      DO CASE
      CASE cMark == "+"
         // full-row green bar (Grok added lines)
         cOut += AGUI_Color( AGUI_DiffPad( cLine, nWidth ), "97;48;2;22;70;40" )
      CASE cMark == "-"
         // full-row red bar (Grok removed lines)
         cOut += AGUI_Color( AGUI_DiffPad( cLine, nWidth ), "97;48;2;90;30;30" )
      OTHERWISE
         // context / header lines stay dim, no heavy indent
         cOut += AGUI_Color( cLine, AGUI_Pal( "dim" ) )
      ENDCASE
      IF i < nShow .OR. Len( aLines ) > nMax
         cOut += Chr(10)
      ENDIF
   NEXT
   IF Len( aLines ) > nMax
      cOut += AGUI_Color( "... (" + LTrim( Str( Len( aLines ) - nMax ) ) + ;
              " more lines)", AGUI_Pal( "dim" ) )
   ENDIF
   RETURN cOut

// Pads a diff line with trailing spaces so its background colour fills the
// row (a coloured diff bar spans the line rather than stopping at the text).
// nWidth is the target visual width; a line already at or over it is
// returned unchanged. nWidth defaults to 110 (the original fixed width).
FUNCTION AGUI_DiffPad( cLine, nWidth )
   LOCAL nLen := hb_UTF8Len( hb_CStr( cLine ) )
   IF ValType( nWidth ) != "N" .OR. nWidth < 1
      nWidth := 110
   ENDIF
   RETURN iif( nLen < nWidth, cLine + Space( nWidth - nLen ), cLine )

// The Claude Code-style tool-call line: an accent dot, then Tool(args). The
// dot is accent-coloured; the label is left in the default foreground.
FUNCTION AGUI_ToolCallLine( cName, cArgsJson )
   RETURN Chr(10) + ;
          AGUI_Color( Chr(226)+Chr(143)+Chr(186), AGUI_Pal( "accent" ) ) + ;
          "  " + AGUI_ToolLabel( cName, cArgsJson ) + Chr(10)

// True when any line of cText is diff-formatted (per AGUI_DiffMark).
STATIC FUNCTION AGUI_HasDiff( cText )
   LOCAL cLine
   FOR EACH cLine IN hb_ATokens( cText, Chr(10) )
      IF !Empty( AGUI_DiffMark( cLine ) )
         RETURN .T.
      ENDIF
   NEXT
   RETURN .F.

// Renders the block printed under a tool call. Diff-formatted content keeps
// the coloured diff block; otherwise a compact tool-aware one-line summary.
// Result ends in LF.
// Grok5-style one-line tool summary after a tool finishes, or a full
// coloured diff block when the content is a line-diff.
FUNCTION AGUI_ResultSummary( cToolName, cContent )
   LOCAL cClean, aLines, nLines, cFirst, cSum
   cToolName := Lower( hb_CStr( cToolName ) )
   cContent  := hb_CStr( cContent )
   cClean    := StrTran( cContent, Chr(13), "" )

   // Diffs paint as full green/red rows (no extra indent wrapper)
   IF AGUI_HasDiff( cClean )
      RETURN AGUI_ResultBlock( cContent ) + Chr(10)
   ENDIF

   IF Left( cClean, 6 ) == "Error:"
      cSum := AGUI_Summarize( cClean, 200 )
   ELSE
      aLines := hb_ATokens( cClean, Chr(10) )
      DO WHILE Len( aLines ) > 1 .AND. Empty( ATail( aLines ) )
         hb_ADel( aLines, Len( aLines ), .T. )
      ENDDO
      nLines := Len( aLines )
      cFirst := Left( iif( nLines > 0, aLines[ 1 ], "" ), 120 )
      DO CASE
      CASE cToolName == "read"
         // Grok5/6: "Read 1 file"
         cSum := "Read 1 file"
      CASE cToolName == "write"
         cSum := "Wrote file"
      CASE cToolName == "edit"
         cSum := iif( Left( cFirst, 5 ) == "Added", cFirst, "Edited file" )
      CASE cToolName == "glob"
         cSum := iif( Left( cFirst, 11 ) == "No matches ", cFirst, ;
                      "Listed " + LTrim( Str( nLines ) ) + " files" )
      CASE cToolName == "grep"
         cSum := iif( Left( cFirst, 11 ) == "No matches ", cFirst, ;
                      "Searched 1 pattern" + iif( nLines > 0, ;
                      " (" + LTrim( Str( nLines ) ) + " hits)", "" ) )
      CASE cToolName == "shell"
         cSum := "Run " + AGUI_Summarize( cFirst, 50 )
      CASE cToolName == "todo_write" .OR. cToolName == "todo"
         cSum := "Updated tasks"
      OTHERWISE
         cSum := Upper( Left( cToolName, 1 ) ) + Lower( SubStr( cToolName, 2 ) )
      ENDCASE
   ENDIF

   // Diamond activity line (Grok5/6): "♦ Read 1 file"
   RETURN AGUI_GrokAct( cSum ) + Chr(10)

// "♦ <label>" activity line used throughout the Grok transcript.
FUNCTION AGUI_GrokAct( cLabel )
   LOCAL cDia := Chr( 226 ) + Chr( 151 ) + Chr( 134 )   // ◆
   RETURN AGUI_Color( cDia, AGUI_Pal( "dim" ) ) + " " + ;
          AGUI_Color( hb_CStr( cLabel ), AGUI_Pal( "dim" ) )

// Active (running) activity line with a green focus bar on the left.
FUNCTION AGUI_GrokActActive( cLabel )
   LOCAL cDia := Chr( 226 ) + Chr( 151 ) + Chr( 134 )
   RETURN AGUI_Color( "|", "92" ) + " " + ;
          AGUI_Color( cDia, "92" ) + " " + ;
          AGUI_Color( hb_CStr( cLabel ), "97" )

// Detects a diff line ("<6-wide number> <+|-|space> <text>"); returns the
// marker "+" or "-", or "" when the line is not a diff line.
STATIC FUNCTION AGUI_DiffMark( cLine )
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
FUNCTION AGUI_SetColor( lOn )
   s_lColor := ( lOn == .T. )
   RETURN NIL

// Wraps text in an ANSI SGR colour code when colour is enabled, otherwise
// returns the text unchanged. cSGR is the code, e.g. "36" (cyan), "90" (grey),
// "31" (red), "1;36" (bold cyan), "33" (yellow).
FUNCTION AGUI_Color( cText, cSGR )
   IF !s_lColor
      RETURN cText
   ENDIF
   RETURN Chr(27) + "[" + cSGR + "m" + cText + Chr(27) + "[0m"

// Returns .T. when ANSI output (colour and cursor control) is enabled.
FUNCTION AGUI_ColorOn()
   RETURN s_lColor

// The Claude Code-style colour palette: maps a name to an ANSI SGR code so
// the codes live in one place. Unknown names return "0" (reset).
FUNCTION AGUI_Pal( cName )
   DO CASE
   CASE cName == "accent"     ; RETURN "38;2;217;119;87"   // Claude Code coral
   CASE cName == "amber"      ; RETURN "38;2;218;165;32"  // OpenCode amber/gold
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
   CASE cName == "card_grok_user" ; RETURN "48;2;55;55;58" // Grok gray user bar
   CASE cName == "card_grok_task" ; RETURN "48;2;48;48;52" // Grok task row (slightly lighter)
   CASE cName == "card_goal"  ; RETURN "48;2;62;56;124"   // goal card (indigo)
   CASE cName == "card_ctx"   ; RETURN "48;2;92;52;30"    // context-critical (orange)
   CASE cName == "card_tool"  ; RETURN "48;2;38;47;60"    // tool actions panel (faint)
   ENDCASE
   RETURN "0"

// Visible column width of a string: ANSI CSI sequences are skipped and
// UTF-8 continuation bytes are not counted (close enough for card padding).
FUNCTION AGUI_VisLen( cText )
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
FUNCTION AGUI_CardLine( cLine, cBgPal, nWidth )
   LOCAL cBg, nVis
   cLine := hb_CStr( cLine )
   IF !AGUI_ColorOn()
      RETURN "  " + cLine
   ENDIF
   IF ValType( nWidth ) != "N" .OR. nWidth < 20
      nWidth := 80
   ENDIF
   cBg   := Chr(27) + "[" + AGUI_Pal( cBgPal ) + "m"
   cLine := "  " + cLine + "  "
   nVis  := AGUI_VisLen( cLine )
   IF nVis < nWidth
      cLine += Space( nWidth - nVis )
   ENDIF
   cLine := StrTran( cLine, Chr(27) + "[0m", Chr(27) + "[0m" + cBg )
   RETURN cBg + cLine + Chr(27) + "[0m"

// Paints a whole (possibly multi-line) block as a card, one row per line.
// Returns the block without a trailing LF.
FUNCTION AGUI_Card( cText, cBgPal, nWidth )
   LOCAL aLines := hb_ATokens( StrTran( hb_CStr( cText ), Chr(13), "" ), Chr(10) )
   LOCAL cOut := "", i
   FOR i := 1 TO Len( aLines )
      cOut += AGUI_CardLine( aLines[ i ], cBgPal, nWidth ) + ;
              iif( i < Len( aLines ), Chr(10), "" )
   NEXT
   RETURN cOut

// Emits an ANSI control sequence (e.g. "1A" = cursor up one line,
// "1G" = move to column 1) when ANSI output is enabled, else "".
FUNCTION AGUI_VT( cSeq )
   IF !s_lColor
      RETURN ""
   ENDIF
   RETURN Chr(27) + "[" + cSeq

// The VT sequence that wipes the terminal: ESC[3J clears scrollback,
// ESC[2J clears the visible screen, ESC[H homes the cursor. Returned
// unconditionally; callers decide whether the terminal can accept it.
FUNCTION AGUI_ClearScreenSeq()
   RETURN Chr(27) + "[3J" + Chr(27) + "[2J" + Chr(27) + "[H"

// The system message seeded into every conversation. When a CC.md file is
// present in the working directory its contents are appended as project
// instructions, so the agent honours per-project conventions. When a
// memory.md file is present it is appended as the agent's persisted memory.
FUNCTION AGUI_SystemPrompt()
   LOCAL cBase, cProj, cMem
   // lean mode: minimal prompt for token-saving sessions
   IF AGREPL_LeanMode()
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
   cProj := AGUI_ProjectContext()
   IF !Empty( cProj )
      cBase += Chr(10) + Chr(10) + ;
         "The following project instructions come from the CC.md file in " + ;
         "the working directory. Treat them as authoritative and follow them:" + ;
         Chr(10) + Chr(10) + cProj
   ENDIF
   cMem := AGUI_MemoryContext()
   IF !Empty( cMem )
      cBase += Chr(10) + Chr(10) + ;
         "The following is your own memory, persisted from previous sessions " + ;
         "in this project. Use it, and keep it current with the memory tool:" + ;
         Chr(10) + Chr(10) + cMem
   ENDIF
   cBase += AGUI_SkillsContext()
   RETURN cBase

// Lists the skills found under .agents/skills/ so the model knows what is
// available without loading every body up front. The model picks one with
// the use_skill tool; that call returns the full body. Returns "" when no
// skills are present so the system prompt stays unchanged.
FUNCTION AGUI_SkillsContext()
   LOCAL aSkills := AGSKILL_List(), hSkill, cOut
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
FUNCTION AGUI_ProjectContext()
   LOCAL cText := ""
   IF File( "CC.md" )
      cText := hb_MemoRead( "CC.md" )
   ENDIF
   RETURN AllTrim( hb_CStr( cText ) )

// Reads the agent's persisted memory from memory.md in the current directory.
// Returns "" when the file is absent or empty.
FUNCTION AGUI_MemoryContext()
   LOCAL cText := ""
   IF File( "memory.md" )
      cText := hb_MemoRead( "memory.md" )
   ENDIF
   RETURN AllTrim( hb_CStr( cText ) )

// Returns a UTF-8 box-drawing glyph by name, built from raw bytes so the
// source file's encoding does not matter.
FUNCTION AGUI_Glyph( cName )
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
STATIC FUNCTION AGUI_PadCell( cText, nWidth, cAlign )
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
FUNCTION AGUI_Version()
   RETURN "2.4.8"

// The pool of short usage tips shown on the banner and at the idle prompt.
FUNCTION AGUI_Tips()
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
FUNCTION AGUI_TipAt( nIndex )
   LOCAL aTips := AGUI_Tips()
   LOCAL nMod  := ( nIndex - 1 ) % Len( aTips )
   IF nMod < 0
      nMod += Len( aTips )
   ENDIF
   RETURN aTips[ nMod + 1 ]

// Formats one tip as a dim-coloured "Tip: <text>" line ending in LF.
FUNCTION AGUI_TipLine( cTip )
   RETURN AGUI_Color( "Tip: " + hb_CStr( cTip ), AGUI_Pal( "dim" ) ) + Chr(10)

// Returns the first non-empty, trimmed line of cText (CR stripped). When no
// such line exists, returns cFallback. Used for the banner's "What's new".
FUNCTION AGUI_ReleaseTagline( cText, cFallback )
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
FUNCTION AGUI_WhatsNew()
   LOCAL cFallback := "Agents v" + AGUI_Version()
   LOCAL cPath := hb_DirBase() + "releasenotes.md"
   IF !hb_FileExists( cPath )
      cPath := "releasenotes.md"
   ENDIF
   IF hb_FileExists( cPath )
      RETURN AGUI_ReleaseTagline( hb_MemoRead( cPath ), cFallback )
   ENDIF
   RETURN cFallback

// Builds a banner cell: text, alignment ("L"/"C"/"R"), and an SGR code ("" = none).
FUNCTION AGUI_Cell( cText, cAlign, cSGR )
   RETURN { "text" => hb_CStr( cText ), ;
            "align" => iif( Empty( cAlign ), "L", cAlign ), ;
            "sgr" => hb_CStr( cSGR ), ;
            "raw" => .F. }

// A cell whose text already carries its own ANSI escapes and padding;
// the panel row renders it verbatim and skips PadCell + Color wrapping.
FUNCTION AGUI_CellRaw( cText )
   RETURN { "text" => hb_CStr( cText ), ;
            "align" => "L", "sgr" => "", "raw" => .T. }

// Renders one cell to nWidth display columns, padded then colour-wrapped.
// Raw cells are emitted as-is (they carry their own colour and padding).
STATIC FUNCTION AGUI_PanelRow( hCell, nWidth )
   LOCAL cCell
   IF hb_HHasKey( hCell, "raw" ) .AND. hCell[ "raw" ] == .T.
      RETURN hCell[ "text" ]
   ENDIF
   cCell := AGUI_PadCell( hCell[ "text" ], nWidth, hCell[ "align" ] )
   IF !Empty( hCell[ "sgr" ] )
      cCell := AGUI_Color( cCell, hCell[ "sgr" ] )
   ENDIF
   RETURN cCell

// Renders one logo row with a per-character magenta -> violet gradient
// (24-bit true colour). Spaces are emitted unchanged; the line is padded
// to nPanelW with normal spaces so the row sits centred in the banner
// panel. When colour is off the gradient is skipped -- only padding.
FUNCTION AGUI_LogoGradientRow( cLine, nPanelW )
   LOCAL i, n, c, t, r, g, b
   LOCAL nLogo := hb_UTF8Len( cLine )
   LOCAL nLeftPad, nRightPad, cOut
   IF nPanelW < nLogo  ; nPanelW := nLogo  ; ENDIF
   nLeftPad  := Int( ( nPanelW - nLogo ) / 2 )
   nRightPad := nPanelW - nLogo - nLeftPad
   cOut := Space( nLeftPad )
   IF !AGUI_ColorOn()
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
FUNCTION AGUI_BannerJoin( aLeft, aRight, nLeftW, nRightW )
   LOCAL aOut := {}, nRows, i, hL, hR
   LOCAL hBlank := AGUI_Cell( "", "L", "" )
   LOCAL cDiv := " " + AGUI_Color( AGUI_Glyph( "v" ), AGUI_Pal( "dim" ) ) + " "
   nRows := Max( Len( aLeft ), Len( aRight ) )
   FOR i := 1 TO nRows
      hL := iif( i <= Len( aLeft ),  aLeft[ i ],  hBlank )
      hR := iif( i <= Len( aRight ), aRight[ i ], hBlank )
      AAdd( aOut, AGUI_PanelRow( hL, nLeftW ) + cDiv + AGUI_PanelRow( hR, nRightW ) )
   NEXT
   RETURN aOut

// Renders a AGSEL selector state to a printable block: a "●" bullet and the
// question, then one numbered row per option. The row at the cursor is marked
// with a "❯" arrow and inverse video; other rows get two leading spaces.
// Each line ends in LF. Pure -- no console I/O.
FUNCTION AGUI_QuestionBlock( oSel )
   LOCAL cOut, i, aOpts := oSel[ "options" ], cRow
   LOCAL cBullet := Chr(226) + Chr(151) + Chr(143)   // U+25CF ●
   LOCAL cArrow  := Chr(226) + Chr(157) + Chr(175)   // U+276F ❯
   cOut := AGUI_Color( cBullet, AGUI_Pal( "accent" ) ) + " " + ;
           AGUI_Color( oSel[ "question" ], AGUI_Pal( "bold" ) ) + ;
           Chr(10) + Chr(10)   // blank line between question and options
   FOR i := 1 TO Len( aOpts )
      cRow := iif( i == oSel[ "cursor" ], cArrow + " ", "  " ) + ;
              LTrim( Str( i ) ) + ". " + aOpts[ i ]
      IF i == oSel[ "cursor" ]
         cRow := AGUI_Color( cRow, AGUI_Pal( "invert" ) )
      ENDIF
      cOut += cRow + Chr(10)
   NEXT
   cOut += Chr(10)   // blank line between options and the hint tail
   cOut += AGUI_Color( "  Esc to cancel " + Chr(194) + Chr(183) + ;
                       " Tab to amend " + Chr(194) + Chr(183) + ;
                       " ctrl+e to explain", AGUI_Pal( "dim" ) ) + Chr(10)
   RETURN cOut

// OpenCode-style todo checklist (opencode1.jpg):
//   [•] active task in amber
//   [x] completed (dim)
//   [ ] pending (dim)
// No heavy bars — clean monospaced list like OpenCode's left panel.
FUNCTION AGUI_TodoBlock( aTodos )
   LOCAL cOut := "", hItem, cBox, cLabel, lBlocked
   IF ValType( aTodos ) != "A" .OR. Len( aTodos ) == 0
      RETURN ""
   ENDIF
   FOR EACH hItem IN aTodos
      cLabel := hItem[ "text" ]
      IF hItem[ "status" ] == "in_progress" .AND. ;
         hb_HHasKey( hItem, "active_form" ) .AND. ;
         !Empty( hItem[ "active_form" ] )
         cLabel := hItem[ "active_form" ]
      ENDIF
      lBlocked := AGTODO_IsBlocked( hItem, aTodos ) .AND. ;
                  hItem[ "status" ] != "completed"
      IF lBlocked
         cLabel := cLabel + " (blocked)"
      ENDIF
      DO CASE
      CASE hItem[ "status" ] == "completed"
         cBox := AGUI_Color( "[x]", AGUI_Pal( "dim" ) )
         cOut += cBox + " " + AGUI_Color( cLabel, AGUI_Pal( "dim" ) ) + Chr(10)
      CASE hItem[ "status" ] == "in_progress"
         // OpenCode amber bullet [•]
         cBox := AGUI_Color( "[" + Chr( 226 ) + Chr( 128 ) + Chr( 162 ) + "]", ;
                             AGUI_Pal( "amber" ) )
         cOut += cBox + " " + AGUI_Color( cLabel, AGUI_Pal( "amber" ) ) + Chr(10)
      OTHERWISE
         cBox := AGUI_Color( "[ ]", AGUI_Pal( "dim" ) )
         cOut += cBox + " " + AGUI_Color( cLabel, AGUI_Pal( "dim" ) ) + Chr(10)
      ENDCASE
   NEXT
   RETURN cOut

// OpenCode model chip (opencode1.jpg): "□ Build · qwen3.6:latest"
FUNCTION AGUI_ModelChip( cModel )
   LOCAL cM := hb_CStr( cModel )
   LOCAL cSq
   IF Empty( cM )
      cM := "model"
   ENDIF
   // U+25A1 WHITE SQUARE
   cSq := Chr( 226 ) + Chr( 150 ) + Chr( 161 )
   RETURN AGUI_Color( cSq + " Build " + Chr( 194 ) + Chr( 183 ) + " " + cM, ;
                      AGUI_Pal( "dim" ) )

// OpenCode footer under the prompt (opencode1.jpg):
//   ······ esc interrupt          48.9K          /help commands
FUNCTION AGUI_OpenCodeFooter( nTokens, nCols )
   LOCAL cLeft, cMid, cRight, nPad, cTok, cDots
   IF ValType( nCols ) != "N" .OR. nCols < 40
      nCols := 80
   ENDIF
   IF ValType( nTokens ) != "N" .OR. nTokens < 0
      nTokens := 0
   ENDIF
   IF nTokens >= 1000
      cTok := LTrim( Str( nTokens / 1000.0, 10, 1 ) ) + "K"
   ELSE
      cTok := LTrim( Str( nTokens ) )
   ENDIF
   // U+00B7 middle dots prefix (OpenCode animated leader)
   cDots  := Replicate( Chr( 194 ) + Chr( 183 ), 6 )
   cLeft  := cDots + " esc interrupt"
   cMid   := cTok
   cRight := "/help commands"
   // Len(cDots) is 12 bytes for 6 UTF-8 chars; visual width is 6.
   // Approximate pad with visual widths so the line fits the terminal.
   nPad   := nCols - 1 - 6 - Len( " esc interrupt" ) - Len( cMid ) - Len( cRight )
   IF nPad < 4
      nPad := 4
   ENDIF
   RETURN AGUI_Color( cLeft + Space( Int( nPad / 2 ) ) + cMid + ;
          Space( nPad - Int( nPad / 2 ) ) + cRight, AGUI_Pal( "dim" ) )

// Builds the two-panel startup banner inside one rounded box, 99 columns wide
// (matching the input frame). Left panel: a "Welcome back" line, the six-row
// block "AG" logo, the name+version and the model. Right panel: a "Tips for
// getting started" list and a "What's new" line from releasenotes.md. The
// shorter panel is blank-padded to equal height. Returns the banner ending in LF.
FUNCTION AGUI_Banner( cModel, cCwd, cUser )
   // Adapts to the current terminal width: nInner is the inside width of
   // the rounded frame (so total banner = nInner + 4). Clamped to keep
   // the logo readable on narrow terminals and contained on wide ones.
   LOCAL nCols := AGREPL_Cols() - 2   // leave 1 col margin per side
   LOCAL nInner, nLeftW, nRightW
   LOCAL cH := AGUI_Glyph( "h" ), cV, cName, aLogo, aLeft, aRight, aRows, cOut, i
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
   cV := AGUI_Color( AGUI_Glyph( "v" ), AGUI_Pal( "dim" ) )

   // the "AG" logo, six rows of block-drawing glyphs
   // Framed "Agents" wordmark — line-art border + text, 6 rows x 28 chars.
   aLogo := { ;
      "┌──────────────────────────┐", ;
      "│                          │", ;
      "│       A g e n t s        │", ;
      "│   Autonomous AI agents   │", ;
      "│                          │", ;
      "└──────────────────────────┘" }

   // left panel: welcome, logo (6, per-char magenta->violet gradient),
   // name+version, model
   aLeft := {}
   AAdd( aLeft, AGUI_Cell( iif( Empty( cName ), "Welcome back!", ;
                                "Welcome back, " + cName + "!" ), "C", "" ) )
   FOR i := 1 TO 6
      AAdd( aLeft, AGUI_CellRaw( AGUI_LogoGradientRow( aLogo[ i ], nLeftW ) ) )
   NEXT
   AAdd( aLeft, AGUI_Cell( "Agents  v" + AGUI_Version(), "C", AGUI_Pal( "accent" ) ) )
   AAdd( aLeft, AGUI_Cell( "model: " + cModel, "C", "" ) )

   // right panel: tips list, divider, what's new (9 rows, matching the left)
   aRight := {}
   AAdd( aRight, AGUI_Cell( "Tips for getting started", "L", AGUI_Pal( "bold" ) ) )
   AAdd( aRight, AGUI_Cell( "", "L", "" ) )
   AAdd( aRight, AGUI_Cell( "Type a request to begin", "L", "" ) )
   AAdd( aRight, AGUI_Cell( "Run /help to list commands", "L", "" ) )
   AAdd( aRight, AGUI_Cell( "Tip: " + ;
         AGUI_TipAt( Int( hb_Random( Len( AGUI_Tips() ) ) ) + 1 ), "L", "" ) )
   AAdd( aRight, AGUI_Cell( Replicate( cH, nRightW ), "L", AGUI_Pal( "dim" ) ) )
   AAdd( aRight, AGUI_Cell( "What's new", "L", AGUI_Pal( "bold" ) ) )
   AAdd( aRight, AGUI_Cell( AGUI_WhatsNew(), "L", AGUI_Pal( "dim" ) ) )
   AAdd( aRight, AGUI_Cell( "cwd: " + cCwd, "L", AGUI_Pal( "dim" ) ) )

   aRows := AGUI_BannerJoin( aLeft, aRight, nLeftW, nRightW )

   cOut := AGUI_Color( AGUI_Glyph( "tl" ) + Replicate( cH, nInner + 2 ) + ;
           AGUI_Glyph( "tr" ), AGUI_Pal( "dim" ) ) + Chr(10)
   FOR i := 1 TO Len( aRows )
      cOut += cV + " " + aRows[ i ] + " " + cV + Chr(10)
   NEXT
   cOut += AGUI_Color( AGUI_Glyph( "bl" ) + Replicate( cH, nInner + 2 ) + ;
           AGUI_Glyph( "br" ), AGUI_Pal( "dim" ) ) + Chr(10)
   RETURN cOut

// The top border of the input frame — a plain horizontal rule with no
// corner glyphs, matching the open-edge look requested by the user.
FUNCTION AGUI_FrameTop()
   LOCAL nFill := AGUI_InputInnerWidth() + 2
   RETURN AGUI_Color( Replicate( AGUI_Glyph( "h" ), nFill ), AGUI_Pal( "dim" ) )

// The bottom border of the input frame. Same width as the top.
FUNCTION AGUI_FrameBottom()
   LOCAL nFill := AGUI_InputInnerWidth() + 2
   RETURN AGUI_Color( Replicate( AGUI_Glyph( "h" ), nFill ), AGUI_Pal( "dim" ) )

// The dim hint line shown beneath the input frame.
// nLines (optional) shows the line count for multi-line input.
FUNCTION AGUI_InputHint( nLines )
   LOCAL cSuffix := ""
   IF ValType( nLines ) == "N" .AND. nLines > 1
      cSuffix := "  " + Chr(226)+Chr(128)+Chr(162) + "  " + LTrim( Str( nLines ) ) + " lines"
   ENDIF
   RETURN AGUI_Color( "  /help for commands" + cSuffix + ;
          "  " + Chr(226)+Chr(128)+Chr(162) + "  /exit /quit /bye", AGUI_Pal( "dim" ) )

// The text-column width available inside the input box. Adapts to the
// current terminal width (AGREPL_Cols) minus a one-column safety margin
// (to avoid auto-wrap on the right edge) minus 6 cols of overhead
// (2 borders + 2 inside spaces + the "> " prompt). Clamped to [70, 200].
FUNCTION AGUI_InputInnerWidth()
   LOCAL nCols := AGREPL_Cols() - 1
   IF nCols < 76 ; nCols := 76 ; ENDIF
   IF nCols > 200 ; nCols := 200 ; ENDIF
   RETURN nCols - 3   // "> " (2 chars) + 1 char right margin

// Renders the propose_agents selector body: a short intro line, one row per
// proposal with a checkbox / index / type / truncated prompt, and a hint
// tail. The caller (AGPROPOSE_Paint) wraps it with the rule + header band.
FUNCTION AGUI_ProposeBlock( oSel )
   LOCAL cOut := "", i, aItems := oSel[ "items" ], cRow, cBox, cType, cPrompt
   LOCAL cCheck := Chr(226) + Chr(156) + Chr(147)   // U+2713 ✓ check
   LOCAL cPend  := Chr(194) + Chr(183)              // U+00B7 · middle dot
   LOCAL cArrow := Chr(226) + Chr(157) + Chr(175)   // U+276F ❯
   LOCAL nMax
   // dynamic max prompt length: terminal width minus the row prefix
   // ("❯ [✓] NN. <type   > ") and a 3-char ellipsis budget
   nMax := AGREPL_Cols() - 22
   IF nMax < 30
      nMax := 30
   ENDIF
   cOut += "  " + AGUI_Color( ;
      "The agent suggests these subagents. Toggle with Space, " + ;
      "confirm with Enter.", AGUI_Pal( "dim" ) ) + Chr(10)
   cOut += Chr(10)
   FOR i := 1 TO Len( aItems )
      cBox := iif( aItems[ i ][ "accepted" ], ;
                   AGUI_Color( "[" + cCheck + "]", AGUI_Pal( "accent" ) ), ;
                   AGUI_Color( "[" + cPend + "]", AGUI_Pal( "dim" ) ) )
      cType := PadR( aItems[ i ][ "type" ], 8 )
      cPrompt := aItems[ i ][ "prompt" ]
      IF hb_UTF8Len( cPrompt ) > nMax
         cPrompt := hb_UTF8SubStr( cPrompt, 1, nMax - 3 ) + "..."
      ENDIF
      cRow := iif( i == oSel[ "cursor" ], cArrow + " ", "  " ) + cBox + " " + ;
              LTrim( Str( i ) ) + ". " + cType + " " + cPrompt
      IF i == oSel[ "cursor" ]
         cRow := AGUI_Color( cRow, AGUI_Pal( "invert" ) )
      ENDIF
      cOut += cRow + Chr(10)
   NEXT
   cOut += Chr(10)
   cOut += AGUI_Color( "  Space toggle " + Chr(194)+Chr(183) + ;
                       " A accept all " + Chr(194)+Chr(183) + ;
                       " N reject all " + Chr(194)+Chr(183) + ;
                       " Enter confirm " + Chr(194)+Chr(183) + ;
                       " Esc cancel", AGUI_Pal( "dim" ) ) + Chr(10)
   RETURN cOut

// Status line under the input box. OpenCode-style footer when idle
// (esc · tokens · /help); badges (skills/plan/pending) when present.
FUNCTION AGUI_SkillsStatusLine( aActive, nCols )
   LOCAL cLine := "", cName, nTok := 0
   IF ValType( aActive ) == "A" .AND. Len( aActive ) > 0
      FOR EACH cName IN aActive
         cLine += "[" + hb_CStr( cName ) + "] "
      NEXT
      cLine := RTrim( cLine )
      cLine := PadR( cLine, Max( 1, nCols - 1 ) )
      RETURN AGUI_Color( cLine, AGUI_Pal( "accent" ) )
   ENDIF
   // OpenCode footer: ······ esc interrupt    12.3K    /help commands
   // NO PadR here: the footer is already padded to nCols-1 VISUAL cells,
   // and PadR counts bytes — ANSI codes + UTF-8 dots made it truncate the
   // coloured string ("/help commands" showed as "/he").
   nTok := AGREPL_SessionTokens()
   RETURN AGUI_OpenCodeFooter( nTok, nCols )

// Renders the multi-line block used for every tool call: a cyan-violet rule
// the full terminal width, the tool's display label ("Bash command", "Edit",
// "Read", ...) on its own line, a blank, then the tool's primary content
// (the command / path / pattern) in green, then the model's narration on a
// Tool content without the old separator bar — just command + explanation,
// indented 3 spaces. Used with the new bullet-based tool header.
FUNCTION AGUI_ToolContentBlock( cArgsJson, cExplain, nCols )
   LOCAL cContent, cLine, cOut := ""
   IF ValType( nCols ) != "N" .OR. nCols < 20
      nCols := 100
   ENDIF
   cContent := AGUI_ToolContent( cArgsJson )
   FOR EACH cLine IN hb_ATokens( hb_CStr( cContent ), Chr(10) )
      cOut += AGUI_Color( "   " + cLine, AGUI_Pal( "bash_command" ) ) + Chr(10)
   NEXT
   IF !Empty( cExplain )
      FOR EACH cLine IN hb_ATokens( hb_CStr( cExplain ), Chr(10) )
         cOut += AGUI_Color( "   " + cLine, AGUI_Pal( "bash_explain" ) ) + Chr(10)
      NEXT
   ENDIF
   RETURN cOut

// soft-white line. Every line is plain (no border) and indented three
// spaces to match Claude Code's tool-call style.
FUNCTION AGUI_ToolBlock( cHeader, cContent, cExplain, nCols )
   LOCAL cOut, cLine
   IF ValType( nCols ) != "N" .OR. nCols < 20
      nCols := 100
   ENDIF
   // Unicode box-drawings ─ is 0xE2 0x94 0x80
   cOut := Chr(10) + ;
           AGUI_Color( Replicate( Chr(226)+Chr(148)+Chr(128), nCols - 1 ), ;
                       AGUI_Pal( "bash_header" ) ) + Chr(10) + ;
           AGUI_Color( " " + hb_CStr( cHeader ), AGUI_Pal( "bash_header" ) ) + ;
           Chr(10)
   // only add the spacer line when there is content or an explanation to
   // separate from the header -- ask_user uses an empty content block and
   // wants the QuestionBlock to land right under the label
   IF !Empty( cContent ) .OR. !Empty( cExplain )
      cOut += Chr(10)
   ENDIF
   FOR EACH cLine IN hb_ATokens( hb_CStr( cContent ), Chr(10) )
      cOut += AGUI_Color( "   " + cLine, AGUI_Pal( "bash_command" ) ) + Chr(10)
   NEXT
   IF !Empty( cExplain )
      FOR EACH cLine IN hb_ATokens( AllTrim( hb_CStr( cExplain ) ), Chr(10) )
         IF !Empty( cLine )
            cOut += AGUI_Color( "   " + cLine, ;
                                AGUI_Pal( "bash_explain" ) ) + Chr(10)
         ENDIF
      NEXT
   ENDIF
   RETURN cOut

// Maps a tool name to the header text used in AGUI_ToolBlock. "shell" is
// special-cased to "Bash command" since users recognise that label from
// Claude Code; every other tool name is capitalised and underscores become
// spaces ("github_read" -> "Github read").
FUNCTION AGUI_ToolHeader( cName )
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
FUNCTION AGUI_ToolContent( cArgsJson )
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

// OpenCode blue left accent (opencode1.jpg input panel).
STATIC FUNCTION AGUI_BlueBar()
   // U+258C LEFT HALF BLOCK in OpenCode blue
   RETURN AGUI_Color( Chr( 226 ) + Chr( 150 ) + Chr( 140 ), "38;2;80;140;255" )

// One framed input-box prompt line with the text rendered in the suggestion
// (light-green) colour. Blue left accent matches OpenCode.
FUNCTION AGUI_InputBoxSuggestion( cText )
   RETURN AGUI_BlueBar() + " " + ;
          AGUI_Color( AGUI_PadCell( hb_CStr( cText ), AGUI_InputInnerWidth(), "L" ), ;
                     AGUI_Pal( "suggestion" ) )

// OpenCode-style input line: blue left bar + text (no heavy top/bottom rules).
// Empty = blank (cursor ready). Model chip lives on the row above the box,
// not as a fake placeholder that made typing look broken.
FUNCTION AGUI_InputBoxLine( cText )
   RETURN AGUI_BlueBar() + " " + ;
          AGUI_PadCell( hb_CStr( cText ), AGUI_InputInnerWidth(), "L" )

// Prompt shown when the user presses Esc to pause tool execution.
// Options: Enter=continue, c=skip remaining tools, a=abort turn.
FUNCTION AGUI_PausePrompt()
   LOCAL cOut := Chr(10)
   cOut += AGUI_Color( AGUI_Glyph( "tl" ) + Replicate( AGUI_Glyph( "h" ), 42 ) + ;
                       AGUI_Glyph( "tr" ), AGUI_Pal( "warn" ) ) + Chr(10)
   cOut += AGUI_Color( AGUI_Glyph( "v" ), AGUI_Pal( "warn" ) ) + ;
           "  " + AGUI_Color( "[PAUSED]", "1;33" ) + ;
           "  Next tool paused by Esc" + ;
           AGUI_Color( "  " + AGUI_Glyph( "v" ), AGUI_Pal( "warn" ) ) + Chr(10)
   cOut += AGUI_Color( AGUI_Glyph( "v" ), AGUI_Pal( "warn" ) ) + ;
           "  Enter=run tool   c=skip all   a=abort turn" + ;
           AGUI_Color( "  " + AGUI_Glyph( "v" ), AGUI_Pal( "warn" ) ) + Chr(10)
   cOut += AGUI_Color( AGUI_Glyph( "bl" ) + Replicate( AGUI_Glyph( "h" ), 42 ) + ;
                       AGUI_Glyph( "br" ), AGUI_Pal( "warn" ) ) + Chr(10)
   cOut += AGUI_Color( "> ", "1;36" )
   RETURN cOut

// The text shown by the /help command.
FUNCTION AGUI_Help()
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
          "  /demo          full random offline session (cards + most cmds, no API)" + Chr(10) + ;
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
          "  /exit          quit (aliases: /quit, /bye)" + Chr(10) + ;
          "Type anything else to talk to the assistant."
