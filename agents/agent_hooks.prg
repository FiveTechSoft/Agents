// Canonical list of events the hooks system supports.
// Keep this small until a real use case justifies expansion.
FUNCTION CCHOOKS_ValidEvents()
   RETURN { "turn_complete" }

// True if cEvent is in the canonical event list.
FUNCTION CCHOOKS_IsValidEvent( cEvent )
   RETURN AScan( CCHOOKS_ValidEvents(), {| c | c == cEvent } ) > 0

// Returns the array of hook command strings registered for cEvent in
// hSet, or an empty array if the event is absent or hSet has no hooks
// key. Safe to call with arbitrary settings hashes.
FUNCTION CCHOOKS_List( hSet, cEvent )
   IF ValType( hSet ) != "H" .OR. !hb_HHasKey( hSet, "hooks" )
      RETURN {}
   ENDIF
   IF ValType( hSet[ "hooks" ] ) != "H" .OR. ;
      !hb_HHasKey( hSet[ "hooks" ], cEvent )
      RETURN {}
   ENDIF
   RETURN hSet[ "hooks" ][ cEvent ]

// Appends cCmd to hSet["hooks"][cEvent], creating intermediate keys as
// needed. Returns .T. on success, .F. if cEvent is not a valid event.
// Mutates hSet in place; caller is responsible for CCSETTINGS_Save.
FUNCTION CCHOOKS_Add( hSet, cEvent, cCmd )
   IF !CCHOOKS_IsValidEvent( cEvent )
      RETURN .F.
   ENDIF
   IF ValType( hSet ) != "H"
      RETURN .F.
   ENDIF
   IF !hb_HHasKey( hSet, "hooks" ) .OR. ValType( hSet[ "hooks" ] ) != "H"
      hSet[ "hooks" ] := {=>}
   ENDIF
   IF !hb_HHasKey( hSet[ "hooks" ], cEvent )
      hSet[ "hooks" ][ cEvent ] := {}
   ENDIF
   AAdd( hSet[ "hooks" ][ cEvent ], cCmd )
   RETURN .T.

// Removes the 1-based nIdx-th entry from hSet["hooks"][cEvent]. Returns
// .F. (and leaves hSet untouched) if the event is missing or the index
// is out of range. Mutates hSet on success.
FUNCTION CCHOOKS_Remove( hSet, cEvent, nIdx )
   LOCAL aHooks
   IF !CCHOOKS_IsValidEvent( cEvent ) .OR. ValType( hSet ) != "H"
      RETURN .F.
   ENDIF
   aHooks := CCHOOKS_List( hSet, cEvent )
   IF nIdx < 1 .OR. nIdx > Len( aHooks )
      RETURN .F.
   ENDIF
   hb_ADel( aHooks, nIdx, .T. )
   RETURN .T.

// Replaces the 1-based nIdx-th entry with cCmd. Same return-value
// semantics as CCHOOKS_Remove.
FUNCTION CCHOOKS_Edit( hSet, cEvent, nIdx, cCmd )
   LOCAL aHooks
   IF !CCHOOKS_IsValidEvent( cEvent ) .OR. ValType( hSet ) != "H"
      RETURN .F.
   ENDIF
   aHooks := CCHOOKS_List( hSet, cEvent )
   IF nIdx < 1 .OR. nIdx > Len( aHooks )
      RETURN .F.
   ENDIF
   aHooks[ nIdx ] := cCmd
   RETURN .T.

// Path to the hooks log file, relative to the CCHarbour cwd. Matches
// the location convention used by .ccharbour/settings.json so the log
// sits next to the config that opted into it.
FUNCTION CCHOOKS_LogPath()
   RETURN ".ccharbour" + hb_ps() + "hooks.log"

