// dispatch_agent: spawns a subagent with its own conversation and a
// filtered tool registry on a self-contained subtask. The parent's main
// loop blocks until the subagent finishes; only the subagent's final
// reply text comes back. A visible Agent block bounds the run, the
// timeout caps wall-clock time, and Esc on the parent box cancels the
// subagent.
//
// Per-turn invocation counter -- reset by AGTOOL_DispatchResetCount at
// the start of every AGREPL_RunTurn. The second consecutive dispatch
// inside the same turn is rejected with a redirect to propose_agents,
// forcing the model to batch its plan and route through the user gate
// instead of dispatching a flurry of subagents without confirmation.
//
// Allowance: when propose_agents is approved by the user, it tops up an
// allowance equal to the number of approved proposals. Each subsequent
// dispatch_agent decrements that allowance before incrementing the
// counter, so a fully-approved batch dispatches without the gate firing.
STATIC s_nDispatchInTurn := 0
STATIC s_nDispatchAllowance := 0

FUNCTION AGTOOL_DispatchResetCount()
   s_nDispatchInTurn := 0
   s_nDispatchAllowance := 0
   RETURN NIL

// Called by propose_agents when the user approves a batch. Adds N to the
// allowance so the next N dispatch_agent calls go through.
FUNCTION AGTOOL_DispatchGrantAllowance( nN )
   s_nDispatchAllowance += Max( 0, Int( nN ) )
   RETURN NIL

FUNCTION AGTOOL_DispatchAgent()
   RETURN { "name" => "dispatch_agent", ;
            "description" => "Launch an isolated subagent on a specific " + ;
               "task. The subagent has its own conversation and its own " + ;
               "(filtered) tool registry; it returns only its final " + ;
               "answer. IMPORTANT: if you plan to call this tool 2 or more " + ;
               "times in succession, STOP and call propose_agents instead, " + ;
               "with all the planned proposals batched into one call; the " + ;
               "user reviews the list and approves before any dispatch " + ;
               "runs. Use dispatch_agent directly only when exactly one " + ;
               "subagent is needed. agent_type: " + ;
               "'explore' (read-only tools: read, glob, grep, " + ;
               "github_read, memory, use_skill) or " + ;
               "'general' (full toolset, no further dispatch). " + ;
               "timeout_s caps the wall-clock seconds the subagent may run " + ;
               "(default 120, max 600). The user can cancel mid-run with Esc. " + ;
               "Example: { prompt: 'List every cctools_*.prg file and " + ;
               "summarise each in one line', agent_type: 'explore', " + ;
               "timeout_s: 60 }", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "prompt" => { "type" => "string", ;
                                "description" => "The task for the subagent" }, ;
                  "agent_type" => { "type" => "string", ;
                                    "description" => "explore | general " + ;
                                       "(default: explore)" }, ;
                  "timeout_s" => { "type" => "number", ;
                                   "description" => "Max wall-clock seconds " + ;
                                      "(default 120, max 600)" } }, ;
               "required" => { "prompt" } }, ;
            "handler" => {| hArgs | AGTOOL_DispatchRun( hArgs ) } }

