// Returns the built-in default settings hash.
// compact_threshold: 0..1 fraction of the model's context window that the
// last turn's prompt_tokens must exceed for CCREPL_Out to print a one-shot
// "/compact" hint (warn-only, never auto-runs).
FUNCTION CCSETTINGS_Defaults()
   RETURN { "model"             => "deepseek-v4-flash", ;
            "base_url"          => "https://api.deepseek.com", ;
            "max_iterations"    => 25, ;
            "color"             => .T., ;
            "co_author"         => "", ;
            "shell_timeout"     => 30, ;
            "api_timeout"       => NIL, ;  // NIL = auto: 600 for Ollama, 120 for cloud
            "compact_threshold" => 0.7, ;
            "permissions"       => { "read"  => "allow", "glob"  => "allow", ;
                                     "grep"  => "allow", "write" => "ask", ;
                                     "edit"  => "ask",   "shell" => "ask", ;
                                     "web_search"   => "ask",   "web_fetch"    => "ask", ;
                                     "github_read"  => "allow", "github_write" => "ask", ;
                                     "memory" => "allow" }, ;
            "hooks"             => {=>}, ;
            "hooks_log"         => .F. }

// Loads settings.json merged over the defaults.
// cPath omitted -> env AGENTS_CONFIG, else .agents/settings.json under cwd.
// When the default file is missing it is auto-created with the defaults so
// the user has something to edit. Missing (after that) or malformed file ->
// the pure defaults. Never throws.
FUNCTION CCSETTINGS_Load( cPath )
   LOCAL hSet := CCSETTINGS_Defaults(), cText, xJson, cKey, cTool
   LOCAL lDefaultPath := .F.
   IF Empty( cPath )
      cPath := hb_GetEnv( "AGENTS_CONFIG" )
   ENDIF
   IF Empty( cPath )
      cPath := ".agents" + hb_ps() + "settings.json"
      lDefaultPath := .T.
   ENDIF
   IF !hb_FileExists( cPath )
      // Only auto-create at the default location; an explicit
      // AGENTS_CONFIG path is left untouched.
      IF lDefaultPath
         CCSETTINGS_Create( cPath, hSet )
      ENDIF
      RETURN hSet
   ENDIF
   cText := hb_MemoRead( cPath )
   xJson := hb_jsonDecode( cText )
   IF ValType( xJson ) != "H"
      RETURN hSet
   ENDIF
   FOR EACH cKey IN hb_HKeys( xJson )
      IF cKey == "permissions"
         IF ValType( xJson[ "permissions" ] ) == "H"
            FOR EACH cTool IN hb_HKeys( xJson[ "permissions" ] )
               hSet[ "permissions" ][ cTool ] := xJson[ "permissions" ][ cTool ]
            NEXT
         ENDIF
      ELSEIF cKey == "hooks"
         IF ValType( xJson[ "hooks" ] ) == "H"
            hSet[ "hooks" ] := xJson[ "hooks" ]
         ENDIF
      ELSE
         hSet[ cKey ] := xJson[ cKey ]
      ENDIF
   NEXT
   RETURN hSet

// Writes hSet to cPath as human-readable JSON, creating the parent
// directory when needed. Best-effort: any failure is ignored, since the
// in-memory defaults still apply when no file can be written.
STATIC FUNCTION CCSETTINGS_Create( cPath, hSet )
   LOCAL cDir := hb_FNameDir( cPath )
   IF !Empty( cDir ) .AND. !hb_DirExists( cDir )
      hb_DirBuild( cDir )
   ENDIF
   hb_MemoWrit( cPath, hb_jsonEncode( hSet, .T. ) )
   RETURN NIL

// Persists hSet to the same path CCSETTINGS_Load would read from. Public
// wrapper around CCSETTINGS_Create for handlers that need to update the
// file at runtime (notably the /provider command).
FUNCTION CCSETTINGS_Save( hSet, cPath )
   IF Empty( cPath )
      cPath := hb_GetEnv( "AGENTS_CONFIG" )
   ENDIF
   IF Empty( cPath )
      cPath := ".agents" + hb_ps() + "settings.json"
   ENDIF
   CCSETTINGS_Create( cPath, hSet )
   RETURN NIL
