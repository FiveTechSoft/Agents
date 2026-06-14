// Runs the agent loop: drive a multi-turn DeepSeek conversation until the model
// stops or the iteration cap is reached. Tool execution is added in Task 3,
// API-failure handling in Task 4.
// hOpts: { model, max_iterations, tools, tool_executor, temperature,
//          max_tokens, transport, interrupt_check, inject }
// "inject" (optional codeblock): polled at the start of every iteration; when
// it returns a non-empty string, that text is appended as a user message
// before the next model request - a mid-run interjection (e.g. the GUI's
// /btw "what are you doing?") that does not interrupt the loop.
// Returns hResult: { success, messages, content, stop_reason, iterations,
//                    usage, error_type, message }
FUNCTION CC_AgentRun( oClient, aMessages, hOpts, bOnEvent )
   LOCAL hResult, aMsgs, nIter := 0, nMax, hUsage, hChat, hChatParams, tc, cRes, bInterrupt
   LOCAL bInject, cInject

   IF ValType( hOpts ) != "H"
      hOpts := {=>}
   ENDIF

   hResult := { "success" => .F., "messages" => {}, "content" => "", ;
                "stop_reason" => NIL, "iterations" => 0, "usage" => {=>}, ;
                "tool_call_count" => 0, ;
                "error_type" => NIL, "message" => NIL }

   // validate the input history
   IF ValType( aMessages ) != "A" .OR. Len( aMessages ) == 0
      hResult[ "error_type" ]  := "config"
      hResult[ "message" ]     := "aMessages must be a non-empty array"
      hResult[ "stop_reason" ] := "error"
      RETURN hResult
   ENDIF

   // deep copy so the caller's array is never mutated
   aMsgs  := hb_jsonDecode( hb_jsonEncode( aMessages ) )
   nMax   := iif( hb_HHasKey( hOpts, "max_iterations" ) .AND. ;
                  ValType( hOpts[ "max_iterations" ] ) == "N" .AND. ;
                  hOpts[ "max_iterations" ] > 0, hOpts[ "max_iterations" ], 25 )
   hUsage := {=>}
   bInterrupt := iif( hb_HHasKey( hOpts, "interrupt_check" ) .AND. ;
                      ValType( hOpts[ "interrupt_check" ] ) == "B", ;
                      hOpts[ "interrupt_check" ], NIL )
   bInject    := iif( hb_HHasKey( hOpts, "inject" ) .AND. ;
                      ValType( hOpts[ "inject" ] ) == "B", ;
                      hOpts[ "inject" ], NIL )

   DO WHILE nIter < nMax
      IF bInterrupt != NIL .AND. Eval( bInterrupt )
         hResult[ "stop_reason" ] := "interrupted"
         EXIT
      ENDIF
      nIter++
      CC_Emit( bOnEvent, { "type" => "iteration_start", "n" => nIter } )

      // mid-run user interjection: append it before the next request
      IF bInject != NIL
         cInject := Eval( bInject )
         IF ValType( cInject ) == "C" .AND. !Empty( cInject )
            AAdd( aMsgs, { "role" => "user", "content" => cInject } )
            CC_Emit( bOnEvent, { "type" => "inject", "text" => cInject } )
         ENDIF
      ENDIF

      hChatParams := {=>}
      IF hb_HHasKey( hOpts, "transport" )
         hChatParams[ "transport" ] := hOpts[ "transport" ]
      ENDIF
      IF hb_HHasKey( hOpts, "model" )
         hChatParams[ "model" ] := hOpts[ "model" ]
      ENDIF
      IF hb_HHasKey( hOpts, "tools" )
         hChatParams[ "tools" ] := hOpts[ "tools" ]
      ENDIF
      IF hb_HHasKey( hOpts, "temperature" )
         hChatParams[ "temperature" ] := hOpts[ "temperature" ]
      ENDIF
      IF hb_HHasKey( hOpts, "max_tokens" )
         hChatParams[ "max_tokens" ] := hOpts[ "max_tokens" ]
      ENDIF

      hChat := CC_ChatCompletion( oClient, aMsgs, hChatParams, bOnEvent )

      IF !hChat[ "success" ]
         hResult[ "messages" ]    := aMsgs
         hResult[ "iterations" ]  := nIter
         hResult[ "usage" ]       := hUsage
         hResult[ "error_type" ]  := hChat[ "error_type" ]
         hResult[ "message" ]     := hChat[ "message" ]
         hResult[ "stop_reason" ] := "error"
         RETURN hResult
      ENDIF

      CC_AgentAddUsage( hUsage, hChat[ "usage" ] )
      AAdd( aMsgs, CC_AgentAsstMsg( hChat ) )

      IF Empty( hChat[ "tool_calls" ] )
         // If the model consumed all tokens on reasoning and produced no
         // visible content, auto-continue so it can still emit the tool
         // call or response it was planning (common with gemma4).
         IF Empty( hChat[ "content" ] ) .AND. ;
            !Empty( hChat[ "reasoning_content" ] ) .AND. ;
            nIter < nMax
            AAdd( aMsgs, { "role" => "user", ;
               "content" => "Continue." } )
            LOOP
         ENDIF
         hResult[ "stop_reason" ] := "stop"
         EXIT
      ENDIF

      // model wants tools but caller supplied no executor -> fast-fail
      IF !hb_HHasKey( hOpts, "tool_executor" ) .OR. hOpts[ "tool_executor" ] == NIL
         hResult[ "messages" ]    := aMsgs
         hResult[ "iterations" ]  := nIter
         hResult[ "usage" ]       := hUsage
         hResult[ "error_type" ]  := "config"
         hResult[ "message" ]     := "model requested tool but no tool_executor provided"
         hResult[ "stop_reason" ] := "error"
         RETURN hResult
      ENDIF

      hResult[ "tool_call_count" ] += Len( hChat[ "tool_calls" ] )
      // execute every tool call this turn, append each result as a tool message
      FOR EACH tc IN hChat[ "tool_calls" ]
         // honour an interruption requested mid-turn
         IF bInterrupt != NIL .AND. Eval( bInterrupt )
            hResult[ "stop_reason" ] := "interrupted"
            EXIT
         ENDIF
         CC_Emit( bOnEvent, { "type" => "tool_call", "id" => tc[ "id" ], ;
                                   "name" => tc[ "name" ], ;
                                   "arguments" => tc[ "arguments" ] } )
         cRes := Eval( hOpts[ "tool_executor" ], tc[ "name" ], tc[ "arguments" ] )
         CC_Emit( bOnEvent, { "type" => "tool_result", "id" => tc[ "id" ], ;
                                   "content" => cRes } )
         AAdd( aMsgs, { "role" => "tool", "tool_call_id" => tc[ "id" ], ;
                        "content" => cRes } )
      NEXT
      // a mid-turn interrupt stops the outer loop
      IF hResult[ "stop_reason" ] == "interrupted"
         EXIT
      ENDIF
   ENDDO

   IF hResult[ "stop_reason" ] == NIL
      hResult[ "stop_reason" ] := "max_iterations"
   ENDIF

   hResult[ "success" ]    := .T.
   hResult[ "messages" ]   := aMsgs
   hResult[ "iterations" ] := nIter
   hResult[ "usage" ]      := hUsage
   hResult[ "content" ]    := CC_AgentLastText( aMsgs )
   RETURN hResult