STATIC FUNCTION AGTOOL_DispatchRun( hArgs )
   LOCAL cPrompt, cType, hSet, hCfg, oClient, oReg, aMsgs, hRes
   LOCAL cReply, hMsg, hKeys
   LOCAL nTimeout, nStartMs, oPrompt, bInterrupt, cStopReason
   LOCAL nElapsedMs, cSummary, nCols, nLastTick
   cPrompt := hb_CStr( hArgs[ "prompt" ] )
   IF Empty( cPrompt )
      RETURN "Error: dispatch_agent requires 'prompt'"
   ENDIF
   cType := iif( hb_HHasKey( hArgs, "agent_type" ) .AND. ;
                 ValType( hArgs[ "agent_type" ] ) == "C", ;
                 Lower( hArgs[ "agent_type" ] ), "explore" )
   IF !( cType == "explore" .OR. cType == "general" )
      RETURN "Error: dispatch_agent agent_type must be 'explore' or 'general'"
   ENDIF
   // Allowance from a recent propose_agents approval bypasses the gate.
   // Otherwise reject the 2nd dispatch in the same turn and redirect to
   // propose_agents.
   IF s_nDispatchAllowance > 0
      s_nDispatchAllowance--
   ELSE
      s_nDispatchInTurn++
      IF s_nDispatchInTurn > 1
         s_nDispatchInTurn := 1
         RETURN "Error: this is your second dispatch_agent call in this " + ;
                "turn (and no propose_agents allowance is left). STOP " + ;
                "dispatching individually. Use propose_agents instead, " + ;
                "passing ALL the remaining subagents you planned (and " + ;
                "this one) as one batch -- the user reviews the full " + ;
                "list and approves before any dispatch runs. Then " + ;
                "iterate over the returned JSON and call dispatch_agent " + ;
                "once per approved item."
      ENDIF
   ENDIF
   nTimeout := iif( hb_HHasKey( hArgs, "timeout_s" ) .AND. ;
                    ValType( hArgs[ "timeout_s" ] ) == "N", ;
                    hArgs[ "timeout_s" ], 120 )
   IF nTimeout < 5  ; nTimeout := 5    ; ENDIF
   IF nTimeout > 600 ; nTimeout := 600 ; ENDIF
   hSet := AGSETTINGS_Load()
   hCfg := AGCFG_Resolve( {=>} )
   IF !hCfg[ "ok" ]
      RETURN "Error: dispatch_agent: no API key configured"
   ENDIF
   oClient := AG_Client( { "model" => hSet[ "model" ], ;
                           "base_url" => hSet[ "base_url" ] } )
   hKeys := { "github"        => AGCFG_ResolveKey( "GITHUB_TOKEN", ;
                                                   "github_token", hSet ), ;
              "co_author"     => hb_HGetDef( hSet, "co_author", "" ), ;
              "shell_timeout" => hb_HGetDef( hSet, "shell_timeout", 30 ) }
   oReg := AGTOOLS_Registry( hKeys )
   AGTOOLS_FilterForAgent( oReg, cType )
   aMsgs := { ;
      { "role" => "system", ;
        "content" => "You are a Agents subagent of type '" + cType + "'. " + ;
           "Complete the task using the tools you have, then return a SHORT " + ;
           "synthesis -- at most 10-15 lines, ideally fewer." + Chr(10) + ;
           Chr(10) + ;
           "Critical rules (every one is non-negotiable):" + Chr(10) + ;
           "  1. NEVER dump raw tool output to the parent. Process it, " + ;
           "count it, summarise it, then report just the conclusion." + Chr(10) + ;
           "  2. When asked to 'list' or 'find' items, return COUNTS and at " + ;
           "most 5 representative examples -- not every match. The parent " + ;
           "agent wants the answer, not the working." + Chr(10) + ;
           "  3. No preamble, no 'Suggested next' line, no chit-chat. " + ;
           "Start with the answer." + Chr(10) + ;
           "  4. Plain text or a tight bullet list. A reply over 15 lines " + ;
           "is a failure unless the user explicitly asked for the full " + ;
           "list." + Chr(10) + ;
           "  5. If the user explicitly asked for a complete list, return " + ;
           "it -- but say so explicitly so the parent knows why the reply " + ;
           "is long." + Chr(10) + ;
           "  6. List formatting: ALWAYS put each list item on its own " + ;
           "physical line with real newlines (Chr 10). Never join items " + ;
           "with commas, spaces or empty separators. Prefer a leading " + ;
           "'- ' or '1. ' marker per line." }, ;
      { "role" => "user", "content" => cPrompt } }
   // Render the opening Agent block above the input box: separator, header,
   // and the prompt summary. The timeout/elapsed line is printed in-place
   // below via AGREPL_OverwriteAtAnchor so it can tick down without
   // pushing the box down on every update.
   nCols := AGREPL_Cols()
   cSummary := iif( hb_UTF8Len( cPrompt ) > 80, ;
                    hb_UTF8SubStr( cPrompt, 1, 77 ) + "...", cPrompt )
   AGREPL_Out( Chr(10) + ;
      AGUI_Color( Replicate( Chr(226)+Chr(148)+Chr(128), nCols - 1 ), ;
                  AGUI_Pal( "bash_header" ) ) + Chr(10) + ;
      AGUI_Color( " Agent " + cType + " working", ;
                  AGUI_Pal( "bash_header" ) ) + Chr(10) + Chr(10) + ;
      AGUI_Color( "   " + cSummary, AGUI_Pal( "bash_command" ) ) + Chr(10) )
   nStartMs := hb_milliseconds()
   nLastTick := nStartMs
   AGREPL_OverwriteAtAnchor( AGUI_Color( ;
      "   0s elapsed / " + LTrim( Str( nTimeout ) ) + "s timeout " + ;
      Chr(194)+Chr(183) + " press Esc on the input box to cancel", ;
      AGUI_Pal( "bash_explain" ) ) )
   // Interrupt check fires from inside AG_AgentRun's polling loop. We
   // piggy-back on it to refresh the elapsed-time line at ~2 Hz: too slow
   // and the counter looks frozen; too fast and we burn cycles repainting.
   oPrompt := AGREPL_BoxPrompt()
   bInterrupt := {|| ;
      iif( hb_milliseconds() - nLastTick >= 500, ;
           ( nLastTick := hb_milliseconds(), ;
             AGREPL_OverwriteAtAnchor( AGUI_Color( ;
                "   " + LTrim( Str( Int( ( hb_milliseconds() - nStartMs ) / 1000 ) ) ) + ;
                "s elapsed / " + LTrim( Str( nTimeout ) ) + "s timeout " + ;
                Chr(194)+Chr(183) + " press Esc on the input box to cancel", ;
                AGUI_Pal( "bash_explain" ) ) ) ), ;
           NIL ), ;
      ( oPrompt != NIL .AND. AGPROMPT_Interrupted( oPrompt ) ) .OR. ;
      ( ( hb_milliseconds() - nStartMs ) / 1000.0 > nTimeout ) }
   hRes := AG_AgentRun( oClient, aMsgs, ;
      { "model"           => hSet[ "model" ], ;
        "tools"           => AGTOOLS_Schemas( oReg ), ;
        "tool_executor"   => AGTOOLS_Executor( oReg ), ;
        "max_iterations"  => 10, ;
        "interrupt_check" => bInterrupt }, ;
      {| hEv | HB_SYMBOL_UNUSED( hEv ) } )
   nElapsedMs := hb_milliseconds() - nStartMs
   // Replace the in-place timer with a final-elapsed line via AGREPL_Out so
   // the row is baked in and content_row advances past it -- the subsequent
   // "Agent done / failed / cancelled" message lands on the next row instead
   // of overwriting the timer.
   AGREPL_Out( AGUI_Color( ;
      "   " + LTrim( Str( nElapsedMs / 1000.0, 10, 1 ) ) + "s elapsed / " + ;
      LTrim( Str( nTimeout ) ) + "s timeout", ;
      AGUI_Pal( "bash_explain" ) ) + Chr(10) )
   // Drain the parent's Esc interrupt if we caused it so the parent loop
   // does not see a stale interrupt after the tool returns
   IF oPrompt != NIL .AND. AGPROMPT_Interrupted( oPrompt )
      oPrompt[ "interrupt" ] := NIL
   ENDIF
   cStopReason := hb_HGetDef( hRes, "stop_reason", "" )
   IF cStopReason == "interrupted"
      IF ( nElapsedMs / 1000.0 ) >= nTimeout - 0.5
         AGREPL_Out( AGUI_Color( " Agent timed out after " + ;
            LTrim( Str( nTimeout ) ) + "s", AGUI_Pal( "warn" ) ) + Chr(10) )
         RETURN "[subagent timed out after " + LTrim( Str( nTimeout ) ) + "s]"
      ENDIF
      AGREPL_Out( AGUI_Color( " Agent cancelled by user", ;
                              AGUI_Pal( "warn" ) ) + Chr(10) )
      RETURN "[subagent cancelled by user]"
   ENDIF
   IF !hRes[ "success" ]
      AGREPL_Out( AGUI_Color( " Agent failed: " + ;
         hb_CStr( hb_HGetDef( hRes, "error_type", "?" ) ), ;
         AGUI_Pal( "error" ) ) + Chr(10) )
      RETURN "Subagent failed: " + ;
             hb_CStr( hb_HGetDef( hRes, "error_type", "?" ) ) + ": " + ;
             hb_CStr( hb_HGetDef( hRes, "message", "" ) )
   ENDIF
   AGREPL_Out( AGUI_Color( " Agent done in " + ;
      LTrim( Str( nElapsedMs / 1000.0, 10, 1 ) ) + "s (" + ;
      LTrim( Str( hb_HGetDef( hRes, "iterations", 0 ) ) ) + " iterations)", ;
      AGUI_Pal( "bash_header" ) ) + Chr(10) )
   cReply := ""
   FOR EACH hMsg IN hRes[ "messages" ]
      IF hMsg[ "role" ] == "assistant" .AND. ;
         hb_HHasKey( hMsg, "content" ) .AND. ;
         ValType( hMsg[ "content" ] ) == "C" .AND. ;
         !Empty( hMsg[ "content" ] )
         cReply := hMsg[ "content" ]
      ENDIF
   NEXT
   RETURN iif( Empty( cReply ), "[subagent returned no text]", cReply )

