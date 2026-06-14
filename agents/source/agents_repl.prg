#include "fileio.ch"
#include "hbdyn.ch"

// Tracks a pending LF to swallow after a CR, so CRLF counts as one line break.
STATIC s_lSkipLF := .F.

// Accumulated usage across the entire session (prompt_tokens, completion_tokens, ...).
STATIC s_hSessionUsage := {=>}
// Cumulative wall-clock milliseconds spent inside agent turns (sum of every
// RunTurn). Surfaces beside the token bar so the user can track how much of
// the session has been spent waiting on the model.
STATIC s_nSessionTurnMs := 0

// Optional session-wide goal, set via /goal <text>. The intent is
// "keep working until the condition is met": the goal text is injected
// into aMsgs as a system note when set, the model emits a sentinel
// (GOAL COMPLETE) when the condition is met, and the main loop auto-
// continues with "Continue toward the goal." until the sentinel
// appears, the user hits Esc, or s_nGoalAutoCap iterations run.
// /goal stop pauses the auto-loop without dropping the goal text.
STATIC s_cGoal := ""
STATIC s_aPlanSteps := {}      // /plan steps: { "title", "state" } (web parity)
STATIC s_lGoalLooping := .F.
// Recurring /loop state. When s_lLoopActive is .T., after each user turn
// the REPL sleeps s_nLoopIntervalSec seconds (interruptible by Esc) then
// re-injects s_cLoopPrompt as the next user message. /loop stop or Esc
// during the sleep clears the flag; the prompt text is kept so /loop
// status can still show it. Mirrors Claude Code's fixed-interval /loop.
STATIC s_cLoopPrompt := ""
STATIC s_nLoopIntervalSec := 0
STATIC s_lLoopActive := .F.
// Rewind snapshot stack. AGREPL_PushRewind saves { aMsgs, state } before
// each model-bound turn (message / init / loop-rerun); /rewind or a
// double-tap of Esc at the idle prompt pops the most recent snapshot
// and restores it, undoing the conversation turn. Files touched during
// the turn are NOT rolled back -- only the conversation state is.
// Capped at AG_REWIND_MAX entries; older snapshots fall off the bottom
// to bound memory in long sessions.
STATIC s_aRewindStack := {}
#define AG_REWIND_MAX 20
// One-shot "model isn't calling tools" hint. Set after the warning fires
// (or the model successfully calls a tool, so the model clearly supports
// tools). Cleared by /clear and /provider so the next session re-evaluates.
STATIC s_lNoToolWarned := .F.
// User override for the model context window (tokens). 0 means "use the
// auto-detected value from AGREPL_ModelContext". Set via /ctx <N> and
// reset via /ctx auto or /clear.
STATIC s_nContextOverride := 0

// One-shot /compact nudge flag: set when MaybeWarnCompact prints the
// "context X% full" warning; cleared by /clear and by a successful
// /compact so the warning can fire again next time the threshold is
// crossed.
STATIC s_lCompactNudged := .F.
#define AG_GOAL_SENTINEL "GOAL COMPLETE"
#define AG_GOAL_AUTO_CAP 25

