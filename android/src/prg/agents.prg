/*
 * AgenticAI for Android - multi-agent, Harbour MT.
 *
 * The dispatcher thread (Main) loads the HTML chat panel into the Android WebView
 * and spawns one Harbour thread per agent (hb_threadStart). Each agent runs the
 * ccharbour streaming chat + tool-calling loop independently, with its own client
 * and history, blocking on its own native event queue (AWV_WaitEvent(nId)).
 *
 * Platform glue vs. the desktop FWH app:
 *   oWeb:Eval(js)      -> AWV_Eval(js)           (UI thread, marshalled in Java)
 *   SendToFWH(...)     -> Android.send(id,act,t) -> AWV_WaitEvent(id)
 *   hbcurl transport   -> AWV_Http() (Java HttpsURLConnection)
 *
 * Build with build-apk.sh (HB_MT_VM). See README.md.
 */

// TEXT INTO is a FiveWin command; the plain host harbour.exe doesn't have it,
// so define it here (Harbour core __cstream pragma).
#xcommand TEXT INTO <v> => #pragma __cstream|<v>:=%s

#define MAX_AGENTS  8

STATIC s_aAgents := {}        // per-agent state hashes, indexed by id
STATIC s_cGhToken             // runtime GitHub token (/ghtoken overrides the file)

THREAD STATIC t_nId           // this thread's agent id
THREAD STATIC t_oClient, t_aMessages, t_aSchemas, t_bExec, t_bTransport
THREAD STATIC t_lStop, t_lYolo, t_lRunning, t_nTurn, t_cAskAnswer, t_cPermit
THREAD STATIC t_cGoal         // active goal set by /goal, used by /plan

// ---------------------------------------------------------------------------
// Dispatcher thread.
// ---------------------------------------------------------------------------
FUNCTION Main()

   LOCAL aEv, cAction, cText, nId

   // (The chdir to the app's writable dir is done in C nativeInit.)

   AWV_SetHtml( ChatHtml() )

   // Dispatcher loop (agentId 0). The page sends 'ready' when its JS is loaded;
   // then we spawn agent 1. '+' sends 'newagent' to spawn more. Each agent runs
   // on its own Harbour MT thread (libhbvmmt) and blocks on its own queue.
   DO WHILE .T.
      aEv     := AWV_WaitEvent( 0 )
      cAction := aEv[ 1 ]
      cText   := aEv[ 2 ]
      DO CASE
      CASE cAction == "ready"
         IF Empty( s_aAgents )
            SpawnAgent( 1 )
         ENDIF
      CASE cAction == "newagent"
         nId := Len( s_aAgents ) + 1
         IF nId <= MAX_AGENTS
            SpawnAgent( nId )
         ENDIF
      CASE cAction == "quit"
         EXIT
      ENDCASE
   ENDDO

RETURN NIL

STATIC FUNCTION SpawnAgent( nId )
   AAdd( s_aAgents, { "id" => nId } )
   AWV_Eval( "newAgentTab(" + LTrim( Str( nId ) ) + ")" )
   hb_threadStart( {| x | AgentMain( x ) }, nId )
RETURN NIL

// ---------------------------------------------------------------------------
// One agent thread. PUBLIC so hb_threadStart's @AgentMain() symbol resolves.
// ---------------------------------------------------------------------------
FUNCTION AgentMain( nId )

   LOCAL aEv, hCfg

   t_nId      := nId
   t_lStop    := .F.
   t_lYolo    := .T.
   t_lRunning := .F.
   t_nTurn    := 0

   WCall( "whatsNew", WhatsNew() )

   t_oClient    := CC_Client( { "model" => "deepseek-chat", "timeout" => 180, ;
                                "api_key" => ReadKeyFile() } )
   hCfg := CCCFG_Resolve( t_oClient[ "opts" ] )
   t_aMessages  := { { "role" => "system", "content" => SystemPrompt() } }
   t_bTransport := {| hReq, bOnChunk | DroidTransport( hReq, bOnChunk ) }
   BuildTools()

   IF !hCfg[ "ok" ]
      WCall( "addNote", "No API key. Type /key <api-key>." )
      WCall( "setStatus", "No API key - use /key", "err" )
   ENDIF

   DO WHILE .T.
      aEv := AWV_WaitEvent( nId )      // blocks
      OnJsMessage( aEv )
   ENDDO

RETURN NIL

// ---------------------------------------------------------------------------
// JS -> PRG event handling (per agent thread).
// ---------------------------------------------------------------------------
STATIC FUNCTION OnJsMessage( aEv )
   LOCAL cAction := aEv[ 1 ], cText := aEv[ 2 ]
   DO CASE
   CASE cAction == "send"
      SendTurn( AllTrim( cText ) )
   CASE cAction == "stop"
      t_lStop := .T.
   CASE cAction == "clear"
      ClearAll()
   CASE cAction == "yolo"
      t_lYolo := ( cText == "1" )
   CASE cAction == "ask"
      t_cAskAnswer := cText
   CASE cAction == "permit"
      t_cPermit := cText
   ENDCASE
RETURN NIL

STATIC FUNCTION ClearAll()
   IF t_lRunning
      RETURN NIL
   ENDIF
   WCall( "clearChat" )
   t_aMessages := { { "role" => "system", "content" => SystemPrompt() } }
   t_nTurn := 0
   WCall( "setStatus", "Ready.", "idle" )
RETURN NIL

// ---------------------------------------------------------------------------
// One turn (runs on this agent's thread - blocking network is fine here).
// ---------------------------------------------------------------------------
STATIC FUNCTION SendTurn( cPrompt )
   LOCAL hOpts, hRes, oErr

   IF t_lRunning .OR. Empty( cPrompt )
      RETURN NIL
   ENDIF
   IF Left( cPrompt, 1 ) == "/"
      SlashCommand( cPrompt )
      RETURN NIL
   ENDIF

   t_nTurn++
   WCall( "addUser", cPrompt )
   WCall( "startTurn", LTrim( Str( t_nTurn ) ), Time() )

   t_lStop := .F. ; t_lRunning := .T.
   WCall( "setRunning", "1" )
   WCall( "setStatus", "Working...", "busy" )

   AAdd( t_aMessages, { "role" => "user", "content" => cPrompt } )

   hOpts := { "model" => "deepseek-chat", "tools" => t_aSchemas, ;
              "tool_executor" => t_bExec, "transport" => t_bTransport, ;
              "max_iterations" => 25, "interrupt_check" => {|| t_lStop } }

   BEGIN SEQUENCE WITH {| o | Break( o ) }
      hRes := CC_AgentRun( t_oClient, t_aMessages, hOpts, {| hEv | OnEvent( hEv ) } )
   RECOVER USING oErr
      hRes := { "success" => .F., "messages" => t_aMessages, "usage" => {=>}, ;
                "message" => iif( ValType( oErr ) == "O", hb_CStr( oErr:Description ), "exception" ) }
   END SEQUENCE

   IF hRes[ "success" ]
      t_aMessages := hRes[ "messages" ]
   ENDIF

   WCall( "finalizeTurn" )
   t_lRunning := .F.
   WCall( "setRunning", "0" )
   WCall( "setStatus", iif( hRes[ "success" ], "Ready.", "Error" ), ;
          iif( hRes[ "success" ], "idle", "err" ) )
RETURN NIL