// Appends cLine + LF to CCHOOKS_LogPath() iff settings have hooks_log
// set to .T.. Best-effort, single-writer: writes are wrapped so a
// missing directory or read-only filesystem cannot crash the REPL,
// and concurrent CCHarbour processes sharing a cwd can clobber each
// other's log lines (acceptable for the per-turn fire rate).
FUNCTION CCHOOKS_Log( cLine )
   LOCAL hSet := CCSETTINGS_Load(), cTs, cPath, cDir
   IF !hb_HGetDef( hSet, "hooks_log", .F. )
      RETURN NIL
   ENDIF
   cTs   := DToS( Date() ) + " " + Time()
   // Normalise "20260527" -> "2026-05-27" for readability.
   cTs := SubStr( cTs, 1, 4 ) + "-" + SubStr( cTs, 5, 2 ) + "-" + ;
          SubStr( cTs, 7, 2 ) + " " + SubStr( cTs, 10 )
   cPath := CCHOOKS_LogPath()
   cDir  := hb_FNameDir( cPath )
   IF !Empty( cDir ) .AND. !hb_DirExists( cDir )
      hb_DirBuild( cDir )
   ENDIF
   hb_MemoWrit( cPath, hb_MemoRead( cPath ) + ;
                "[" + cTs + "] " + cLine + Chr(10) )
   RETURN NIL

// Fires every hook registered under cEvent. hContext keys consumed:
//   "status"       -> "success" | "error" | "interrupted"
//   "model"        -> active model name (string)
//   "tokens"       -> total turn tokens (numeric, 0 if unavailable)
//   "duration_ms"  -> turn wall-clock duration (numeric, 0 if unavailable)
// Each hook is spawned detached (fire-and-forget). Env vars are set on
// the CCHarbour process before each spawn; the child inherits them.
// Failures are logged when hooks_log is on and otherwise silenced.
FUNCTION CCHOOKS_Run( cEvent, hContext )
   LOCAL aHooks, cCmd, hSet, nProc, cStatus
   IF !CCHOOKS_IsValidEvent( cEvent )
      CCHOOKS_Log( "event=" + hb_CStr( cEvent ) + " WARN unknown-event skip" )
      RETURN NIL
   ENDIF
   hSet := CCSETTINGS_Load()
   aHooks := CCHOOKS_List( hSet, cEvent )
   IF Len( aHooks ) == 0
      RETURN NIL
   ENDIF
   IF ValType( hContext ) != "H"
      hContext := {=>}
   ENDIF
   cStatus := hb_CStr( hb_HGetDef( hContext, "status", "success" ) )
   hb_SetEnv( "CCHARBOUR_EVENT", cEvent )
   hb_SetEnv( "CCHARBOUR_STATUS", cStatus )
   hb_SetEnv( "CCHARBOUR_MODEL", ;
      hb_CStr( hb_HGetDef( hContext, "model", "" ) ) )
   hb_SetEnv( "CCHARBOUR_TOKENS", ;
      LTrim( Str( hb_HGetDef( hContext, "tokens", 0 ) ) ) )
   hb_SetEnv( "CCHARBOUR_DURATION_MS", ;
      LTrim( Str( hb_HGetDef( hContext, "duration_ms", 0 ) ) ) )
   hb_SetEnv( "CCHARBOUR_CWD", hb_cwd() )
   FOR EACH cCmd IN aHooks
      BEGIN SEQUENCE WITH {| oErr | Break( oErr ) }
         nProc := hb_processOpen( cCmd, NIL, NIL, NIL, .T. /* detach */ )
         IF nProc == -1
            CCHOOKS_Log( "event=" + cEvent + " ERROR spawn-failed cmd=" + cCmd )
         ELSE
            CCHOOKS_Log( "event=" + cEvent + " status=" + cStatus + " cmd=" + cCmd )
         ENDIF
         RECOVER USING oErr
         CCHOOKS_Log( "event=" + cEvent + " ERROR exception cmd=" + cCmd )
         HB_SYMBOL_UNUSED( oErr )
      END SEQUENCE
   NEXT
   RETURN NIL