// dispatch_agent_background -- fire-and-forget variant of dispatch_agent.
// Returns IMMEDIATELY with a task-id ("bg1", "bg2", ...) so the parent
// agent does not block. A worker thread runs AG_AgentRun in the
// background and writes status / reply / error into the ccbg.prg
// registry as it progresses. The user inspects, attaches or kills via
// the /tasks slash command. No UI is painted by the worker -- terminal
// I/O from a thread would corrupt the dynamic input box.
FUNCTION AGTOOL_DispatchAgentBackground()
   RETURN { "name" => "dispatch_agent_background", ;
            "description" => "Spawn a subagent in the BACKGROUND and " + ;
               "return a task-id IMMEDIATELY. The agent loop does not " + ;
               "block: use this when the subagent's work is independent " + ;
               "of your next step (a long search, a parallel analysis, " + ;
               "a polling job). The user inspects progress with /tasks, " + ;
               "/tasks view <id>, /tasks kill <id>. The handler returns " + ;
               "ONLY the task-id -- do NOT wait for it; continue your " + ;
               "own work and tell the user how to retrieve the result. " + ;
               "agent_type: 'explore' (read-only) or 'general' (full " + ;
               "toolset). timeout_s caps wall-clock (default 120, max 600).", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "prompt" => { "type" => "string", ;
                                "description" => "The task for the subagent" }, ;
                  "agent_type" => { "type" => "string", ;
                                    "description" => "explore | general (default: explore)" }, ;
                  "timeout_s" => { "type" => "number", ;
                                   "description" => "Max wall-clock seconds (default 120, max 600)" } }, ;
               "required" => { "prompt" } }, ;
            "handler" => {| hArgs | AGTOOL_DispatchBackgroundRun( hArgs ) } }