// Builds an OpenAI-format assistant message from a CC_ChatCompletion result.
STATIC FUNCTION CC_AgentAsstMsg( hChat )
   LOCAL hMsg, aTC := {}, tc
   hMsg := { "role" => "assistant", "content" => hChat[ "content" ] }
   IF !Empty( hChat[ "tool_calls" ] )
      FOR EACH tc IN hChat[ "tool_calls" ]
         AAdd( aTC, { "id" => tc[ "id" ], "type" => "function", ;
                      "function" => { "name" => tc[ "name" ], ;
                                      "arguments" => tc[ "arguments" ] } } )
      NEXT
      hMsg[ "tool_calls" ] := aTC
      // thinking models require their reasoning_content to be passed back on
      // the assistant message that carries tool_calls
      IF hb_HHasKey( hChat, "reasoning_content" ) .AND. ;
         ValType( hChat[ "reasoning_content" ] ) == "C" .AND. ;
         !Empty( hChat[ "reasoning_content" ] )
         hMsg[ "reasoning_content" ] := hChat[ "reasoning_content" ]
      ENDIF
   ENDIF
   RETURN hMsg

// Returns the content of the last assistant message, or "" if there is none.
STATIC FUNCTION CC_AgentLastText( aMsgs )
   LOCAL i
   FOR i := Len( aMsgs ) TO 1 STEP -1
      IF aMsgs[ i ][ "role" ] == "assistant"
         RETURN aMsgs[ i ][ "content" ]
      ENDIF
   NEXT
   RETURN ""

// Adds the numeric keys of xUsage into hUsage (running totals across turns).
STATIC FUNCTION CC_AgentAddUsage( hUsage, xUsage )
   LOCAL cKey
   IF ValType( xUsage ) != "H"
      RETURN NIL
   ENDIF
   FOR EACH cKey IN hb_HKeys( xUsage )
      IF ValType( xUsage[ cKey ] ) == "N"
         hUsage[ cKey ] := iif( hb_HHasKey( hUsage, cKey ), hUsage[ cKey ], 0 ) + ;
                           xUsage[ cKey ]
      ENDIF
   NEXT
   RETURN NIL