STATIC FUNCTION SlashCommand( cLine )
   LOCAL nSp := At( " ", cLine )
   LOCAL cCmd := Lower( iif( nSp > 0, Left( cLine, nSp - 1 ), cLine ) )
   LOCAL cArg := iif( nSp > 0, AllTrim( SubStr( cLine, nSp + 1 ) ), "" )
   DO CASE
   CASE cCmd == "/key"
      IF Empty( cArg )
         WCall( "addNote", "Usage: /key <your-api-key>" )
      ELSE
         t_oClient[ "opts" ][ "api_key" ] := cArg
         WCall( "addNote", "API key set." )
         WCall( "setStatus", "Ready.", "idle" )
      ENDIF
   CASE cCmd == "/ghtoken"
      IF Empty( cArg )
         WCall( "addNote", "Usage: /ghtoken <github-personal-access-token>" )
      ELSE
         s_cGhToken := cArg
         WCall( "addNote", "GitHub token set. github_read/list/write enabled." )
      ENDIF
   CASE cCmd == "/goal"
      IF !Empty( cArg )
         t_cGoal := cArg
      ENDIF
      WCall( "goalCard", iif( Empty( t_cGoal ), ;
         "Migrar todo el sistema de autenticacion de JWT a sesiones basadas en " + ;
         "cookies y asegurar que la cobertura de pruebas no baje del 90%.", t_cGoal ) )
   CASE cCmd == "/plan"
      PlanReal( iif( !Empty( cArg ), cArg, ;
                iif( !Empty( t_cGoal ), t_cGoal, ;
                "Migrar el sistema de autenticacion de JWT a sesiones con cookies" ) ) )
   CASE cCmd == "/loop"
      WCall( "loopCard", hb_jsonEncode( { "iter" => 3, "max" => 15, "cmds" => 8 } ) )
   CASE cCmd == "/clear"
      ClearAll()
   CASE cCmd == "/help"
      WCall( "addNote", "Commands: /key  /ghtoken  /goal  /plan  /loop  /clear  /help" )
   OTHERWISE
      WCall( "addNote", "Unknown command. Try /key, /clear, /help." )
   ENDCASE
RETURN NIL

// ccharbour streaming events -> webview.
STATIC FUNCTION OnEvent( hEv )
   DO CASE
   CASE hEv[ "type" ] == "text_delta"
      WCall( "aDelta", hEv[ "text" ] )
   CASE hEv[ "type" ] == "iteration_start"
      WCall( "setStatus", "Thinking... (step " + LTrim( Str( hEv[ "n" ] ) ) + ")", "busy" )
   CASE hEv[ "type" ] == "tool_call"
      WCall( "toolCall", hEv[ "name" ], Left( hb_CStr( hEv[ "arguments" ] ), 200 ) )
   CASE hEv[ "type" ] == "tool_result"
      WCall( "toolResult", RTrimEOL( StrTran( Left( hb_CStr( hEv[ "content" ] ), 400 ), Chr( 13 ), "" ) ) )
   CASE hEv[ "type" ] == "error"
      WCall( "errMsg", hb_CStr( hEv[ "message" ] ) )
   ENDCASE
RETURN NIL

// ---------------------------------------------------------------------------
// Tools + permission gate (per agent).
// ---------------------------------------------------------------------------
STATIC FUNCTION BuildTools( lTeam )
   LOCAL oReg := {=>}, bRaw
   IF lTeam == NIL ; lTeam := .T. ; ENDIF   // workers build without dispatch (no recursion)
   CCTOOLS_Register( oReg, CCTool_Read() )
   CCTOOLS_Register( oReg, CCTool_Write() )
   CCTOOLS_Register( oReg, CCTool_Edit() )
   CCTOOLS_Register( oReg, CCTool_Glob() )
   CCTOOLS_Register( oReg, CCTool_Grep() )
   CCTOOLS_Register( oReg, CCTool_Shell( "", 30 ) )
   CCTOOLS_Register( oReg, CCTool_WebSearch() )
   CCTOOLS_Register( oReg, CCTool_WebFetch() )
   CCTOOLS_Register( oReg, CCTool_Memory( "memory_" + LTrim( Str( t_nId ) ) + ".md" ) )
   CCTOOLS_Register( oReg, GuiAskUser() )
   CCTOOLS_Register( oReg, CCTool_GhRead() )
   CCTOOLS_Register( oReg, CCTool_GhList() )
   CCTOOLS_Register( oReg, CCTool_GhWrite() )
   IF lTeam
      CCTOOLS_Register( oReg, TeamTool() )   // dispatch_team (coordinator only)
   ENDIF
   t_aSchemas := CCTOOLS_Schemas( oReg )
   bRaw := CCTOOLS_Executor( oReg )
   t_bExec := {| cName, cArgs | GateTool( bRaw, cName, cArgs ) }
RETURN NIL

// ---------------------------------------------------------------------------
// dispatch_team: run independent subtasks on parallel agent threads and
// SYNCHRONIZE (join) before returning the combined result. Each subtask gets
// its own visible agent tab streaming live.
// ---------------------------------------------------------------------------
STATIC FUNCTION TeamTool()
   RETURN { "name" => "dispatch_team", ;
            "description" => "Run 2 to 4 INDEPENDENT subtasks in parallel, each " + ;
               "on its own agent, then wait for all and return the combined " + ;
               "results. Use to split a task into parts that do not depend on " + ;
               "each other. Each item is a self-contained instruction.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "tasks" => { "type" => "array", "items" => { "type" => "string" }, ;
                               "description" => "2 to 4 independent subtasks" } }, ;
               "required" => { "tasks" } }, ;
            "handler" => {| hArgs | TeamRun( hArgs ) } }

STATIC FUNCTION TeamRun( hArgs )
   LOCAL aTasks, aTh := {}, aRes, oMtx, i, nId, nBase, cOut

   aTasks := hArgs[ "tasks" ]
   IF ValType( aTasks ) != "A" .OR. Len( aTasks ) < 2
      RETURN "Error: 'tasks' must be an array of at least 2 subtasks."
   ENDIF
   IF Len( aTasks ) > 4
      aTasks := { aTasks[ 1 ], aTasks[ 2 ], aTasks[ 3 ], aTasks[ 4 ] }
   ENDIF

   aRes := Array( Len( aTasks ) )
   oMtx := hb_mutexCreate()
   WCall( "addNote", "Dispatching " + LTrim( Str( Len( aTasks ) ) ) + ;
          " sub-agents in parallel, then syncing (join)..." )

   nBase := Len( s_aAgents )
   FOR i := 1 TO Len( aTasks )
      nId := nBase + i
      AAdd( s_aAgents, { "id" => nId } )
      AWV_Eval( "newAgentTab(" + LTrim( Str( nId ) ) + ")" )
      AAdd( aTh, hb_threadStart( {| n, t, id | Worker( n, t, id, aRes, oMtx ) }, ;
                                 i, aTasks[ i ], nId ) )
   NEXT

   // SYNCHRONIZE: block until every sub-agent thread has finished.
   AEval( aTh, {| h | hb_threadJoin( h ) } )

   cOut := "All " + LTrim( Str( Len( aTasks ) ) ) + " sub-agents finished. Combined:" + Chr( 10 )
   FOR i := 1 TO Len( aRes )
      cOut += Chr( 10 ) + LTrim( Str( i ) ) + ") " + hb_CStr( aRes[ i ] )
   NEXT
RETURN cOut

// One sub-agent thread: runs its subtask in its own visible tab, stores result.
FUNCTION Worker( nIdx, cTask, nId, aRes, oMtx )
   LOCAL oCli, aMsg, hRes, cAns
   t_nId    := nId          // THREAD STATIC -> WCall/OnEvent target this tab
   t_lYolo  := .T.
   t_lStop  := .F.
   t_nTurn  := 1

   WCall( "addUser", cTask )
   WCall( "startTurn", "1", Time() )
   WCall( "setRunning", "1" )
   WCall( "setStatus", "Working...", "busy" )

   oCli := CC_Client( { "model" => "deepseek-chat", "timeout" => 120, ;
                        "api_key" => ReadKeyFile() } )
   aMsg := { { "role" => "system", "content" => "You are a sub-agent. Do exactly " + ;
              "this one subtask and answer briefly. Working dir: " + AWV_FilesDir() + "." }, ;
             { "role" => "user", "content" => cTask } }
   BuildTools( .F. )        // no dispatch_team in workers

   hRes := CC_AgentRun( oCli, aMsg, { "model" => "deepseek-chat", ;
              "tools" => t_aSchemas, "tool_executor" => t_bExec, ;
              "transport" => {| q, b | DroidTransport( q, b ) }, ;
              "max_iterations" => 6 }, {| hEv | OnEvent( hEv ) } )

   WCall( "finalizeTurn" )
   WCall( "setRunning", "0" )
   WCall( "setStatus", "Done.", "idle" )

   cAns := LastAssistant( hRes )
   hb_mutexLock( oMtx )
   aRes[ nIdx ] := Left( hb_CStr( cTask ), 50 ) + " => " + cAns
   hb_mutexUnlock( oMtx )