STATIC FUNCTION AGTOOL_DispatchBackgroundRun( hArgs )
   LOCAL cPrompt, cType, nTimeout, cId
   cPrompt := hb_CStr( hArgs[ "prompt" ] )
   IF Empty( cPrompt )
      RETURN "Error: dispatch_agent_background requires 'prompt'"
   ENDIF
   cType := iif( hb_HHasKey( hArgs, "agent_type" ) .AND. ;
                 ValType( hArgs[ "agent_type" ] ) == "C", ;
                 Lower( hArgs[ "agent_type" ] ), "explore" )
   IF !( cType == "explore" .OR. cType == "general" )
      RETURN "Error: agent_type must be 'explore' or 'general'"
   ENDIF
   nTimeout := iif( hb_HHasKey( hArgs, "timeout_s" ) .AND. ;
                    ValType( hArgs[ "timeout_s" ] ) == "N", ;
                    hArgs[ "timeout_s" ], 120 )
   IF nTimeout < 5  ; nTimeout := 5    ; ENDIF
   IF nTimeout > 600 ; nTimeout := 600 ; ENDIF
   cId := AGBG_NextId()
   AGBG_Add( cId, cType, cPrompt, nTimeout )
   // hb_threadStart copies the arguments by value, so the worker gets
   // an independent snapshot of the prompt / type / timeout.
   hb_threadStart( @AGTOOL_BackgroundWorker(), cId, cType, cPrompt, nTimeout )
   RETURN "[background task started: " + cId + " -- inspect with /tasks " + ;
          "view " + cId + " when it finishes]"

