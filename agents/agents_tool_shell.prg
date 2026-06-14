#include "fileio.ch"   // F_ERROR

// shell: runs a command through the system shell and returns combined output.
// On Windows the command runs via "cmd.exe /c"; on POSIX via "/bin/sh".
// There is deliberately no shell parameter, since models tend to send it a
// boolean and break the call.
// When cCoAuthor is non-empty, any "git commit" command automatically gets
// a --trailer "Co-authored-by: ..." appended (configurable in settings.json
// under the "co_author" key).
// nTimeout: max seconds the command may run (0 = no limit, auto-estimate).
//           Configurable via "shell_timeout" in settings (default 30).
// The model can also pass an optional "timeout" parameter per-call (A).
// When no explicit timeout is given, CCTool_EstimateTimeout() guesses
// a sensible value based on the command type (B).
FUNCTION CCTool_Shell( cCoAuthor, nTimeout )
   IF ValType( nTimeout ) != "N" .OR. nTimeout < 0
      nTimeout := 0
   ENDIF
   RETURN { "name" => "shell", ;
            "description" => "Run a shell command and return its combined output and exit code.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "command" => { "type" => "string", ;
                                 "description" => "Command line to run" }, ;
                  "timeout" => { "type" => "number", ;
                                 "description" => "Max seconds the command may run (0 = no limit). " + ;
                                                   "If not supplied, the setting shell_timeout or " + ;
                                                   "an automatic estimate is used." } }, ;
               "required" => { "command" } }, ;
            "handler" => {| hArgs | CCTool_ShellRun( hArgs, cCoAuthor, nTimeout ) } }

STATIC FUNCTION CCTool_ShellRun( hArgs, cCoAuthor, nTimeout )
   LOCAL cCommand, cCmdLine, cOut := "", cErr := "", nExit, cResult
   LOCAL cOutFile, cScriptFile := "", hProc, hIn, hOut, hErr, nStart, lTimedOut := .F.
   LOCAL nActualTimeout, lShow, nLeft, nShown := -1

   cCommand := hb_CStr( hArgs[ "command" ] )

   // auto-inject co-author trailer on git commit commands
   IF !Empty( cCoAuthor ) .AND. CCTool_IsGitCommit( cCommand )
      cCommand += ' --trailer "Co-authored-by: ' + cCoAuthor + '"'
   ENDIF

   // --- Determine effective timeout ---
   // 1) Model passed "timeout" in the call (approach A)
   IF hb_HHasKey( hArgs, "timeout" )
      nActualTimeout := hb_HGetDef( hArgs, "timeout", 0 )
      IF ValType( nActualTimeout ) != "N" .OR. nActualTimeout < 0
         nActualTimeout := 0
      ENDIF
   ELSEIF nTimeout > 0
      // 2) Default from settings (shell_timeout in registry)
      nActualTimeout := nTimeout
   ELSE
      // 3) Auto-estimate based on command type (approach B)
      nActualTimeout := CCTool_EstimateTimeout( cCommand )
   ENDIF

   IF nActualTimeout > 0
      // === Timed execution ===
      // Redirect output to a temp file (so a large output cannot deadlock
      // an unread pipe), then poll the process for completion or timeout.
      cOutFile := ""
      hOut := hb_FTempCreateEx( @cOutFile, hb_DirTemp(), "ccsh", ".out" )
      IF hOut != F_ERROR
         FClose( hOut )
      ENDIF

#ifdef __PLATFORM__WINDOWS
      cCmdLine := 'cmd.exe /c (' + cCommand + ') > "' + cOutFile + '" 2>&1'
#else
      // POSIX: write the command to a temp script so it never needs argv-level
      // quoting; the script redirects its own output to the capture file.
      cScriptFile := CCTool_ShellScript( "exec > '" + cOutFile + "' 2>&1" + ;
                                         Chr( 10 ) + cCommand + Chr( 10 ) )
      cCmdLine := "/bin/sh '" + cScriptFile + "'"
