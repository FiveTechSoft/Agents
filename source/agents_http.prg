// Creates a client. hOpts: { api_key, base_url, model, timeout, config_path }.
// The returned hash holds only immutable data -> safe to share read-only
// across pool threads.
FUNCTION AG_Client( hOpts )
   IF ValType( hOpts ) != "H"
      hOpts := {=>}
   ENDIF
   RETURN { "opts" => hOpts, ;
            "model" => iif( hb_HHasKey( hOpts, "model" ), hOpts[ "model" ], NIL ), ;
            "timeout" => iif( hb_HHasKey( hOpts, "timeout" ), hOpts[ "timeout" ], 120 ) }

// Runs one streaming chat completion.
// hParams: { model, temperature, max_tokens, tools, tool_choice, transport }.
// bOnEvent (optional): codeblock invoked per parsed SSE event.
// Returns hResult: { success, content, tool_calls, finish_reason, usage,
//                    error_type, status, curl_code, retryable, message }
FUNCTION AG_ChatCompletion( oClient, aMessages, hParams, bOnEvent )
   LOCAL hCfg, hResult, hState, oParser, hReq, hHttp, cBody, cModel, bEmit

   IF ValType( hParams ) != "H"
      hParams := {=>}
   ENDIF

   hResult := { "success" => .F., "content" => "", "tool_calls" => {}, ;
                "finish_reason" => NIL, "usage" => NIL, "error_type" => NIL, ;
                "status" => NIL, "curl_code" => NIL, "retryable" => .F., ;
                "message" => NIL, "reasoning_content" => "" }

   // 1. resolve key/url (fail fast, no HTTP)
   hCfg := AGCFG_Resolve( oClient[ "opts" ] )
   IF !hCfg[ "ok" ]
      hResult[ "error_type" ] := hCfg[ "error_type" ]
      hResult[ "message" ]    := hCfg[ "message" ]
      AG_Emit( bOnEvent, { "type" => "error", "error_type" => hCfg[ "error_type" ], ;
                           "message" => hCfg[ "message" ] } )
      RETURN hResult
   ENDIF

   cModel := iif( hb_HHasKey( hParams, "model" ), hParams[ "model" ], oClient[ "model" ] )
   IF Empty( cModel )
      hResult[ "error_type" ] := "config"
      hResult[ "message" ]    := "No model id: set it on the client or in hParams"
      AG_Emit( bOnEvent, { "type" => "error", "error_type" => "config", ;
                           "message" => hResult[ "message" ] } )
      RETURN hResult
   ENDIF

   // 2. build request body
   cBody := hb_jsonEncode( AG_BuildBody( cModel, aMessages, hParams, ;
                                         hCfg[ "base_url" ] ) )
   // Ollama 0.20.x specifics, captured here so the rest of the stack is
   // backend-agnostic:
   //   - drop "Accept: text/event-stream" -- with it, Ollama collapses
   //     tool calls into a JSON blob inside message.content instead of
   //     populating tool_calls. SSE is still produced by "stream": true.
   //   - force "Authorization: Bearer ollama" -- when the header carries
   //     a real cloud key (e.g. "Bearer sk-..." left over from a prior
   //     /provider deepseek session) Ollama silently hangs the request,
   //     apparently treating it as a cloud-forward credential and waiting
   //     on a remote that never answers. The stored cloud key is left
   //     untouched in settings.json so /provider deepseek re-uses it.
   hReq  := { "url" => hCfg[ "base_url" ] + "/chat/completions", ;
              "headers" => iif( AG_IsOllamaUrl( hCfg[ "base_url" ] ), ;
                                { "Content-Type: application/json", ;
                                  "Authorization: Bearer ollama" }, ;
                                { "Content-Type: application/json", ;
                                  "Accept: text/event-stream", ;
                                  "Authorization: Bearer " + hCfg[ "api_key" ] } ), ;
              "body" => cBody, ;
              "timeout" => oClient[ "timeout" ] }
   // Optional idle heartbeat (spinner + keyboard) while waiting on Ollama.
   IF hb_HHasKey( hParams, "on_idle" ) .AND. ValType( hParams[ "on_idle" ] ) == "B"
      hReq[ "on_idle" ] := hParams[ "on_idle" ]
   ENDIF

   // 3. stream: feed every chunk to a fresh parser; assemble into hState
   hState  := { "content" => "", "tools" => {}, "finish" => NIL, ;
                "usage" => NIL, "got_done" => .F., "raw" => "", "reasoning" => "" }
   oParser := AGSSE_New()
   bEmit   := {| hEv | AG_OnEvent( hEv, hState, bOnEvent ) }

   hHttp := AGHTTP_Post( hReq, ;
      {| cChunk | AG_FeedChunk( cChunk, hState, oParser, bEmit ) }, ;
      iif( hb_HHasKey( hParams, "transport" ), hParams[ "transport" ], NIL ) )

   // 4. classify the outcome
   hResult[ "status" ]    := hHttp[ "status" ]
   hResult[ "curl_code" ] := hHttp[ "curl_code" ]

   IF !hHttp[ "ok" ]
      IF hHttp[ "curl_code" ] == -2
         hResult[ "error_type" ] := "cancelled"
         hResult[ "message" ]    := "cancelled"
      ELSE
         hResult[ "error_type" ] := "network"
         hResult[ "message" ]    := hHttp[ "error" ]
      ENDIF
      AG_Emit( bOnEvent, { "type" => "error", "error_type" => hResult[ "error_type" ], ;
                           "message" => hResult[ "message" ] } )
      RETURN hResult
   ENDIF

   IF hHttp[ "status" ] < 200 .OR. hHttp[ "status" ] >= 300
      hResult[ "error_type" ] := "api"
      hResult[ "retryable" ]  := ( hHttp[ "status" ] == 429 .OR. hHttp[ "status" ] >= 500 )
      hResult[ "message" ]    := AG_ApiErrorMessage( hState[ "raw" ], hHttp[ "status" ] )
      AG_Emit( bOnEvent, { "type" => "error", "error_type" => "api", ;
                           "message" => hResult[ "message" ] } )
      RETURN hResult
   ENDIF

   IF !hState[ "got_done" ]
      hResult[ "error_type" ] := "stream_incomplete"
      hResult[ "message" ]    := "Stream closed before [DONE]"
      AG_Emit( bOnEvent, { "type" => "error", "error_type" => "stream_incomplete", ;
                           "message" => hResult[ "message" ] } )
      RETURN hResult
   ENDIF

   hResult[ "success" ]           := .T.
   hResult[ "content" ]           := hState[ "content" ]
   hResult[ "tool_calls" ]        := hState[ "tools" ]
   hResult[ "finish_reason" ]     := hState[ "finish" ]
   hResult[ "usage" ]             := hState[ "usage" ]
   hResult[ "reasoning_content" ] := hState[ "reasoning" ]
   RETURN hResult

