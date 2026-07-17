// Resolves API key + base URL. Precedence for the key:
//   hOpts["api_key"]
//     -> env DEEPSEEK_API_KEY    (default DeepSeek backend)
//     -> env AGENTS_API_KEY   (generic, any OpenAI-compatible provider)
//     -> env GLM_API_KEY         (Zhipu / GLM)
//     -> env MOONSHOT_API_KEY    (Moonshot Kimi)
//     -> env OPENAI_API_KEY      (OpenAI)
//     -> config file at hOpts["config_path"]
//     -> .agents/settings.json (or AGENTS_CONFIG)
//     -> synthetic "ollama" when base_url points at a local Ollama daemon
// base_url precedence: hOpts["base_url"] -> settings.json -> DeepSeek default
// Returns: { ok, api_key, base_url, error_type, message }
FUNCTION AGCFG_Resolve( hOpts )
   LOCAL hRes, cKey := "", cFileKey, aEnvs, cEnvName, cEnv, cBase

   IF ValType( hOpts ) != "H"
      hOpts := {=>}
   ENDIF

   // base_url: explicit opt > settings.json > DeepSeek cloud default
   IF hb_HHasKey( hOpts, "base_url" ) .AND. !Empty( hOpts[ "base_url" ] )
      cBase := hOpts[ "base_url" ]
   ELSE
      cBase := AGCFG_SettingsField( "base_url" )
      IF Empty( cBase )
         cBase := "https://api.deepseek.com"
      ENDIF
   ENDIF
   // Windows: Ollama binds 127.0.0.1 only; "localhost" often resolves to
   // ::1 first and the request fails to connect. Always pin local URLs.
   cBase := AGCFG_NormalizeBaseUrl( cBase )

   hRes := { "ok" => .F., "api_key" => "", ;
             "base_url" => cBase, ;
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

   // Local Ollama needs no real secret: the HTTP layer always sends
   // "Authorization: Bearer ollama" for 11434 / ollama URLs. Accept a
   // synthetic key so the agent loop does not block on empty api_key.
   IF Empty( cKey ) .AND. AGCFG_IsOllamaUrl( hRes[ "base_url" ] )
      cKey := "ollama"
   ENDIF

   IF Empty( cKey )
      hRes[ "error_type" ] := "config"
      hRes[ "message" ]    := "No API key. Set DEEPSEEK_API_KEY (or " + ;
                              "AGENTS_API_KEY / GLM_API_KEY / " + ;
                              "MOONSHOT_API_KEY / OPENAI_API_KEY), put " + ;
                              "api_key in settings.json, pass " + ;
                              "hOpts api_key, or run a local Ollama " + ;
                              "server (auto-detected when no key is set)."
      RETURN hRes
   ENDIF

   hRes[ "api_key" ] := cKey
   hRes[ "ok" ]      := .T.
   RETURN hRes

// True when cUrl looks like a local / reverse-proxied Ollama endpoint.
FUNCTION AGCFG_IsOllamaUrl( cUrl )
   LOCAL cLow := Lower( hb_CStr( cUrl ) )
   RETURN "11434" $ cLow .OR. "ollama" $ cLow

// Rewrite localhost / IPv6-loopback to 127.0.0.1 so curl never tries ::1
// against an Ollama daemon that only listens on IPv4.
FUNCTION AGCFG_NormalizeBaseUrl( cUrl )
   LOCAL c := hb_CStr( cUrl )
   IF Empty( c )
      RETURN c
   ENDIF
   // Only rewrite loopback hostnames — leave reverse-proxied "ollama"
   // hosts (e.g. http://mybox/ollama/v1) untouched aside from literal
   // localhost / ::1 labels.
   c := StrTran( c, "://localhost", "://127.0.0.1" )
   c := StrTran( c, "://LOCALHOST", "://127.0.0.1" )
   c := StrTran( c, "://[::1]", "://127.0.0.1" )
   c := StrTran( c, "://::1", "://127.0.0.1" )
   RETURN c

// Hard-coded Ollama preset model (same as /provider ollama fallback).
FUNCTION AGCFG_OllamaDefaultModel()
   RETURN "llama3.1:8b"

// Hard-coded Ollama OpenAI-compatible base URL.
// Prefer 127.0.0.1 over "localhost" so Windows never hits an IPv6
// ::1 listener mismatch when the daemon only binds 127.0.0.1.
FUNCTION AGCFG_OllamaBaseUrl()
   RETURN "http://127.0.0.1:11434/v1"

// Probes the local Ollama daemon (GET /api/tags, short timeout).
// Returns: { ok, model, models, message }
//   model  = recommended id. Preference order:
//            1) preset default if installed
//            2) first installed model advertising tools capability
//               (required by the agent tool loop)
//            3) first installed model
//            4) preset default name (may need `ollama pull`)
//   models = array of installed model name strings (may be empty)
FUNCTION AGCFG_OllamaProbe( nTimeout )
   LOCAL hRes, xJson, aList, hMod, cName, cDef, cPick := ""
   LOCAL aNames := {}, aTools := {}, cCap, lTools
   IF ValType( nTimeout ) != "N" .OR. nTimeout <= 0
      nTimeout := 5
   ENDIF
   cDef := AGCFG_OllamaDefaultModel()
   // 127.0.0.1: matches the typical Ollama Windows bind (not ::1)
   hRes := AGHTTP_Fetch( { ;
      "url"     => "http://127.0.0.1:11434/api/tags", ;
      "method"  => "GET", ;
      "timeout" => nTimeout } )
   IF ValType( hRes ) != "H" .OR. !hb_HGetDef( hRes, "ok", .F. ) .OR. ;
      hb_HGetDef( hRes, "status", 0 ) < 200 .OR. ;
      hb_HGetDef( hRes, "status", 0 ) >= 300
      RETURN { "ok" => .F., "model" => cDef, "models" => {}, ;
               "message" => iif( ValType( hRes ) == "H", ;
                  hb_HGetDef( hRes, "error", "unreachable" ), "unreachable" ) }
   ENDIF
   xJson := hb_jsonDecode( hb_HGetDef( hRes, "body", "" ) )
   IF ValType( xJson ) == "H" .AND. hb_HHasKey( xJson, "models" ) .AND. ;
      ValType( xJson[ "models" ] ) == "A"
      aList := xJson[ "models" ]
      FOR EACH hMod IN aList
         lTools := .F.
         IF ValType( hMod ) == "H"
            cName := hb_HGetDef( hMod, "name", "" )
            IF Empty( cName )
               cName := hb_HGetDef( hMod, "model", "" )
            ENDIF
            IF hb_HHasKey( hMod, "capabilities" ) .AND. ;
               ValType( hMod[ "capabilities" ] ) == "A"
               FOR EACH cCap IN hMod[ "capabilities" ]
                  IF Lower( hb_CStr( cCap ) ) == "tools"
                     lTools := .T.
                     EXIT
                  ENDIF
               NEXT
            ENDIF
         ELSEIF ValType( hMod ) == "C"
            cName := hMod
         ELSE
            cName := ""
         ENDIF
         IF !Empty( cName )
            AAdd( aNames, cName )
            IF lTools
               AAdd( aTools, cName )
            ENDIF
            // Prefer the preset default when it is already pulled
            IF Empty( cPick ) .AND. AGCFG_OllamaNameMatch( cName, cDef )
               cPick := cName
            ENDIF
         ENDIF
      NEXT
   ENDIF
   // No preset match: prefer a tools-capable model (agent loop needs it)
   IF Empty( cPick ) .AND. Len( aTools ) > 0
      cPick := aTools[ 1 ]
   ENDIF
   IF Empty( cPick ) .AND. Len( aNames ) > 0
      cPick := aNames[ 1 ]
   ENDIF
   IF Empty( cPick )
      cPick := cDef
   ENDIF
   RETURN { "ok" => .T., "model" => cPick, "models" => aNames, ;
            "message" => "" }

// True when cName is cWant or cWant:<tag> (case-insensitive).
STATIC FUNCTION AGCFG_OllamaNameMatch( cName, cWant )
   LOCAL cN := Lower( hb_CStr( cName ) ), cW := Lower( hb_CStr( cWant ) )
   IF Empty( cW )
      RETURN .F.
   ENDIF
   RETURN cN == cW .OR. Left( cN, Len( cW ) + 1 ) == cW + ":"

// When no cloud API key is configured, try local Ollama and apply the
// same preset as `/provider ollama` (persist to settings.json so the rest
// of the stack sees a consistent backend).
// Returns: { applied, model, base_url, message }
//   applied=.T. when settings were switched to Ollama.
FUNCTION AGCFG_AutoOllama( hSet, lKeepModel )
   LOCAL hProbe, cModel, cBase, lChanged := .F.
   IF ValType( hSet ) != "H"
      hSet := {=>}
   ENDIF
   // Already pointing at Ollama: still normalize localhost -> 127.0.0.1
   // and seed the placeholder key so the agent loop does not block.
   IF AGCFG_IsOllamaUrl( hb_HGetDef( hSet, "base_url", "" ) )
      cBase := AGCFG_NormalizeBaseUrl( hSet[ "base_url" ] )
      IF cBase != hSet[ "base_url" ]
         hSet[ "base_url" ] := cBase
         lChanged := .T.
      ENDIF
      IF Empty( hb_HGetDef( hSet, "api_key", "" ) )
         hSet[ "api_key" ] := "ollama"
         lChanged := .T.
      ENDIF
      IF lChanged
         AGSETTINGS_Save( hSet )
      ENDIF
      RETURN { "applied" => lChanged, ;
               "model" => hb_HGetDef( hSet, "model", AGCFG_OllamaDefaultModel() ), ;
               "base_url" => hSet[ "base_url" ], ;
               "message" => iif( lChanged, "normalized ollama", "already ollama" ) }
   ENDIF
   hProbe := AGCFG_OllamaProbe()
   IF !hProbe[ "ok" ]
      RETURN { "applied" => .F., "model" => "", "base_url" => "", ;
               "message" => hProbe[ "message" ] }
   ENDIF
   hSet[ "base_url" ] := AGCFG_OllamaBaseUrl()
   IF Empty( lKeepModel ) .OR. lKeepModel != .T.
      cModel := hProbe[ "model" ]
      hSet[ "model" ] := cModel
   ELSE
      cModel := hb_HGetDef( hSet, "model", hProbe[ "model" ] )
   ENDIF
   // Placeholder only when nothing is stored; keep a real cloud key if
   // the user wiped base_url but left the secret (unlikely, but safe).
   IF Empty( hb_HGetDef( hSet, "api_key", "" ) )
      hSet[ "api_key" ] := "ollama"
   ENDIF
   AGSETTINGS_Save( hSet )
   RETURN { "applied" => .T., "model" => cModel, ;
            "base_url" => hSet[ "base_url" ], ;
            "message" => "ollama at " + hSet[ "base_url" ] + " / " + cModel }

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

// Reads a single string field from the active settings.json (AGENTS_CONFIG
// or .agents/settings.json). Returns "" when missing / not a string.
STATIC FUNCTION AGCFG_SettingsField( cField )
   LOCAL cPath, cText, xJson
   cPath := hb_GetEnv( "AGENTS_CONFIG" )
   IF Empty( cPath )
      cPath := ".agents" + hb_ps() + "settings.json"
   ENDIF
   IF !hb_FileExists( cPath )
      RETURN ""
   ENDIF
   cText := hb_MemoRead( cPath )
   xJson := hb_jsonDecode( cText )
   IF ValType( xJson ) == "H" .AND. hb_HHasKey( xJson, cField ) .AND. ;
      ValType( xJson[ cField ] ) == "C" .AND. !Empty( xJson[ cField ] )
      RETURN xJson[ cField ]
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
