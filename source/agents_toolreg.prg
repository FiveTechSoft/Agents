// Creates a fresh tool registry with all builtin tools registered.
// hKeys (optional): { github => <token> } — captured by
// the web/github tool handlers. Omitting it leaves those keys empty; the
// affected tools then return a clear error at call time.
FUNCTION AGTOOLS_Registry( hKeys )
   LOCAL oReg := {=>}
   IF ValType( hKeys ) != "H"
      hKeys := {=>}
   ENDIF
   AGTOOLS_Register( oReg, AGTOOL_Read() )
   AGTOOLS_Register( oReg, AGTOOL_Write() )
   AGTOOLS_Register( oReg, AGTOOL_Edit() )
   AGTOOLS_Register( oReg, AGTOOL_Glob() )
   AGTOOLS_Register( oReg, AGTOOL_Grep() )
   AGTOOLS_Register( oReg, AGTOOL_Shell( hb_HGetDef( hKeys, "co_author", "" ), ;
                                       hb_HGetDef( hKeys, "shell_timeout", 30 ) ) )
   AGTOOLS_Register( oReg, AGTOOL_WebSearch() )
   AGTOOLS_Register( oReg, AGTOOL_WebFetch() )
   AGTOOLS_Register( oReg, AGTOOL_GithubRead( hb_HGetDef( hKeys, "github", "" ) ) )
   AGTOOLS_Register( oReg, AGTOOL_GithubWrite( hb_HGetDef( hKeys, "github", "" ) ) )
   AGTOOLS_Register( oReg, AGTOOL_Memory( "memory.md" ) )
   AGTOOLS_Register( oReg, AGTOOL_AskUser() )
   AGTOOLS_Register( oReg, AGTOOL_TodoWrite() )
   AGTOOLS_Register( oReg, AGTOOL_UseSkill() )
   AGTOOLS_Register( oReg, AGTOOL_DispatchAgent() )
   AGTOOLS_Register( oReg, AGTOOL_DispatchAgentBackground() )
   AGTOOLS_Register( oReg, AGTOOL_ProposeAgents() )
   AGTOOLS_Register( oReg, AGTOOL_GrokChat() )
   AGTOOLS_Register( oReg, AGTOOL_GrokList() )
   AGTOOLS_Register( oReg, AGTOOL_DeepSeekChat() )
   AGTOOLS_Register( oReg, AGTOOL_DeepSeekList() )
   RETURN oReg

// Strips a tool registry down to the set allowed for a subagent of the
// given type. Always removes dispatch_agent so a subagent cannot spawn its
// own subagent (no recursion). For "explore", keeps read-only tools only.
// For "general", keeps everything except dispatch_agent.
FUNCTION AGTOOLS_FilterForAgent( oReg, cType )
   LOCAL aRemove := { "dispatch_agent", "dispatch_agent_background" }, cKey
   LOCAL aKeepExplore := { "read", "glob", "grep", "github_read", ;
                           "memory", "use_skill" }
   IF cType == "explore"
      FOR EACH cKey IN hb_HKeys( oReg )
         IF AScan( aKeepExplore, {| c | c == cKey } ) == 0 .AND. ;
            AScan( aRemove, {| c | c == cKey } ) == 0
            AAdd( aRemove, cKey )
         ENDIF
      NEXT
   ENDIF
   FOR EACH cKey IN aRemove
      IF hb_HHasKey( oReg, cKey )
         hb_HDel( oReg, cKey )
      ENDIF
   NEXT
   RETURN oReg

// Adds a tool record to the registry, keyed by its name.
// hTool: { name, description, parameters, handler }.
FUNCTION AGTOOLS_Register( oReg, hTool )
   oReg[ hTool[ "name" ] ] := hTool
   RETURN oReg

// Returns the OpenAI "tools" array for every registered tool.
FUNCTION AGTOOLS_Schemas( oReg )
   LOCAL aOut := {}, cKey, hTool
   FOR EACH cKey IN hb_HKeys( oReg )
      hTool := oReg[ cKey ]
      AAdd( aOut, { "type" => "function", ;
                    "function" => { "name" => hTool[ "name" ], ;
                                    "description" => hTool[ "description" ], ;
                                    "parameters" => hTool[ "parameters" ] } } )
   NEXT
   RETURN aOut

// Returns the executor codeblock { |cName,cArgsJson| -> cResultString }.
// It plugs straight into AG_AgentRun's hOpts["tool_executor"].
FUNCTION AGTOOLS_Executor( oReg )
   RETURN {| cName, cArgsJson | AGTOOLS_Dispatch( oReg, cName, cArgsJson ) }

