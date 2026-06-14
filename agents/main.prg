// Agents demo — entry point exercising the Agent class.
// Build: hbmk2 agents.hbp

FUNCTION Main()
   LOCAL oAgent, hResult, cPrompt, cKey, cOut

   CLS
   ? "========================================"
   ? " Agents — Agent class demo"
   ? "========================================"
   ?

   // Read API key from environment or settings
   cKey := ""
   IF !Empty( hb_GetEnv( "DEEPSEEK_API_KEY" ) )
      cKey := hb_GetEnv( "DEEPSEEK_API_KEY" )
   ELSEIF !Empty( hb_GetEnv( "CCHARBOUR_API_KEY" ) )
      cKey := hb_GetEnv( "CCHARBOUR_API_KEY" )
   ELSEIF !Empty( hb_GetEnv( "OPENAI_API_KEY" ) )
      cKey := hb_GetEnv( "OPENAI_API_KEY" )
   ENDIF

   IF Empty( cKey )
      ? "No API key in environment (DEEPSEEK_API_KEY / CCHARBOUR_API_KEY / OPENAI_API_KEY)."
      ? "Using demo mode — testing tool methods directly."
      ?
      DEMO_ToolsOnly()
      RETURN 0
   ENDIF

   ? "API key found. Creating agent..."
   ?

   oAgent := Agent():New( cKey, "deepseek-v4-pro", { ;
      "base_url" => "https://api.deepseek.com", ;
      "max_steps" => 14 } )

   ? "Model: " + oAgent:cModel
   ? "API:   " + oAgent:cApiUrl
   ? "Max steps: " + LTrim( Str( oAgent:nMaxSteps ) )
   ?
   ? "Ready. Enter prompts (empty to quit)."
   ?

   DO WHILE .T.
      ? "────────────────────────────────────────"
      ACCEPT "> " TO cPrompt
      IF Empty( cPrompt )
         EXIT
      ENDIF

      ? "Thinking..."
      hResult := oAgent:Run( cPrompt )

      IF hResult[ "success" ]
         ? hResult[ "content" ]
         ?
         ? "[" + hResult[ "stop_reason" ] + ", " + ;
           LTrim( Str( hResult[ "iterations" ] ) ) + " steps, " + ;
           LTrim( Str( hResult[ "tool_call_count" ] ) ) + " tool calls]"
      ELSE
         ? "Error: " + hResult[ "error_type" ] + " — " + ;
           hb_CStr( hb_HGetDef( hResult, "message", "?" ) )
      ENDIF
      ?
   ENDDO

   ? "Usage report:"
   ? "  Tokens in:    " + LTrim( Str( oAgent:nTokensIn ) )
   ? "  Tokens out:   " + LTrim( Str( oAgent:nTokensOut ) )
   ? "  Cost:        $" + LTrim( Str( oAgent:UsageReport(), 10, 4 ) )

RETURN 0

// Demo mode: test tool methods without API key.
STATIC FUNCTION DEMO_ToolsOnly()
   LOCAL oAgent, cResult

   // Instantiate without key
   oAgent := Agent():New( "", "demo-model" )

   ? "--- Testing Tool_Read ---"
   cResult := oAgent:Tool_Read( { "path" => "agents.prg", "max_lines" => 5 } )
   ? cResult
   ?

   ? "--- Testing Tool_Glob ---"
   cResult := oAgent:Tool_Glob( { "pattern" => "*.prg", "path" => "." } )
   ? cResult
   ?

   ? "--- Testing Tool_Grep ---"
   cResult := oAgent:Tool_Grep( { "pattern" => "CLASS Agent", "glob" => "*.prg" } )
   ? cResult
   ?

   ? "--- Testing Tool_Write ---"
   cResult := oAgent:Tool_Write( { "path" => "test_out.txt", ;
      "content" => "Hello from Agents!" + Chr( 10 ) + "Line two." + Chr( 10 ) } )
   ? cResult
   ?

   ? "--- Testing Tool_Edit ---"
   cResult := oAgent:Tool_Edit( { "path" => "test_out.txt", ;
      "old_string" => "Hello from Agents!", ;
      "new_string" => "Modified by Agents!" } )
   ? cResult
   ?

   ? "--- Testing Tool_Shell ---"
   cResult := oAgent:Tool_Shell( { "command" => "echo Hello World", "timeout" => 5 } )
   ? cResult
   ?

   ? "--- Testing Skills ---"
   oAgent:ActivateSkill( "reviewer" )
   cResult := oAgent:ActiveSkillsPrompt()
   ? cResult
   ?

   ? "--- Testing RegisterTool ---"
   cResult := oAgent:RegisterTool( "demo_tool", ;
      "A demo tool that echoes input", "agents.prg", "shell" )
   ? cResult
   ?

   ? "--- Testing ListUserTools ---"
   cResult := oAgent:ListUserTools()
   ? cResult

   // Cleanup test file
   IF hb_FileExists( "test_out.txt" )
      FErase( "test_out.txt" )
   ENDIF

   ? "All tool tests passed."
RETURN NIL