RETURN NIL

STATIC FUNCTION LastAssistant( hRes )
   LOCAL aMsgs, i, m
   IF ValType( hRes ) != "H" .OR. !hRes[ "success" ]
      RETURN "(error)"
   ENDIF
   aMsgs := hRes[ "messages" ]
   FOR i := Len( aMsgs ) TO 1 STEP -1
      m := aMsgs[ i ]
      IF m[ "role" ] == "assistant" .AND. !Empty( hb_HGetDef( m, "content", "" ) )
         RETURN Left( hb_CStr( m[ "content" ] ), 120 )
      ENDIF
   NEXT
RETURN "(no answer)"

STATIC FUNCTION GateTool( bRaw, cName, cArgs )
   IF ( cName == "shell" .OR. cName == "write" .OR. cName == "edit" ) .AND. !t_lYolo
      IF !AskPermission( cName, cArgs )
         RETURN "Error: the user rejected running '" + cName + "'. Do not retry it."
      ENDIF
   ENDIF
   RETURN Eval( bRaw, cName, cArgs )

STATIC FUNCTION AskPermission( cName, cArgs )
   LOCAL aEv
   t_cPermit := NIL
   WCall( "permitCard", hb_jsonEncode( { "name" => cName, "args" => hb_CStr( cArgs ) } ) )
   WCall( "setStatus", "Esperando autorizacion...", "busy" )
   DO WHILE t_cPermit == NIL .AND. !t_lStop
      aEv := AWV_WaitEvent( t_nId )    // blocks for this agent's next event
      OnJsMessage( aEv )               // sets t_cPermit / t_lStop
   ENDDO
   WCall( "setStatus", "Working...", "busy" )
RETURN ( t_cPermit == "1" )

STATIC FUNCTION GuiAskUser()
   RETURN { "name" => "ask_user", ;
            "description" => "Ask the user a multiple-choice question and return their answer.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "question" => { "type" => "string", "description" => "The question" }, ;
                  "options" => { "type" => "array", "items" => { "type" => "string" }, ;
                                 "description" => "2 to 4 choices" } }, ;
               "required" => { "question", "options" } }, ;
            "handler" => {| hArgs | GuiAskRun( hArgs ) } }

STATIC FUNCTION GuiAskRun( hArgs )
   LOCAL aEv
   IF ValType( hArgs[ "options" ] ) != "A" .OR. Len( hArgs[ "options" ] ) < 2
      RETURN "Error: 'options' must be an array of at least 2 strings"
   ENDIF
   t_cAskAnswer := NIL
   WCall( "askCard", hb_jsonEncode( { "q" => hb_CStr( hArgs[ "question" ] ), "opts" => hArgs[ "options" ] } ) )
   WCall( "setStatus", "Waiting for your choice...", "busy" )
   DO WHILE t_cAskAnswer == NIL .AND. !t_lStop
      aEv := AWV_WaitEvent( t_nId )
      OnJsMessage( aEv )
   ENDDO
   IF t_lStop .OR. t_cAskAnswer == NIL
      RETURN "User stopped without answering."
   ENDIF
   WCall( "setStatus", "Working...", "busy" )
RETURN "The user selected: " + t_cAskAnswer

// In-app changelog (kept in sync with Android/whatsnew.txt on the PC).
STATIC FUNCTION WhatsNew()
   RETURN "v1.5 (2026-06-09)" + Chr( 10 ) + ;
          "- GitHub via REST API: tools github_read / github_list / github_write." + Chr( 10 ) + ;
          "  Token con /ghtoken; si falta, el agente propone configurarlo." + Chr( 10 ) + Chr( 10 ) + ;
          "v1.4 (2026-06-09)" + Chr( 10 ) + ;
          "- Modo horizontal: las pestanas pasan a barra lateral izquierda." + Chr( 10 ) + ;
          "- Card renombrada 'Whatsnew'." + Chr( 10 ) + Chr( 10 ) + ;
          "v1.2 (2026-06-09)" + Chr( 10 ) + ;
          "- Multi-agente sincronizado: tool dispatch_team reparte una tarea en" + Chr( 10 ) + ;
          "  2-4 sub-agentes en paralelo y los une (hb_threadJoin)." + Chr( 10 ) + ;
          "- Toggle Auto-aprobar en el menu; tabs mas pequenos." + Chr( 10 ) + Chr( 10 ) + ;
          "v1.0 (2026-06-09) - Primer release publico." + Chr( 10 ) + ;
          "- Tabs 'Agent N'; gafas del fondo oscuras (como el icono)." + Chr( 10 ) + Chr( 10 ) + ;
          "v0.9 (2026-06-09)" + Chr( 10 ) + ;
          "- Acerca de: version Harbour, (c) FiveTech Software 2026, contacto." + Chr( 10 ) + ;
          "- Fondo watermark mas intenso." + Chr( 10 ) + Chr( 10 ) + ;
          "v0.8 (2026-06-09)" + Chr( 10 ) + ;
          "- 'Acerca de' en el menu: hecho en Harbour con el API de ccharbour." + Chr( 10 ) + ;
          "- Fondo watermark mas visible." + Chr( 10 ) + Chr( 10 ) + ;
          "v0.7 (2026-06-09)" + Chr( 10 ) + ;
          "- Sin barra de titulo 'Agents' (mas espacio)." + Chr( 10 ) + ;
          "- Menu de 3 puntos fijado arriba a la derecha." + Chr( 10 ) + Chr( 10 ) + ;
          "v0.6 (2026-06-09)" + Chr( 10 ) + ;
          "- Pestanas (tabs) para los agentes." + Chr( 10 ) + ;
          "- Fondo watermark del icono (estilo WhatsApp)." + Chr( 10 ) + ;
          "- Tamano de texto in-app + menu config (3 puntos arriba dcha)." + Chr( 10 ) + ;
          "- Boton de microfono (dictado por voz)." + Chr( 10 ) + Chr( 10 ) + ;
          "v0.5 (2026-06-09)" + Chr( 10 ) + ;
          "- Diffs en color: + verde / - rojo en write/edit." + Chr( 10 ) + ;
          "- Font mas pequeno (text-sm; es un ajuste de la app, no global)." + Chr( 10 ) + Chr( 10 ) + ;
          "v0.4 (2026-06-09)" + Chr( 10 ) + ;
          "- Multi-agente ACTIVADO: cada agente en su propio hilo Harbour (MT)." + Chr( 10 ) + ;
          "  Pulsa '+' para abrir mas agentes en paralelo." + Chr( 10 ) + Chr( 10 ) + ;
          "v0.3 (2026-06-09)" + Chr( 10 ) + ;
          "- Identidad del system prompt: 'You are Agents...'." + Chr( 10 ) + Chr( 10 ) + ;
          "v0.2 (2026-06-09)" + Chr( 10 ) + ;
          "- Directorio de trabajo escribible: memory / write / edit funcionan." + Chr( 10 ) + ;
          "- Icono: cara con gafas de sol (emoji)." + Chr( 10 ) + ;
          "- Card de Novedades al arrancar." + Chr( 10 ) + Chr( 10 ) + ;
          "v0.1 (2026-06-09) - Primer build funcional en Android, 100% Harbour." + Chr( 10 ) + ;
          "- WebView con el panel de chat; ccharbour arm64-v8a." + Chr( 10 ) + ;
          "- Transporte LLM via Java HttpsURLConnection (sin curl/openssl)." + Chr( 10 ) + ;
          "- DeepSeek respondiendo en el movil; markdown (marked.js)." + Chr( 10 ) + ;
          "- API key desde fichero local; /key override; boton de envio." + Chr( 10 ) + ;
          "Pendiente: multi-agente concurrente (hb_threadStart), streaming."

