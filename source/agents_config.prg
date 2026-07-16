// Resolves API key + base URL. Precedence for the key:
//   hOpts["api_key"]
//     -> env DEEPSEEK_API_KEY    (default DeepSeek backend)
//     -> env AGENTS_API_KEY   (generic, any OpenAI-compatible provider)
//     -> env GLM_API_KEY         (Zhipu / GLM)
//     -> env MOONSHOT_API_KEY    (Moonshot Kimi)
//     -> env OPENAI_API_KEY      (OpenAI)
//     -> config file at hOpts["config_path"]
// Returns: { ok, api_key, base_url, error_type, message }
FUNCTION AGCFG_Resolve( hOpts )
   LOCAL hRes, cKey := "", cFileKey, aEnvs, cEnvName, cEnv

   IF ValType( hOpts ) != "H"
      hOpts := {=>}
   ENDIF

   hRes := { "ok" => .F., "api_key" => "", ;
             "base_url" => iif( hb_HHasKey( hOpts, "base_url" ) .AND. ;
                                !Empty( hOpts[ "base_url" ] ), ;
                                hOpts[ "base_url" ], "https://api.deepseek.com" ), ;
             "error_type" => NIL, "message" => NIL }

   IF hb_HHasKey( hOpts, "api_key" ) .AND. !Empty( hOpts[ "api_key" ] )
      cKey := hOpts[ "api_key" ]
   ELSE
      aEnvs := { "DEEPSEEK_API_KEY", "AGENTS_API_KEY", ;
                 "GLM_API_KEY", "ZHIPU_API_KEY", ;
                 "MOONSHOT_API_KEY", "OPENAI_API_KEY" }
      FOR EACH cEnvName IN aEnvs
         cEnv := hb_GetEnv( cEnvName )
         IF !Empty( cEnv )
            cKey := cEnv
            EXIT
         ENDIF
      NEXT
      IF Empty( cKey ) .AND. ;
         hb_HHasKey( hOpts, "config_path" ) .AND. ;
         !Empty( hOpts[ "config_path" ] )
         cFileKey := AGCFG_FromFile( hOpts[ "config_path" ] )
         IF !Empty( cFileKey )
            cKey := cFileKey
         ENDIF
      ENDIF
      // Fall back to settings.json so a key saved via /provider key
      // <secret> is picked up on the next turn without rebuilding the
      // client. Honour AGENTS_CONFIG first (same precedence as
      // AGSETTINGS_Load), then the default .agents/settings.json.
      IF Empty( cKey )
         cFileKey := hb_GetEnv( "AGENTS_CONFIG" )
         IF Empty( cFileKey )
            cFileKey := ".agents" + hb_ps() + "settings.json"
         ENDIF
         cFileKey := AGCFG_FromFile( cFileKey )
         IF !Empty( cFileKey )
            cKey := cFileKey
         ENDIF
      ENDIF
   ENDIF

   IF Empty( cKey )
      hRes[ "error_type" ] := "config"
      hRes[ "message" ]    := "No API key. Set DEEPSEEK_API_KEY (or " + ;
                              "AGENTS_API_KEY / GLM_API_KEY / " + ;
                              "MOONSHOT_API_KEY / OPENAI_API_KEY), put " + ;
                              "api_key in settings.json, or pass " + ;
                              "hOpts api_key directly."
      RETURN hRes
   ENDIF

   hRes[ "api_key" ] := cKey
   hRes[ "ok" ]      := .T.
   RETURN hRes

STATIC FUNCTION AGCFG_FromFile( cPath )
   LOCAL cText, xJson
   IF !hb_FileExists( cPath )
      RETURN ""
   ENDIF
   cText := hb_MemoRead( cPath )
   xJson := hb_jsonDecode( cText )
   IF ValType( xJson ) == "H" .AND. hb_HHasKey( xJson, "api_key" ) .AND. ;
      ValType( xJson[ "api_key" ] ) == "C"
      RETURN xJson[ "api_key" ]
   ENDIF
   RETURN ""

// Resolves a secret value. Precedence: environment variable cEnvName, then
// hSettings[ cSettingKey ]. Returns "" when neither is set.
FUNCTION AGCFG_ResolveKey( cEnvName, cSettingKey, hSettings )
   LOCAL cEnv := hb_GetEnv( cEnvName )
   IF !Empty( cEnv )
      RETURN cEnv
   ENDIF
   IF ValType( hSettings ) == "H" .AND. hb_HHasKey( hSettings, cSettingKey ) .AND. ;
      ValType( hSettings[ cSettingKey ] ) == "C"
      RETURN hSettings[ cSettingKey ]
   ENDIF
   RETURN ""
