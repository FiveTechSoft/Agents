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