// /plan, real: ask the LLM to break the task into steps and render the plan card.
STATIC FUNCTION PlanReal( cTask )
   LOCAL aMsg, hRes, cAns, cJson, oErr, hPlan
   WCall( "addUser", "/plan " + cTask )
   WCall( "setStatus", "Generando plan...", "busy" )
   WCall( "setRunning", "1" )

   aMsg := { { "role" => "system", "content" => ;
             "You are a planner. Break the user's task into 3 to 6 short concrete " + ;
             "steps. Reply ONLY with compact JSON (real double quotes): an object " + ;
             "with key 'steps', an array of objects each with keys 'title' (string) " + ;
             "and 'state'. Make the FIRST step state 'active' and the rest 'pending'. " + ;
             "No markdown, no prose, JSON only." }, ;
             { "role" => "user", "content" => cTask } }

   BEGIN SEQUENCE WITH {| o | Break( o ) }
      hRes := CC_AgentRun( t_oClient, aMsg, ;
                 { "model" => "deepseek-chat", "transport" => t_bTransport, ;
                   "max_iterations" => 1 }, NIL )
      cAns  := LastAssistant( hRes )
   RECOVER USING oErr
      cAns := ""
   END SEQUENCE

   cJson := ExtractJson( cAns )
   hPlan := hb_jsonDecode( cJson )       // direct-return form
   IF ValType( hPlan ) == "H" .AND. hb_HHasKey( hPlan, "steps" )
      WCall( "planCard", hb_jsonEncode( hPlan ) )
   ELSE
      WCall( "planCard", cJson )        // let the page try JSON.parse as a fallback
   ENDIF
   WCall( "setRunning", "0" )
   WCall( "setStatus", "Ready.", "idle" )
RETURN NIL

STATIC FUNCTION ExtractJson( cText )
   LOCAL n1, n2, c
   cText := hb_CStr( cText )
   n1 := At( "{", cText )
   n2 := RAt( "}", cText )
   IF n1 == 0 .OR. n2 <= n1
      RETURN '{"steps":[]}'
   ENDIF
   c := SubStr( cText, n1, n2 - n1 + 1 )
   // normalize: collapse newlines/tabs and strip trailing commas (LLMs add them)
   c := StrTran( StrTran( StrTran( c, Chr( 13 ), " " ), Chr( 10 ), " " ), Chr( 9 ), " " )
   DO WHILE ", }" $ c .OR. ", ]" $ c .OR. ",}" $ c .OR. ",]" $ c
      c := StrTran( StrTran( StrTran( StrTran( c, ", }", " }" ), ", ]", " ]" ), ",}", "}" ), ",]", "]" )
   ENDDO
RETURN c

STATIC FUNCTION SystemPrompt()
   RETURN "You are Agents, a coding agent running on Android. Be concise. " + ;
          "Your writable working directory is " + AWV_FilesDir() + " (use relative " + ;
          "paths there for read/write/edit/memory; the rest of the filesystem " + ;
          "is mostly read-only on Android). When a request naturally splits into " + ;
          "2-4 INDEPENDENT parts, call the dispatch_team tool with the list of " + ;
          "subtasks - they run in parallel on separate agents and are joined " + ;
          "(synchronized) before you get the combined result."

// Reads the LLM API key from a local file on the device, if present. Lets the
// app pick up the key without an env var. /key in chat still overrides at runtime.
STATIC FUNCTION ReadKeyFile()
   LOCAL cKey := ""
   LOCAL aPaths := { "/data/local/tmp/deepseek.key", ;
                     "/sdcard/Download/deepseek.key" }
   LOCAL cPath, c
   FOR EACH cPath IN aPaths
      c := hb_MemoRead( cPath )
      IF !Empty( c )
         cKey := AllTrim( StrTran( StrTran( c, Chr( 13 ), "" ), Chr( 10 ), "" ) )
         EXIT
      ENDIF
   NEXT
RETURN cKey

// ---------------------------------------------------------------------------
// HTTP transport via Java (no libcurl). First cut: non-streaming - the whole
// body is fed to the SSE parser at once (the live token stream is a TODO that
// needs a per-chunk JNI callback from the Java reader).
// ---------------------------------------------------------------------------
STATIC FUNCTION DroidTransport( hReq, bOnChunk )
   LOCAL hHttp, cHeaders := ""
   LOCAL aH := hReq[ "headers" ], cH

   FOR EACH cH IN aH
      cHeaders += cH + Chr( 10 )
   NEXT

   hHttp := AWV_Http( "POST", hReq[ "url" ], cHeaders, hReq[ "body" ], ;
                      iif( hb_HHasKey( hReq, "timeout" ), hReq[ "timeout" ], 120 ) )

   IF hHttp[ "ok" ]
      Eval( bOnChunk, hHttp[ "body" ] )
   ENDIF

   RETURN { "ok" => hHttp[ "ok" ], "status" => hHttp[ "status" ], ;
            "curl_code" => iif( hHttp[ "ok" ], 0, 1 ), ;
            "error" => iif( hHttp[ "ok" ], NIL, "http error" ) }

// ---------------------------------------------------------------------------
// GitHub tools over the REST API (HTTPS via the Java transport). No git binary,
// no SSH - clone/read/write files through api.github.com.
// ---------------------------------------------------------------------------
STATIC FUNCTION GhToken()
   LOCAL c
   IF s_cGhToken != NIL .AND. !Empty( s_cGhToken )
      RETURN s_cGhToken
   ENDIF
   c := hb_MemoRead( "/data/local/tmp/github.token" )
   IF Empty( c )
      c := hb_MemoRead( "/sdcard/Download/github.token" )
   ENDIF
RETURN AllTrim( StrTran( StrTran( hb_CStr( c ), Chr( 13 ), "" ), Chr( 10 ), "" ) )

// Proposed setup text returned when the token is missing.
STATIC FUNCTION GhNeedToken()
   RETURN "No GitHub token configured. To enable GitHub, set a personal access " + ;
          "token (repo scope) either by telling the user to run " + ;
          "'/ghtoken <token>' in the app, or push it with " + ;
          "'adb push token /data/local/tmp/github.token'. Ask the user to do " + ;
          "this, then retry."

STATIC FUNCTION GhHttp( cMethod, cUrl, cBody )
   LOCAL cTok := GhToken(), cHdr
   cHdr := "Accept: application/vnd.github+json" + Chr( 10 ) + ;
           "User-Agent: Agents-app" + Chr( 10 ) + ;
           "X-GitHub-Api-Version: 2022-11-28" + Chr( 10 ) + ;
           "Content-Type: application/json"
   IF !Empty( cTok )
      cHdr += Chr( 10 ) + "Authorization: Bearer " + cTok
   ENDIF
RETURN AWV_Http( cMethod, cUrl, cHdr, iif( cBody == NIL, "", cBody ), 60 )

STATIC FUNCTION GhContentsUrl( cRepo, cPath )
   RETURN "https://api.github.com/repos/" + cRepo + "/contents/" + cPath