// When no cloud API key is set, probe the local Ollama daemon. If it answers,
// switch settings to Ollama (placeholder api_key, localhost base_url, a
// pulled model) and return a short status hash. Caller should rebuild the
// client with the new base_url / model.
//
// Returns: { ok, model, base_url, message }  or  { ok => .F. }
FUNCTION AGCFG_AutoOllama( hSet )
   LOCAL hHttp, xJson, aList, hM, cName, cPick := ""
   LOCAL aPrefer, cPref, cBase, i, n
   LOCAL cUrl := "http://127.0.0.1:11434/api/tags"

   IF ValType( hSet ) != "H"
      hSet := AGSETTINGS_Load()
   ENDIF

   // Short timeout: if Ollama is not up we must not delay startup.
   hHttp := AGHTTP_Fetch( { "url" => cUrl, "timeout" => 2 } )
   IF ! hb_HGetDef( hHttp, "ok", .F. )
      RETURN { "ok" => .F. }
   ENDIF
   n := hb_HGetDef( hHttp, "status", 0 )
   IF n < 200 .OR. n >= 300
      RETURN { "ok" => .F. }
   ENDIF

   xJson := hb_jsonDecode( hb_HGetDef( hHttp, "body", "" ) )
   aList := {}
   IF ValType( xJson ) == "H" .AND. hb_HHasKey( xJson, "models" ) .AND. ;
      ValType( xJson[ "models" ] ) == "A"
      FOR EACH hM IN xJson[ "models" ]
         IF ValType( hM ) == "H"
            cName := hb_HGetDef( hM, "name", hb_HGetDef( hM, "model", "" ) )
            IF ! Empty( cName )
               AAdd( aList, cName )
            ENDIF
         ENDIF
      NEXT
   ENDIF

   // Prefer the model already in settings if Ollama has it.
   cName := hb_HGetDef( hSet, "model", "" )
   IF ! Empty( cName )
      FOR i := 1 TO Len( aList )
         IF Lower( aList[ i ] ) == Lower( cName ) .OR. ;
            Left( Lower( aList[ i ] ), Len( cName ) + 1 ) == Lower( cName ) + ":"
            cPick := aList[ i ]
            EXIT
         ENDIF
      NEXT
   ENDIF

   // Then prefer models known to work well with tool_calls.
   IF Empty( cPick )
      aPrefer := { "llama3.1:8b", "llama3.1", "mistral-nemo", ;
                   "command-r", "llama3.2", "llama3", "mistral", ;
                   "phi3", "gemma2", "qwen2.5" }
      FOR EACH cPref IN aPrefer
         FOR i := 1 TO Len( aList )
            IF Lower( aList[ i ] ) == Lower( cPref ) .OR. ;
               Left( Lower( aList[ i ] ), Len( cPref ) + 1 ) == Lower( cPref ) + ":" .OR. ;
               Left( Lower( aList[ i ] ), Len( cPref ) ) == Lower( cPref )
               cPick := aList[ i ]
               EXIT
            ENDIF
         NEXT
         IF ! Empty( cPick )
            EXIT
         ENDIF
      NEXT
   ENDIF

   // Any installed model, else the preset default (user must pull it).
   IF Empty( cPick ) .AND. Len( aList ) > 0
      cPick := aList[ 1 ]
   ENDIF
   IF Empty( cPick )
      cPick := "llama3.1:8b"
   ENDIF

   cBase := "http://localhost:11434/v1"
   hSet[ "base_url" ] := cBase
   hSet[ "model" ]    := cPick
   // Placeholder key: AG_ChatCompletion rewrites the header for Ollama URLs.
   IF Empty( hb_HGetDef( hSet, "api_key", "" ) )
      hSet[ "api_key" ] := "ollama"
   ENDIF
   AGSETTINGS_Save( hSet )

   RETURN { "ok" => .T., ;
            "model" => cPick, ;
            "base_url" => cBase, ;
            "message" => "[no API key -- Ollama is running; switched to model " + ;
                           cPick + " @ " + cBase + "]" }