#endif

      hProc := hb_processOpen( cCmdLine, @hIn, @hOut, @hErr )
      IF hProc == F_ERROR
         RETURN "Error: cannot run shell: " + cCmdLine
      ENDIF
      // all output goes to the temp file — close the unused pipes
      FClose( hIn )
      FClose( hOut )
      FClose( hErr )

      // Poll the process: hb_processValue( hProc, .F. ) returns -1 while the
      // process is still running, otherwise its real exit code. While it
      // runs, show a live countdown of the remaining timeout.
      lShow  := CCUI_ColorOn()
      nExit  := -1
      nStart := Seconds()
      DO WHILE .T.
         nExit := hb_processValue( hProc, .F. )
         IF nExit != -1
            EXIT   // command finished
         ENDIF
         nLeft := nActualTimeout - ( Seconds() - nStart )
         IF nLeft <= 0
            lTimedOut := .T.
            EXIT
         ENDIF
         IF lShow .AND. Int( nLeft ) != nShown
            nShown := Int( nLeft )
            CCTool_ShowCountdown( nActualTimeout, nShown )
         ENDIF
         hb_IdleSleep( 0.05 )
      ENDDO

      // erase the countdown line so the result summary prints cleanly
      IF lShow
         CCTool_ClearCountdown()
      ENDIF

      // On timeout, release the process handle (the orphaned cmd.exe ends
      // on its own); on normal completion hb_processValue already reaped it.
      IF lTimedOut
         hb_processClose( hProc )
         nExit := -1
      ENDIF

      // Read whatever output was captured
      cResult := iif( hb_FileExists( cOutFile ), hb_MemoRead( cOutFile ), "" )
      FErase( cOutFile )
      cResult := RTrim( cResult )

      IF lTimedOut
         cResult += Chr( 10 ) + "[timed out after " + LTrim( Str( nActualTimeout ) ) + ;
                    " seconds]" + Chr( 10 )
      ENDIF
   ELSE
      // === Original approach (no timeout) — uses hb_processRun directly ===
#ifdef __PLATFORM__WINDOWS
      cCmdLine := "cmd.exe /c " + cCommand
#else
      cScriptFile := CCTool_ShellScript( cCommand + Chr( 10 ) )
      cCmdLine := "/bin/sh '" + cScriptFile + "'"
#endif
      nExit := hb_processRun( cCmdLine, , @cOut, @cErr )
      IF nExit == -1
         RETURN "Error: cannot run shell: " + cCmdLine
      ENDIF
      cResult := cOut
      IF !Empty( cErr )
         cResult += cErr
      ENDIF
   ENDIF

   // Common output post-processing
   IF !Empty( cScriptFile )
      FErase( cScriptFile )
   ENDIF
   IF hb_BLen( cResult ) > 30000
      cResult := hb_BLeft( cResult, 30000 ) + Chr(10) + "[output truncated]" + Chr(10)
   ENDIF
   IF !Empty( cResult ) .AND. !( Right( cResult, 1 ) == Chr(10) )
      cResult += Chr(10)
   ENDIF
   cResult += "[exit code: " + LTrim( Str( nExit ) ) + "]"
   RETURN cResult

// Renders the shell countdown line in place. In box mode it routes through
// CCREPL_OverwriteAtAnchor so the line lands on the saved scroll-region
// anchor (right under the tool block) instead of on the input box. The
// plain-CR path is kept for the cooked / non-VT fallback.
STATIC FUNCTION CCTool_ShowCountdown( nTotal, nLeft )
   LOCAL cBr := Chr(226)+Chr(142)+Chr(191)   // the ⎿ result glyph
   LOCAL cLine := "  " + cBr + " " + Chr(27) + "[90m" + ;
      "timeout " + LTrim( Str( Int( nTotal ) ) ) + "s · " + ;
      LTrim( Str( Int( nLeft ) ) ) + "s left" + Chr(27) + "[0m"
   IF CCREPL_BoxActive()
      CCREPL_OverwriteAtAnchor( cLine )
   ELSE
      FWrite( hb_GetStdOut(), Chr(13) + cLine + Chr(27) + "[K" )
   ENDIF
   RETURN NIL

// Bakes the final countdown state into the scroll above the box (in box
// mode) or erases the in-place line (cooked mode) so the result summary
// prints on a fresh row.
STATIC FUNCTION CCTool_ClearCountdown()
   IF CCREPL_BoxActive()
      // Advance content_row past the in-place countdown row by writing a
      // single LF through CCREPL_Out -- the last OverwriteAtAnchor value
      // stays visible and the next CCREPL_Out lands below it.
      CCREPL_Out( Chr(10) )
   ELSE
      FWrite( hb_GetStdOut(), Chr(13) + Chr(27) + "[K" )
   ENDIF
   RETURN NIL

// Writes cBody to a temporary shell script and returns its path.  Used on
// POSIX so a shell command never needs argv-level quoting: the raw command
// goes into the file, and only the (safe) temp path appears on the command
// line.  Returns "" when the temp file cannot be created.
STATIC FUNCTION CCTool_ShellScript( cBody )
   LOCAL cFile := ""
   LOCAL hFile := hb_FTempCreateEx( @cFile, hb_DirTemp(), "ccsh", ".sh" )
   IF hFile != F_ERROR
      FWrite( hFile, cBody )
      FClose( hFile )
   ENDIF
   RETURN cFile