STATIC FUNCTION CCTool_GhRead()
   RETURN { "name" => "github_read", ;
            "description" => "Read a file from a GitHub repo via the REST API. " + ;
               "repo is 'owner/name', path is the file path in the repo.", ;
            "parameters" => { "type" => "object", "properties" => { ;
               "repo" => { "type" => "string", "description" => "owner/name" }, ;
               "path" => { "type" => "string", "description" => "file path" } }, ;
               "required" => { "repo", "path" } }, ;
            "handler" => {| h | GhReadRun( h ) } }

STATIC FUNCTION GhReadRun( hArgs )
   LOCAL hHttp, hJ := NIL, cB64
   hHttp := GhHttp( "GET", GhContentsUrl( hArgs[ "repo" ], hArgs[ "path" ] ) )
   IF hHttp[ "status" ] == 404
      RETURN "Not found: " + hArgs[ "path" ] + " in " + hArgs[ "repo" ]
   ENDIF
   IF !hHttp[ "ok" ]
      RETURN "GitHub error " + LTrim( Str( hHttp[ "status" ] ) ) + ": " + Left( hHttp[ "body" ], 200 )
   ENDIF
   hb_jsonDecode( hHttp[ "body" ], @hJ )
   IF ValType( hJ ) == "H" .AND. hb_HHasKey( hJ, "content" )
      cB64 := StrTran( StrTran( hb_CStr( hJ[ "content" ] ), Chr( 10 ), "" ), Chr( 13 ), "" )
      RETURN hb_base64Decode( cB64 )
   ENDIF
RETURN "Unexpected response: " + Left( hHttp[ "body" ], 200 )

STATIC FUNCTION CCTool_GhList()
   RETURN { "name" => "github_list", ;
            "description" => "List a directory of a GitHub repo (REST API). " + ;
               "repo 'owner/name', path is the directory ('' for root).", ;
            "parameters" => { "type" => "object", "properties" => { ;
               "repo" => { "type" => "string" }, "path" => { "type" => "string" } }, ;
               "required" => { "repo" } }, ;
            "handler" => {| h | GhListRun( h ) } }

STATIC FUNCTION GhListRun( hArgs )
   LOCAL hHttp, aJ := NIL, cOut := "", e
   hHttp := GhHttp( "GET", GhContentsUrl( hArgs[ "repo" ], hb_HGetDef( hArgs, "path", "" ) ) )
   IF !hHttp[ "ok" ]
      RETURN "GitHub error " + LTrim( Str( hHttp[ "status" ] ) ) + ": " + Left( hHttp[ "body" ], 200 )
   ENDIF
   hb_jsonDecode( hHttp[ "body" ], @aJ )
   IF ValType( aJ ) != "A"
      RETURN "Not a directory or empty."
   ENDIF
   FOR EACH e IN aJ
      cOut += hb_HGetDef( e, "type", "?" ) + "  " + hb_HGetDef( e, "name", "?" ) + Chr( 10 )
   NEXT
RETURN cOut

STATIC FUNCTION CCTool_GhWrite()
   RETURN { "name" => "github_write", ;
            "description" => "Create or update a file in a GitHub repo (REST API), " + ;
               "i.e. commit+push a single file. Needs a configured token.", ;
            "parameters" => { "type" => "object", "properties" => { ;
               "repo" => { "type" => "string", "description" => "owner/name" }, ;
               "path" => { "type" => "string" }, ;
               "content" => { "type" => "string", "description" => "new file content" }, ;
               "message" => { "type" => "string", "description" => "commit message" } }, ;
               "required" => { "repo", "path", "content", "message" } }, ;
            "handler" => {| h | GhWriteRun( h ) } }

STATIC FUNCTION GhWriteRun( hArgs )
   LOCAL cUrl, hGet, hJ := NIL, cSha := "", hBody, cBodyJson, hPut

   IF Empty( GhToken() )
      RETURN GhNeedToken()
   ENDIF
   cUrl := GhContentsUrl( hArgs[ "repo" ], hArgs[ "path" ] )

   hGet := GhHttp( "GET", cUrl )          // existing file -> need its sha to update
   IF hGet[ "ok" ]
      hb_jsonDecode( hGet[ "body" ], @hJ )
      IF ValType( hJ ) == "H"
         cSha := hb_HGetDef( hJ, "sha", "" )
      ENDIF
   ENDIF

   hBody := { "message" => hArgs[ "message" ], ;
              "content" => hb_base64Encode( hb_CStr( hArgs[ "content" ] ) ) }
   IF !Empty( cSha )
      hBody[ "sha" ] := cSha
   ENDIF
   cBodyJson := hb_jsonEncode( hBody )

   hPut := GhHttp( "PUT", cUrl, cBodyJson )
   IF hPut[ "status" ] == 200 .OR. hPut[ "status" ] == 201
      RETURN "Committed " + hArgs[ "path" ] + " to " + hArgs[ "repo" ] + ;
             iif( Empty( cSha ), " (created)", " (updated)" )
   ENDIF
RETURN "GitHub write error " + LTrim( Str( hPut[ "status" ] ) ) + ": " + Left( hPut[ "body" ], 200 )

// ---------------------------------------------------------------------------
// PRG -> page. AWV_Eval routes the JS to the (single) WebView; the JS helpers
// take the agent id as their first argument so each agent updates its own tab.
// ---------------------------------------------------------------------------
STATIC FUNCTION WCall( cFunc )
   LOCAL aArgs := hb_AParams(), cJs := cFunc + "(" + LTrim( Str( t_nId ) ), i
   FOR i := 2 TO Len( aArgs )
      cJs += "," + hb_jsonEncode( hb_CStr( aArgs[ i ] ) )
   NEXT
   cJs += ")"
   AWV_Eval( cJs )
RETURN NIL

STATIC FUNCTION RTrimEOL( cText )
   DO WHILE Len( cText ) > 0 .AND. ;
            ( Right( cText, 1 ) == Chr( 10 ) .OR. Right( cText, 1 ) == Chr( 13 ) )
      cText := Left( cText, Len( cText ) - 1 )
   ENDDO
RETURN cText

// ---------------------------------------------------------------------------
// HTML chat panel - multi-agent (tab bar + one panel per agent). Every JS
// helper takes the agent id first and targets that agent's DOM. (Markdown/diff
// rendering ported from the desktop sample is a follow-up.)
// ---------------------------------------------------------------------------
STATIC FUNCTION ChatHtml()
   LOCAL cHtml
   TEXT INTO cHtml