// Looks up a tool, validates arguments, runs the handler under an error net.
STATIC FUNCTION AGTOOLS_Dispatch( oReg, cName, cArgsJson )
   LOCAL hTool, xArgs, cReq, cResult, oErr
   IF !hb_HHasKey( oReg, cName )
      RETURN "Error: unknown tool '" + hb_CStr( cName ) + "'"
   ENDIF
   hTool := oReg[ cName ]
   xArgs := hb_jsonDecode( hb_CStr( cArgsJson ) )
   IF ValType( xArgs ) != "H"
      RETURN "Error: invalid arguments JSON"
   ENDIF
   IF hb_HHasKey( hTool[ "parameters" ], "required" )
      FOR EACH cReq IN hTool[ "parameters" ][ "required" ]
         IF !hb_HHasKey( xArgs, cReq )
            RETURN "Error: missing required argument '" + cReq + "'"
         ENDIF
      NEXT
   ENDIF
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      cResult := Eval( hTool[ "handler" ], xArgs )
   RECOVER USING oErr
      cResult := "Error: tool '" + cName + "' failed: " + ;
                 iif( ValType( oErr ) == "O", hb_CStr( oErr:Description ), "exception" )
   END SEQUENCE
   RETURN AG_SanitizeUTF8( cResult )

// Replaces invalid UTF-8 byte sequences (and non-printable control chars
// except tab/CR/LF) with "?" so that hb_jsonEncode produces valid JSON
// that the API server can parse.
FUNCTION AG_SanitizeUTF8( cText )
   LOCAL cOut := "", i := 1, nLen, nByte, nCont, nNeed
   IF ValType( cText ) != "C"
      RETURN "?"
   ENDIF
   nLen := hb_BLen( cText )
   DO WHILE i <= nLen
      nByte := hb_BCode( hb_BSubStr( cText, i, 1 ) )
      DO CASE
      CASE nByte < 32
         // keep only common ASCII whitespace
         IF nByte == 9 .OR. nByte == 10 .OR. nByte == 13
            cOut += hb_BSubStr( cText, i, 1 )
         ELSE
            cOut += "?"
         ENDIF
         i++
      CASE nByte < 128
         // printable ASCII — keep as-is
         cOut += hb_BSubStr( cText, i, 1 )
         i++
      CASE nByte < 192
         // orphaned continuation byte (0x80-0xBF) — invalid
         cOut += "?"
         i++
      CASE nByte < 224
         // 2-byte sequence lead (0xC0-0xDF) — need 1 continuation byte
         nNeed := 1
         IF i + nNeed <= nLen
            nCont := hb_BCode( hb_BSubStr( cText, i + 1, 1 ) )
            IF nCont >= 128 .AND. nCont < 192
               cOut += hb_BSubStr( cText, i, 2 )
               i += 2
            ELSE
               cOut += "?"
               i++
            ENDIF
         ELSE
            cOut += "?"
            i++
         ENDIF
      CASE nByte < 240
         // 3-byte sequence lead (0xE0-0xEF) — need 2 continuation bytes
         nNeed := 2
         IF i + nNeed <= nLen
            nCont := hb_BCode( hb_BSubStr( cText, i + 1, 1 ) )
            IF nCont >= 128 .AND. nCont < 192
               nCont := hb_BCode( hb_BSubStr( cText, i + 2, 1 ) )
               IF nCont >= 128 .AND. nCont < 192
                  cOut += hb_BSubStr( cText, i, 3 )
                  i += 3
               ELSE
                  cOut += "?"
                  i++
               ENDIF
            ELSE
               cOut += "?"
               i++
            ENDIF
         ELSE
            cOut += "?"
            i++
         ENDIF
      CASE nByte < 248
         // 4-byte sequence lead (0xF0-0xF7) — need 3 continuation bytes
         nNeed := 3
         IF i + nNeed <= nLen
            nCont := hb_BCode( hb_BSubStr( cText, i + 1, 1 ) )
            IF nCont >= 128 .AND. nCont < 192
               nCont := hb_BCode( hb_BSubStr( cText, i + 2, 1 ) )
               IF nCont >= 128 .AND. nCont < 192
                  nCont := hb_BCode( hb_BSubStr( cText, i + 3, 1 ) )
                  IF nCont >= 128 .AND. nCont < 192
                     cOut += hb_BSubStr( cText, i, 4 )
                     i += 4
                  ELSE
                     cOut += "?"
                     i++
                  ENDIF
               ELSE
                  cOut += "?"
                  i++
               ENDIF
            ELSE
               cOut += "?"
               i++
            ENDIF
         ELSE
            cOut += "?"
            i++
         ENDIF
      OTHERWISE
         // >= 0xF8 — invalid start byte
         cOut += "?"
         i++
      ENDCASE
   ENDDO
   RETURN cOut