// Worker body run on a fresh thread. Mirrors the synchronous dispatch
// path but writes every progress signal into the registry instead of
// painting to the terminal. interrupt_check checks the cancel-request
// flag and the per-task timeout. The final status / reply / error /
// ended_ms is committed before the thread exits.
STATIC FUNCTION AGTOOL_BackgroundWorker( cId, cType, cPrompt, nTimeout )
   LOCAL hSet, hCfg, oClient, oReg, hKeys, aMsgs, hRes, cReply, hMsg
   LOCAL nStartMs, bInterrupt, cStopReason, nElapsedMs
   nStartMs := hb_milliseconds()
   AGBG_Update( cId, { "status" => "running", "started_ms" => nStartMs } )
   hSet := AGSETTINGS_Load()
   hCfg := AGCFG_Resolve( {=>} )
   IF !hCfg[ "ok" ]
      AGBG_Update( cId, { "status" => "failed", ;
                          "error" => "no API key configured", ;
                          "ended_ms" => hb_milliseconds() } )
      RETURN NIL
   ENDIF
   oClient := AG_Client( { "model" => hSet[ "model" ], ;
                           "base_url" => hSet[ "base_url" ] } )
   hKeys := { "github"        => AGCFG_ResolveKey( "GITHUB_TOKEN", ;
                                                   "github_token", hSet ), ;
              "co_author"     => hb_HGetDef( hSet, "co_author", "" ), ;
              "shell_timeout" => hb_HGetDef( hSet, "shell_timeout", 30 ) }
   oReg := AGTOOLS_Registry( hKeys )
   AGTOOLS_FilterForAgent( oReg, cType )
   aMsgs := { ;
      { "role" => "system", ;
        "content" => "You are a Agents background subagent of type '" + ;
           cType + "'. Complete the task using the tools you have, then " + ;
           "return a SHORT synthesis -- at most 10-15 lines, ideally " + ;
           "fewer. NEVER dump raw tool output. No preamble, no " + ;
           "'Suggested next' line. Start with the answer." }, ;
      { "role" => "user", "content" => cPrompt } }
   // Cancel on user request OR on per-task timeout. The body runs in
   // its own thread, so it CANNOT touch AGPROMPT state.
   bInterrupt := {|| ;
      AGBG_CancelRequested( cId ) .OR. ;
      ( ( hb_milliseconds() - nStartMs ) / 1000.0 > nTimeout ) }
   hRes := AG_AgentRun( oClient, aMsgs, ;
      { "model"           => hSet[ "model" ], ;
        "tools"           => AGTOOLS_Schemas( oReg ), ;
        "tool_executor"   => AGTOOLS_Executor( oReg ), ;
        "max_iterations"  => 10, ;
        "interrupt_check" => bInterrupt }, ;
      {| hEv | HB_SYMBOL_UNUSED( hEv ) } )
   nElapsedMs := hb_milliseconds() - nStartMs
   cStopReason := hb_HGetDef( hRes, "stop_reason", "" )
   IF cStopReason == "interrupted"
      IF ( nElapsedMs / 1000.0 ) >= nTimeout - 0.5
         AGBG_Update( cId, { "status" => "timed_out", ;
                             "ended_ms" => hb_milliseconds(), ;
                             "error" => "wall-clock timeout (" + ;
                                LTrim( Str( Int( nTimeout ) ) ) + "s)" } )
      ELSE
         AGBG_Update( cId, { "status" => "cancelled", ;
                             "ended_ms" => hb_milliseconds() } )
      ENDIF
      RETURN NIL
   ENDIF
   IF !hRes[ "success" ]
      AGBG_Update( cId, { "status" => "failed", ;
                          "ended_ms" => hb_milliseconds(), ;
                          "error" => hb_CStr( hb_HGetDef( hRes, "error_type", "?" ) ) + ;
                             ": " + hb_CStr( hb_HGetDef( hRes, "message", "" ) ) } )
      RETURN NIL
   ENDIF
   cReply := ""
   FOR EACH hMsg IN hRes[ "messages" ]
      IF hMsg[ "role" ] == "assistant" .AND. ;
         hb_HHasKey( hMsg, "content" ) .AND. ;
         ValType( hMsg[ "content" ] ) == "C" .AND. ;
         !Empty( hMsg[ "content" ] )
         cReply := hMsg[ "content" ]
      ENDIF
   NEXT
   AGBG_Update( cId, { "status" => "done", ;
                       "ended_ms" => hb_milliseconds(), ;
                       "iterations" => hb_HGetDef( hRes, "iterations", 0 ), ;
                       "reply" => iif( Empty( cReply ), ;
                                       "[subagent returned no text]", cReply ) } )
   RETURN NIL