<!DOCTYPE html><html lang="es"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>FWH Agentic AI</title>
<script src="https://cdn.tailwindcss.com"></script>
<script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
<style>
  /* WhatsApp-style faint tiled watermark of the sunglasses icon behind the chat */
  #panels { background-color:#0b141a;
    background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='96' height='96' viewBox='0 0 96 96'%3E%3Cg opacity='0.5'%3E%3Ccircle cx='48' cy='48' r='22' fill='%23FFCC4D'/%3E%3Crect x='27' y='39' width='42' height='5' fill='%23292F33'/%3E%3Cellipse cx='38' cy='48' rx='9' ry='7' fill='%23292F33'/%3E%3Cellipse cx='58' cy='48' rx='9' ry='7' fill='%23292F33'/%3E%3C/g%3E%3C/svg%3E");
    background-repeat:repeat; }
  .tab { padding:4px 10px; white-space:nowrap; border-top-left-radius:8px; border-top-right-radius:8px;
         font-size:.72rem; margin-bottom:-1px; cursor:pointer; }
  .tab-on  { background:#0b141a; color:#fff; border:1px solid #374151; border-bottom:1px solid #0b141a; font-weight:600; }
  .tab-off { background:#273244; color:#9ca3af; border:1px solid transparent; }
  .fbtn { width:30px; height:30px; border-radius:8px; background:#273244; color:#cbd5e1; font-weight:700; }

  /* Landscape: tabs become a vertical sidebar on the left, chat fills the right */
  @media (orientation: landscape) {
    #app { flex-direction: row; }
    #tabs { flex-direction: column; align-items: stretch;
            width: 150px; max-width: 38vw; overflow-y: auto; overflow-x: hidden;
            border-right: 1px solid #374151; border-bottom: none; padding: 8px 6px 60px 6px; gap: 4px; }
    #tabs .tab { border-radius: 8px; margin-bottom: 0; text-align: left; }
    #tabs .tab-on { border-bottom: 1px solid #374151; }
  }
</style>
</head>
<body class="bg-gray-900 text-gray-100 h-screen overflow-hidden font-sans text-sm">
<div id="app" class="flex flex-col h-full">
  <div id="tabs" class="flex items-center gap-1 px-2 pt-2 bg-gray-800 border-b border-gray-700 shrink-0 overflow-x-auto"></div>
  <div id="main" class="flex-1 flex flex-col min-w-0 min-h-0">
  <div id="panels" class="flex-1 relative overflow-hidden"></div>
  <div class="p-2 border-t border-gray-700 bg-gray-900 shrink-0 flex items-center gap-2">
    <button id="micbtn" onclick="toggleMic()" class="shrink-0 bg-gray-700 hover:bg-gray-600 text-gray-200 rounded-lg w-11 h-11 flex items-center justify-center">
      <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"></path><path d="M19 10v2a7 7 0 0 1-14 0v-2"></path><line x1="12" y1="19" x2="12" y2="23"></line><line x1="8" y1="23" x2="16" y2="23"></line></svg>
    </button>
    <div class="relative flex-1">
      <input id="prompt" type="text" placeholder="Pregunta algo..." enterkeyhint="send"
        onkeydown="if(event.key==='Enter'){event.preventDefault();sendPrompt();}"
        class="w-full bg-gray-800 border border-gray-700 rounded-lg pl-4 pr-14 py-3 focus:outline-none focus:border-blue-500 text-gray-200">
      <button id="sendbtn" onclick="sendPrompt()"
        class="absolute right-1.5 top-1/2 -translate-y-1/2 bg-blue-600 hover:bg-blue-500 text-white rounded-lg w-10 h-10 flex items-center justify-center">
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="22" y1="2" x2="11" y2="13"></line><polygon points="22 2 15 22 11 13 2 9 22 2"></polygon></svg>
      </button>
    </div>
  </div>
  </div>
</div>
<script>
  let cur = 0;
  const A = {};                         // agent id -> { chat, running, turn, curMsg }
  function send(id, action, text){ Android.send(id, action, text||''); }
  function el(h){ const t=document.createElement('template'); t.innerHTML=h.trim(); return t.content.firstChild; }
  function panel(id){ return A[id] && A[id].chat; }
  function down(id){ const c=panel(id); if(c) c.scrollTop=c.scrollHeight; }
  function show(id){
    cur=id;
    document.querySelectorAll('#panels > div').forEach(function(p){ p.style.display='none'; });
    document.querySelectorAll('#tabs button').forEach(function(b){ b.className=tabCls(false); });
    const p=document.getElementById('p'+id); if(p) p.style.display='block';
    const t=document.getElementById('t'+id); if(t) t.className=tabCls(true);
  }
  function tabCls(on){ return 'tab '+(on?'tab-on':'tab-off'); }
  function applyFont(px){ px=Math.max(11,Math.min(22,px)); document.documentElement.style.fontSize=px+'px'; try{localStorage.setItem('fs',px);}catch(e){} }
  function bumpFont(d){ let px=16; try{px=parseInt(localStorage.getItem('fs')||'15');}catch(e){} applyFont(px+d); }

  function newAgentTab(id){
    const t=el('<button id="t'+id+'" onclick="show('+id+')"></button>');
    t.className=tabCls(false); t.textContent='Agent '+id;
    document.getElementById('tabs').appendChild(t);
    const p=el('<div id="p'+id+'" class="absolute inset-0 overflow-y-auto p-3 space-y-4"></div>');
    document.getElementById('panels').appendChild(p);
    A[id]={ chat:p, running:false, turn:null, curMsg:null };
    show(id);
  }

  function addUser(id, text){ const c=panel(id); if(!c)return;
    const d=el('<div class="flex justify-end"><div class="bg-blue-600 text-white p-3 rounded-xl rounded-tr-none max-w-[85%] whitespace-pre-wrap"></div></div>');
    d.firstElementChild.textContent=text; c.appendChild(d); down(id); }
  function startTurn(id, n, ts){ const c=panel(id); if(!c)return;
    c.appendChild(el('<div class="text-xs text-white text-center">Turn '+n+' · '+ts+'</div>'));
    A[id].turn=el('<div class="flex flex-col space-y-3 max-w-[95%]"></div>'); c.appendChild(A[id].turn);
    A[id].curMsg=null; down(id); }
  function aDelta(id, text){ const a=A[id]; if(!a||!a.turn)return;
    if(!a.curMsg){ a.curMsg=el('<div class="amsg bg-gray-800 border border-gray-700 p-3 rounded-xl rounded-tl-none whitespace-pre-wrap"></div>'); a.curMsg._raw=''; a.turn.appendChild(a.curMsg); }
    a.curMsg._raw+=text; a.curMsg.textContent=a.curMsg._raw; down(id); }
  function finalizeTurn(id){ const a=A[id]; if(!a||!a.turn||!window.marked)return;
    a.turn.querySelectorAll('.amsg').forEach(function(b){ if(b._raw!=null){ b.innerHTML=marked.parse(b._raw); } }); a.curMsg=null; down(id); }
  function toolCall(id, name, args){ const a=A[id]; if(!a||!a.turn)return; a.curMsg=null;
    const r=el('<div class="text-xs text-gray-300 bg-gray-800/50 border border-gray-700 rounded p-2"></div>');
    r.textContent='▸ '+name+'  '+args; a.turn.appendChild(r); down(id); }
  function toolResult(id, text){ const a=A[id]; if(!a||!a.turn)return;
    const box=el('<div class="text-xs border-l-2 border-green-600 pl-3 font-mono leading-snug"></div>');
    (text||'').split(String.fromCharCode(10)).forEach(function(ln){
      const row=document.createElement('div'); row.style.whiteSpace='pre-wrap'; row.style.wordBreak='break-word';
      const m=ln.match(/^( *[0-9]+) ([-+ ]) (.*)$/);
      if(m&&m[2]==='+'){ row.style.color='#86efac'; row.style.background='rgba(34,197,94,.18)'; }
      else if(m&&m[2]==='-'){ row.style.color='#fca5a5'; row.style.background='rgba(239,68,68,.18)'; }
      else { row.style.color='#9ca3af'; }
      row.textContent=ln; box.appendChild(row);
    });
    a.turn.appendChild(box); down(id); }
  function errMsg(id, text){ const a=A[id]; if(!a||!a.turn)return;
    const r=el('<div class="text-xs text-red-300 bg-red-900/40 border border-red-700/50 p-2 rounded whitespace-pre-wrap"></div>');
    r.textContent='ERROR: '+text; a.turn.appendChild(r); down(id); }
  function addNote(id, text){ const c=panel(id); if(!c)return;
    const r=el('<div class="text-xs text-gray-400 bg-gray-800/40 border border-gray-700 rounded p-2 whitespace-pre-wrap"></div>');
    r.textContent=text; c.appendChild(r); down(id); }
  function whatsNew(id, text){ const c=panel(id); if(!c)return;
    const ver=(text.split(String.fromCharCode(10))[0]||'').trim();   // "v0.5 (..)"
    const card=el('<div class="bg-blue-900/30 border border-blue-700/50 rounded-lg overflow-hidden"></div>');
    const btn=el('<button class="w-full text-left px-3 py-2 text-sm font-semibold text-blue-200 flex justify-between items-center"></button>');
    const t=document.createElement('span'); t.textContent='Whatsnew  ·  '+ver;
    const chev=document.createElement('span'); chev.textContent='▼'; btn.appendChild(t); btn.appendChild(chev);
    const body=el('<div class="px-3 pb-3 text-xs text-gray-300 whitespace-pre-wrap"></div>'); body.textContent=text;
    btn.onclick=function(){ body.style.display=(body.style.display==='none'?'block':'none'); };
    card.appendChild(btn); card.appendChild(body); c.appendChild(card);
    c.scrollTop=0;   // keep the version line in view on startup
  }
  function userBubble(id, text){ const c=panel(id); if(!c)return;
    const d=el('<div class="flex justify-end mb-1"><div class="bg-blue-600 text-white p-2 px-4 rounded-xl rounded-tr-none text-xs font-mono"></div></div>');
    d.firstElementChild.textContent=text; c.appendChild(d); down(id); }

  // /goal -> "Objetivo Activo" card
  function goalCard(id, text){ const c=panel(id); if(!c)return; userBubble(id,'/goal');
    const card=el('<div class="bg-gradient-to-br from-indigo-900/40 to-gray-800 border border-indigo-500/50 p-4 rounded-xl shadow-sm relative overflow-hidden"></div>');
    card.innerHTML='<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1" class="absolute -right-4 -bottom-4 text-indigo-500/10"><circle cx="12" cy="12" r="10"></circle><circle cx="12" cy="12" r="6"></circle><circle cx="12" cy="12" r="2"></circle></svg>'+
      '<div class="flex items-start gap-3 relative z-10"><div class="p-2 bg-indigo-500/20 text-indigo-400 rounded-lg shrink-0 mt-0.5"><svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"></circle><circle cx="12" cy="12" r="6"></circle><circle cx="12" cy="12" r="2"></circle></svg></div>'+
      '<div><h4 class="text-indigo-300 font-semibold text-xs uppercase tracking-wider mb-1">Objetivo Activo</h4><p class="text-gray-200 text-sm leading-relaxed goaltext"></p></div></div>';
    card.querySelector('.goaltext').textContent=text||'(sin objetivo definido)'; c.appendChild(card); down(id); }

  // /plan -> "Plan de Accion" timeline. steps: [{title,state}] state=done|active|pending
  function planCard(id, json){ const c=panel(id); if(!c)return; userBubble(id,'/plan');
    let d; try{ d=JSON.parse(json); }catch(e){ d={steps:[]}; }
    const steps=d.steps||[]; const done=steps.filter(function(s){return s.state==='done';}).length;
    const card=el('<div class="bg-gray-800 border border-gray-700 p-4 rounded-xl shadow-sm"></div>');
    card.innerHTML='<div class="flex items-center justify-between mb-4 pb-2 border-b border-gray-700"><h4 class="text-sm font-semibold text-gray-200 flex items-center gap-2"><svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="text-blue-400"><path d="M9 11l3 3L22 4"></path><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"></path></svg>Plan de Accion</h4><span class="text-[10px] bg-blue-900/50 text-blue-300 px-2 py-1 rounded font-medium">'+done+' / '+steps.length+' Completado</span></div><div class="planbody space-y-4 relative before:absolute before:inset-0 before:ml-2.5 before:-translate-x-px before:h-full before:w-0.5 before:bg-gradient-to-b before:from-green-500 before:via-blue-500 before:to-gray-700"></div>';
    const body=card.querySelector('.planbody');
    steps.forEach(function(s){
      let dot,cls;
      if(s.state==='done'){ dot='<div class="h-5 w-5 rounded-full bg-green-500 border-4 border-gray-800 flex items-center justify-center shrink-0 z-10"><svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="3"><polyline points="20 6 9 17 4 12"></polyline></svg></div>'; cls='text-xs font-semibold text-gray-300 line-through'; }
      else if(s.state==='active'){ dot='<div class="h-5 w-5 rounded-full bg-blue-500 border-4 border-gray-800 shrink-0 z-10 animate-pulse"></div>'; cls='text-xs font-semibold text-blue-400'; }
      else { dot='<div class="h-5 w-5 rounded-full bg-gray-700 border-4 border-gray-800 shrink-0 z-10"></div>'; cls='text-xs font-medium text-gray-500'; }
      const row=el('<div class="relative flex items-start gap-4">'+dot+'<div class="pt-0.5"><h5 class="'+cls+'"></h5></div></div>');
      row.querySelector('h5').textContent=s.title||'';
      if(s.note){ const p=document.createElement('p'); p.className='text-[10px] text-gray-400 mt-1'; p.textContent=s.note; row.querySelector('h5').parentNode.appendChild(p); }
      body.appendChild(row);
    });
    c.appendChild(card); down(id); }

  // /loop -> "Telemetria del Bucle" card. d:{iter,max,cmds}
  function loopCard(id, json){ const c=panel(id); if(!c)return; userBubble(id,'/loop');
    let d; try{ d=JSON.parse(json); }catch(e){ d={}; }
    const card=el('<div class="bg-gray-800 border border-gray-700 p-4 rounded-xl shadow-sm"></div>');
    card.innerHTML='<h4 class="text-sm font-semibold text-gray-200 mb-4 flex items-center gap-2"><svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="text-orange-400"><path d="M21.5 2v6h-6M21.34 15.57a10 10 0 1 1-.59-9.5"></path></svg>Telemetria del Bucle</h4>'+
      '<div class="grid grid-cols-2 gap-3 mb-4"><div class="bg-gray-900 border border-gray-700 rounded-lg p-3 text-center"><div class="text-2xl font-bold text-gray-100">'+(d.iter||0)+' <span class="text-xs text-gray-500 font-normal">/ '+(d.max||0)+'</span></div><div class="text-[10px] text-gray-400 uppercase tracking-widest mt-1">Iteracion Actual</div></div>'+
      '<div class="bg-gray-900 border border-gray-700 rounded-lg p-3 text-center"><div class="text-2xl font-bold text-orange-400">'+(d.cmds||0)+' <span class="text-xs text-gray-500 font-normal">cmds</span></div><div class="text-[10px] text-gray-400 uppercase tracking-widest mt-1">Limite Autonomo</div></div></div>'+
      '<div class="flex items-center justify-between bg-gray-900 p-2.5 rounded border border-gray-700"><div class="flex items-center gap-2"><span class="relative flex h-2.5 w-2.5"><span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-orange-400 opacity-75"></span><span class="relative inline-flex rounded-full h-2.5 w-2.5 bg-orange-500"></span></span><span class="text-xs text-gray-300">Bucle en ejecucion</span></div><button class="loopstop text-[10px] bg-red-900/50 text-red-300 hover:bg-red-800/60 px-2 py-1 rounded border border-red-800/50">Interrumpir</button></div>';
    card.querySelector('.loopstop').onclick=function(){ send(id,'stop',''); };
    c.appendChild(card); down(id); }

  function setStatus(id, text, state){ /* could show a per-tab dot */ }
  function setRunning(id, b){ if(A[id]) A[id].running=(b==='1'); }
  function clearChat(id){ const c=panel(id); if(c) c.innerHTML=''; }

  function askCard(id, j){ const a=A[id]; if(!a)return; let d; try{d=JSON.parse(j);}catch(e){return;}
    const card=el('<div class="bg-[#2a1f0c] border border-yellow-700/50 p-3 rounded-lg"></div>');
    const q=el('<div class="text-yellow-300 font-semibold mb-2"></div>'); q.textContent=d.q; card.appendChild(q);
    (d.opts||[]).forEach(function(opt){ const b=el('<button class="block w-full text-left bg-yellow-700/30 hover:bg-yellow-600 text-yellow-100 px-3 py-2 rounded mb-1"></button>');
      b.textContent=opt; b.onclick=function(){ card.querySelectorAll('button').forEach(x=>x.disabled=true); send(id,'ask',opt); }; card.appendChild(b); });
    (a.turn||a.chat).appendChild(card); down(id); }
  function permitCard(id, j){ const a=A[id]; if(!a)return; let d; try{d=JSON.parse(j);}catch(e){return;}
    const verb=d.name==='shell'?'ejecutar':'escribir';
    const card=el('<div class="bg-[#2a1f0c] border border-yellow-700/50 p-3 rounded-lg"></div>');
    const p=el('<div class="text-xs text-gray-300 mb-2"></div>'); p.textContent='El agente desea '+verb+': '+d.args; card.appendChild(p);
    const ok=el('<button class="bg-yellow-600 text-white text-xs px-3 py-2 rounded mr-2">Permitir</button>');
    const no=el('<button class="bg-gray-700 text-white text-xs px-3 py-2 rounded">Rechazar</button>');
    ok.onclick=function(){ ok.disabled=no.disabled=true; send(id,'permit','1'); };
    no.onclick=function(){ ok.disabled=no.disabled=true; send(id,'permit','0'); };
    card.appendChild(ok); card.appendChild(no); (a.turn||a.chat).appendChild(card); down(id); }

  function sendPrompt(){ const i=document.getElementById('prompt'); const v=i.value.trim();
    if(!v||(A[cur]&&A[cur].running))return; i.value=''; send(cur,'send',v); }

  let rec=null, listening=false;
  function toggleMic(){
    const SR=window.SpeechRecognition||window.webkitSpeechRecognition;
    if(!SR){ alert('Dictado por voz no disponible en este WebView.'); return; }
    if(listening){ if(rec) rec.stop(); return; }
    rec=new SR(); rec.lang='es-ES'; rec.interimResults=true; rec.continuous=false;
    const mic=document.getElementById('micbtn');
    rec.onstart=function(){ listening=true; mic.style.background='#dc2626'; };
    rec.onend=function(){ listening=false; mic.style.background=''; };
    rec.onerror=function(){ listening=false; mic.style.background=''; };
    rec.onresult=function(e){ let t=''; for(let i=0;i<e.results.length;i++){ t+=e.results[i][0].transcript; } document.getElementById('prompt').value=t; };
    rec.start();
  }

  function mi(label, fn){ const b=el('<button class="block w-full text-left px-3 py-2 hover:bg-gray-700 text-gray-200 text-sm"></button>'); b.textContent=label; b.onclick=function(ev){ ev.stopPropagation(); document.getElementById('cfgmenu').style.display='none'; fn(); }; return b; }

  function showAbout(){
    const ov=el('<div style="position:fixed;inset:0;background:rgba(0,0,0,.65);z-index:80;display:flex;align-items:center;justify-content:center;padding:22px"></div>');
    const box=el('<div class="bg-gray-800 border border-gray-700 rounded-xl p-5 text-sm text-gray-200" style="max-width:340px"></div>');
    box.innerHTML='<div style="text-align:center;font-size:34px;margin-bottom:6px">😎</div>'+
      '<div style="text-align:center;font-weight:600;font-size:18px;margin-bottom:10px">Agents</div>'+
      '<p style="margin-bottom:10px">App agentica de IA hecha <b>100% en Harbour</b> (FiveWin/FWH en escritorio), usando el <b>API de ccharbour</b> para el bucle de chat con herramientas (CC_Client / CC_AgentRun) - el mismo nucleo que el cc.exe de consola.</p>'+
      '<p style="color:#9ca3af;font-size:12px;margin-bottom:10px">UI en WebView de Android; transporte HTTPS por Java (JNI); multi-agente sobre hilos Harbour MT; LLM DeepSeek.</p>'+
      '<p style="color:#9ca3af;font-size:12px;margin-bottom:4px">Compilado con Harbour 3.2.0dev (r2502031126), NDK clang arm64-v8a.</p>'+
      '<p style="color:#9ca3af;font-size:12px;margin-bottom:4px;text-align:center">Desarrollado por &#169; FiveTech Software 2026</p>'+
      '<p style="font-size:12px;margin-bottom:14px;text-align:center"><a href="mailto:antonio.fivetech@gmail.com" style="color:#60a5fa">antonio.fivetech@gmail.com</a></p>';
    const close=el('<button class="w-full bg-blue-600 hover:bg-blue-500 text-white py-2 rounded-lg">Cerrar</button>');
    close.onclick=function(){ ov.remove(); };
    box.appendChild(close); ov.appendChild(box);
    ov.onclick=function(e){ if(e.target===ov) ov.remove(); };
    document.body.appendChild(ov);
  }

  (function(){
    const tabs=document.getElementById('tabs');
    const add=el('<button class="tab tab-off">+</button>');
    add.onclick=function(){ send(0,'newagent',''); }; tabs.appendChild(add);

    // stop + clear buttons, fixed top-right (left of the kebab), inside the tab bar
    const stp=el('<button class="fbtn" style="position:fixed;top:8px;right:80px;z-index:60;background:#273244" title="Detener"><svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="currentColor" stroke="none" style="margin:auto"><rect x="6" y="6" width="12" height="12" rx="2"></rect></svg></button>');
    stp.onclick=function(ev){ ev.stopPropagation(); send(cur,'stop',''); };
    document.body.appendChild(stp);
    const clr=el('<button class="fbtn" style="position:fixed;top:8px;right:44px;z-index:60;background:#273244" title="Limpiar chat"><svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="margin:auto"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path></svg></button>');
    clr.onclick=function(ev){ ev.stopPropagation(); send(cur,'clear',''); };
    document.body.appendChild(clr);

    // config kebab (three vertical dots), fixed at the very top-right so the
    // agent tabs (added later, scrolling) never push it out of place.
    const kebab=el('<button class="fbtn" style="position:fixed;top:8px;right:8px;z-index:60;background:transparent;font-size:22px;line-height:1">⋮</button>');
    const menu=el('<div id="cfgmenu" class="rounded-md shadow-lg border border-gray-700 bg-gray-800 overflow-hidden" style="display:none;position:fixed;top:46px;right:8px;width:200px;z-index:60"></div>');
    let yoloOn=true;
    const yoloItem=document.createElement('button');
    yoloItem.className='block w-full text-left px-3 py-2 hover:bg-gray-700 text-gray-200 text-sm';
    function updYolo(){ yoloItem.textContent=(yoloOn?'☑ ':'☐ ')+'Auto-aprobar (shell/write/edit)'; }
    updYolo();
    yoloItem.onclick=function(ev){ ev.stopPropagation(); yoloOn=!yoloOn; updYolo(); send(cur,'yolo',yoloOn?'1':'0'); };
    menu.appendChild(yoloItem);
    menu.appendChild(mi('Texto mas grande  (A+)', function(){ bumpFont(1); }));
    menu.appendChild(mi('Texto mas pequeno  (A-)', function(){ bumpFont(-1); }));
    menu.appendChild(mi('Nuevo agente', function(){ send(0,'newagent',''); }));
    menu.appendChild(mi('Limpiar chat', function(){ send(cur,'clear',''); }));
    menu.appendChild(mi('Acerca de', showAbout));
    kebab.onclick=function(ev){ ev.stopPropagation(); menu.style.display=(menu.style.display==='none'?'block':'none'); };
    document.addEventListener('click', function(){ menu.style.display='none'; });
    document.body.appendChild(kebab); document.body.appendChild(menu);
    // keep the tab row clear of the fixed kebab
    tabs.style.paddingRight='44px';
  })();

  // apply saved font size, then tell Harbour the page is ready
  bumpFont(0);
  send(0, 'ready', '');
</script>
</body></html>
   ENDTEXT
RETURN cHtml