// Returns .T. when cCmd looks like a "git commit" invocation.
// Checks that the command contains "git commit" and does not already have
// a --trailer or Co-authored-by marker (to avoid double-injection).
STATIC FUNCTION CCTool_IsGitCommit( cCmd )
   LOCAL cLow := Lower( AllTrim( cCmd ) )
   // bail if the user already included a trailer manually
   IF "co-authored-by" $ cLow .OR. "--trailer" $ cLow
      RETURN .F.
   ENDIF
   // detect "git commit" followed by space, end-of-string, or a flag
   RETURN "git commit" $ cLow

// Estimates a sensible timeout (in seconds) for a shell command based on
// its type.  Used when neither the model nor settings provided a timeout.
STATIC FUNCTION CCTool_EstimateTimeout( cCommand )
   LOCAL cLow := Lower( AllTrim( cCommand ) )
   LOCAL nPos, cRest, cNum, cCh, i
   LOCAL nDefault := 30

   // --- Trivially fast commands ---
   DO CASE
   CASE Left( cLow, 4 ) == "echo"
   CASE Left( cLow, 3 ) == "dir"
   CASE Left( cLow, 4 ) == "type"
   CASE Left( cLow, 6 ) == "chcp"
   CASE Left( cLow, 3 ) == "ver"
   CASE Left( cLow, 3 ) == "cls"
   CASE Left( cLow, 4 ) == "help"
   CASE Left( cLow, 3 ) == "set"
   CASE Left( cLow, 2 ) == "cd"
      RETURN 5
   ENDCASE

   // --- File operations ---
   DO CASE
   CASE Left( cLow, 4 ) == "copy"
   CASE Left( cLow, 4 ) == "move"
   CASE Left( cLow, 3 ) == "del"
   CASE Left( cLow, 6 ) == "rename"
   CASE Left( cLow, 5 ) == "mkdir"
   CASE Left( cLow, 5 ) == "rmdir"
      RETURN 10
   ENDCASE

   // --- grep / find ---
   DO CASE
   CASE Left( cLow, 7 ) == "findstr"
   CASE Left( cLow, 4 ) == "find"
      RETURN 15
   ENDCASE

   // --- Ping: try to parse "-n N" ---
   IF Left( cLow, 4 ) == "ping"
      nPos := At( " -n ", cLow )
      IF nPos > 0
         cRest := SubStr( cLow, nPos + 4 )
         cNum  := ""
         FOR i := 1 TO Len( cRest )
            cCh := SubStr( cRest, i, 1 )
            IF cCh >= "0" .AND. cCh <= "9"
               cNum += cCh
            ELSE
               EXIT
            ENDIF
         NEXT
         IF !Empty( cNum )
            RETURN Val( cNum ) * 3 + 5
         ENDIF
      ENDIF
      RETURN 30   // default ping (4 pings ~16s, give30)
   ENDIF

   // --- Tracert ---
   IF Left( cLow, 7 ) == "tracert" .OR. Left( cLow, 4 ) == "trac"
      RETURN 60
   ENDIF

   // --- Git operations ---
   IF "git clone" $ cLow
      RETURN 120
   ENDIF
   IF "git fetch" $ cLow .OR. "git pull" $ cLow
      RETURN 60
   ENDIF
   IF "git push" $ cLow
      RETURN 60
   ENDIF
   IF "git commit" $ cLow .OR. "git add" $ cLow
      RETURN 15
   ENDIF
   IF "git status" $ cLow .OR. "git log" $ cLow .OR. "git diff" $ cLow .OR. ;
      "git branch" $ cLow
      RETURN 10
   ENDIF

   // --- Build / compile ---
   IF "msbuild" $ cLow .OR. "make" $ cLow .OR. "nmake" $ cLow .OR. ;
      "harbour" $ cLow .OR. "hbmk2" $ cLow .OR. "bcc32" $ cLow .OR. ;
      "gcc" $ cLow .OR. "g++" $ cLow .OR. "clang" $ cLow .OR. "cl.exe" $ cLow
      RETURN 120
   ENDIF

   // --- xcopy / robocopy ---
   IF Left( cLow, 5 ) == "xcopy" .OR. Left( cLow, 7 ) == "robocopy"
      RETURN 60
   ENDIF

   // --- Default ---
   RETURN nDefault