// Braille-pattern spinner frames for the animated "thinking" indicator.
STATIC s_aSpinnerFrames := { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
STATIC s_aWorkFrames := { "✻", "✼", "✽", "✾", "✿" }
STATIC s_aWorkActions := { ;
   "Brewing coffee…", "Chasing bits…", "Counting tokens…", ;
   "Petting the GPU…", "Polishing answers…", "Untangling thoughts…", ;
   "Warming up neurons…", "Dusting the cache…", "Feeding the hamsters…", ;
   "Aligning pixels…", "Folding spacetime…", "Consulting the oracle…", ;
   "Sharpening pencils…", "Calibrating wit…", "Herding electrons…", ;
   "Buffering brilliance…", "Defragging ideas…", "Recharging wit…", ;
   "Polishing syntax…", "Synthesising genius…" }
STATIC s_nWorkAction := 0

// The active persistent prompt box, when one is mounted. While set, AGREPL_Out
// writes agent output at a saved scroll-region anchor and returns the cursor
// to the input box, so the visible cursor stays inside the box.
STATIC s_oBoxPrompt := NIL

// .T. while the user has put the session in plan-mode (/plan). The permission
// gate blocks write/edit/shell so the agent can plan freely without touching
// the codebase. Cleared by /plan accept (proceed) or /plan cancel (drop).
STATIC s_lPlanMode := .F.

// .T. while the session is in lean-mode (/lean). The system prompt drops the
// skills list, project context and persisted memory so each turn sends ~500
// fewer input tokens. Toggle off with /lean off.
STATIC s_lLeanMode := .F.

// Index into the AGUI tip pool, advanced once per idle prompt so the idle
// line cycles through the tips rather than always showing the same one.
STATIC s_nTipIdx := 0

// Program entry point. Optional cModel CLI argument overrides the settings model.
FUNCTION Main( cModel )
   LOCAL hSet, hCfg, oClient, oReg, bGate, oErr, lVT
   lVT := AGREPL_InitConsole()
   hSet := AGSETTINGS_Load()
   // colour only when the console accepted virtual-terminal mode AND the
   // settings do not switch it off -- avoids ANSI codes on a plain console
   AGUI_SetColor( lVT .AND. hSet[ "color" ] == .T. )
   IF Empty( cModel )
      cModel := hb_GetEnv( "DEEPSEEK_MODEL" )
   ENDIF
   IF Empty( cModel )
      cModel := hSet[ "model" ]
   ENDIF
   // No-key path: still start the REPL so the user can use /provider to
   // configure a backend. The warning itself is printed BELOW the banner
   // from inside AGREPL_Run (otherwise it would shift the banner down and
   // throw off the dynamic-box header-row count).
   hCfg := AGCFG_Resolve( {=>} )
   HB_SYMBOL_UNUSED( hCfg )
   oClient := AG_Client( { "model" => cModel, "base_url" => hSet[ "base_url" ], ;
                           "timeout" => AGREPL_ApiTimeout( hSet ) } )
   oReg    := AGTOOLS_Registry( { ;
      "github"       => AGCFG_ResolveKey( "GITHUB_TOKEN", "github_token", hSet ), ;
      "co_author"    => hb_HGetDef( hSet, "co_author", "" ), ;
      "shell_timeout" => hb_HGetDef( hSet, "shell_timeout", 30 ) } )
   bGate   := AGPERM_Gate( AGTOOLS_Executor( oReg ), hSet[ "permissions" ], ;
                           {| cN, cA | AGREPL_AskPerm( cN, cA ) } )
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      AGREPL_Run( oClient, oReg, cModel, bGate, hSet[ "max_iterations" ] )
   RECOVER USING oErr
      AGCON_RawMode( .F. )   // restore the console if a crash happened mid-editor
      AGREPL_Out( Chr(27) + "[r" )   // reset any VT scroll region the prompt set
      AGREPL_Out( Chr(10) + "Fatal: " + ;
              iif( ValType( oErr ) == "O", hb_CStr( oErr:Description ), "exception" ) + ;
              Chr(10) )
      ErrorLevel( 1 )
      RETURN NIL
   END SEQUENCE
   RETURN NIL

// The interactive loop: read a line, dispatch, run the agent, repeat.
FUNCTION AGREPL_Run( oClient, oReg, cModel, bGate, nMaxIter )
   LOCAL aMsgs, cLine, hAction, aTurn, hRes, cMsg, cSuggest, lCooked, hLoaded, hTurn, oPrompt
   LOCAL cBanner, nHeaderRows, i
   aMsgs    := { { "role" => "system", "content" => AGUI_SystemPrompt() } }
   cSuggest := ""
   cBanner  := AGUI_Banner( cModel, hb_cwd(), hb_GetEnv( "USERNAME" ) )
   nHeaderRows := 0
   FOR i := 1 TO Len( cBanner )
      IF SubStr( cBanner, i, 1 ) == Chr(10)
         nHeaderRows++
      ENDIF
   NEXT
   // Anchor the banner at absolute row 1 so nHeaderRows + 1 deterministically
   // points to the first row BELOW the banner. Without this, the banner is
   // printed at whatever row the cursor sat on (e.g. row 2 after the shell's
   // "cc" line), so row nHeaderRows + 1 lands on the banner's bottom border
   // -- and every subsequent AGREPL_Out (the no-key warning, the tip line)
   // overwrites the banner. Only do it in box mode; the cooked path streams
   // to a non-VT terminal where ESC[H/ESC[2J would print as literal junk.
   IF AGCON_HasConsole() .AND. AGUI_ColorOn()
      AGREPL_Out( Chr(27) + "[H" + Chr(27) + "[2J" )
   ENDIF
   AGREPL_Out( cBanner )
   IF !Empty( AGUI_ProjectContext() )
      AGREPL_Out( AGUI_Color( "[loaded CC.md project instructions]", ;
                              "90" ) + Chr(10) )
      nHeaderRows++
   ENDIF
   oPrompt := NIL
   IF AGCON_HasConsole() .AND. AGUI_ColorOn()
      oPrompt := AGPROMPT_New()
      // Start the scroll region just below the banner so the logo stays
      // pinned at the top of the screen for a while and the first agent
      // output appears right under it instead of jumping to the bottom.
      AGPROMPT_Activate( oPrompt, nHeaderRows + 1 )
      s_oBoxPrompt := oPrompt
   ENDIF
   // Surface the no-key warning AFTER the banner so the banner is not
   // pushed off the top row and the dynamic-box content-row counter
   // remains correct. The warning lives in the scrollable content area.
   IF Empty( AGCFG_Resolve( {=>} )[ "api_key" ] )
      AGREPL_Out( AGUI_Color( "[no API key configured -- type /provider to " + ;
                              "set up a backend (deepseek/glm/moonshot/openai/" + ;
                              "ollama), or export DEEPSEEK_API_KEY before " + ;
                              "starting]", ;
                              "33" ) + Chr(10) )
   ENDIF
   DO WHILE .T.
      lCooked := .F.
      IF oPrompt != NIL
         IF AGTODO_HasOpen()
            AGREPL_Out( AGUI_TodoBlock( AGTODO_Get() ) )
         ENDIF
         // seed the box editor with the model's "Suggested next:" so it shows
         // as a green translucent prompt the user can Tab-accept or replace
         IF !Empty( cSuggest )
            oPrompt[ "editor" ] := AGIN_New( cSuggest )
            AGPROMPT_Redraw( oPrompt )
         ENDIF
         cLine := AGREPL_PromptIdle( oPrompt )
      ELSEIF AGCON_HasConsole()
         cLine := AGIN_ReadLine( cSuggest )
         IF ValType( cLine ) == "H"   // the no-console sentinel
            lCooked := .T.
            AGREPL_Out( Chr(10) + AGUI_FrameTop() + Chr(10) + "> " )
            cLine := AGREPL_ReadLine()
         ENDIF
      ELSE
         // piped / non-interactive input: the cooked reader, no box editor
         lCooked := .T.
         AGREPL_Out( Chr(10) + AGUI_FrameTop() + Chr(10) + "> " )
         cLine := AGREPL_ReadLine()
      ENDIF
      cSuggest := ""
      IF cLine == NIL
         EXIT
      ENDIF
      IF lCooked
         AGREPL_Out( AGUI_FrameBottom() + Chr(10) )
      ENDIF
      // echo the submitted prompt in white above the box, so the transcript
      // shows what the user just asked. Cooked path skipped: the line is
      // already visible in the terminal as the user typed it.
      IF !lCooked .AND. !Empty( AllTrim( hb_CStr( cLine ) ) )
         AGREPL_Out( Chr(10) + AGREPL_UserCard( cLine ) )
      ENDIF
      hAction := AGUI_ParseCommand( cLine )
      DO CASE
      CASE hAction[ "type" ] == "empty"
         // nothing
      CASE hAction[ "type" ] == "exit"
         EXIT
      CASE hAction[ "type" ] == "help"
         AGREPL_Out( AGUI_Help() + Chr(10) )
      CASE hAction[ "type" ] == "clear"
         AGREPL_ClearScreen( oPrompt )
         aMsgs := { { "role" => "system", "content" => AGUI_SystemPrompt() } }
         s_hSessionUsage := {=>}
         s_nSessionTurnMs := 0
         s_cGoal := ""
         s_aPlanSteps := {}
         s_lGoalLooping := .F.
         s_cLoopPrompt := ""
         s_nLoopIntervalSec := 0
         s_lLoopActive := .F.
         s_aRewindStack := {}
         s_lNoToolWarned := .F.
         s_lCompactNudged := .F.
         s_nContextOverride := 0
         AGREPL_Out( AGUI_Color( "[conversation reset]", "90" ) + Chr(10) )
      CASE hAction[ "type" ] == "model"
         IF Empty( hAction[ "text" ] )
            AGREPL_Out( AGUI_Color( "model: " + cModel, "90" ) + Chr(10) )
         ELSE
            cModel := hAction[ "text" ]
            AGREPL_Out( AGUI_Color( "[model -> " + cModel + "]", "90" ) + Chr(10) )
         ENDIF
      CASE hAction[ "type" ] == "cost"
         AGREPL_Out( AGUI_CostReport( s_hSessionUsage ) )
      CASE hAction[ "type" ] == "save"
         AGREPL_SaveSession( aMsgs, cModel, s_hSessionUsage, cSuggest, hAction[ "text" ] )
      CASE hAction[ "type" ] == "load"
         hLoaded := AGREPL_LoadSession( hAction[ "text" ] )
         IF ValType( hLoaded ) == "H"
            aMsgs    := hLoaded[ "messages" ]
            cModel   := hb_HGetDef( hLoaded, "model", cModel )
            s_hSessionUsage := iif( hb_HHasKey( hLoaded, "usage" ) .AND. ;
                                    ValType( hLoaded[ "usage" ] ) == "H", ;
                                    hLoaded[ "usage" ], {=>} )
            // Restore the REPL-level statics (goal, modes, skills, timer)
            // and the suggested-next prompt; AGREPL_StateImport silently
            // skips missing keys so legacy session files still load.
            IF hb_HHasKey( hLoaded, "state" )
               AGREPL_StateImport( hLoaded[ "state" ] )
            ENDIF
            // a loaded session has its own history -- the previous in-memory
            // rewind stack does not apply any more.
            s_aRewindStack := {}
            cSuggest := hb_HGetDef( hLoaded, "suggest", "" )
         ENDIF
      CASE hAction[ "type" ] == "skill"
         AGREPL_ActivateSkill( hAction[ "text" ], aMsgs, oPrompt )
      CASE hAction[ "type" ] == "lean"
         AGREPL_ToggleLean( hAction[ "text" ], aMsgs, oPrompt )
      CASE hAction[ "type" ] == "provider"
         hLoaded := AGREPL_HandleProvider( hAction[ "text" ], oPrompt )
         IF ValType( hLoaded ) == "H"
            IF hb_HHasKey( hLoaded, "model" ) .AND. !Empty( hLoaded[ "model" ] )
               cModel := hLoaded[ "model" ]
            ENDIF
            IF hb_HGetDef( hLoaded, "rebuild_client", .F. )
               oClient := AG_Client( { "model" => cModel, ;
                  "base_url" => AGSETTINGS_Load()[ "base_url" ], ;
                  "timeout"  => AGREPL_ApiTimeout( AGSETTINGS_Load() ) } )
            ENDIF
         ENDIF
      CASE hAction[ "type" ] == "goal"
         AGREPL_HandleGoal( hAction[ "text" ], aMsgs, oPrompt )
      CASE hAction[ "type" ] == "tasks"
         AGREPL_HandleTasks( hAction[ "text" ] )
      CASE hAction[ "type" ] == "ctx"
         AGREPL_HandleCtx( hAction[ "text" ], cModel )
      CASE hAction[ "type" ] == "compact"
         aMsgs := AGREPL_HandleCompact( aMsgs, oClient, cModel )
      CASE hAction[ "type" ] == "loop"
         AGREPL_HandleLoop( hAction[ "text" ] )
      CASE hAction[ "type" ] == "rewind"
         aMsgs := AGREPL_HandleRewind( hAction[ "text" ], aMsgs )
      CASE hAction[ "type" ] == "hook"
         AGREPL_HandleHook( hAction[ "text" ], oPrompt )
      CASE hAction[ "type" ] == "run"
         AGREPL_RunPlan( @aMsgs, oClient, oReg, cModel, bGate, nMaxIter, oPrompt )
      CASE hAction[ "type" ] == "demo"
         AGREPL_Demo()
      CASE hAction[ "type" ] == "shx"
         AGREPL_ShellCmd( hAction[ "text" ], oReg )
      CASE hAction[ "type" ] == "gitx"
         AGREPL_ShellCmd( "git " + iif( Empty( hAction[ "text" ] ), "status", ;
                          hAction[ "text" ] ), oReg )
      CASE hAction[ "type" ] == "clonex"
         IF Empty( hAction[ "text" ] )
            AGREPL_Out( AGUI_Color( "Usage: /clone <url-or-user/repo>", ;
                                    AGUI_Pal( "error" ) ) + Chr(10) )
         ELSE
            AGREPL_ShellCmd( "git clone " + ;
               iif( "://" $ hAction[ "text" ], hAction[ "text" ], ;
                    "https://github.com/" + hAction[ "text" ] ), oReg )
         ENDIF
      CASE hAction[ "type" ] == "keyx"
         // /key <secret>: web-style alias of /provider key
         IF Empty( hAction[ "text" ] )
            AGREPL_Out( AGUI_Color( "Usage: /key <api-key>", ;
                                    AGUI_Pal( "error" ) ) + Chr(10) )
         ELSE
            hLoaded := AGSETTINGS_Load()
            hLoaded[ "api_key" ] := hAction[ "text" ]
            AGSETTINGS_Save( hLoaded )
            AGREPL_Out( AGUI_Color( "[api key saved to settings.json]", ;
                                    AGUI_Pal( "accent" ) ) + Chr(10) )
         ENDIF
      CASE hAction[ "type" ] == "skillx"
         AGREPL_SkillCmd( hAction[ "text" ], aMsgs, oPrompt )
      CASE hAction[ "type" ] == "toolx"
         AGREPL_ToolsList( oReg )
      CASE hAction[ "type" ] == "plan"
         cMsg := AGREPL_HandlePlan( hAction[ "text" ], aMsgs, oPrompt, oClient, cModel )
         IF !Empty( cMsg )
            // /plan <text>: run the text as the first planning prompt
            aTurn := AClone( aMsgs )
            AAdd( aTurn, { "role" => "user", "content" => cMsg } )
            hTurn := AGREPL_RunTurn( oClient, oReg, cModel, bGate, ;
                                     nMaxIter, aTurn, oPrompt )
            hRes := hTurn[ "result" ]
            IF hRes[ "success" ]
               aMsgs := hRes[ "messages" ]
            ENDIF
         ENDIF
      CASE hAction[ "type" ] == "message" .OR. hAction[ "type" ] == "init"
         IF Empty( AGCFG_Resolve( {=>} )[ "api_key" ] )
            AGREPL_Out( AGUI_Color( "[no API key configured -- type " + ;
               "/provider for the list of backends, or set a key via " + ;
               "/provider key <secret>]", "33" ) + Chr(10) )
            LOOP
         ENDIF
         cMsg := iif( hAction[ "type" ] == "init", ;
                      AGUI_InitPrompt(), hAction[ "text" ] )
         AGREPL_PushRewind( aMsgs, cMsg )
         AGREPL_ApplyAutoSkills( cMsg, aMsgs, oPrompt )
         aTurn := AClone( aMsgs )
         AAdd( aTurn, { "role" => "user", "content" => cMsg } )
         hTurn := AGREPL_RunTurn( oClient, oReg, cModel, bGate, nMaxIter, aTurn, oPrompt )
         hRes := hTurn[ "result" ]
         // when the turn stopped on the iteration cap, offer to resume it
         // with 25 more iterations -- repeatably, until done or declined.
         DO WHILE hRes[ "success" ] .AND. ;
                  hRes[ "stop_reason" ] == "max_iterations" .AND. ;
                  AGREPL_AskExtend()
            hTurn := AGREPL_RunTurn( oClient, oReg, cModel, bGate, 25, hRes[ "messages" ], oPrompt )
            hRes  := hTurn[ "result" ]
         ENDDO
         cSuggest := AGMD_Suggestion( hTurn[ "render" ][ "md" ] )
         IF hRes[ "success" ]
            aMsgs := hRes[ "messages" ]
            IF hRes[ "stop_reason" ] == "max_iterations"
               AGREPL_Out( AGUI_Color( "[stopped: iteration cap]", "33" ) + Chr(10) )
            ELSEIF hRes[ "stop_reason" ] == "interrupted"
               AGREPL_Out( AGUI_Color( "[interrupted]", "33" ) + Chr(10) )
            ENDIF
         ELSE
            IF hb_CStr( hRes[ "error_type" ] ) == "cancelled"
               AGREPL_Out( AGUI_Color( "[cancelled]", "33" ) + Chr(10) )
            ELSE
               AGREPL_Out( AGUI_Color( "!! error: " + hb_CStr( hRes[ "error_type" ] ) + ": " + ;
                       hb_CStr( hRes[ "message" ] ), "31" ) + Chr(10) )
            ENDIF
         ENDIF
         // Goal auto-continue: while a goal is active and the model has
         // not emitted the GOAL COMPLETE sentinel, keep feeding "Continue
         // toward the goal." between turns. Esc on the box pauses the
         // loop (AGPROMPT_Interrupted drained below); AG_GOAL_AUTO_CAP
         // is the safety cap on auto-iterations per user turn.
         IF hRes[ "success" ] .AND. AGREPL_GoalLooping()
            AGREPL_RunGoalLoop( @aMsgs, oClient, oReg, cModel, bGate, ;
                                nMaxIter, oPrompt )
         ENDIF
         // /loop auto-rerun: while a loop is armed, sleep the configured
         // interval (interruptible) then re-issue the loop prompt. Each
         // iteration is one full turn -- including any /btw drain below.
         IF hRes[ "success" ] .AND. s_lLoopActive
            AGREPL_RunLoopLoop( @aMsgs, oClient, oReg, cModel, bGate, ;
                                nMaxIter, oPrompt )
         ENDIF
         // a /btw interrupt carries the next message; an Esc interrupt just
         // returns to idle. Then drain any messages queued during the turn.
         DO WHILE oPrompt != NIL
            IF AGPROMPT_Interrupted( oPrompt )
               cMsg := iif( oPrompt[ "interrupt" ][ "kind" ] == "btw", ;
                            oPrompt[ "interrupt" ][ "text" ], "" )
               oPrompt[ "interrupt" ] := NIL
            ELSE
               // do NOT hb_CStr() this -- an empty queue returns NIL, and
               // hb_CStr(NIL) is the literal string "NIL", which is not Empty
               // and would loop forever running "NIL" as a message.
               cMsg := AGPROMPT_Dequeue( oPrompt )
            ENDIF
            IF Empty( cMsg )
               EXIT
            ENDIF
            AGREPL_Out( AGREPL_UserCard( cMsg ) )
            AGREPL_Out( AGUI_Color( "[handling: " + ;
                        AGUI_Summarize( cMsg, 60 ) + "]", "90" ) + Chr(10) )
            AGREPL_PushRewind( aMsgs, cMsg )
            AGREPL_ApplyAutoSkills( cMsg, aMsgs, oPrompt )
            aTurn := AClone( aMsgs )
            AAdd( aTurn, { "role" => "user", "content" => cMsg } )
            hTurn := AGREPL_RunTurn( oClient, oReg, cModel, bGate, nMaxIter, aTurn, oPrompt )
            hRes  := hTurn[ "result" ]
            IF hRes[ "success" ]
               aMsgs := hRes[ "messages" ]
               IF hRes[ "stop_reason" ] == "interrupted"
                  AGREPL_Out( AGUI_Color( "[interrupted]", "33" ) + Chr(10) )
               ENDIF
            ENDIF
         ENDDO
      ENDCASE
   ENDDO
   IF oPrompt != NIL
      s_oBoxPrompt := NIL
      AGPROMPT_Teardown( oPrompt )
   ENDIF
   RETURN NIL

// Runs one agent turn: calls AG_AgentRun, renders output, shows token bar,
// accumulates usage, and returns { result, render }.
STATIC FUNCTION AGREPL_RunTurn( oClient, oReg, cModel, bGate, nMaxIter, aMessages, oPrompt )
   LOCAL hRes, oRender, hOpts, nTurnStartMs, nTurnMs
   LOCAL aWithGoal, nUser
   oRender := AGREPL_RenderNew()
   hOpts := { "model" => cModel, ;
              "tools" => AGTOOLS_Schemas( oReg ), ;
              "tool_executor" => bGate, ;
              "max_iterations" => nMaxIter }
   IF oPrompt != NIL
      hOpts[ "interrupt_check" ] := {|| AGPROMPT_Interrupted( oPrompt ) }
   ENDIF
   // Help small/local models stay on task: when the conversation has
   // tool calls (multi-turn), inject the original user request as a
   // goal reminder right after the system prompt.
   aWithGoal := aMessages
   nUser := AGREPL_FirstUserMsg( aMessages )
   IF Len( aMessages ) > 3 .AND. nUser > 0
      aWithGoal := AClone( aMessages )
      hb_AIns( aWithGoal, 2, { "role" => "system", ;
         "content" => "IMPORTANT: Your task is: " + ;
         hb_CStr( aMessages[ nUser ][ "content" ] ) + ;
         ". Work on this until it is DONE. Do NOT ask what to do next." }, .T. )
   ENDIF
   AGTOOL_DispatchResetCount()   // reset per-turn dispatch_agent counter
   nTurnStartMs := hb_MilliSeconds()
   hRes := AG_AgentRun( oClient, aWithGoal, hOpts, ;
      {| hEv | AGREPL_RenderEv( hEv, oRender ), ;
               iif( oPrompt != NIL, AGPROMPT_Poll( oPrompt ), NIL ) } )
   // any narration left in the buffer was the final answer (no tool call
   // followed) -- print it now with the assistant bullet
   oRender[ "pendingText" ] += AGMD_Flush( oRender[ "md" ] )
   AGREPL_FlushPending( oRender )
   // tip line below the response so the user sees it immediately
   IF oRender[ "inText" ]
      AGREPL_Out( Chr(10) + AGUI_TipLine( AGUI_TipAt( ++s_nTipIdx ) ) )
   ENDIF
   nTurnMs := hb_MilliSeconds() - nTurnStartMs
   s_nSessionTurnMs += nTurnMs
   IF hRes[ "success" ]
      AGREPL_ShowTokenBar( hRes[ "usage" ], nTurnMs )
      AGREPL_AccumUsage( hRes[ "usage" ] )
      AGREPL_MaybeWarnCompact( hRes[ "usage" ], cModel )
      AGREPL_MaybeWarnNoToolCall( hRes, cModel )
   ELSE
      AGREPL_Out( Chr(10) )
   ENDIF
   AGHOOKS_Run( "turn_complete", { ;
      "status"      => AGREPL_TurnStatus( hRes ), ;
      "model"       => hb_CStr( cModel ), ;
      "tokens"      => AGREPL_TurnTokens( hRes ), ;
      "duration_ms" => nTurnMs } )
   RETURN { "result" => hRes, "render" => oRender }

// Maps an agent result hash to the string status the hooks system
// expects. interrupted > error precedence: an interrupted turn often
// surfaces as success=.F. with error_type="cancelled" or as
// stop_reason="interrupted" on success=.T..
STATIC FUNCTION AGREPL_TurnStatus( hRes )
   IF ValType( hRes ) != "H"
      RETURN "error"
   ENDIF
   IF hb_HGetDef( hRes, "stop_reason", "" ) == "interrupted" .OR. ;
      hb_CStr( hb_HGetDef( hRes, "error_type", "" ) ) == "cancelled"
      RETURN "interrupted"
   ENDIF
   IF hb_HGetDef( hRes, "success", .F. )
      RETURN "success"
   ENDIF
   RETURN "error"

// Best-effort total-token extraction from an agent result hash. Returns
// 0 when the turn errored before the model returned a usage block.
STATIC FUNCTION AGREPL_TurnTokens( hRes )
   LOCAL hU
   IF ValType( hRes ) != "H" .OR. !hb_HHasKey( hRes, "usage" )
      RETURN 0
   ENDIF
   hU := hRes[ "usage" ]
   IF ValType( hU ) != "H"
      RETURN 0
   ENDIF
   RETURN hb_HGetDef( hU, "prompt_tokens", 0 ) + ;
          hb_HGetDef( hU, "completion_tokens", 0 )

// Implements /provider — switches the active backend / model / API key.
// Usage:
//   /provider                       show current state + presets
//   /provider deepseek|glm|moonshot|openai
//                                  apply preset base_url + default model
//   /provider key <secret>         store the API key in settings.json
//   /provider model <name>         switch the model
//   /provider clear                wipe the stored API key
// Returns NIL or a hash with optional fields: { model, rebuild_client }.
STATIC FUNCTION AGREPL_HandleProvider( cArg, oPrompt )
   LOCAL cMode, cRest, hSet, hPresets, hUpd := {=>}, cMsg
   LOCAL nSpace
   cArg := AllTrim( hb_CStr( cArg ) )
   nSpace := At( " ", cArg )
   IF nSpace > 0
      cMode := Lower( Left( cArg, nSpace - 1 ) )
      cRest := AllTrim( SubStr( cArg, nSpace + 1 ) )
   ELSE
      cMode := Lower( cArg )
      cRest := ""
   ENDIF
   hSet := AGSETTINGS_Load()
   hPresets := { ;
      "deepseek" => { "base_url" => "https://api.deepseek.com", ;
                      "model"    => "deepseek-v4-flash", ;
                      "env"      => "DEEPSEEK_API_KEY" }, ;
      "glm"      => { "base_url" => "https://open.bigmodel.cn/api/paas/v4", ;
                      "model"    => "glm-4.6", ;
                      "env"      => "GLM_API_KEY" }, ;
      "moonshot" => { "base_url" => "https://api.moonshot.cn/v1", ;
                      "model"    => "kimi-k2", ;
                      "env"      => "MOONSHOT_API_KEY" }, ;
      "openai"   => { "base_url" => "https://api.openai.com/v1", ;
                      "model"    => "gpt-5", ;
                      "env"      => "OPENAI_API_KEY" }, ;
      "ollama"   => { "base_url" => "http://localhost:11434/v1", ;
                      "model"    => "llama3.1:8b", ;
                      "env"      => "" } }
   DO CASE
   CASE Empty( cMode )
      AGREPL_Out( AGUI_Color( "Current provider:", "1" ) + Chr(10) )
      AGREPL_Out( AGUI_Color( "  base_url: " + hSet[ "base_url" ], "90" ) + Chr(10) )
      AGREPL_Out( AGUI_Color( "  model:    " + hSet[ "model" ], "90" ) + Chr(10) )
      AGREPL_Out( AGUI_Color( "  api_key:  " + ;
         iif( Empty( AGCFG_Resolve( {=>} )[ "api_key" ] ), ;
              "(none -- run /provider key <secret>)", "(set)" ), "90" ) + Chr(10) )
      AGREPL_Out( Chr(10) + AGUI_Color( "Presets:", "1" ) + Chr(10) )
      AGREPL_Out( AGUI_Color( ;
         "  /provider deepseek   -> api.deepseek.com    / deepseek-v4-flash" + Chr(10) + ;
         "  /provider glm        -> open.bigmodel.cn    / glm-4.6" + Chr(10) + ;
         "  /provider moonshot   -> api.moonshot.cn     / kimi-k2" + Chr(10) + ;
         "  /provider openai     -> api.openai.com      / gpt-5" + Chr(10) + ;
         "  /provider ollama     -> localhost:11434/v1  / llama3.1:8b" + Chr(10) + ;
         Chr(10) + ;
         "  /provider key <secret>   -- save the API key in settings.json" + Chr(10) + ;
         "  /provider model <name>   -- switch the model only" + Chr(10) + ;
         "  /provider clear          -- wipe the stored API key", "90" ) + Chr(10) )
   CASE hb_HHasKey( hPresets, cMode )
      // model is about to change -- re-arm the "no tool calls" hint so
      // the next backend gets a fair re-evaluation
      s_lNoToolWarned := .F.
      hSet[ "base_url" ] := hPresets[ cMode ][ "base_url" ]
      hSet[ "model" ]    := hPresets[ cMode ][ "model" ]
      // Ollama needs no real API key, but the agent loop blocks when
      // api_key is empty. Seed a placeholder only when there isn't one
      // already; the runtime header override in ccapi.prg replaces the
      // stored cloud key with "ollama" on every request to a
      // localhost:11434 URL, so the user's real cloud key stays in
      // settings.json for the next /provider switch back to deepseek
      // / openai / etc.
      IF cMode == "ollama" .AND. Empty( hb_HGetDef( hSet, "api_key", "" ) )
         hSet[ "api_key" ] := "ollama"
      ENDIF
      AGSETTINGS_Save( hSet )
      hUpd[ "model" ] := hSet[ "model" ]
      hUpd[ "rebuild_client" ] := .T.
      cMsg := "[provider -> " + cMode + "  (" + hSet[ "base_url" ] + " / " + ;
              hSet[ "model" ] + ")]"
      IF cMode == "ollama"
         cMsg += " -- start ollama with a larger context " + ;
                 "(OLLAMA_CONTEXT_LENGTH=16384 ollama serve) and pull the " + ;
                 "model (ollama pull " + hSet[ "model" ] + "). Use a model " + ;
                 "that emits OpenAI tool_calls -- llama3.1:8b, " + ;
                 "mistral-nemo, command-r are confirmed working; " + ;
                 "qwen2.5-coder emits bare JSON in content and is NOT " + ;
                 "compatible with the agent loop. Default ollama ctx 4096 " + ;
                 "is too small for the agent prompt + tool schemas."
      ELSEIF Empty( AGCFG_Resolve( {=>} )[ "api_key" ] )
         cMsg += " -- now set the key with /provider key <secret> or " + ;
                 "export " + hPresets[ cMode ][ "env" ]
      ENDIF
      AGREPL_Out( AGUI_Color( cMsg, AGUI_Pal( "accent" ) ) + Chr(10) )
   CASE cMode == "key"
      IF Empty( cRest )
         AGREPL_Out( AGUI_Color( "Usage: /provider key <secret>", ;
                                 AGUI_Pal( "error" ) ) + Chr(10) )
         RETURN NIL
      ENDIF
      hSet[ "api_key" ] := cRest
      AGSETTINGS_Save( hSet )
      AGREPL_Out( AGUI_Color( "[api key saved to settings.json]", ;
                              AGUI_Pal( "accent" ) ) + Chr(10) )
   CASE cMode == "model"
      IF Empty( cRest )
         AGREPL_Out( AGUI_Color( "Usage: /provider model <name>", ;
                                 AGUI_Pal( "error" ) ) + Chr(10) )
         RETURN NIL
      ENDIF
      s_lNoToolWarned := .F.
      hSet[ "model" ] := cRest
      AGSETTINGS_Save( hSet )
      hUpd[ "model" ] := cRest
      hUpd[ "rebuild_client" ] := .T.
      AGREPL_Out( AGUI_Color( "[model -> " + cRest + "]", ;
                              AGUI_Pal( "accent" ) ) + Chr(10) )
   CASE cMode == "clear" .OR. cMode == "off"
      IF hb_HHasKey( hSet, "api_key" )
         hb_HDel( hSet, "api_key" )
      ENDIF
      AGSETTINGS_Save( hSet )
      AGREPL_Out( AGUI_Color( "[api key wiped from settings.json]", ;
                              AGUI_Pal( "dim" ) ) + Chr(10) )
   OTHERWISE
      AGREPL_Out( AGUI_Color( "Unknown /provider sub-command. Type " + ;
         "/provider for the list.", AGUI_Pal( "error" ) ) + Chr(10) )
      RETURN NIL
   ENDCASE
   IF oPrompt != NIL
      AGPROMPT_Redraw( oPrompt )
   ENDIF
   RETURN iif( Empty( hUpd ), NIL, hUpd )

// Implements /hook -- thin REPL adapter that delegates to the pure
// renderer AGHOOKS_Render. The renderer (in cchooks.prg) owns all the
// subcommand parsing, settings.json writes, and output formatting; this
// wrapper just pipes the text to the REPL and redraws the prompt box.
// Co-locating the renderer with the rest of the hooks logic also keeps
// it reachable from the test build (which excludes ccrepl.prg).
STATIC FUNCTION AGREPL_HandleHook( cArg, oPrompt )
   LOCAL cOut := AGHOOKS_Render( cArg )
   AGREPL_Out( cOut )
   IF oPrompt != NIL
      AGPROMPT_Redraw( oPrompt )
   ENDIF
   RETURN NIL

// Returns the API timeout in seconds for the given settings. When the user
// sets api_timeout explicitly it takes precedence. Otherwise, Ollama URLs
// get 600 s (local models can be slow), cloud backends get 120 s.
STATIC FUNCTION AGREPL_ApiTimeout( hSet )
   LOCAL nUser
   IF ValType( hSet ) == "H" .AND. hb_HHasKey( hSet, "api_timeout" ) .AND. ;
      ValType( hSet[ "api_timeout" ] ) == "N" .AND. hSet[ "api_timeout" ] > 0
      RETURN hSet[ "api_timeout" ]
   ENDIF
   // Auto-detect: Ollama runs locally on slow hardware → longer timeout
   IF "11434" $ Lower( hb_CStr( hb_HGetDef( hSet, "base_url", "" ) ) ) .OR. ;
      "ollama" $ Lower( hb_CStr( hb_HGetDef( hSet, "base_url", "" ) ) )
      RETURN 600
   ENDIF
   RETURN 120

// Per-model context window (in tokens). Used by /compact to decide
// when to suggest compaction and by AGREPL_HandleCompact to size the
// summary against the budget. Values mirror the upstream provider
// documentation at the time of writing; the function falls back to a
// conservative 32k when the model id is not in the table.
STATIC FUNCTION AGREPL_ModelContext( cModel )
   LOCAL cLow := Lower( hb_CStr( cModel ) )
   IF s_nContextOverride > 0
      RETURN s_nContextOverride
   ENDIF
   DO CASE
   CASE "deepseek-v4-pro"   $ cLow ; RETURN 1000000
   CASE "deepseek-v4-flash" $ cLow ; RETURN 1000000
   CASE "deepseek-reasoner" $ cLow ; RETURN   64000
   CASE "deepseek"          $ cLow ; RETURN 1000000
   CASE "glm-4.6"           $ cLow ; RETURN  128000
   CASE "glm"               $ cLow ; RETURN  128000
   CASE "kimi-k2"           $ cLow ; RETURN  200000
   CASE "moonshot"          $ cLow ; RETURN  200000
   CASE "gpt-5"             $ cLow ; RETURN  400000
   CASE "gpt-4o"            $ cLow ; RETURN  128000
   CASE "gpt-4"             $ cLow ; RETURN  128000
   CASE "gemma4"            $ cLow ; RETURN  128000
   CASE "gemma3"            $ cLow ; RETURN  128000
   CASE "gemma"             $ cLow ; RETURN  128000
   CASE "gemini"            $ cLow ; RETURN 1048576
   ENDCASE
   RETURN 32000

// After every successful turn, compare the LAST turn's prompt_tokens
// against the configured fraction of the model's context window and
// print a single dim hint when it crosses the threshold. Non-blocking,
// non-destructive -- the user runs /compact when they decide. No second
// warning is printed during a session until the user actually compacts
// or /clears, to avoid noise.
STATIC FUNCTION AGREPL_MaybeWarnCompact( hUsage, cModel )
   LOCAL nIn, nCtx, nThr, nPct
   IF s_lCompactNudged
      RETURN NIL
   ENDIF
   IF ValType( hUsage ) != "H"
      RETURN NIL
   ENDIF
   nIn := hb_HGetDef( hUsage, "prompt_tokens", 0 )
   IF nIn <= 0
      RETURN NIL
   ENDIF
   nCtx := AGREPL_ModelContext( cModel )
   nThr := hb_HGetDef( AGSETTINGS_Load(), "compact_threshold", 0.7 )
   IF ValType( nThr ) != "N" .OR. nThr <= 0 .OR. nThr >= 1
      nThr := 0.7
   ENDIF
   IF nIn < ( nCtx * nThr )
      RETURN NIL
   ENDIF
   nPct := Int( ( nIn * 100.0 ) / nCtx )
   IF AGUI_ColorOn()
      // orange context-critical card (web contextCard parity)
      AGREPL_Out( AGUI_Card( ;
         AGUI_Color( "CONTEXT WINDOW CRITICAL", "1;38;2;251;146;60" ) + "   " + ;
         AGUI_Color( LTrim( Str( nIn ) ) + " / " + LTrim( Str( nCtx ) ) + ;
                     " tkns  (" + LTrim( Str( nPct ) ) + "%)", "2" ) + Chr(10) + ;
         "Memory is filling up: run /compact to summarise old turns, or " + ;
         "/clear to start fresh.", ;
         "card_ctx", Min( AGREPL_Cols() - 2, 100 ) ) + Chr(10) )
   ELSE
      AGREPL_Out( AGUI_Color( ;
         "[context " + LTrim( Str( nPct ) ) + "% full -- run /compact to " + ;
         "summarise old turns and free up space]", ;
         AGUI_Pal( "warn" ) ) + Chr(10) )
   ENDIF
   s_lCompactNudged := .T.
   RETURN NIL

// After every successful turn, check whether the model actually called
// any tool. If the turn ended on a plain text reply AND that reply
// contains a phrase suggesting the model wanted to act but could not
// ("I would run...", "I cannot access...", "without access to tools"),
// print a one-shot hint pointing at /provider model. Tool-calling
// requires model support: qwen2.5-coder, llama3.1+, mistral-nemo for
// Ollama; deepseek-v4-flash, gpt-5, kimi-k2, glm-4.6 for cloud. Cleared
// once the model successfully calls a tool (proof of support) or by
// /clear and /provider. The check fires at most once per session so
// the hint never spams.
STATIC FUNCTION AGREPL_MaybeWarnNoToolCall( hRes, cModel )
   LOCAL nCalls, cText, cLow, aPhrases, cPhrase
   nCalls := hb_HGetDef( hRes, "tool_call_count", 0 )
   IF nCalls > 0
      // model proved it supports tools -- mute the hint for the rest
      // of the session even if a later turn happens to be conversational
      s_lNoToolWarned := .T.
      RETURN NIL
   ENDIF
   IF s_lNoToolWarned
      RETURN NIL
   ENDIF
   cText := hb_CStr( hb_HGetDef( hRes, "content", "" ) )
   IF Empty( cText )
      RETURN NIL
   ENDIF
   cLow := Lower( cText )
   aPhrases := { ;
      "i would run", "i would use", "i would call", "i would invoke", ;
      "i'll need to", "i'd need to", "i would need to", ;
      "i cannot run", "i can't run", "i cannot execute", "i can't execute", ;
      "i cannot access", "i can't access", "i do not have access", ;
      "i don't have access", "without access to tool", ;
      "i'm unable to run", "unable to execute", ;
      "you can run", "you could run", "you would run" }
   FOR EACH cPhrase IN aPhrases
      IF cPhrase $ cLow
         AGREPL_Out( AGUI_Color( ;
            "[hint: 0 tool calls and reply reads like the model wants " + ;
            "to act but cannot. If '" + cModel + "' lacks tool-calling, " + ;
            "switch with /provider model <name>. Tested: qwen2.5-coder, " + ;
            "llama3.1+, mistral-nemo (Ollama); deepseek-v4-flash, gpt-5, " + ;
            "kimi-k2, glm-4.6 (cloud).]", ;
            AGUI_Pal( "warn" ) ) + Chr(10) )
         s_lNoToolWarned := .T.
         RETURN NIL
      ENDIF
   NEXT
   RETURN NIL

// Implements /compact -- ask the model to summarise the old part of
// the conversation, then replace it with one synthetic system note.
//   aMsgs[ 1 ]   the system prompt (kept verbatim)
//   aMsgs[ 2..K ]  candidates for summarisation
//   aMsgs[ K+1..N ]  recent turns kept verbatim (default last 4)
// Refuses to compact when the very last assistant turn has dangling
// tool_calls -- compacting between a tool_call and its matching
// tool_result would orphan an id and break the next turn. Returns the
// new aMsgs array; on any failure returns the original untouched.
STATIC FUNCTION AGREPL_HandleCompact( aMsgs, oClient, cModel )
   LOCAL nKeep := 4, nN, i, aOld, aSumMsgs, hRes, cSummary
   LOCAL aNew, hMsg
   nN := Len( aMsgs )
   IF nN < 6
      AGREPL_Out( AGUI_Color( "[nothing to compact -- conversation is short]", ;
                              AGUI_Pal( "dim" ) ) + Chr(10) )
      RETURN aMsgs
   ENDIF
   // Bail if the boundary would land mid tool-call cycle
   IF ValType( aMsgs[ nN ] ) == "H" .AND. ;
      hb_HGetDef( aMsgs[ nN ], "role", "" ) == "assistant" .AND. ;
      hb_HHasKey( aMsgs[ nN ], "tool_calls" )
      AGREPL_Out( AGUI_Color( "[cannot compact: last assistant turn has a " + ;
                              "pending tool_call -- send a message first]", ;
                              AGUI_Pal( "error" ) ) + Chr(10) )
      RETURN aMsgs
   ENDIF
   // Gather the slice to summarise into a string. Skip tool calls;
   // include role labels so the summariser knows who said what.
   aOld := {}
   FOR i := 2 TO nN - nKeep
      hMsg := aMsgs[ i ]
      IF ValType( hMsg ) == "H" .AND. ;
         ValType( hb_HGetDef( hMsg, "content", NIL ) ) == "C" .AND. ;
         !Empty( hMsg[ "content" ] )
         AAdd( aOld, "[" + hb_HGetDef( hMsg, "role", "?" ) + "] " + ;
                     hMsg[ "content" ] )
      ENDIF
   NEXT
   IF Empty( aOld )
      AGREPL_Out( AGUI_Color( "[nothing to compact -- nothing in range]", ;
                              AGUI_Pal( "dim" ) ) + Chr(10) )
      RETURN aMsgs
   ENDIF
   AGREPL_Out( AGUI_Color( "[compacting " + LTrim( Str( Len( aOld ) ) ) + ;
                           " turns into a summary...]", ;
                           AGUI_Pal( "dim" ) ) + Chr(10) )
   // Stateless one-shot summarisation turn -- bypasses the agent loop
   // (no tools, no skills, no goal injection), just a single call.
   aSumMsgs := { ;
      { "role" => "system", ;
        "content" => "You are a compaction assistant. Produce a TIGHT 15-25 " + ;
           "line bullet summary of the conversation below. Preserve: " + ;
           "decisions taken, exact file paths, exact identifier / symbol " + ;
           "names, open todos, error messages quoted verbatim, recent " + ;
           "tool results. Do NOT paraphrase code or commands -- keep " + ;
           "them verbatim. Do NOT invent details. No preamble, no " + ;
           "'Suggested next' line." }, ;
      { "role" => "user", ;
        "content" => "Conversation to compact:" + Chr(10) + Chr(10) + ;
                     AGREPL_JoinArray( aOld, Chr(10) + Chr(10) ) } }
   hRes := AG_AgentRun( oClient, aSumMsgs, ;
      { "model" => cModel, "max_iterations" => 1 }, ;
      {| hEv | HB_SYMBOL_UNUSED( hEv ) } )
   IF !hRes[ "success" ]
      AGREPL_Out( AGUI_Color( "[compact failed: " + ;
                              hb_CStr( hb_HGetDef( hRes, "error_type", "?" ) ) + ;
                              "]", AGUI_Pal( "error" ) ) + Chr(10) )
      RETURN aMsgs
   ENDIF
   cSummary := AGREPL_LastAssistantText( hRes[ "messages" ] )
   IF Empty( cSummary )
      AGREPL_Out( AGUI_Color( "[compact failed: empty summary]", ;
                              AGUI_Pal( "error" ) ) + Chr(10) )
      RETURN aMsgs
   ENDIF
   // Rebuild aMsgs: original system prompt, the new compaction note,
   // then the last nKeep turns verbatim.
   aNew := { aMsgs[ 1 ] }
   AAdd( aNew, { "role" => "system", ;
                 "content" => "[Conversation compacted by /compact -- " + ;
                    "summary of older turns follows. Treat as authoritative " + ;
                    "context for what came before.]" + Chr(10) + Chr(10) + ;
                    cSummary } )
   FOR i := nN - nKeep + 1 TO nN
      AAdd( aNew, aMsgs[ i ] )
   NEXT
   s_lCompactNudged := .F.
   IF AGUI_ColorOn()
      // purple "context compacted" card (web compactCard parity)
      AGREPL_Out( AGUI_Card( ;
         AGUI_Color( "CONTEXT COMPACTED", "1;38;2;192;132;252" ) + Chr(10) + ;
         AGUI_Color( LTrim( Str( Len( aOld ) ) ) + " turns -> 1 summary, " + ;
                     "kept last " + LTrim( Str( nKeep ) ) + " verbatim", ;
                     "38;2;232;226;248" ), ;
         "card_think", Min( AGREPL_Cols() - 2, 100 ) ) + Chr(10) )
   ELSE
      AGREPL_Out( AGUI_Color( "[compacted: " + LTrim( Str( Len( aOld ) ) ) + ;
                              " turns -> 1 summary, kept last " + ;
                              LTrim( Str( nKeep ) ) + "]", ;
                              AGUI_Pal( "accent" ) ) + Chr(10) )
   ENDIF
   RETURN aNew

// Joins an array of strings with cSep. Local helper (avoids depending
// on hbct's array-join routine across builds).
STATIC FUNCTION AGREPL_JoinArray( aArr, cSep )
   LOCAL cOut := "", i, n := Len( aArr )
   FOR i := 1 TO n
      cOut += aArr[ i ]
      IF i < n
         cOut += cSep
      ENDIF
   NEXT
   RETURN cOut

// Implements /tasks — inspect background subagent tasks. Forms:
//   /tasks            -> tabular list (id, status, elapsed, prompt summary)
//   /tasks view <id>  -> full record (prompt, reply or error)
//   /tasks kill <id>  -> request cancel; worker exits at next agent boundary
//   /tasks clear      -> remove finished/failed/cancelled records
// No UI runs on the worker thread itself; this handler is the user's
// only window into the registry maintained by ccbg.prg.
STATIC FUNCTION AGREPL_HandleTasks( cArg )
   LOCAL cTrim := AllTrim( hb_CStr( cArg ) )
   LOCAL cLow  := Lower( cTrim )
   LOCAL nSp, cMode, cRest, hTask, aTasks, cOut, cElapsed, cPrev, cSummary
   nSp := At( " ", cTrim )
   IF nSp > 0
      cMode := Lower( Left( cTrim, nSp - 1 ) )
      cRest := AllTrim( SubStr( cTrim, nSp + 1 ) )
   ELSE
      cMode := cLow
      cRest := ""
   ENDIF
   DO CASE
   CASE Empty( cMode )
      aTasks := AGBG_List()
      IF Empty( aTasks )
         AGREPL_Out( AGUI_Color( "[no background tasks yet -- use the " + ;
                                 "dispatch_agent_background tool]", ;
                                 AGUI_Pal( "dim" ) ) + Chr(10) )
         RETURN NIL
      ENDIF
      cOut := AGUI_Color( "  id     status     elapsed  type      prompt", "1" ) + Chr(10)
      FOR EACH hTask IN aTasks
         cElapsed := AGREPL_TaskElapsed( hTask )
         cSummary := hb_CStr( hTask[ "prompt" ] )
         IF hb_UTF8Len( cSummary ) > 60
            cSummary := hb_UTF8SubStr( cSummary, 1, 57 ) + "..."
         ENDIF
         cOut += "  " + PadR( hTask[ "id" ], 6 ) + " " + ;
                 PadR( hTask[ "status" ], 10 ) + " " + ;
                 PadR( cElapsed, 8 ) + " " + ;
                 PadR( hTask[ "type" ], 9 ) + " " + cSummary + Chr(10)
      NEXT
      AGREPL_Out( AGUI_Color( cOut, "90" ) )
   CASE cMode == "view"
      IF Empty( cRest )
         AGREPL_Out( AGUI_Color( "Usage: /tasks view <id>", ;
                                 AGUI_Pal( "error" ) ) + Chr(10) )
         RETURN NIL
      ENDIF
      hTask := AGBG_Get( cRest )
      IF hTask == NIL
         AGREPL_Out( AGUI_Color( "[task '" + cRest + "' not found]", ;
                                 AGUI_Pal( "error" ) ) + Chr(10) )
         RETURN NIL
      ENDIF
      cElapsed := AGREPL_TaskElapsed( hTask )
      cOut := AGUI_Color( "  id:         " + hTask[ "id" ] + Chr(10) + ;
                          "  status:     " + hTask[ "status" ] + Chr(10) + ;
                          "  type:       " + hTask[ "type" ] + Chr(10) + ;
                          "  elapsed:    " + cElapsed + Chr(10) + ;
                          "  timeout:    " + LTrim( Str( hTask[ "timeout" ] ) ) + "s" + Chr(10) + ;
                          "  iterations: " + LTrim( Str( hTask[ "iterations" ] ) ) + Chr(10) + ;
                          "  prompt:     " + hTask[ "prompt" ] + Chr(10), "90" )
      IF !Empty( hTask[ "error" ] )
         cOut += AGUI_Color( "  error:" + Chr(10), "1;31" ) + ;
                 "    " + hTask[ "error" ] + Chr(10)
      ENDIF
      IF !Empty( hTask[ "reply" ] )
         cOut += AGUI_Color( "  reply:" + Chr(10), "1" ) + ;
                 "    " + StrTran( hTask[ "reply" ], Chr(10), Chr(10) + "    " ) + Chr(10)
      ENDIF
      AGREPL_Out( cOut )
   CASE cMode == "kill"
      IF Empty( cRest )
         AGREPL_Out( AGUI_Color( "Usage: /tasks kill <id>", ;
                                 AGUI_Pal( "error" ) ) + Chr(10) )
         RETURN NIL
      ENDIF
      IF AGBG_Kill( cRest )
         AGREPL_Out( AGUI_Color( "[cancel requested for " + cRest + ;
                                 " -- worker exits at next agent boundary]", ;
                                 AGUI_Pal( "dim" ) ) + Chr(10) )
      ELSE
         AGREPL_Out( AGUI_Color( "[task '" + cRest + "' not running or not found]", ;
                                 AGUI_Pal( "error" ) ) + Chr(10) )
      ENDIF
   CASE cMode == "clear"
      AGREPL_Out( AGUI_Color( "[" + LTrim( Str( AGBG_ClearFinished() ) ) + ;
                              " finished tasks cleared]", ;
                              AGUI_Pal( "dim" ) ) + Chr(10) )
   OTHERWISE
      AGREPL_Out( AGUI_Color( "Unknown /tasks sub-command. " + ;
                              "Use /tasks, /tasks view <id>, " + ;
                              "/tasks kill <id>, /tasks clear.", ;
                              AGUI_Pal( "error" ) ) + Chr(10) )
   ENDCASE
   RETURN NIL

// Formats the elapsed time for one task record as "Ns" or "still running".
// Uses ended_ms when set, otherwise the wall clock; queued tasks show "-".
STATIC FUNCTION AGREPL_TaskElapsed( hTask )
   LOCAL nStart := hb_HGetDef( hTask, "started_ms", 0 )
   LOCAL nEnd   := hb_HGetDef( hTask, "ended_ms",   0 )
   IF nStart == 0
      RETURN "-"
   ENDIF
   IF nEnd == 0
      nEnd := hb_milliseconds()
   ENDIF
   RETURN Str( ( nEnd - nStart ) / 1000.0, 6, 1 ) + "s"

// Auto-continue loop driven by /goal. Called from the main loop after a
// user-initiated turn returns, while a goal is active and the auto-
// continue flag is on. Each iteration:
//   1. scans the last assistant reply for the GOAL COMPLETE sentinel.
//      Found -> announce, clear s_lGoalLooping, return.
//   2. checks for an Esc interrupt on the box. Pressed -> pause the
//      loop (keeps the goal text), drain the interrupt, return.
//   3. runs one more turn with a synthetic "Continue toward the goal."
//      user message and the same RunTurn machinery.
// AG_GOAL_AUTO_CAP caps the iterations per user turn so a runaway
// model cannot loop forever.
STATIC FUNCTION AGREPL_RunGoalLoop( aMsgs, oClient, oReg, cModel, bGate, nMaxIter, oPrompt )
   LOCAL nIter := 0, cLast, aTurn, hTurn, hRes
   DO WHILE s_lGoalLooping .AND. nIter < AG_GOAL_AUTO_CAP
      cLast := AGREPL_LastAssistantText( aMsgs )
      IF AGREPL_GoalDone( cLast )
         AGREPL_Out( AGUI_Color( "[" + AG_GOAL_SENTINEL + " -- goal " + ;
                                 "reached, auto-continue off]", ;
                                 AGUI_Pal( "accent" ) ) + Chr(10) )
         s_lGoalLooping := .F.
         EXIT
      ENDIF
      IF oPrompt != NIL .AND. AGPROMPT_Interrupted( oPrompt )
         oPrompt[ "interrupt" ] := NIL
         s_lGoalLooping := .F.
         AGREPL_Out( AGUI_Color( "[goal auto-continue paused by Esc -- " + ;
                                 "/goal <text> or a new message to restart]", ;
                                 AGUI_Pal( "dim" ) ) + Chr(10) )
         EXIT
      ENDIF
      nIter++
      AGREPL_Out( AGUI_Color( "[goal auto-continue " + LTrim( Str( nIter ) ) + ;
                              "/" + LTrim( Str( AG_GOAL_AUTO_CAP ) ) + "]", ;
                              AGUI_Pal( "dim" ) ) + Chr(10) )
      aTurn := AClone( aMsgs )
      AAdd( aTurn, { "role" => "user", ;
                     "content" => "Continue toward the goal. When it is " + ;
                        "fully met, reply with ONLY the literal sentinel " + ;
                        "on its own line: " + AG_GOAL_SENTINEL } )
      hTurn := AGREPL_RunTurn( oClient, oReg, cModel, bGate, nMaxIter, ;
                               aTurn, oPrompt )
      hRes := hTurn[ "result" ]
      IF !hRes[ "success" ]
         AGREPL_Out( AGUI_Color( "[goal auto-continue stopped: " + ;
                                 hb_CStr( hb_HGetDef( hRes, "error_type", "?" ) ) + ;
                                 "]", "33" ) + Chr(10) )
         s_lGoalLooping := .F.
         EXIT
      ENDIF
      aMsgs := hRes[ "messages" ]
   ENDDO
   IF nIter >= AG_GOAL_AUTO_CAP .AND. s_lGoalLooping
      AGREPL_Out( AGUI_Color( "[goal auto-continue cap (" + ;
                              LTrim( Str( AG_GOAL_AUTO_CAP ) ) + ;
                              ") hit -- send a message to keep going, " + ;
                              "or /goal stop / /goal clear]", ;
                              AGUI_Pal( "dim" ) ) + Chr(10) )
   ENDIF
   RETURN NIL

// Walks aMsgs back-to-front and returns the content of the most recent
// assistant message (or "" when none). Used by the goal auto-loop to
// inspect the model's reply for the GOAL COMPLETE sentinel.
STATIC FUNCTION AGREPL_LastAssistantText( aMsgs )
   LOCAL i, hMsg
   IF ValType( aMsgs ) != "A"
      RETURN ""
   ENDIF
   FOR i := Len( aMsgs ) TO 1 STEP -1
      hMsg := aMsgs[ i ]
      IF ValType( hMsg ) == "H" .AND. ;
         hb_HGetDef( hMsg, "role", "" ) == "assistant" .AND. ;
         ValType( hb_HGetDef( hMsg, "content", NIL ) ) == "C"
         RETURN hMsg[ "content" ]
      ENDIF
   NEXT
   RETURN ""

// Implements /goal — set / show / clear a "keep working until the
// condition is met" goal.
//   /goal              -> print the current goal (or "(none)")
//   /goal <text>       -> store the goal, inject the keep-working
//                         system note into aMsgs, and arm the auto-
//                         continue loop in the main REPL loop
//   /goal stop         -> pause the auto-continue loop without
//                         dropping the goal (next /goal <text> or a
//                         normal message restarts the behaviour)
//   /goal clear|off    -> drop the goal entirely
// The injected system note teaches the model the sentinel
// "GOAL COMPLETE": when the condition is met it should reply ONLY
// with that line. The main loop watches for the sentinel and
// auto-issues "Continue toward the goal." until it appears, the
// user hits Esc, or AG_GOAL_AUTO_CAP iterations have run.
STATIC FUNCTION AGREPL_HandleGoal( cArg, aMsgs, oPrompt )
   LOCAL cTrim := AllTrim( hb_CStr( cArg ) )
   LOCAL cLow  := Lower( cTrim )
   DO CASE
   CASE Empty( cTrim )
      IF Empty( s_cGoal )
         AGREPL_Out( AGUI_Color( "[no goal -- /goal <text> to set]", ;
                                 AGUI_Pal( "dim" ) ) + Chr(10) )
      ELSE
         AGREPL_GoalCard()
      ENDIF
   CASE cLow == "stop"
      IF !s_lGoalLooping
         AGREPL_Out( AGUI_Color( "[auto-continue already off]", ;
                                 AGUI_Pal( "dim" ) ) + Chr(10) )
      ELSE
         s_lGoalLooping := .F.
         AGREPL_Out( AGUI_Color( "[goal auto-continue stopped]", ;
                                 AGUI_Pal( "dim" ) ) + Chr(10) )
      ENDIF
   CASE cLow == "clear" .OR. cLow == "off"
      IF Empty( s_cGoal )
         AGREPL_Out( AGUI_Color( "[no goal to clear]", ;
                                 AGUI_Pal( "dim" ) ) + Chr(10) )
      ELSE
         s_cGoal := ""
         s_lGoalLooping := .F.
         AAdd( aMsgs, { "role" => "system", ;
                        "content" => "User cleared the session goal. Do not " + ;
                           "treat the previous goal as a constraint, and do " + ;
                           "not emit the GOAL COMPLETE sentinel any more." } )
         AGREPL_Out( AGUI_Color( "[goal cleared]", AGUI_Pal( "dim" ) ) + Chr(10) )
      ENDIF
   OTHERWISE
      s_cGoal := cTrim
      s_lGoalLooping := .T.
      AAdd( aMsgs, { "role" => "system", ;
                     "content" => "Goal set by /goal -- keep working until " + ;
                        "the condition is met. After every turn ask yourself " + ;
                        "whether the goal is fully achieved. If it IS, reply " + ;
                        "with ONLY the literal sentinel on its own line:" + Chr(10) + Chr(10) + ;
                        "    " + AG_GOAL_SENTINEL + Chr(10) + Chr(10) + ;
                        "If it is NOT, continue with the next concrete step. " + ;
                        "The REPL will auto-feed 'Continue toward the goal.' " + ;
                        "between turns, so do not wait for the user." + Chr(10) + Chr(10) + ;
                        "Goal:" + Chr(10) + Chr(10) + s_cGoal } )
      AGREPL_GoalCard()
   ENDCASE
   IF oPrompt != NIL
      AGPROMPT_Redraw( oPrompt )
   ENDIF
   RETURN NIL

// The active goal as an indigo card (web goalCard parity). Falls back to
// the old accent line when colour is off.
STATIC FUNCTION AGREPL_GoalCard()
   LOCAL nW
   IF !AGUI_ColorOn()
      AGREPL_Out( AGUI_Color( "[goal: " + s_cGoal + ;
                  iif( s_lGoalLooping, "  (auto-continue ON)", ;
                                       "  (auto-continue paused)" ) + "]", ;
                  AGUI_Pal( "accent" ) ) + Chr(10) )
      RETURN NIL
   ENDIF
   nW := Min( AGREPL_Cols() - 2, 100 )
   AGREPL_Out( AGUI_CardLine( AGUI_Color( "ACTIVE GOAL", ;
               "1;38;2;165;180;252" ) + "   " + ;
               AGUI_Color( iif( s_lGoalLooping, "auto-continue ON", ;
                                "auto-continue paused" ), "2" ), ;
               "card_goal", nW ) + Chr(10) )
   AGREPL_Out( AGUI_CardLine( s_cGoal, "card_goal", nW ) + Chr(10) )
   RETURN NIL

// True when a goal is set. Public so the status line in AGPROMPT_Redraw
// can show a [goal] badge alongside [plan-mode] / [lean].
FUNCTION AGREPL_HasGoal()
   RETURN !Empty( s_cGoal )

// True when the agent should auto-continue after a turn (goal active AND
// not paused). Public so the main loop can inspect it without poking the
// static directly.
FUNCTION AGREPL_GoalLooping()
   RETURN s_lGoalLooping

// Stops the auto-continue loop. Called by the main loop when it detects
// the GOAL COMPLETE sentinel or when the user hits Esc mid-loop.
FUNCTION AGREPL_StopGoalLoop()
   s_lGoalLooping := .F.
   RETURN NIL

// /ctx handler: show or set the context window size override.
//   /ctx          -> display current context window + usage
//   /ctx <N>      -> set override to N tokens (must be >= 1024)
//   /ctx auto     -> reset to auto-detected from the model table
STATIC FUNCTION AGREPL_HandleCtx( cArg, cModel )
   LOCAL nAuto, nCur, nUsed, nPct
   nAuto := AGREPL_AutoContext( cModel )
   nCur  := AGREPL_ModelContext( cModel )   // respects override
   IF Empty( cArg )
      // display current context info
      AGREPL_Out( AGUI_Color( "[context: " + ;
         LTrim( Str( nCur ) ) + " tokens (" + cModel + ;
         iif( s_nContextOverride > 0, ", override, auto=" + ;
              LTrim( Str( nAuto ) ), "" ) + ")]", "90" ) + Chr(10) )
      nUsed := 0
      AEval( hb_HKeys( s_hSessionUsage ), {| cKey | ;
         nUsed += hb_HGetDef( s_hSessionUsage, cKey, 0 ) } )
      IF nUsed > 0
         nPct := Int( nUsed / nCur * 100 )
         AGREPL_Out( AGUI_Color( "[session usage: " + ;
            LTrim( Str( nUsed ) ) + " tokens (" + LTrim( Str( nPct ) ) + ;
            "%)]", "90" ) + Chr(10) )
      ENDIF
      AGREPL_Out( AGUI_Color( "[override: /ctx <N> to set, /ctx auto to reset]", ;
         "90" ) + Chr(10) )
      RETURN NIL
   ENDIF
   IF Lower( cArg ) == "auto"
      s_nContextOverride := 0
      AGREPL_Out( AGUI_Color( "[context: auto-detected from model (" + ;
         LTrim( Str( nAuto ) ) + " tokens)]", "90" ) + Chr(10) )
      RETURN NIL
   ENDIF
   IF IsDigit( Left( cArg, 1 ) )
      s_nContextOverride := Val( cArg )
      IF s_nContextOverride < 1024
         s_nContextOverride := 0
         AGREPL_Out( AGUI_Color( "[context must be >= 1024 tokens]", "33" ) + ;
            Chr(10) )
         RETURN NIL
      ENDIF
      AGREPL_Out( AGUI_Color( "[context override: " + ;
         LTrim( Str( s_nContextOverride ) ) + " tokens " + ;
         "(auto would be " + LTrim( Str( nAuto ) ) + ")]", "90" ) + Chr(10) )
      RETURN NIL
   ENDIF
   AGREPL_Out( AGUI_Color( "[usage: /ctx, /ctx <N>, or /ctx auto]", "33" ) + ;
      Chr(10) )
   RETURN NIL

// Like AGREPL_ModelContext but ignores the override so HandleCtx can
// show the auto-detected value alongside the override.
STATIC FUNCTION AGREPL_AutoContext( cModel )
   LOCAL nSave := s_nContextOverride, nResult
   s_nContextOverride := 0
   nResult := AGREPL_ModelContext( cModel )
   s_nContextOverride := nSave
   RETURN nResult

// Returns a hash of every REPL-level static that /save needs to persist,
// so /load can restore the full session state (not just messages + model
// + usage). Skills are returned as the array of active names; the
// pending suggested-next prompt is owned by AGREPL_Run and threaded in
// separately. Values stay primitive (string / numeric / logical / array)
// so hb_jsonEncode round-trips cleanly.
FUNCTION AGREPL_StateExport()
   RETURN { "goal"             => s_cGoal, ;
            "goal_looping"     => s_lGoalLooping, ;
            "session_turn_ms"  => s_nSessionTurnMs, ;
            "plan_mode"        => s_lPlanMode, ;
            "plan_steps"       => s_aPlanSteps, ;
            "lean_mode"        => s_lLeanMode, ;
            "skills"           => AGSKILL_Active() }

// Restores the REPL-level statics from a hash produced by
// AGREPL_StateExport. Missing keys fall back to current defaults so an
// old session file without these fields still loads cleanly.
FUNCTION AGREPL_StateImport( hState )
   LOCAL aSkills, cName
   IF ValType( hState ) != "H"
      RETURN NIL
   ENDIF
   s_cGoal          := hb_HGetDef( hState, "goal",            "" )
   s_lGoalLooping   := hb_HGetDef( hState, "goal_looping",    .F. )
   s_nSessionTurnMs := hb_HGetDef( hState, "session_turn_ms", 0 )
   s_lPlanMode      := hb_HGetDef( hState, "plan_mode",       .F. )
   s_aPlanSteps     := hb_HGetDef( hState, "plan_steps",      {} )
   s_lLeanMode      := hb_HGetDef( hState, "lean_mode",       .F. )
   AGSKILL_ClearAll()
   aSkills := hb_HGetDef( hState, "skills", {} )
   IF ValType( aSkills ) == "A"
      FOR EACH cName IN aSkills
         IF ValType( cName ) == "C" .AND. !Empty( cName )
            AGSKILL_Activate( cName )
         ENDIF
      NEXT
   ENDIF
   RETURN NIL

// True when cReply ends with (or contains, on its own line) the GOAL
// COMPLETE sentinel emitted by the model when it believes the condition
// is met. The check is case-sensitive on the sentinel itself and
// tolerates surrounding whitespace / punctuation.
FUNCTION AGREPL_GoalDone( cReply )
   LOCAL cTrim
   IF ValType( cReply ) != "C" .OR. Empty( cReply )
      RETURN .F.
   ENDIF
   cTrim := AllTrim( hb_CStr( cReply ) )
   RETURN ( AG_GOAL_SENTINEL $ cTrim )

// True when /loop is armed -- the main loop reruns the prompt on the
// configured interval after each turn. Public for AGPROMPT_Redraw to
// optionally show a [loop] badge.
FUNCTION AGREPL_LoopActive()
   RETURN s_lLoopActive

// Parses a duration like "30s", "5m", "1h", or a bare number (seconds).
// Returns the duration in seconds, or 0 on parse failure / non-positive.
STATIC FUNCTION AGREPL_ParseInterval( cArg )
   LOCAL cTrim := Lower( AllTrim( hb_CStr( cArg ) ) )
   LOCAL cUnit, cNum, nVal
   IF Empty( cTrim )
      RETURN 0
   ENDIF
   cUnit := Right( cTrim, 1 )
   IF cUnit $ "smh"
      cNum := Left( cTrim, Len( cTrim ) - 1 )
   ELSE
      cUnit := "s"
      cNum  := cTrim
   ENDIF
   IF Empty( cNum ) .OR. ! AGREPL_IsAllDigits( cNum )
      RETURN 0
   ENDIF
   nVal := Val( cNum )
   DO CASE
   CASE cUnit == "s" ; RETURN nVal
   CASE cUnit == "m" ; RETURN nVal * 60
   CASE cUnit == "h" ; RETURN nVal * 3600
   ENDCASE
   RETURN 0

STATIC FUNCTION AGREPL_IsAllDigits( cStr )
   LOCAL i
   IF Empty( cStr )
      RETURN .F.
   ENDIF
   FOR i := 1 TO Len( cStr )
      IF !IsDigit( SubStr( cStr, i, 1 ) )
         RETURN .F.
      ENDIF
   NEXT
   RETURN .T.

// Formats nSec back into the compact "5m", "30s", "1h" form used in
// /loop status output. Picks the largest exact-divisor unit; falls back
// to seconds when none divide evenly.
STATIC FUNCTION AGREPL_FormatInterval( nSec )
   IF nSec >= 3600 .AND. ( nSec % 3600 ) == 0
      RETURN LTrim( Str( Int( nSec / 3600 ) ) ) + "h"
   ELSEIF nSec >= 60 .AND. ( nSec % 60 ) == 0
      RETURN LTrim( Str( Int( nSec / 60 ) ) ) + "m"
   ENDIF
   RETURN LTrim( Str( nSec ) ) + "s"

// Implements /loop — fixed-interval prompt rerun, like Claude Code.
//   /loop <interval> <prompt>  arm the loop (e.g. /loop 5m check CI)
//   /loop                      show the active loop (or "(none)")
//   /loop status               same as bare /loop
//   /loop stop|off             stop the auto-rerun, keep the prompt text
//   /loop clear                drop the prompt text entirely
// Interval suffixes: s (default), m, h. Bare numbers = seconds.
STATIC FUNCTION AGREPL_HandleLoop( cArg )
   LOCAL cTrim := AllTrim( hb_CStr( cArg ) )
   LOCAL cLow  := Lower( cTrim )
   LOCAL nSpace, cFirst, cRest, nSec
   DO CASE
   CASE Empty( cTrim ) .OR. cLow == "status"
      IF Empty( s_cLoopPrompt )
         AGREPL_Out( AGUI_Color( "[no loop -- /loop <interval> <prompt> to " + ;
                                 "arm (e.g. /loop 5m check CI)]", ;
                                 AGUI_Pal( "dim" ) ) + Chr(10) )
      ELSE
         AGREPL_Out( AGUI_Color( "[loop: every " + ;
                                 AGREPL_FormatInterval( s_nLoopIntervalSec ) + ;
                                 " -> " + s_cLoopPrompt + ;
                                 iif( s_lLoopActive, "  (ON)", ;
                                                     "  (stopped)" ) + "]", ;
                                 AGUI_Pal( "accent" ) ) + Chr(10) )
      ENDIF
   CASE cLow == "stop" .OR. cLow == "off"
      IF !s_lLoopActive
         AGREPL_Out( AGUI_Color( "[loop already stopped]", ;
                                 AGUI_Pal( "dim" ) ) + Chr(10) )
      ELSE
         s_lLoopActive := .F.
         AGREPL_Out( AGUI_Color( "[loop stopped]", ;
                                 AGUI_Pal( "dim" ) ) + Chr(10) )
      ENDIF
   CASE cLow == "clear"
      IF Empty( s_cLoopPrompt )
         AGREPL_Out( AGUI_Color( "[no loop to clear]", ;
                                 AGUI_Pal( "dim" ) ) + Chr(10) )
      ELSE
         s_cLoopPrompt := ""
         s_nLoopIntervalSec := 0
         s_lLoopActive := .F.
         AGREPL_Out( AGUI_Color( "[loop cleared]", ;
                                 AGUI_Pal( "dim" ) ) + Chr(10) )
      ENDIF
   OTHERWISE
      nSpace := At( " ", cTrim )
      IF nSpace == 0
         AGREPL_Out( AGUI_Color( "[/loop needs <interval> <prompt> -- e.g. " + ;
                                 "/loop 5m check CI]", AGUI_Pal( "warn" ) ) + ;
                     Chr(10) )
         RETURN NIL
      ENDIF
      cFirst := Left( cTrim, nSpace - 1 )
      cRest  := AllTrim( SubStr( cTrim, nSpace + 1 ) )
      nSec   := AGREPL_ParseInterval( cFirst )
      IF nSec <= 0
         AGREPL_Out( AGUI_Color( "[bad interval '" + cFirst + "' -- use " + ;
                                 "30s / 5m / 1h]", AGUI_Pal( "warn" ) ) + Chr(10) )
         RETURN NIL
      ENDIF
      IF Empty( cRest )
         AGREPL_Out( AGUI_Color( "[/loop needs a prompt after the interval]", ;
                                 AGUI_Pal( "warn" ) ) + Chr(10) )
         RETURN NIL
      ENDIF
      s_cLoopPrompt      := cRest
      s_nLoopIntervalSec := nSec
      s_lLoopActive      := .T.
      AGREPL_Out( AGUI_Color( "[loop armed: every " + ;
                              AGREPL_FormatInterval( nSec ) + " -> " + ;
                              cRest + " -- Esc or /loop stop to end]", ;
                              AGUI_Pal( "accent" ) ) + Chr(10) )
   ENDCASE
   RETURN NIL

// Sleeps nSec seconds in 0.2s slices while polling oPrompt for Esc.
// Returns .T. when the full interval elapsed, .F. when interrupted.
STATIC FUNCTION AGREPL_LoopSleep( nSec, oPrompt )
   LOCAL nStart := hb_MilliSeconds(), nElapsed
   DO WHILE .T.
      IF oPrompt != NIL .AND. AGPROMPT_Interrupted( oPrompt )
         oPrompt[ "interrupt" ] := NIL
         RETURN .F.
      ENDIF
      nElapsed := ( hb_MilliSeconds() - nStart ) / 1000.0
      IF nElapsed >= nSec
         EXIT
      ENDIF
      hb_idleSleep( 0.2 )
   ENDDO
   RETURN .T.

// Runs the /loop auto-rerun: after the user turn that armed the loop
// finishes, sleep the interval (interruptible by Esc) then issue the
// stored prompt as the next turn. Repeats until /loop stop or Esc.
STATIC FUNCTION AGREPL_RunLoopLoop( aMsgs, oClient, oReg, cModel, bGate, nMaxIter, oPrompt )
   LOCAL aTurn, hTurn, hRes
   DO WHILE s_lLoopActive
      AGREPL_Out( AGUI_Color( "[loop: sleeping " + ;
                              AGREPL_FormatInterval( s_nLoopIntervalSec ) + ;
                              " -- Esc to stop]", ;
                              AGUI_Pal( "dim" ) ) + Chr(10) )
      IF !AGREPL_LoopSleep( s_nLoopIntervalSec, oPrompt )
         s_lLoopActive := .F.
         AGREPL_Out( AGUI_Color( "[loop stopped by Esc -- " + ;
                                 "/loop status to inspect, " + ;
                                 "/loop <int> <prompt> to rearm]", ;
                                 AGUI_Pal( "dim" ) ) + Chr(10) )
         EXIT
      ENDIF
      IF !s_lLoopActive   // /loop stop may have fired during sleep
         EXIT
      ENDIF
      AGREPL_Out( AGREPL_UserCard( s_cLoopPrompt ) )
      AGREPL_PushRewind( aMsgs, s_cLoopPrompt )
      AGREPL_ApplyAutoSkills( s_cLoopPrompt, aMsgs, oPrompt )
      aTurn := AClone( aMsgs )
      AAdd( aTurn, { "role" => "user", "content" => s_cLoopPrompt } )
      hTurn := AGREPL_RunTurn( oClient, oReg, cModel, bGate, nMaxIter, ;
                               aTurn, oPrompt )
      hRes := hTurn[ "result" ]
      IF !hRes[ "success" ]
         AGREPL_Out( AGUI_Color( "[loop stopped: " + ;
                                 hb_CStr( hb_HGetDef( hRes, "error_type", "?" ) ) + ;
                                 "]", "33" ) + Chr(10) )
         s_lLoopActive := .F.
         EXIT
      ENDIF
      aMsgs := hRes[ "messages" ]
      IF hRes[ "stop_reason" ] == "interrupted"
         s_lLoopActive := .F.
         AGREPL_Out( AGUI_Color( "[loop stopped by Esc]", ;
                                 AGUI_Pal( "dim" ) ) + Chr(10) )
         EXIT
      ENDIF
   ENDDO
   RETURN NIL

// Pushes the current conversation state onto the rewind stack just
// before a user-issued turn modifies aMsgs. cPreview is a short label
// (the user's prompt, summarised) shown in /rewind output. The stack
// is capped at AG_REWIND_MAX -- when full, the oldest entry falls off
// the bottom so memory stays bounded.
FUNCTION AGREPL_PushRewind( aMsgs, cPreview )
   LOCAL hSnap
   IF ValType( aMsgs ) != "A"
      RETURN NIL
   ENDIF
   hSnap := { ;
      "msgs"        => AClone( aMsgs ), ;
      "preview"     => AGUI_Summarize( hb_CStr( cPreview ), 60 ), ;
      "goal"        => s_cGoal, ;
      "goal_loop"   => s_lGoalLooping, ;
      "loop_prompt" => s_cLoopPrompt, ;
      "loop_int"    => s_nLoopIntervalSec, ;
      "loop_active" => s_lLoopActive, ;
      "plan_mode"   => s_lPlanMode, ;
      "plan_steps"  => AClone( s_aPlanSteps ), ;
      "lean_mode"   => s_lLeanMode, ;
      "usage"       => hb_HClone( s_hSessionUsage ), ;
      "compact_nudged" => s_lCompactNudged, ;
      "ctx_override"   => s_nContextOverride }
   AAdd( s_aRewindStack, hSnap )
   DO WHILE Len( s_aRewindStack ) > AG_REWIND_MAX
      hb_ADel( s_aRewindStack, 1, .T. )
   ENDDO
   RETURN NIL

// Pops nCount snapshots off the rewind stack and restores the one at the
// new top. Returns the restored aMsgs, or the input array unchanged when
// the stack is empty / nCount exceeds the depth.
FUNCTION AGREPL_PopRewind( aMsgs, nCount )
   LOCAL hSnap, nPops, i
   IF Empty( s_aRewindStack )
      AGREPL_Out( AGUI_Color( "[no turns to rewind]", ;
                              AGUI_Pal( "dim" ) ) + Chr(10) )
      RETURN aMsgs
   ENDIF
   IF ValType( nCount ) != "N" .OR. nCount < 1
      nCount := 1
   ENDIF
   nPops := Min( nCount, Len( s_aRewindStack ) )
   // discard nPops-1 entries on top, then restore the one underneath
   FOR i := 1 TO nPops - 1
      hb_ADel( s_aRewindStack, Len( s_aRewindStack ), .T. )
   NEXT
   hSnap := ATail( s_aRewindStack )
   hb_ADel( s_aRewindStack, Len( s_aRewindStack ), .T. )
   aMsgs            := AClone( hSnap[ "msgs" ] )
   s_cGoal          := hSnap[ "goal" ]
   s_lGoalLooping   := hSnap[ "goal_loop" ]
   s_cLoopPrompt    := hSnap[ "loop_prompt" ]
   s_nLoopIntervalSec := hSnap[ "loop_int" ]
   s_lLoopActive    := hSnap[ "loop_active" ]
   s_lPlanMode      := hSnap[ "plan_mode" ]
   s_aPlanSteps     := hb_HGetDef( hSnap, "plan_steps", {} )
   s_lLeanMode      := hSnap[ "lean_mode" ]
   s_hSessionUsage  := hb_HClone( hSnap[ "usage" ] )
   s_lCompactNudged := hSnap[ "compact_nudged" ]
   s_nContextOverride := hb_HGetDef( hSnap, "ctx_override", 0 )
   AGREPL_Out( AGUI_Color( "[rewound " + LTrim( Str( nPops ) ) + " turn" + ;
                           iif( nPops == 1, "", "s" ) + " -- restored before: " + ;
                           hSnap[ "preview" ] + "]", ;
                           AGUI_Pal( "accent" ) ) + Chr(10) )
   RETURN aMsgs

// Implements /rewind. Bare /rewind pops one turn; /rewind <N> pops N.
// Also invoked by a double-tap of Esc at the idle prompt (the prompt
// poll converts the second Esc into a "rewind" interrupt kind, which
// AGREPL_PromptIdle returns as the literal "/rewind").
STATIC FUNCTION AGREPL_HandleRewind( cArg, aMsgs )
   LOCAL cTrim := AllTrim( hb_CStr( cArg ) )
   LOCAL nCount := 1
   IF !Empty( cTrim )
      IF AGREPL_IsAllDigits( cTrim )
         nCount := Val( cTrim )
         IF nCount < 1 ; nCount := 1 ; ENDIF
      ELSE
         AGREPL_Out( AGUI_Color( "[/rewind takes a count -- e.g. /rewind 3]", ;
                                 AGUI_Pal( "warn" ) ) + Chr(10) )
         RETURN aMsgs
      ENDIF
   ENDIF
   RETURN AGREPL_PopRewind( aMsgs, nCount )

// Implements /lean — toggles lean-mode. While on, AGUI_SystemPrompt returns
// a minimal version of the prompt (no skills section, no CC.md, no
// memory.md, no narration block), and a [lean] badge appears in the status
// line. The trimmed prompt itself instructs the model to be ultra-terse,
// so no extra skill body needs to be injected.
STATIC FUNCTION AGREPL_ToggleLean( cArg, aMsgs, oPrompt )
   LOCAL cMode := Lower( AllTrim( hb_CStr( cArg ) ) )
   DO CASE
   CASE cMode == "off"
      IF !s_lLeanMode
         AGREPL_Out( AGUI_Color( "[lean mode already off]", ;
                                 AGUI_Pal( "dim" ) ) + Chr(10) )
         RETURN NIL
      ENDIF
      s_lLeanMode := .F.
      // refresh the system message so the next turn sees the full prompt
      IF Len( aMsgs ) > 0 .AND. aMsgs[ 1 ][ "role" ] == "system"
         aMsgs[ 1 ][ "content" ] := AGUI_SystemPrompt()
      ENDIF
      AGREPL_Out( AGUI_Color( "[lean mode OFF]", AGUI_Pal( "dim" ) ) + Chr(10) )
   CASE Empty( cMode ) .OR. cMode == "on"
      IF s_lLeanMode
         AGREPL_Out( AGUI_Color( "[lean mode already on]", ;
                                 AGUI_Pal( "dim" ) ) + Chr(10) )
         RETURN NIL
      ENDIF
      s_lLeanMode := .T.
      // refresh the system message so the next turn sees the trimmed prompt
      IF Len( aMsgs ) > 0 .AND. aMsgs[ 1 ][ "role" ] == "system"
         aMsgs[ 1 ][ "content" ] := AGUI_SystemPrompt()
      ENDIF
      AGREPL_Out( AGUI_Color( "[lean mode ON - system prompt trimmed. " + ;
                              "/lean off to revert]", ;
                              AGUI_Pal( "accent" ) ) + Chr(10) )
   OTHERWISE
      AGREPL_Out( AGUI_Color( "Usage: /lean [on|off]", ;
                              AGUI_Pal( "error" ) ) + Chr(10) )
      RETURN NIL
   ENDCASE
   IF oPrompt != NIL
      AGPROMPT_Redraw( oPrompt )
   ENDIF
   RETURN NIL

// Implements /plan, the web Agents action-plan system (console flavour):
//
//   /plan <tarea>     -> ask the model for 3-6 JSON steps, show the plan card
//   /plan             -> show the current plan, or generate one from the
//                        goal / recent conversation when none exists
//   /plan add <t>     -> append a pending step
//   /plan del <n>     -> delete step n
//   /plan done <n>    -> toggle step n done/pending
//   /plan edit <n> <t> -> retitle step n
//   /plan clear       -> drop the plan
//   /run              -> execute the plan one step per agent turn
//
// The pre-existing plan MODE (lock write/edit/shell while the model writes an
// implementation plan) moved to "/plan mode"; /plan accept and /plan cancel
// keep working as before. Returns the free-text prompt the caller should run
// as a user message ("" when nothing should be dispatched).
STATIC FUNCTION AGREPL_HandlePlan( cArg, aMsgs, oPrompt, oClient, cModel )
   LOCAL cTrim := AllTrim( hb_CStr( cArg ) )
   LOCAL cMode := Lower( cTrim )
   LOCAL cSub, cRest, nSp, nStep
   nSp   := At( " ", cTrim )
   cSub  := Lower( iif( nSp > 0, Left( cTrim, nSp - 1 ), cTrim ) )
   cRest := iif( nSp > 0, AllTrim( SubStr( cTrim, nSp + 1 ) ), "" )
   DO CASE
   CASE cMode == "off" .OR. cMode == "cancel"
      s_lPlanMode := .F.
      AAdd( aMsgs, { "role" => "system", ;
                     "content" => "User cancelled /plan. Drop the plan and " + ;
                        "wait for the next instruction without modifying " + ;
                        "the codebase." } )
      AGREPL_Out( AGUI_Color( "[plan mode cancelled]", ;
                              AGUI_Pal( "dim" ) ) + Chr(10) )
      IF oPrompt != NIL
         AGPROMPT_Redraw( oPrompt )
      ENDIF
   CASE cMode == "accept" .OR. cMode == "go" .OR. cMode == "approve"
      s_lPlanMode := .F.
      AAdd( aMsgs, { "role" => "system", ;
                     "content" => "User approved the plan with /plan accept. " + ;
                        "Proceed with the implementation step by step, " + ;
                        "verifying each step before moving to the next." } )
      AGREPL_Out( AGUI_Color( "[plan accepted - proceeding with implementation]", ;
                              AGUI_Pal( "accent" ) ) + Chr(10) )
      IF oPrompt != NIL
         AGPROMPT_Redraw( oPrompt )
      ENDIF
   CASE cSub == "mode"
      // legacy plan mode: lock mutating tools until /plan accept
      IF !s_lPlanMode
         s_lPlanMode := .T.
         AGREPL_ActivateSkill( "writing-plans", aMsgs, oPrompt )
         AGREPL_Out( AGUI_Color( "[plan mode ON - write/edit/shell are " + ;
                                 "locked until /plan accept]", ;
                                 AGUI_Pal( "accent" ) ) + Chr(10) )
         IF oPrompt != NIL
            AGPROMPT_Redraw( oPrompt )
         ENDIF
      ELSE
         AGREPL_Out( AGUI_Color( "[plan mode already active]", ;
                                 AGUI_Pal( "dim" ) ) + Chr(10) )
      ENDIF
      // optional trailing text runs as the first planning prompt
      RETURN cRest
   CASE cMode == "clear"
      s_aPlanSteps := {}
      AGREPL_Out( AGUI_Color( "[plan dropped]", AGUI_Pal( "dim" ) ) + Chr(10) )
   CASE cSub == "add" .AND. !Empty( cRest )
      AAdd( s_aPlanSteps, { "title" => cRest, "state" => "pending" } )
      AGREPL_PlanCard()
   CASE ( cSub == "del" .OR. cSub == "done" .OR. cSub == "edit" ) .AND. ;
        !Empty( cRest )
      nStep := Val( cRest )
      IF nStep < 1 .OR. nStep > Len( s_aPlanSteps )
         AGREPL_Out( AGUI_Color( "[paso fuera de rango: " + cRest + "]", ;
                                 "33" ) + Chr(10) )
      ELSE
         DO CASE
         CASE cSub == "del"
            hb_ADel( s_aPlanSteps, nStep, .T. )
         CASE cSub == "done"
            s_aPlanSteps[ nStep ][ "state" ] := ;
               iif( s_aPlanSteps[ nStep ][ "state" ] == "done", "pending", "done" )
         CASE cSub == "edit"
            // /plan edit <n> <new title>
            cRest := AllTrim( SubStr( cRest, At( " ", cRest + " " ) ) )
            IF !Empty( cRest )
               s_aPlanSteps[ nStep ][ "title" ] := cRest
            ENDIF
         ENDCASE
         AGREPL_PlanCard()
      ENDIF
   CASE Empty( cTrim ) .AND. !Empty( s_aPlanSteps )
      AGREPL_PlanCard()   // show the current plan
   OTHERWISE
      // /plan <tarea> (or bare /plan with no stored plan): generate
      AGREPL_PlanGenerate( oClient, cModel, cTrim, aMsgs )
   ENDCASE
   RETURN ""

// Asks the model (plain completion, no tools) for a 3-6 step plan and stores
// it in s_aPlanSteps. With no task, plans from the goal or the recent
// conversation, like the web version.
STATIC FUNCTION AGREPL_PlanGenerate( oClient, cModel, cTask, aMsgs )
   LOCAL aPMsgs, hRes, cContent, nStart, nEnd, xJson, hStep, cUser, i, hMsg
   cUser := cTask
   IF Empty( cUser )
      IF !Empty( s_cGoal )
         cUser := "Objetivo: " + s_cGoal
      ELSE
         cUser := ""
         FOR i := Max( 2, Len( aMsgs ) - 6 ) TO Len( aMsgs )
            hMsg := aMsgs[ i ]
            IF ( hMsg[ "role" ] == "user" .OR. hMsg[ "role" ] == "assistant" ) .AND. ;
               ValType( hb_HGetDef( hMsg, "content", NIL ) ) == "C" .AND. ;
               !Empty( hMsg[ "content" ] )
               cUser += hMsg[ "role" ] + ": " + ;
                        Left( hMsg[ "content" ], 300 ) + Chr(10)
            ENDIF
         NEXT
         IF Empty( cUser )
            cUser := "Propon un plan corto y util para trabajar con los " + ;
                     "ficheros de la carpeta actual (" + hb_cwd() + "): " + ;
                     "revisar, mejorar, organizar, documentar o generar codigo."
         ELSE
            cUser := "Conversacion reciente:" + Chr(10) + cUser + Chr(10) + ;
                     "Propon un plan corto y util que continue este trabajo."
         ENDIF
      ENDIF
   ENDIF
   AGREPL_Out( AGUI_Color( "[generando plan...]", AGUI_Pal( "dim" ) ) + Chr(10) )
   aPMsgs := { { "role" => "system", "content" => ;
                 'You are a planner. Break the request into 3 to 6 short ' + ;
                 'concrete steps. Reply ONLY with compact JSON: ' + ;
                 '{"steps":[{"title":"...","state":"active|pending"}]}. ' + ;
                 'First step active, the rest pending. No prose. ' + ;
                 'Answer in the language of the request.' }, ;
               { "role" => "user", "content" => cUser } }
   hRes := AG_ChatCompletion( oClient, aPMsgs, { "model" => cModel }, NIL )
   IF !hRes[ "success" ]
      AGREPL_Out( AGUI_Color( "!! error: no se pudo generar el plan: " + ;
                  hb_CStr( hRes[ "message" ] ), "31" ) + Chr(10) )
      RETURN NIL
   ENDIF
   cContent := hb_CStr( hRes[ "content" ] )
   nStart   := At( "{", cContent )
   nEnd     := RAt( "}", cContent )
   xJson    := iif( nStart > 0 .AND. nEnd > nStart, ;
                    hb_jsonDecode( SubStr( cContent, nStart, ;
                                           nEnd - nStart + 1 ) ), NIL )
   s_aPlanSteps := {}
   IF ValType( xJson ) == "H" .AND. hb_HHasKey( xJson, "steps" ) .AND. ;
      ValType( xJson[ "steps" ] ) == "A"
      FOR EACH hStep IN xJson[ "steps" ]
         IF ValType( hStep ) == "H" .AND. hb_HHasKey( hStep, "title" )
            AAdd( s_aPlanSteps, { "title" => hb_CStr( hStep[ "title" ] ), ;
                  "state" => iif( hb_HGetDef( hStep, "state", "" ) == "active", ;
                                  "active", "pending" ) } )
         ENDIF
      NEXT
   ENDIF
   IF Empty( s_aPlanSteps )
      AGREPL_Out( AGUI_Color( "[el modelo no devolvio un plan valido - " + ;
                  "reintenta /plan]", "33" ) + Chr(10) )
   ELSE
      AGREPL_PlanCard()
   ENDIF
   RETURN NIL

// Renders the plan as a slate card (GUI parity): ✓ done / ● active / ○ pending.
STATIC FUNCTION AGREPL_PlanCard()
   LOCAL nW := Min( AGREPL_Cols() - 2, 100 )
   LOCAL i, hStep, nDone := 0, cRow, cHead
   IF Empty( s_aPlanSteps )
      AGREPL_Out( AGUI_Color( "[no hay plan - usa /plan <tarea>]", ;
                              AGUI_Pal( "dim" ) ) + Chr(10) )
      RETURN NIL
   ENDIF
   AEval( s_aPlanSteps, {| h | iif( h[ "state" ] == "done", nDone++, NIL ) } )
   cHead := AGUI_Color( "Plan de Accion", "1" ) + "   " + ;
            AGUI_Color( LTrim( Str( nDone ) ) + " / " + ;
                        LTrim( Str( Len( s_aPlanSteps ) ) ) + " completado", ;
                        "38;2;120;160;230" )
   AGREPL_Out( Chr(10) + AGUI_CardLine( cHead, "card", nW ) + Chr(10) )
   AGREPL_Out( AGUI_CardLine( "", "card", nW ) + Chr(10) )
   FOR i := 1 TO Len( s_aPlanSteps )
      hStep := s_aPlanSteps[ i ]
      DO CASE
      CASE hStep[ "state" ] == "done"
         cRow := AGUI_Color( Chr(226)+Chr(156)+Chr(147), "92" ) + " " + ;
                 AGUI_Color( LTrim( Str( i ) ) + ". " + hStep[ "title" ], "2" )
      CASE hStep[ "state" ] == "active"
         cRow := AGUI_Color( Chr(226)+Chr(151)+Chr(143), "94" ) + " " + ;
                 AGUI_Color( LTrim( Str( i ) ) + ". " + hStep[ "title" ], "1;94" )
      OTHERWISE
         cRow := AGUI_Color( Chr(226)+Chr(151)+Chr(139), "90" ) + " " + ;
                 AGUI_Color( LTrim( Str( i ) ) + ". " + hStep[ "title" ], "90" )
      ENDCASE
      AGREPL_Out( AGUI_CardLine( cRow, "card", nW ) + Chr(10) )
   NEXT
   AGREPL_Out( AGUI_CardLine( AGUI_Color( "/run ejecutar - /plan " + ;
               "add|del|done|edit <n> - /plan clear", "2" ), "card", nW ) + ;
               Chr(10) )
   RETURN NIL

// /run: executes the plan one step per agent turn. Each step gets the goal +
// the full plan as context and runs ONLY that step; the run pauses when the
// agent ends a step asking the user something (web parity).
STATIC FUNCTION AGREPL_RunPlan( aMsgs, oClient, oReg, cModel, bGate, ;
                                nMaxIter, oPrompt )
   LOCAL n, i, cPlanTxt, cMsg, aTurn, hTurn, hRes, cTail
   IF Empty( s_aPlanSteps )
      AGREPL_Out( AGUI_Color( "[no hay plan - usa /plan primero]", "33" ) + ;
                  Chr(10) )
      RETURN NIL
   ENDIF
   DO WHILE .T.
      n := 0
      FOR i := 1 TO Len( s_aPlanSteps )
         IF s_aPlanSteps[ i ][ "state" ] != "done"
            n := i
            EXIT
         ENDIF
      NEXT
      IF n == 0
         AGREPL_PlanCard()
         AGREPL_Out( AGUI_Color( "[" + Chr(226)+Chr(156)+Chr(147) + ;
                     " plan completado]", "92" ) + Chr(10) )
         EXIT
      ENDIF
      FOR i := 1 TO Len( s_aPlanSteps )
         s_aPlanSteps[ i ][ "state" ] := ;
            iif( i < n, "done", iif( i == n, "active", "pending" ) )
      NEXT
      AGREPL_PlanCard()
      AGREPL_Out( AGUI_Color( "[paso " + LTrim( Str( n ) ) + "/" + ;
                  LTrim( Str( Len( s_aPlanSteps ) ) ) + ": " + ;
                  s_aPlanSteps[ n ][ "title" ] + "]", ;
                  AGUI_Pal( "accent" ) ) + Chr(10) )
      cPlanTxt := ""
      FOR i := 1 TO Len( s_aPlanSteps )
         cPlanTxt += LTrim( Str( i ) ) + ". " + ;
                     s_aPlanSteps[ i ][ "title" ] + Chr(10)
      NEXT
      cMsg := iif( !Empty( s_cGoal ), "Objetivo: " + s_cGoal + Chr(10), "" ) + ;
         "Plan en curso:" + Chr(10) + cPlanTxt + Chr(10) + ;
         "Ejecuta SOLO el paso " + LTrim( Str( n ) ) + ': "' + ;
         s_aPlanSteps[ n ][ "title" ] + '". Los pasos anteriores ya estan ' + ;
         "hechos (su resultado esta en la conversacion). No preguntes salvo " + ;
         "bloqueo real."
      aTurn := AClone( aMsgs )
      AAdd( aTurn, { "role" => "user", "content" => cMsg } )
      hTurn := AGREPL_RunTurn( oClient, oReg, cModel, bGate, nMaxIter, ;
                               aTurn, oPrompt )
      hRes := hTurn[ "result" ]
      IF !hRes[ "success" ] .OR. hRes[ "stop_reason" ] == "interrupted"
         AGREPL_Out( AGUI_Color( "[plan detenido]", "33" ) + Chr(10) )
         EXIT
      ENDIF
      aMsgs := hRes[ "messages" ]
      cTail := Right( hb_CStr( hRes[ "content" ] ), 200 )
      IF "?" $ cTail .OR. hb_UTF8Chr( 0xBF ) $ cTail
         AGREPL_Out( AGUI_Color( "[plan pausado en el paso " + ;
                     LTrim( Str( n ) ) + ": el agente espera tu respuesta. " + ;
                     "Contesta y usa /run para continuar]", "33" ) + Chr(10) )
         EXIT
      ENDIF
      s_aPlanSteps[ n ][ "state" ] := "done"
   ENDDO
   RETURN NIL

// Manually activates a skill by name (used by /caveman and any future
// /skill <name> command). Loads the body, injects it as a system note in
// aMsgs, prints a notice, and repaints the box so the status line refreshes.
// Reports an error in the scroll when the skill is unknown.
STATIC FUNCTION AGREPL_ActivateSkill( cName, aMsgs, oPrompt )
   LOCAL cBody, aActive
   cBody := AGSKILL_Load( cName )
   IF cBody == NIL
      AGREPL_Out( AGUI_Color( "Skill '" + hb_CStr( cName ) + ;
                              "' not found in .agents/skills/", ;
                              AGUI_Pal( "error" ) ) + Chr(10) )
      RETURN NIL
   ENDIF
   aActive := AGSKILL_Active()
   IF AScan( aActive, {| c | c == hb_CStr( cName ) } ) > 0
      AGREPL_Out( AGUI_Color( "[skill '" + cName + "' already active]", ;
                              AGUI_Pal( "dim" ) ) + Chr(10) )
      RETURN NIL
   ENDIF
   AGSKILL_Activate( cName )
   AAdd( aMsgs, { "role" => "system", ;
                  "content" => "Skill '" + cName + "' activated by /" + ;
                     cName + " command. Follow it as guidance:" + ;
                     Chr(10) + Chr(10) + cBody } )
   AGREPL_Out( AGUI_Color( "[skill '" + cName + "' activated]", ;
                           AGUI_Pal( "accent" ) ) + Chr(10) )
   IF oPrompt != NIL
      AGPROMPT_Redraw( oPrompt )
   ENDIF
   RETURN NIL

// Detects which project skills' triggers match the user message, activates
// them, injects their body into aMsgs as a system note, prints a notice in
// the scroll, and repaints the box so the status line shows the new tags.
// No-op when nothing matches; cheap to call before every turn.
STATIC FUNCTION AGREPL_ApplyAutoSkills( cMsg, aMsgs, oPrompt )
   LOCAL aNew, cName, cBody
   aNew := AGSKILL_AutoActivate( cMsg )
   IF Empty( aNew )
      RETURN NIL
   ENDIF
   FOR EACH cName IN aNew
      cBody := AGSKILL_Load( cName )
      IF cBody != NIL
         AAdd( aMsgs, { "role" => "system", ;
                        "content" => "Skill '" + cName + "' auto-activated " + ;
                           "for this request — its description matched. " + ;
                           "Follow it as guidance for the turn:" + ;
                           Chr(10) + Chr(10) + cBody } )
         AGREPL_Out( AGUI_Color( "[skill '" + cName + "' auto-activated]", ;
                                 AGUI_Pal( "accent" ) ) + Chr(10) )
      ENDIF
   NEXT
   IF oPrompt != NIL
      AGPROMPT_Redraw( oPrompt )
   ENDIF
   RETURN NIL

// Idles on the persistent box until the user submits a line (Enter on a
// non-empty buffer, or a /btw line). Returns the submitted text, or loops
// on a bare Esc.
STATIC FUNCTION AGREPL_PromptIdle( oPrompt )
   LOCAL cAction, cText
   DO WHILE .T.
      cAction := AGPROMPT_Poll( oPrompt )
      IF cAction == "queued"
         RETURN AGPROMPT_Dequeue( oPrompt )
      ELSEIF cAction == "interrupt"
         IF oPrompt[ "interrupt" ][ "kind" ] == "btw" .AND. ;
            !Empty( oPrompt[ "interrupt" ][ "text" ] )
            cText := oPrompt[ "interrupt" ][ "text" ]
            oPrompt[ "interrupt" ] := NIL
            RETURN cText
         ENDIF
         // double-tap Esc at idle -> /rewind one conversation turn
         IF oPrompt[ "interrupt" ][ "kind" ] == "rewind"
            oPrompt[ "interrupt" ] := NIL
            RETURN "/rewind"
         ENDIF
         oPrompt[ "interrupt" ] := NIL
      ENDIF
      hb_IdleSleep( 0.02 )
   ENDDO
   RETURN NIL

// Wipes the terminal screen for /clear. Skipped when there is no console or
// colour/VT output is off (piped input) -- the escape bytes would be garbage.
// When the persistent box is mounted, ESC[2J also clears it, so the box and
// its scroll region are rebuilt with AGPROMPT_Activate.
STATIC FUNCTION AGREPL_ClearScreen( oPrompt )
   IF !AGCON_HasConsole() .OR. !AGUI_ColorOn()
      RETURN NIL
   ENDIF
   FWrite( hb_GetStdOut(), AGUI_ClearScreenSeq() )
   IF oPrompt != NIL
      AGPROMPT_Activate( oPrompt )
   ENDIF
   RETURN NIL

// Merges a usage hash (from one agent turn) into the session total.
STATIC FUNCTION AGREPL_AccumUsage( hTurnUsage )
   LOCAL cKey
   IF ValType( hTurnUsage ) != "H"
      RETURN NIL
   ENDIF
   FOR EACH cKey IN hb_HKeys( hTurnUsage )
      IF ValType( hTurnUsage[ cKey ] ) == "N"
         s_hSessionUsage[ cKey ] := ;
            hb_HGetDef( s_hSessionUsage, cKey, 0 ) + hTurnUsage[ cKey ]
      ENDIF
   NEXT
   RETURN NIL

// Saves the current session to a JSON file.
// cArg is the user-supplied name (empty = auto-name with timestamp).
STATIC FUNCTION AGREPL_SaveSession( aMsgs, cModel, hUsage, cSuggest, cArg )
   LOCAL cName, cPath, hPack, cJson, hSaved
   LOCAL aSessions

   IF !AGUI_EnsureSessionDir()
      AGREPL_Out( AGUI_Color( "!! error: cannot create sessions directory", "31" ) + Chr(10) )
      RETURN NIL
   ENDIF

   // determine the session name
   IF Empty( cArg )
      // auto-name: session_YYYY-MM-DD_HHMMSS
      cName := "session_" + StrTran( StrTran( DToS( Date() ), "/", "-" ), ".", "-" ) + ;
               "_" + StrTran( SubStr( Time(), 1, 8 ), ":", "" )
   ELSE
      cName := AllTrim( cArg )
      // sanitise the name: keep only safe chars
      cName := AGREPL_SanitiseName( cName )
      IF Empty( cName )
         AGREPL_Out( AGUI_Color( "!! error: invalid session name", "31" ) + Chr(10) )
         RETURN NIL
      ENDIF
   ENDIF

   cPath := AGUI_SessionPath( cName )
   hPack := { "model"    => cModel, ;
              "saved_at" => DToS( Date() ) + "T" + Time(), ;
              "usage"    => hUsage, ;
              "messages" => aMsgs, ;
              "state"    => AGREPL_StateExport(), ;
              "suggest"  => hb_CStr( cSuggest ) }
   cJson := hb_jsonEncode( hPack, .T. )  // .T. = pretty-print

   IF !hb_MemoWrit( cPath, cJson )
      AGREPL_Out( AGUI_Color( "!! error: failed to write " + cPath, "31" ) + Chr(10) )
      RETURN NIL
   ENDIF

   AGREPL_Out( AGUI_Color( "[saved: " + cName + "]", "90" ) + Chr(10) )
   RETURN NIL

// Loads a session from a JSON file.
// cArg is the session name (empty = list available sessions).
// Returns a hash { messages, model, usage } on success, or NIL on error.
STATIC FUNCTION AGREPL_LoadSession( cArg )
   LOCAL aSessions, hPack, cJson, cPath, cName

   IF Empty( cArg )
      // list available sessions
      aSessions := AGUI_SessionList()
      AGREPL_Out( AGUI_SessionListOutput( aSessions ) )
      RETURN NIL
   ENDIF

   cName := AGREPL_SanitiseName( AllTrim( cArg ) )
   IF Empty( cName )
      // maybe it's "autosave" with special chars removed - try as-is
      cName := AllTrim( cArg )
   ENDIF

   cPath := AGUI_SessionPath( cName )
   IF !hb_FileExists( cPath )
      AGREPL_Out( AGUI_Color( "!! error: session '" + cName + "' not found", "31" ) + Chr(10) )
      RETURN NIL
   ENDIF

   cJson := hb_MemoRead( cPath )
   hPack := hb_jsonDecode( cJson )
   IF ValType( hPack ) != "H" .OR. !hb_HHasKey( hPack, "messages" )
      AGREPL_Out( AGUI_Color( "!! error: invalid session file", "31" ) + Chr(10) )
      RETURN NIL
   ENDIF

   AGREPL_Out( AGUI_Color( "[loaded: " + cName + "]", "90" ) + Chr(10) )
   AGREPL_Out( AGUI_Color( "  model: " + hb_CStr( hb_HGetDef( hPack, "model", "" ) ), "90" ) + Chr(10) )
   AGREPL_Out( AGUI_Color( "  messages: " + LTrim( Str( Len( hPack[ "messages" ] ) ) ), "90" ) + Chr(10) )

   RETURN hPack

// Sanitises a session name: keeps only alphanumeric, underscores, hyphens.
STATIC FUNCTION AGREPL_SanitiseName( cName )
   LOCAL cOut := "", i, cCh
   FOR i := 1 TO Len( cName )
      cCh := SubStr( cName, i, 1 )
      IF cCh >= "A" .AND. cCh <= "Z" .OR. ;
         cCh >= "a" .AND. cCh <= "z" .OR. ;
         cCh >= "0" .AND. cCh <= "9" .OR. ;
         cCh == "_" .OR. cCh == "-"
         cOut += cCh
      ENDIF
   NEXT
   RETURN cOut

// Creates a per-turn render state: the markdown renderer, an id->tool-name
// map (to label tool results), the assistant-bullet run flag, spinner state,
// reasoning-character counter, and last-seen usage hash.
// Prints the buffered narration text (pendingText) with the assistant
// bullet prefix, then clears it. No-op when nothing is pending.
STATIC FUNCTION AGREPL_FlushPending( oRender )
   LOCAL aLines, i, nW
   IF Empty( oRender[ "pendingText" ] )
      RETURN NIL
   ENDIF
   IF !oRender[ "inText" ]
      // clear the working spinner before showing the response
      IF oRender[ "spinner" ]
         AGREPL_SpinnerClear()
         oRender[ "spinner" ] := .F.
      ENDIF
      IF AGUI_ColorOn()
         // GUI-style reply bubble: the card itself marks the response
         AGREPL_Out( Chr(10) )
      ELSE
         AGREPL_Out( Chr(10) + ;
            AGUI_Color( Chr(226)+Chr(143)+Chr(186), AGUI_Pal( "accent" ) ) + "  " )
      ENDIF
      oRender[ "inText" ] := .T.
   ENDIF
   IF AGUI_ColorOn()
      // paint the reply as a card, one tinted row per (complete) line.
      // AGMD_Feed only emits whole lines, so no partial line is repainted.
      nW := Min( AGREPL_Cols() - 2, 100 )
      aLines := hb_ATokens( StrTran( oRender[ "pendingText" ], Chr(13), "" ), ;
                            Chr(10) )
      // a trailing LF yields a final empty token: drop it (not a blank row)
      IF Len( aLines ) > 0 .AND. Empty( ATail( aLines ) )
         hb_ADel( aLines, Len( aLines ), .T. )
      ENDIF
      FOR i := 1 TO Len( aLines )
         AGREPL_Out( AGUI_CardLine( aLines[ i ], "card", nW ) + Chr(10) )
      NEXT
   ELSE
      AGREPL_Out( oRender[ "pendingText" ] )
   ENDIF
   oRender[ "pendingText" ] := ""
   RETURN NIL

// Counts the visual rows a chunk would consume when written at col 1 of
// an nCols-wide terminal: every LF adds a row, ANSI CSI sequences are
// skipped, and a run of printable bytes that exceeds nCols wraps to the
// next row. The byte count is a rough display-cell count -- UTF-8 multi-
// byte sequences over-count, but for the dynamic-box layout we only need
// "at least this many rows" so over-counting is safe (the box drops one
// or two rows further than the true content, never overlaps it).
FUNCTION AGREPL_VisualRows( cText, nCols )
   LOCAL nRows := 0, nCol := 1, i := 1, n, c
   IF ValType( cText ) != "C" .OR. Len( cText ) == 0 ; RETURN 0 ; ENDIF
   IF nCols < 20 ; nCols := 20 ; ENDIF
   n := Len( cText )
   DO WHILE i <= n
      c := SubStr( cText, i, 1 )
      DO CASE
      CASE c == Chr(27) .AND. SubStr( cText, i + 1, 1 ) == "["
         // CSI sequence ESC[...<final byte 0x40..0x7E>
         i += 2
         DO WHILE i <= n
            c := SubStr( cText, i, 1 )
            i++
            IF c >= "@" .AND. c <= "~" ; EXIT ; ENDIF
         ENDDO
      CASE c == Chr(10)
         nRows++
         nCol := 1
         i++
      CASE c == Chr(13)
         nCol := 1
         i++
      OTHERWISE
         nCol++
         IF nCol > nCols
            nRows++
            nCol := 2
         ENDIF
         i++
      ENDCASE
   ENDDO
   RETURN nRows

// Returns the current terminal column count, falling back to 100 when no
// console is available (piped input, tests). Public so tools (notably
// dispatch_agent) can render full-width rules.
FUNCTION AGREPL_Cols()
   LOCAL hSz
   IF !AGCON_HasConsole()
      RETURN 100
   ENDIF
   hSz := AGCON_Size()
   IF ValType( hSz ) == "H" .AND. hb_HHasKey( hSz, "cols" ) .AND. ;
      hSz[ "cols" ] >= 20
      RETURN hSz[ "cols" ]
   ENDIF
   RETURN 100

STATIC FUNCTION AGREPL_RenderNew()
   RETURN { "md" => AGMD_New(), "tools" => {=>}, "inText" => .F., ;
            "spinner" => .F., "spinnerFrame" => 1, ;
            "reasoningChars" => 0, "reasoningBuf" => "", ;
            "reasoningLines" => 0, ;
            "thinkHeaderDone" => .F., ;
            "thinkCornerUsed" => .F., ;  // .T. after first ⎿ line printed
            "thinkLastUpdate" => 0, ;
            "lastUsage" => {=>}, ;
            "lastFrameTime" => 0, "spinnerStartMs" => 0, ;
            "pendingText" => "" }   // narration buffered for the next tool block

// Renders one agent event into the terminal, using the render state oRender.
STATIC FUNCTION AGREPL_RenderEv( hEv, oRender )
   LOCAL cType, cId, cSpinner, nPrompt, nComp, cMsg, cThinking, cTokenPart, nNow
   IF ValType( hEv ) != "H" .OR. !hb_HHasKey( hEv, "type" )
      RETURN NIL
   ENDIF
   cType := hEv[ "type" ]
   // blink removed — static working line is simpler and more reliable
   // than VT-overwrite animation with the box prompt cursor system
   DO CASE

   CASE cType == "iteration_start"
      oRender[ "reasoningChars" ] := 0
      oRender[ "reasoningBuf" ]   := ""
      oRender[ "reasoningLines" ] := 0
      oRender[ "thinkHeaderDone" ] := .F.
      oRender[ "thinkCornerUsed" ] := .F.
      oRender[ "thinkLastUpdate" ] := 0
      oRender[ "spinnerStartMs" ] := hb_MilliSeconds()
      // start the working indicator immediately so activity is visible
      // even before the first reasoning token arrives
      IF !oRender[ "spinner" ]
         oRender[ "spinner" ] := .T.
         oRender[ "spinnerFrame" ] := 0
         // trailing newline so the next AGREPL_Out (ThinkShow, etc.)
         // starts on the line below, not on the same line
         AGREPL_Out( Chr(10) + AGUI_Color( "●", "92" ) + " Working" + ;
            AGUI_Color( Chr( 226 ) + Chr( 128 ) + Chr( 166 ), AGUI_Pal( "dim" ) ) + ;
            Chr(10) )
      ENDIF
      AGREPL_ThinkShow( oRender )

   CASE cType == "reasoning_delta"
      // accumulate reasoning text, print wrapped lines with ⎿ prefix
      // as they become complete, update the summary header in-place
      oRender[ "reasoningBuf" ]   += hb_CStr( hEv[ "text" ] )
      oRender[ "reasoningChars" ] += Len( hb_CStr( hEv[ "text" ] ) )
      AGREPL_FlushReasoningLines( oRender )
      AGREPL_ThinkShow( oRender )

   CASE cType == "text_delta"
      // flush any unfinished reasoning on the first text_delta,
      // then let the spinner keep running while text accumulates.
      // The spinner clears only when output is ready to display
      // (tool_call, tool_result, or final flush at turn end).
      IF oRender[ "reasoningBuf" ] != ""
         AGREPL_FlushReasoningTail( oRender )
      ENDIF
      oRender[ "pendingText" ] += ;
         AGMD_Feed( oRender[ "md" ], hb_CStr( hEv[ "text" ] ) )

   CASE cType == "usage"
      // store the usage hash for display after the turn
      oRender[ "lastUsage" ] := hEv[ "usage" ]

   CASE cType == "tool_call"
      // clear the working spinner before the tool block
      IF oRender[ "spinner" ]
         AGREPL_SpinnerClear()
         oRender[ "spinner" ] := .F.
      ENDIF
      // flush reasoning (only if buffer still has content)
      IF oRender[ "reasoningBuf" ] != ""
         AGREPL_FlushReasoningTail( oRender )
      ENDIF
      IF hb_HHasKey( hEv, "id" )
         oRender[ "tools" ][ hb_CStr( hEv[ "id" ] ) ] := hb_CStr( hEv[ "name" ] )
      ENDIF
      IF Lower( hb_CStr( hEv[ "name" ] ) ) == "ask_user" .OR. ;
         Lower( hb_CStr( hEv[ "name" ] ) ) == "propose_agents"
         AGMD_Flush( oRender[ "md" ] )
      ELSE
         // bullet line: ● Running <name>… (white, active) on the faint
         // actions-panel tint (web "acciones" panel parity)
         AGREPL_Out( Chr(10) + AGREPL_ToolCard( AGUI_Color( "●", "97" ) + ;
            " Running " + hb_CStr( hEv[ "name" ] ) + ;
            AGUI_Color( Chr( 226 ) + Chr( 128 ) + Chr( 166 ), AGUI_Pal( "dim" ) ) ) )
         // tool content below (command + explanation, no separator)
         AGREPL_Out( AGREPL_ToolCard( AGUI_ToolContentBlock( hEv[ "arguments" ], ;
            oRender[ "pendingText" ] + AGMD_Flush( oRender[ "md" ] ), ;
            AGREPL_Cols() ) ) )
      ENDIF
      oRender[ "pendingText" ] := ""
      oRender[ "inText" ] := .F.

   CASE cType == "tool_result"
      AGREPL_FlushPending( oRender )
      oRender[ "inText" ] := .F.
      cId := hb_CStr( hb_HGetDef( hEv, "id", "" ) )
      // completed line: ✓ <name> <summary> (green check, web parity)
      AGREPL_Out( AGREPL_ToolCard( AGUI_Color( Chr(226)+Chr(156)+Chr(147), "92" ) + " " + ;
         hb_HGetDef( oRender[ "tools" ], cId, "" ) + " " + ;
         AGUI_Color( AGUI_Summarize( hb_CStr( hEv[ "content" ] ), 60 ), ;
                     AGUI_Pal( "dim" ) ) ) )
      AGREPL_Out( AGREPL_ToolCard( AGUI_ResultSummary( ;
         hb_HGetDef( oRender[ "tools" ], cId, "" ), ;
         hb_CStr( hEv[ "content" ] ) ) ) )

   OTHERWISE
      AGREPL_FlushPending( oRender )
      oRender[ "inText" ] := .F.
      AGREPL_Out( AGUI_RenderEvent( hEv ) )

   ENDCASE
   RETURN NIL

// Returns the 1-based index of the first "user" role message in the
// array, or 0 when none is found. Used to extract the original task
// for goal injection.
STATIC FUNCTION AGREPL_FirstUserMsg( aMsgs )
   LOCAL i
   FOR i := 1 TO Len( aMsgs )
      IF ValType( aMsgs[ i ] ) == "H" .AND. ;
         hb_HGetDef( aMsgs[ i ], "role", "" ) == "user"
         RETURN i
      ENDIF
   NEXT
   RETURN 0

// ── Thinking display helpers ─────────────────────────────────────────

// Draws the thinking summary line once per turn:
//   ● Thinking for Ns, <first reasoning words>…
// Printed with a trailing newline so reasoning lines land below it.
// Subsequent calls are no-ops — the header stays as first printed.
STATIC FUNCTION AGREPL_ThinkShow( oRender )
   LOCAL cMsg
   IF oRender[ "thinkHeaderDone" ]
      RETURN NIL
   ENDIF
   oRender[ "thinkHeaderDone" ] := .T.
   cMsg := AGUI_Color( "●", "97" ) + " Thinking" + ;
           AGUI_Color( Chr( 226 ) + Chr( 128 ) + Chr( 166 ), ;
                        AGUI_Pal( "dim" ) )   // … (ellipsis)
   AGREPL_Out( cMsg + Chr(10) )
   RETURN NIL

// Prints the trailing partial reasoning line (not yet terminated by \n)
// as a final indented line, then reprints the summary header with a green
// bullet to signal that thinking completed. Called when thinking
// transitions to visible output (text_delta or tool_call).
STATIC FUNCTION AGREPL_FlushReasoningTail( oRender )
   LOCAL cTail := AGREPL_ThinkPending( oRender )
   LOCAL cPrefix
   IF !Empty( cTail )
      IF !oRender[ "thinkCornerUsed" ]
         cPrefix := "  " + Chr( 226 ) + Chr( 142 ) + Chr( 191 ) + "  "
         oRender[ "thinkCornerUsed" ] := .T.
      ELSE
         cPrefix := "     "
      ENDIF
      AGREPL_Out( AGREPL_ThinkLine( cPrefix + cTail ) + Chr(10) )
   ENDIF
   // Reprint the summary with a green bullet to mark thinking as done.
   // The working indicator is already running from iteration_start.
   AGREPL_ThinkDone( oRender )
   oRender[ "reasoningBuf" ]   := ""
   oRender[ "reasoningLines" ] := 0
   RETURN NIL

// Reprints the thinking summary line with a green bullet (completed).
STATIC FUNCTION AGREPL_ThinkDone( oRender )
   LOCAL nNow := hb_MilliSeconds()
   LOCAL nElapsed, cTime, cMsg
   IF oRender[ "reasoningChars" ] == 0
      RETURN NIL   // never had any reasoning — nothing to mark as done
   ENDIF
   IF oRender[ "thinkHeaderDone" ] .AND. oRender[ "reasoningBuf" ] == ""
      RETURN NIL
   ENDIF
   nElapsed := Int( ( nNow - oRender[ "spinnerStartMs" ] ) / 1000 )
   cTime := iif( nElapsed == 0, "", ;
             " for " + iif( nElapsed < 60, LTrim( Str( nElapsed ) ) + "s", ;
             LTrim( Str( Int( nElapsed / 60 ) ) ) + "m " + ;
             LTrim( Str( nElapsed % 60 ) ) + "s" ) )
   cMsg := AGUI_Color( "●", "92" ) + " Thinking" + cTime
   cMsg += AGUI_Color( Chr( 226 ) + Chr( 128 ) + Chr( 166 ), ;
                        AGUI_Pal( "dim" ) )   // … (ellipsis)
   AGREPL_Out( cMsg + Chr(10) )
   RETURN NIL

// Returns the trailing unprinted portion of the reasoning buffer
// (everything after the last newline). Used for the partial line at
// the end of thinking.
STATIC FUNCTION AGREPL_ThinkPending( oRender )
   LOCAL cBuf := oRender[ "reasoningBuf" ]
   LOCAL nPos := hb_RAt( Chr(10), cBuf )
   LOCAL cTail
   IF nPos > 0
      cTail := SubStr( cBuf, nPos + 1 )
   ELSE
      cTail := cBuf
   ENDIF
   cTail := StrTran( cTail, Chr(13), "" )
   RETURN cTail

// Prints complete reasoning lines accumulated since the last flush. Each
// line is output dimmed with a "  ⎿  " prefix (the ⎿ glyph is U+23BF).
// Lines are wrapped at terminal width so the full text is visible without
// horizontal scrolling.
STATIC FUNCTION AGREPL_FlushReasoningLines( oRender )
   LOCAL cBuf := oRender[ "reasoningBuf" ]
   LOCAL nPrinted := oRender[ "reasoningLines" ]
   LOCAL nTotal, nStart, nPos, cLine, nLine
   LOCAL nWrap := Min( AGREPL_Cols(), 102 ) - 8   // card width cap + inner padding
   // Count newlines (complete segments)
   nTotal := 0 ; nStart := 1
   DO WHILE ( nPos := hb_At( Chr(10), cBuf, nStart ) ) > 0
      nTotal++ ; nStart := nPos + 1
   ENDDO
   IF nTotal <= nPrinted .AND. Empty( AGREPL_ThinkPending( oRender ) )
      RETURN NIL
   ENDIF
   // Print each new complete segment, word-wrapped
   nStart := 1 ; nLine := 0
   DO WHILE ( nPos := hb_At( Chr(10), cBuf, nStart ) ) > 0
      nLine++
      IF nLine > nPrinted
         cLine := SubStr( cBuf, nStart, nPos - nStart )
         cLine := StrTran( cLine, Chr(13), "" )
         AGREPL_ThinkPrintWrapped( cLine, nWrap, oRender )
      ENDIF
      nStart := nPos + 1
   ENDDO
   oRender[ "reasoningLines" ] := nTotal
   RETURN NIL

// Prints a single reasoning line, word-wrapped to nWrap chars per visual
// line. Each visual line gets the "  ⎿  " dimmed prefix.
STATIC FUNCTION AGREPL_ThinkPrintWrapped( cText, nWrap, oRender )
   LOCAL cPFirst := "  " + Chr( 226 ) + Chr( 142 ) + Chr( 191 ) + "  "
   LOCAL cPCont  := "     "   // 5 spaces to align with text after first prefix
   LOCAL cPrefix, cLine, nLen, nSpace
   IF nWrap < 20 ; nWrap := 20 ; ENDIF
   IF Empty( cText )
      RETURN NIL
   ENDIF
   // first reasoning line of the turn gets the corner glyph;
   // all subsequent lines (including wraps) use plain spaces
   IF !oRender[ "thinkCornerUsed" ]
      cPrefix := cPFirst
      oRender[ "thinkCornerUsed" ] := .T.
   ELSE
      cPrefix := cPCont
   ENDIF
   DO WHILE .T.
      cText := AllTrim( cText )
      nLen := hb_BLen( cText )
      IF nLen <= nWrap
         AGREPL_Out( AGREPL_ThinkLine( cPrefix + cText ) + Chr(10) )
         RETURN NIL
      ENDIF
      cLine := hb_BLeft( cText, nWrap )
      nSpace := hb_RAt( " ", cLine )
      IF nSpace < 20
         cLine := hb_BLeft( cText, nWrap )
         cText := hb_BSubStr( cText, nWrap + 1 )
      ELSE
         cLine := hb_BLeft( cText, nSpace - 1 )
         cText := hb_BSubStr( cText, nSpace + 1 )
      ENDIF
      AGREPL_Out( AGREPL_ThinkLine( cPrefix + cLine ) + Chr(10) )
      cPrefix := cPCont   // continuation lines use plain spaces
   ENDDO
   RETURN NIL

// /demo -- showcase of the card UI with sample content, like the web Agents
// demo button: goal, plan, thinking, tool actions, diff, reply, error,
// permit, cost, compact and context cards, no API key required. Session
// state (goal / plan) is saved and restored around the show.
STATIC FUNCTION AGREPL_Demo()
   LOCAL nW := Min( AGREPL_Cols() - 2, 100 )
   LOCAL aOldPlan := s_aPlanSteps, cOldGoal := s_cGoal, lOldLoop := s_lGoalLooping
   LOCAL hUsage := { "prompt_tokens" => 125430, "completion_tokens" => 8205, ;
                     "prompt_cache_hit_tokens" => 98000 }
   LOCAL cCorner := "  " + Chr(226)+Chr(142)+Chr(191) + "  "
   LOCAL cCheck  := Chr(226)+Chr(156)+Chr(147)
   AGREPL_Out( Chr(10) + AGUI_Color( "[" + Chr(226)+Chr(150)+Chr(182) + ;
      " Demo (simulada): cards de muestra - sin API]", ;
      AGUI_Pal( "accent" ) ) + Chr(10) + Chr(10) )
   hb_idleSleep( 0.35 )
   // goal card
   AGREPL_Out( AGREPL_UserCard( "/goal" ) )
   s_cGoal := "Mostrar las capacidades de Agents: planes, cards, diffs, " + ;
              "coste y compactado."
   s_lGoalLooping := .F.
   AGREPL_GoalCard()
   hb_idleSleep( 0.35 )
   // plan card
   AGREPL_Out( AGREPL_UserCard( "/plan" ) )
   s_aPlanSteps := { ;
      { "title" => "Crear bienvenida.md", "state" => "done" }, ;
      { "title" => "Editar el fichero y mostrar el diff", "state" => "active" }, ;
      { "title" => "Resumir el coste de la sesion", "state" => "pending" } }
   AGREPL_PlanCard()
   hb_idleSleep( 0.35 )
   // thinking glass box
   AGREPL_Out( Chr(10) + AGUI_Color( "●", "97" ) + " Thinking" + ;
      AGUI_Color( Chr(226)+Chr(128)+Chr(166), AGUI_Pal( "dim" ) ) + Chr(10) )
   AGREPL_Out( AGREPL_ThinkLine( cCorner + "El usuario quiere ver las cards. " + ;
      "Creo el fichero, lo edito y muestro el diff antes de seguir." ) + Chr(10) )
   hb_idleSleep( 0.35 )
   // tool action lines + diff
   AGREPL_Out( AGREPL_UserCard( "Crea bienvenida.md y luego editalo" ) )
   AGREPL_Out( Chr(10) + AGREPL_ToolCard( AGUI_Color( "●", "97" ) + " Running write" + ;
      AGUI_Color( Chr(226)+Chr(128)+Chr(166), AGUI_Pal( "dim" ) ) ) )
   AGREPL_Out( AGREPL_ToolCard( AGUI_Color( cCheck, "92" ) + " write " + ;
      AGUI_Color( "Created bienvenida.md (3 lines)", AGUI_Pal( "dim" ) ) ) )
   hb_idleSleep( 0.35 )
   AGREPL_Out( Chr(10) + AGREPL_ToolCard( AGUI_Color( "●", "97" ) + " Running edit" + ;
      AGUI_Color( Chr(226)+Chr(128)+Chr(166), AGUI_Pal( "dim" ) ) ) )
   AGREPL_Out( AGREPL_ToolCard( AGUI_Color( cCheck, "92" ) + " edit " + ;
      AGUI_Color( "bienvenida.md: 1 removed, 3 added", AGUI_Pal( "dim" ) ) ) )
   AGREPL_Out( AGREPL_ToolCard( AGUI_ResultSummary( "edit", ;
      "     1   # Agents" + Chr(10) + ;
      "     2 - Agente IA en tu terminal." + Chr(10) + ;
      "     2 + Agente IA en tu terminal, con cards como la web." + Chr(10) + ;
      "     3 + " + Chr(10) + ;
      "     4 + Comandos: /plan, /run, /cost, /demo" ) ) )
   hb_idleSleep( 0.35 )
   // assistant reply card
   AGREPL_Out( Chr(10) )
   AGREPL_Out( AGUI_CardLine( "Listo: he creado bienvenida.md y lo he ampliado.", ;
               "card", nW ) + Chr(10) )
   AGREPL_Out( AGUI_CardLine( "El diff de arriba muestra los cambios linea a linea.", ;
               "card", nW ) + Chr(10) )
   hb_idleSleep( 0.35 )
   // error card
   AGREPL_Out( AGUI_RenderEvent( { "type" => "error", ;
      "message" => "Cannot find module 'clsx' (ejemplo de error simulado)" } ) )
   hb_idleSleep( 0.35 )
   // permit card (visual only)
   AGREPL_Out( Chr(10) + AGUI_Card( ;
      AGUI_Color( "CONFIRMATION REQUIRED", "1;33" ) + Chr(10) + ;
      "The agent wants to run " + AGUI_Color( "shell", "1" ) + ;
      ": npm install clsx   (demo: no espera respuesta)", ;
      "card_warn", nW ) + Chr(10) )
   hb_idleSleep( 0.35 )
   // cost card
   AGREPL_Out( AGREPL_UserCard( "/cost" ) )
   AGREPL_Out( AGUI_CostReport( hUsage ) )
   hb_idleSleep( 0.35 )
   // compact card
   AGREPL_Out( AGREPL_UserCard( "/compact" ) )
   AGREPL_Out( AGUI_Card( ;
      AGUI_Color( "CONTEXT COMPACTED", "1;38;2;192;132;252" ) + Chr(10) + ;
      AGUI_Color( "12 turns -> 1 summary, kept last 4 verbatim", ;
                  "38;2;232;226;248" ), ;
      "card_think", nW ) + Chr(10) )
   hb_idleSleep( 0.35 )
   // context-critical card
   AGREPL_Out( Chr(10) + AGUI_Card( ;
      AGUI_Color( "CONTEXT WINDOW CRITICAL", "1;38;2;251;146;60" ) + "   " + ;
      AGUI_Color( "112000 / 128000 tkns  (87%)", "2" ) + Chr(10) + ;
      "Memory is filling up: run /compact to summarise old turns, or " + ;
      "/clear to start fresh.", "card_ctx", nW ) + Chr(10) )
   hb_idleSleep( 0.35 )
   AGREPL_Out( Chr(10) + AGUI_Color( "[" + cCheck + " Demo completada - " + ;
      "goal - plan - thinking - acciones - diff - respuesta - error - " + ;
      "permit - cost - compact - contexto]", "92" ) + Chr(10) )
   // restore the real session state
   s_cGoal        := cOldGoal
   s_lGoalLooping := lOldLoop
   s_aPlanSteps   := aOldPlan
   RETURN NIL

// /sh /git /clone: run a shell command directly (no LLM) and print it as a
// terminal card, like the web version's /sh. Uses the registry executor
// directly: the command was typed explicitly by the user, so no permission
// prompt applies.
STATIC FUNCTION AGREPL_ShellCmd( cCmd, oReg )
   LOCAL cOut, cLine, cBlock := ""
   IF Empty( cCmd )
      AGREPL_Out( AGUI_Color( "Usage: /sh <command>", ;
                              AGUI_Pal( "error" ) ) + Chr(10) )
      RETURN NIL
   ENDIF
   cOut := hb_CStr( Eval( AGTOOLS_Executor( oReg ), "shell", ;
                          hb_jsonEncode( { "command" => cCmd } ) ) )
   cBlock := AGUI_Color( "> " + cCmd, "92" )
   FOR EACH cLine IN hb_ATokens( StrTran( cOut, Chr(13), "" ), Chr(10) )
      cBlock += Chr(10) + cLine
   NEXT
   AGREPL_Out( Chr(10) + AGREPL_ToolCard( cBlock ) )
   RETURN NIL

// /skill: list the available skills (a card with on/off state) or toggle one
// by name. Active skills inject their body as a system note (web parity).
STATIC FUNCTION AGREPL_SkillCmd( cArg, aMsgs, oPrompt )
   LOCAL aList := AGSKILL_List(), aActive := AGSKILL_Active()
   LOCAL hSkill, lOn, cRow, nW := Min( AGREPL_Cols() - 2, 100 ), cName
   cArg := Lower( AllTrim( hb_CStr( cArg ) ) )
   IF !Empty( cArg )
      // toggle
      IF AScan( aActive, {| c | Lower( c ) == cArg } ) > 0
         AGSKILL_Deactivate( cArg )
         AAdd( aMsgs, { "role" => "system", ;
            "content" => "The user deactivated the skill '" + cArg + ;
                         "'. Stop following its instructions." } )
         AGREPL_Out( AGUI_Color( "[skill '" + cArg + "' off]", ;
                                 AGUI_Pal( "dim" ) ) + Chr(10) )
         IF oPrompt != NIL
            AGPROMPT_Redraw( oPrompt )
         ENDIF
      ELSE
         AGREPL_ActivateSkill( cArg, aMsgs, oPrompt )
      ENDIF
      RETURN NIL
   ENDIF
   // list card
   IF Empty( aList )
      AGREPL_Out( AGUI_Color( "[no skills in " + AGSKILL_Dir() + ;
                  " -- add <name>.md files with name/description frontmatter]", ;
                  AGUI_Pal( "dim" ) ) + Chr(10) )
      RETURN NIL
   ENDIF
   AGREPL_Out( Chr(10) + AGUI_CardLine( AGUI_Color( "SKILLS", ;
               "1;38;2;244;114;182" ) + "   " + ;
               AGUI_Color( "/skill <name> activa o desactiva", "2" ), ;
               "card", nW ) + Chr(10) )
   FOR EACH hSkill IN aList
      cName := hSkill[ "name" ]
      lOn   := AScan( aActive, {| c | Lower( c ) == Lower( cName ) } ) > 0
      cRow  := AGUI_Color( iif( lOn, Chr(226)+Chr(151)+Chr(143), ;
                                     Chr(226)+Chr(151)+Chr(139) ), ;
                           iif( lOn, "38;2;244;114;182", "90" ) ) + " " + ;
               AGUI_Color( cName, iif( lOn, "1", "0" ) ) + "  " + ;
               AGUI_Color( Left( hb_CStr( hSkill[ "description" ] ), 60 ), "90" )
      AGREPL_Out( AGUI_CardLine( cRow, "card", nW ) + Chr(10) )
   NEXT
   RETURN NIL

// /tool: the tools-registry card -- one row per registered tool with a
// security dot: red for mutating tools (permission-gated), green read-only.
STATIC FUNCTION AGREPL_ToolsList( oReg )
   LOCAL aSchemas := AGTOOLS_Schemas( oReg ), hTool, cName, lMut, cRow
   LOCAL nW := Min( AGREPL_Cols() - 2, 100 )
   AGREPL_Out( Chr(10) + AGUI_CardLine( AGUI_Color( "TOOLS", "1;36" ) + "   " + ;
               AGUI_Color( "rojo = mutante (permission gate) - verde = lectura", ;
                           "2" ), "card", nW ) + Chr(10) )
   FOR EACH hTool IN aSchemas
      cName := hTool[ "function" ][ "name" ]
      lMut  := cName == "shell" .OR. cName == "write" .OR. cName == "edit" .OR. ;
               cName == "github_write"
      cRow  := AGUI_Color( Chr(226)+Chr(151)+Chr(143), ;
                           iif( lMut, "91", "92" ) ) + " " + ;
               AGUI_Color( PadR( cName, 16 ), "1;36" ) + ;
               AGUI_Color( Left( hb_CStr( ;
                  hTool[ "function" ][ "description" ] ), 70 ), "90" )
      AGREPL_Out( AGUI_CardLine( cRow, "card", nW ) + Chr(10) )
   NEXT
   RETURN NIL

// Paints a tool-action line/block on the faint actions-panel tint (the web
// version's collapsible "acciones" panel). Pass-through when colour is off.
// Always ends in exactly one LF.
STATIC FUNCTION AGREPL_ToolCard( cText )
   cText := hb_CStr( cText )
   DO WHILE Right( cText, 1 ) == Chr(10) .OR. Right( cText, 1 ) == Chr(13)
      cText := hb_StrShrink( cText, 1 )
   ENDDO
   IF Empty( cText )
      RETURN ""
   ENDIF
   IF !AGUI_ColorOn()
      RETURN cText + Chr(10)
   ENDIF
   RETURN AGUI_Card( cText, "card_tool", Min( AGREPL_Cols() - 2, 100 ) ) + Chr(10)

// The user's prompt echoed as a blue bubble (web addUser parity): white
// text on a blue card. Plain "> text" line when colour is off. Ends in LF.
STATIC FUNCTION AGREPL_UserCard( cText )
   LOCAL aLines, i, cOut := "", nW
   cText := hb_CStr( cText )
   IF !AGUI_ColorOn()
      RETURN AGUI_Color( "> " + cText, AGUI_Pal( "user" ) ) + Chr(10)
   ENDIF
   nW := Min( AGREPL_Cols() - 2, 100 )
   aLines := hb_ATokens( StrTran( cText, Chr(13), "" ), Chr(10) )
   FOR i := 1 TO Len( aLines )
      cOut += AGUI_CardLine( AGUI_Color( aLines[ i ], "97" ), "card_user", nW ) + ;
              Chr(10)
   NEXT
   RETURN cOut

// One reasoning line, GUI glass-box style: pink text on a faint purple card.
// Falls back to the plain pink line when colour is off.
STATIC FUNCTION AGREPL_ThinkLine( cText )
   IF AGUI_ColorOn()
      RETURN AGUI_CardLine( AGUI_Color( cText, "38;2;225;150;170" ), ;
                            "card_think", Min( AGREPL_Cols() - 2, 100 ) )
   ENDIF
   RETURN AGUI_Color( cText, "38;2;225;150;170" )

// Toggles the working bullet between filled (●) and hollow (○) on each
// call, overwriting the same physical line via ESC[1G ESC[K. Called from
// usage events during streaming to create a visible blink effect.
STATIC FUNCTION AGREPL_WorkBlink( oRender )
   LOCAL cBullet := iif( oRender[ "spinnerFrame" ] % 2 == 0, "●", "○" )
   AGREPL_Out( AGUI_VT( "1G" ) + AGUI_VT( "K" ) + ;
      AGUI_Color( cBullet, "92" ) + " Working" + ;
      AGUI_Color( Chr( 226 ) + Chr( 128 ) + Chr( 166 ), AGUI_Pal( "dim" ) ) )
   RETURN NIL

STATIC FUNCTION AGREPL_SpinnerShow( oRender, cExtra )
   HB_SYMBOL_UNUSED( oRender ) ; HB_SYMBOL_UNUSED( cExtra )
   RETURN NIL

STATIC FUNCTION AGREPL_SpinnerClear()
   AGREPL_Out( AGUI_VT( "1G" ) + AGUI_VT( "K" ) )
   RETURN NIL

// After a turn completes, optionally prints a compact token-usage bar when
// usage data was collected from the stream. nTurnMs is the wall-clock time
// the turn just spent inside AG_AgentRun; appended to the bar along with the
// session-cumulative time so the user can track latency without /cost.
STATIC FUNCTION AGREPL_ShowTokenBar( hUsage, nTurnMs )
   LOCAL nPrompt, nComp, nTotal, cBar
   IF ValType( hUsage ) != "H" .OR. Len( hb_HKeys( hUsage ) ) == 0
      RETURN NIL
   ENDIF
   nPrompt := hb_HGetDef( hUsage, "prompt_tokens", 0 )
   nComp   := hb_HGetDef( hUsage, "completion_tokens", 0 )
   nTotal  := nPrompt + nComp
   IF nTotal == 0
      RETURN NIL
   ENDIF
   IF ValType( nTurnMs ) != "N"
      nTurnMs := 0
   ENDIF
   cBar := AGUI_Color( "  ", "90" ) + ;
           AGUI_Color( Chr(226)+Chr(150)+Chr(146) + " ", "90" ) + ;   // ┒
           AGUI_Color( "tokens in: ", "90" ) + ;
           AGUI_Color( LTrim( Str( nPrompt ) ), "1;36" ) + ;
           AGUI_Color( "  out: ", "90" ) + ;
           AGUI_Color( LTrim( Str( nComp ) ), "1;36" ) + ;
           AGUI_Color( "  total: ", "90" ) + ;
           AGUI_Color( LTrim( Str( nTotal ) ), "1" ) + ;
           AGUI_Color( "  turn: ", "90" ) + ;
           AGUI_Color( LTrim( Str( nTurnMs / 1000.0, 10, 1 ) ) + "s", "1;36" ) + ;
           AGUI_Color( "  session: ", "90" ) + ;
           AGUI_Color( LTrim( Str( s_nSessionTurnMs / 1000.0, 10, 1 ) ) + "s", "1" )
   AGREPL_Out( AGUI_VT( "1G" ) + AGUI_VT( "K" ) + cBar + Chr(10) )
   RETURN NIL

// Asks whether to continue a capped turn with 25 more iterations.
// Returns .T. for a "y" answer; end-of-input (piped stdin) -> .F. (no hang).
STATIC FUNCTION AGREPL_AskExtend()
   LOCAL cLine
   AGREPL_Out( Chr(10) + AGUI_Color( ;
      "[iteration cap reached -- continue with 25 more? y/n] ", ;
      AGUI_Pal( "warn" ) ) )
   cLine := AGREPL_ReadLine()
   IF cLine == NIL
      RETURN .F.
   ENDIF
   RETURN Lower( Left( AllTrim( cLine ), 1 ) ) == "y"

// The active persistent box prompt instance, or NIL when no box is
// mounted. Public so the question selector can route keystrokes into the
// box editor while it waits for the user to choose an option.
FUNCTION AGREPL_BoxPrompt()
   RETURN s_oBoxPrompt

// True while the session is in plan-mode (toggled by /plan). Public so the
// permission gate can block write/edit/shell and the status line can show
// the [plan-mode] badge.
FUNCTION AGREPL_PlanMode()
   RETURN s_lPlanMode

// True while the session is in lean-mode (toggled by /lean). Public so the
// system-prompt builder can return a minimal version and the status line
// can show the [lean] badge.
FUNCTION AGREPL_LeanMode()
   RETURN s_lLeanMode

// True when the persistent box prompt is mounted with an active scroll
// region. Modules that want to paint above the box (e.g. the question
// selector) check this to know whether they can rely on the ESC[s/[u
// anchor managed by AGREPL_Out.
FUNCTION AGREPL_BoxActive()
   RETURN s_oBoxPrompt != NIL .AND. ;
          ValType( s_oBoxPrompt[ "region" ] ) == "H" .AND. ;
          s_oBoxPrompt[ "region" ][ "active" ] == .T.

// Overwrites the saved-anchor row in place with cText: jumps to the anchor,
// resets to col 1, wipes the row, writes the text, then returns the visible
// cursor to the input box. Does NOT advance content_row and does NOT re-save
// the anchor -- the NEXT call lands on the same row, so a tool can animate
// one row (e.g. dispatch_agent's elapsed-time line) without pushing the box
// down. To bake the final value in and let subsequent output land below it,
// follow the last overwrite with a AGREPL_Out call ending in Chr(10) -- that
// repaints the row and advances content_row in the same write.
FUNCTION AGREPL_OverwriteAtAnchor( cText )
   IF s_oBoxPrompt != NIL .AND. s_oBoxPrompt[ "region" ][ "active" ]
      FWrite( hb_GetStdOut(), ;
         Chr(27) + "[u" + Chr(27) + "[1G" + Chr(27) + "[K" + ;
         hb_CStr( cText ) + AGREPL_BoxCursorSeq() )
   ELSE
      FWrite( hb_GetStdOut(), Chr(13) + Chr(27) + "[K" + hb_CStr( cText ) )
   ENDIF
   RETURN NIL

// Writes raw bytes straight to the OS stdout handle, bypassing the GT layer
// so UTF-8 output is not re-encoded. The console code page is set to UTF-8
// by AGREPL_InitConsole, so these bytes render correctly. Line feeds are
// normalised to CRLF: bypassing the GT also loses its LF -> CRLF translation,
// and a Windows console needs the CR to return to column 0.
FUNCTION AGREPL_Out( cText )
   LOCAL nNL, i, lTrailingLF
   // Test the length, not Empty(): Empty() is true for a whitespace-only
   // string, so a streamed delta of just "\n" would be dropped and the line
   // break lost.
   IF ValType( cText ) == "C" .AND. Len( cText ) > 0
      cText := StrTran( cText, Chr(13), "" )
      // Capture the trailing-LF status BEFORE the LF substitution below so
      // AGPROMPT_Redraw's wipe can tell whether the cursor lands on a new
      // empty row (trailing LF) or on the last written content row (no
      // trailing LF). Without this, a chunk like the FlushPending bullet
      // "\n + glyph + 2sp" -- no trailing LF -- has its just-written content
      // wiped by the wipe range Max(oldBoxTop, contentRow) ... newBoxTop-1.
      lTrailingLF := Right( cText, 1 ) == Chr(10)
      // Clear-to-end-of-line BEFORE each line break, so a short content
      // line never lets the previous frame's trailing chars (a box top
      // border, an old reply) survive to the right of the new text.
      // Order: ESC[K, then CR LF.
      cText := StrTran( cText, Chr(10), Chr(27) + "[K" + Chr(13) + Chr(10) )
      // Same protection for the FINAL line of the chunk (no trailing LF)
      // -- append ESC[K so the trailing junk on its row is wiped too.
      IF !lTrailingLF
         cText += Chr(27) + "[K"
      ENDIF
      IF s_oBoxPrompt != NIL .AND. s_oBoxPrompt[ "region" ][ "active" ]
         // box mode: jump to the saved scroll-region anchor, write there,
         // re-save the anchor, then return the cursor to the input box so
         // the visible cursor stays where the user is typing.
         FWrite( hb_GetStdOut(), ;
            Chr(27) + "[u" + cText + Chr(27) + "[s" + AGREPL_BoxCursorSeq() )
         // While the box is still "travelling" (not yet pinned to the
         // floor), advance content_row by the number of VISUAL rows the
         // chunk consumed -- not just LFs. A long line that auto-wraps
         // occupies several physical rows even with a single \n; missing
         // those rows in the count leaves the box overlapping the
         // wrapped content. Once content_row + 1 reaches the floor the
         // region becomes pinned and the LF-driven scroll takes over.
         // Spinner updates (ESC[1G ESC[K prefix) overwrite the same
         // physical row — skip content_row advance so the box doesn't
         // drift down with every animation frame.
         IF !( Left( cText, 7 ) == Chr(27) + "[1G" + Chr(27) + "[K" )
            IF !hb_HGetDef( s_oBoxPrompt[ "region" ], "pinned", .F. )
               nNL := AGREPL_VisualRows( cText, AGREPL_Cols() )
               IF nNL > 0
                  s_oBoxPrompt[ "last_write_start" ] := ;
                     hb_HGetDef( s_oBoxPrompt, "content_row", 1 )
                  s_oBoxPrompt[ "last_write_trailing_lf" ] := lTrailingLF
                  s_oBoxPrompt[ "content_row" ] := ;
                     hb_HGetDef( s_oBoxPrompt, "content_row", 1 ) + nNL
                  AGPROMPT_Redraw( s_oBoxPrompt )
               ENDIF
            ENDIF
         ENDIF
      ELSE
         FWrite( hb_GetStdOut(), cText )
      ENDIF
   ENDIF
   RETURN NIL

// The VT escape that moves the cursor onto the input box's editing line at
// the current edit column (box content starts at column 5: border, space,
// "> ", then text). Public so the question selector can park the visible
// cursor in the box while it waits for a key.
FUNCTION AGREPL_BoxCursorSeq()
   LOCAL hReg := s_oBoxPrompt[ "region" ], hW
   hW := AGIN_Window( s_oBoxPrompt[ "editor" ], AGUI_InputInnerWidth() )
   RETURN Chr(27) + "[" + LTrim( Str( hReg[ "box_top" ] + 1 ) ) + ";" + ;
          LTrim( Str( 3 + hW[ "col" ] ) ) + "H"

// Sets the Windows console to the UTF-8 code page (65001) so the model's
// UTF-8 output renders, and enables virtual-terminal mode so ANSI colours
// work. Returns .T. when VT mode was accepted (so the caller can decide
// whether to colour output). Wrapped so a missing console API never aborts.
STATIC FUNCTION AGREPL_InitConsole()
   LOCAL oErr, hOut, lVT := .F.
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      hb_dynCall( { "SetConsoleOutputCP", "kernel32.dll", ;
         hb_bitOr( HB_DYN_CALLCONV_STDCALL, HB_DYN_CTYPE_BOOL ) }, 65001 )
      hb_dynCall( { "SetConsoleCP", "kernel32.dll", ;
         hb_bitOr( HB_DYN_CALLCONV_STDCALL, HB_DYN_CTYPE_BOOL ) }, 65001 )
      hOut := hb_dynCall( { "GetStdHandle", "kernel32.dll", ;
         hb_bitOr( HB_DYN_CALLCONV_STDCALL, HB_DYN_CTYPE_VOID_PTR ) }, -11 )
      // mode 7 = PROCESSED_OUTPUT | WRAP_AT_EOL | VIRTUAL_TERMINAL_PROCESSING
      lVT := hb_dynCall( { "SetConsoleMode", "kernel32.dll", ;
         hb_bitOr( HB_DYN_CALLCONV_STDCALL, HB_DYN_CTYPE_BOOL ), ;
         { HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_LONG_UNSIGNED } }, hOut, 7 )
   RECOVER USING oErr
      HB_SYMBOL_UNUSED( oErr )
      // console API unavailable -> leave the console as is
   END SEQUENCE
   RETURN ( lVT == .T. )

// Permission prompt for a tool in "ask" mode. Returns the typed answer
// ("y"/"n"/"a"); the gate normalises it. Never throws.
STATIC FUNCTION AGREPL_AskPerm( cName, cArgsJson )
   LOCAL cLine := "n", oErr, nTimeout
   // AGENTS_ASK_TIMEOUT (env, seconds): when > 0, deny if no answer
   // arrives within that window. Non-interactive stdin (piped, script,
   // background) auto-denies immediately -- nobody can answer.
   nTimeout := Val( hb_GetEnv( "AGENTS_ASK_TIMEOUT", "0" ) )
   IF !AGCON_HasConsole()
      AGREPL_Out( Chr(10) + "[non-interactive stdin -- '" + hb_CStr( cName ) + "' denied]" + Chr(10) )
      RETURN "n"
   ENDIF
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      IF AGUI_ColorOn()
         // amber confirmation card (web permitCard parity); the answer
         // prompt itself stays a plain line so input lands after it
         AGREPL_Out( Chr(10) + AGUI_Card( ;
            AGUI_Color( "CONFIRMATION REQUIRED", "1;33" ) + Chr(10) + ;
            "The agent wants to run " + AGUI_Color( hb_CStr( cName ), "1" ) + ;
            ": " + AGUI_Summarize( hb_CStr( cArgsJson ), 120 ), ;
            "card_warn", Min( AGREPL_Cols() - 2, 100 ) ) + Chr(10) )
         AGREPL_Out( AGUI_Color( "Allow? [y/n/a] ", "33" ) )
      ELSE
         AGREPL_Out( Chr(10) + AGUI_Color( "Tool '" + hb_CStr( cName ) + ;
                 "' wants to run: " + AGUI_Summarize( hb_CStr( cArgsJson ), 120 ) + ;
                 Chr(10) + "Allow? [y/n/a] ", "33" ) )
      ENDIF
      IF nTimeout > 0
         cLine := AGREPL_ReadLineTimeout( nTimeout )
         IF cLine == NIL
            AGREPL_Out( Chr(10) + AGUI_Color( "[no response in " + ;
                LTrim(Str(nTimeout)) + "s -- denied]", "31" ) + Chr(10) )
            cLine := "n"
         ENDIF
      ELSE
         cLine := AGREPL_ReadLine()
         IF cLine == NIL
            cLine := "n"
         ENDIF
      ENDIF
   RECOVER USING oErr
      HB_SYMBOL_UNUSED( oErr )
      cLine := "n"
   END SEQUENCE
   // Clear answer from prompt box so it does not linger
   IF s_oBoxPrompt != NIL
      s_oBoxPrompt[ "editor" ] := AGIN_New( "" )
      AGPROMPT_Redraw( s_oBoxPrompt )
   ENDIF
   RETURN cLine

// Like AGREPL_ReadLine but returns NIL after nSeconds with no input.
// Polls stdin via AGCON_StdInWait (POSIX select) before each FRead so
// the loop can wake periodically and check the deadline.
STATIC FUNCTION AGREPL_ReadLineTimeout( nSeconds )
   LOCAL cLine := "", cCh := Space(1), nRead, hIn := hb_GetStdIn()
   LOCAL nDeadlineMs := hb_MilliSeconds() + nSeconds * 1000
   LOCAL nRemMs
   DO WHILE .T.
      nRemMs := nDeadlineMs - hb_MilliSeconds()
      IF nRemMs <= 0
         RETURN iif( Empty( cLine ), NIL, cLine )
      ENDIF
      IF !AGCON_StdInWait( iif( nRemMs > 500, 500, nRemMs ) )
         LOOP
      ENDIF
      nRead := FRead( hIn, @cCh, 1 )
      IF nRead == 0
         RETURN iif( Empty( cLine ), NIL, cLine )
      ENDIF
      IF s_lSkipLF
         s_lSkipLF := .F.
         IF cCh == Chr(10)
            LOOP
         ENDIF
      ENDIF
      DO CASE
      CASE cCh == Chr(10)
         EXIT
      CASE cCh == Chr(13)
         s_lSkipLF := .T.
         EXIT
      CASE ( cCh == Chr(8) .OR. cCh == Chr(127) ) .AND. !Empty( cLine )
         cLine := hb_BLeft( cLine, hb_BLen( cLine ) - 1 )
      CASE cCh >= " "
         cLine += cCh
      ENDCASE
   ENDDO
   IF hb_BLeft( cLine, 3 ) == Chr(239) + Chr(187) + Chr(191)
      cLine := SubStr( cLine, 4 )
   ENDIF
   RETURN cLine

// Reads one line from stdin. Returns the line, or NIL at end of input.
// Terminates on LF, CR, or CRLF. The console runs in its default cooked mode
// (gtnul does not touch it), so it echoes the typed line and applies editing
// itself -- this function must NOT echo, or the input would appear twice.
FUNCTION AGREPL_ReadLine()
   LOCAL cLine := "", cCh := Space(1), nRead, hIn := hb_GetStdIn()
   DO WHILE .T.
      nRead := FRead( hIn, @cCh, 1 )
      IF nRead == 0
         RETURN iif( Empty( cLine ), NIL, cLine )
      ENDIF
      IF s_lSkipLF
         s_lSkipLF := .F.
         IF cCh == Chr(10)
            LOOP   // swallow the LF that follows a CR (CRLF)
         ENDIF
      ENDIF
      DO CASE
      CASE cCh == Chr(10)
         EXIT
      CASE cCh == Chr(13)
         s_lSkipLF := .T.
         EXIT
      CASE ( cCh == Chr(8) .OR. cCh == Chr(127) ) .AND. !Empty( cLine )
         cLine := hb_BLeft( cLine, hb_BLen( cLine ) - 1 )
      CASE cCh >= " "
         cLine += cCh
      ENDCASE
   ENDDO
   // strip a leading UTF-8 BOM (piped input on Windows may prepend one)
   IF hb_BLeft( cLine, 3 ) == Chr(239) + Chr(187) + Chr(191)
      cLine := SubStr( cLine, 4 )
   ENDIF
   RETURN cLine