// Detects an Ollama-style base_url so callers can flip to Ollama-specific
// request shape. Matches the standard "localhost:11434" / "127.0.0.1:11434"
// daemon URL plus an explicit "ollama" path component for reverse-proxied
// installs. Case-insensitive.
STATIC FUNCTION AG_IsOllamaUrl( cUrl )
   LOCAL cLow := Lower( hb_CStr( cUrl ) )
   RETURN "11434" $ cLow .OR. "ollama" $ cLow

STATIC FUNCTION AG_BuildBody( cModel, aMessages, hParams, cBaseUrl )
   LOCAL hBody, lOllama := AG_IsOllamaUrl( cBaseUrl )
   hBody := { "model" => cModel, "messages" => aMessages, ;
              "stream" => .T. }
   // Ollama 0.20.x does not support OpenAI's stream_options.include_usage
   // and stalls when it is set. Cloud backends understand it and emit a
   // final usage chunk we rely on for /cost.
   IF !lOllama
      hBody[ "stream_options" ] := { "include_usage" => .T. }
   ENDIF
   IF hb_HHasKey( hParams, "temperature" )
      hBody[ "temperature" ] := hParams[ "temperature" ]
   ENDIF
   IF hb_HHasKey( hParams, "max_tokens" )
      hBody[ "max_tokens" ] := hParams[ "max_tokens" ]
   ENDIF
   IF hb_HHasKey( hParams, "tools" )
      hBody[ "tools" ] := hParams[ "tools" ]
   ENDIF
   IF hb_HHasKey( hParams, "tool_choice" )
      hBody[ "tool_choice" ] := hParams[ "tool_choice" ]
   ENDIF
   RETURN hBody

// Records raw bytes (for error bodies) and feeds the SSE parser.
STATIC FUNCTION AG_FeedChunk( cChunk, hState, oParser, bEmit )
   hState[ "raw" ] += cChunk
   AGSSE_Feed( oParser, cChunk, bEmit )
   RETURN NIL