// Pure renderer for the /hook REPL command. Takes the raw arg string
// (everything after "/hook ") and returns the text the REPL should
// display. Also used by tests to assert on output without going through
// the live REPL output path. All persistence side-effects (settings.json
// writes) happen here; only the visible output is returned.
// Subcommands:
//   "" / "list" [event]            list hooks per event
//   "add <event> <cmd...>"         append a hook
//   "remove <event> <idx>"         remove the idx-th hook
//   "edit <event> <idx> <cmd>"     replace the idx-th hook
//   "test <event>"                 fire with dummy env
//   "log"                          tail last 20 log lines or hint
FUNCTION CCHOOKS_Render( cArg )
   LOCAL cSub, cRest, cOut := "", hSet, aHooks, i, cEvent
   LOCAL nIdx, cCmd, nSpace, cLog, aLines, nStart
   cArg := AllTrim( hb_CStr( cArg ) )
   nSpace := At( " ", cArg )
   IF nSpace > 0
      cSub  := Lower( Left( cArg, nSpace - 1 ) )
      cRest := AllTrim( SubStr( cArg, nSpace + 1 ) )
   ELSE
      cSub  := Lower( cArg )
      cRest := ""
   ENDIF
   IF Empty( cSub )
      cSub := "list"
   ENDIF
   hSet := CCSETTINGS_Load()
   DO CASE
   CASE cSub == "list"
      cOut += "Hooks:" + Chr(10)
      FOR EACH cEvent IN CCHOOKS_ValidEvents()
         IF !Empty( cRest ) .AND. cRest != cEvent
            LOOP
         ENDIF
         aHooks := CCHOOKS_List( hSet, cEvent )
         cOut += "  " + cEvent + ":" + Chr(10)
         IF Len( aHooks ) == 0
            cOut += "    (none)" + Chr(10)
         ELSE
            FOR i := 1 TO Len( aHooks )
               cOut += "    " + LTrim( Str( i ) ) + ". " + aHooks[ i ] + Chr(10)
            NEXT
         ENDIF
      NEXT
   CASE cSub == "add"
      nSpace := At( " ", cRest )
      IF nSpace == 0
         RETURN "usage: /hook add <event> <cmd>" + Chr(10)
      ENDIF
      cEvent := Lower( Left( cRest, nSpace - 1 ) )
      cCmd   := AllTrim( SubStr( cRest, nSpace + 1 ) )
      IF Empty( cCmd )
         RETURN "error: command empty" + Chr(10)
      ENDIF
      IF !CCHOOKS_IsValidEvent( cEvent )
         RETURN "error: unknown event '" + cEvent + ;
                "'. Valid: " + CCHOOKS_EventList() + Chr(10)
      ENDIF
      CCHOOKS_Add( hSet, cEvent, cCmd )
      CCSETTINGS_Save( hSet )
      cOut := "[hook added -> " + cEvent + ": " + cCmd + "]" + Chr(10)
   CASE cSub == "remove"
      nSpace := At( " ", cRest )
      IF nSpace == 0
         RETURN "usage: /hook remove <event> <idx>" + Chr(10)
      ENDIF
      cEvent := Lower( Left( cRest, nSpace - 1 ) )
      nIdx   := Val( AllTrim( SubStr( cRest, nSpace + 1 ) ) )
      IF !CCHOOKS_IsValidEvent( cEvent )
         RETURN "error: unknown event '" + cEvent + ;
                "'. Valid: " + CCHOOKS_EventList() + Chr(10)
      ENDIF
      aHooks := CCHOOKS_List( hSet, cEvent )
      IF nIdx < 1 .OR. nIdx > Len( aHooks )
         RETURN "error: index " + LTrim( Str( nIdx ) ) + ;
                " out of range (1.." + LTrim( Str( Len( aHooks ) ) ) + ")" + Chr(10)
      ENDIF
      CCHOOKS_Remove( hSet, cEvent, nIdx )
      CCSETTINGS_Save( hSet )
      cOut := "[hook removed -> " + cEvent + " #" + LTrim( Str( nIdx ) ) + "]" + Chr(10)
   CASE cSub == "edit"
      nSpace := At( " ", cRest )
      IF nSpace == 0
         RETURN "usage: /hook edit <event> <idx> <cmd>" + Chr(10)
      ENDIF
      cEvent := Lower( Left( cRest, nSpace - 1 ) )
      cRest  := AllTrim( SubStr( cRest, nSpace + 1 ) )
      nSpace := At( " ", cRest )
      IF nSpace == 0
         RETURN "usage: /hook edit <event> <idx> <cmd>" + Chr(10)
      ENDIF
      nIdx := Val( Left( cRest, nSpace - 1 ) )
      cCmd := AllTrim( SubStr( cRest, nSpace + 1 ) )
      IF Empty( cCmd )
         RETURN "error: command empty" + Chr(10)
      ENDIF
      IF !CCHOOKS_IsValidEvent( cEvent )
         RETURN "error: unknown event '" + cEvent + ;
                "'. Valid: " + CCHOOKS_EventList() + Chr(10)
      ENDIF
      aHooks := CCHOOKS_List( hSet, cEvent )
      IF nIdx < 1 .OR. nIdx > Len( aHooks )
         RETURN "error: index " + LTrim( Str( nIdx ) ) + ;
                " out of range (1.." + LTrim( Str( Len( aHooks ) ) ) + ")" + Chr(10)
      ENDIF
      CCHOOKS_Edit( hSet, cEvent, nIdx, cCmd )
      CCSETTINGS_Save( hSet )
      cOut := "[hook edited -> " + cEvent + " #" + LTrim( Str( nIdx ) ) + ": " + ;
              cCmd + "]" + Chr(10)
   CASE cSub == "test"
      cEvent := iif( Empty( cRest ), "turn_complete", Lower( cRest ) )
      IF !CCHOOKS_IsValidEvent( cEvent )
         RETURN "error: unknown event '" + cEvent + ;
                "'. Valid: " + CCHOOKS_EventList() + Chr(10)
      ENDIF
      CCHOOKS_Run( cEvent, { "status" => "success", ;
         "model" => "test", "tokens" => 0, "duration_ms" => 0 } )
      cOut := "[fired " + LTrim( Str( Len( CCHOOKS_List( hSet, cEvent ) ) ) ) + ;
              " hook(s) -- check log if hooks_log enabled]" + Chr(10)
   CASE cSub == "log"
      IF !hb_HGetDef( hSet, "hooks_log", .F. )
         RETURN "[hooks_log disabled -- set " + Chr(34) + "hooks_log" + ;
                Chr(34) + ": true in " + ".ccharbour" + hb_ps() + ;
                "settings.json]" + Chr(10)
      ENDIF
      cOut := "[log: " + CCHOOKS_LogPath() + "]" + Chr(10)
      IF hb_FileExists( CCHOOKS_LogPath() )
         cLog := hb_MemoRead( CCHOOKS_LogPath() )
         aLines := hb_ATokens( cLog, Chr(10) )
         nStart := Max( 1, Len( aLines ) - 19 )
         FOR i := nStart TO Len( aLines )
            IF !Empty( aLines[ i ] )
               cOut += "  " + aLines[ i ] + Chr(10)
            ENDIF
         NEXT
      ENDIF
   OTHERWISE
      RETURN "Unknown /hook subcommand. " + ;
             "Use: list | add | remove | edit | test | log" + Chr(10)
   ENDCASE
   RETURN cOut

// Comma-separated string of valid event names for error messages.
FUNCTION CCHOOKS_EventList()
   LOCAL aEv := CCHOOKS_ValidEvents(), cOut := "", i
   FOR i := 1 TO Len( aEv )
      cOut += aEv[ i ]
      IF i < Len( aEv )
         cOut += ", "
      ENDIF
   NEXT
   RETURN cOut