// Folds one parsed SSE event into hState and forwards it to the caller.
STATIC FUNCTION AG_OnEvent( hEv, hState, bOnEvent )
   DO CASE
   CASE hEv[ "type" ] == "text_delta"
      hState[ "content" ] += hEv[ "text" ]
   CASE hEv[ "type" ] == "reasoning_delta"
      hState[ "reasoning" ] += hEv[ "text" ]
   CASE hEv[ "type" ] == "tool_call_delta"
      AG_AccTool( hState[ "tools" ], hEv )
   CASE hEv[ "type" ] == "finish"
      hState[ "finish" ] := hEv[ "finish_reason" ]
   CASE hEv[ "type" ] == "usage"
      hState[ "usage" ] := hEv[ "usage" ]
   CASE hEv[ "type" ] == "done"
      hState[ "got_done" ] := .T.
   ENDCASE
   AG_Emit( bOnEvent, hEv )
   RETURN NIL

// Merges a tool_call_delta into the accumulator array, keyed by "index".
STATIC FUNCTION AG_AccTool( aTools, hEv )
   LOCAL hTool, nFound := 0, i
   FOR i := 1 TO Len( aTools )
      IF aTools[ i ][ "index" ] == hEv[ "index" ]
         nFound := i
         EXIT
      ENDIF
   NEXT
   IF nFound == 0
      hTool := { "index" => hEv[ "index" ], "id" => "", "name" => "", "arguments" => "" }
      AAdd( aTools, hTool )
   ELSE
      hTool := aTools[ nFound ]
   ENDIF
   IF hEv[ "id" ] != NIL
      hTool[ "id" ] := hEv[ "id" ]
   ENDIF
   IF hEv[ "name" ] != NIL
      hTool[ "name" ] := hEv[ "name" ]
   ENDIF
   IF hEv[ "arguments" ] != NIL
      hTool[ "arguments" ] += hEv[ "arguments" ]
   ENDIF
   RETURN NIL

STATIC FUNCTION AG_ApiErrorMessage( cRaw, nStatus )
   LOCAL xJson, cMsg, cSnippet, cClean
   cClean := AG_SanitizeUTF8( cRaw )
   xJson := hb_jsonDecode( cClean )
   IF ValType( xJson ) == "H" .AND. hb_HHasKey( xJson, "error" ) .AND. ;
      ValType( xJson[ "error" ] ) == "H"
      IF hb_HHasKey( xJson[ "error" ], "message" )
         cMsg := hb_CStr( xJson[ "error" ][ "message" ] )
      ELSE
         cMsg := "(no message)"
      ENDIF
      IF hb_HHasKey( xJson[ "error" ], "type" ) .AND. !Empty( xJson[ "error" ][ "type" ] )
         cMsg += " (" + hb_CStr( xJson[ "error" ][ "type" ] ) + ")"
      ENDIF
      RETURN "HTTP " + LTrim( Str( nStatus ) ) + " - " + cMsg
   ENDIF
   // fallback: scan for "message" key via plain string search
   xJson := AG_JsonFindMsg( cClean )
   IF xJson != NIL
      RETURN "HTTP " + LTrim( Str( nStatus ) ) + " - " + hb_CStr( xJson )
   ENDIF
   cSnippet := Left( cClean, 300 )
   cSnippet := StrTran( cSnippet, Chr(10), "\\n" )
   cSnippet := StrTran( cSnippet, Chr(13), "\\r" )
   RETURN "HTTP " + LTrim( Str( nStatus ) ) + " - body: " + cSnippet

// Scans cText for a JSON key "message" and returns its value string, or NIL.
STATIC FUNCTION AG_JsonFindMsg( cText )
   LOCAL nPos, nEnd, cVal
   nPos := hb_At( '"message"', cText, 1 )
   IF nPos == 0
      nPos := hb_At( "'message'", cText, 1 )
   ENDIF
   IF nPos == 0
      RETURN NIL
   ENDIF
   nPos := hb_At( ':', cText, nPos + 8 )
   IF nPos == 0
      RETURN NIL
   ENDIF
   nPos := hb_At( '"', cText, nPos )
   IF nPos == 0
      RETURN NIL
   ENDIF
   nEnd := hb_At( '"', cText, nPos + 1 )
   IF nEnd == 0
      RETURN NIL
   ENDIF
   cVal := SubStr( cText, nPos + 1, nEnd - nPos - 1 )
   cVal := StrTran( cVal, '\\"', '"' )
   cVal := StrTran( cVal, '\\n', Chr(10) )
   cVal := StrTran( cVal, '\\t', Chr(9) )
   RETURN cVal

FUNCTION AG_Emit( bOnEvent, hEv )
   IF bOnEvent != NIL
      Eval( bOnEvent, hEv )
   ENDIF
   RETURN NIL
