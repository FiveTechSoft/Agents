// Agents — Agent class: OOP refactoring of CCHarbour's agent loop.
// Based on c:\fwteam\source\classes\agent.prg pattern.
// Reusable OOP wrapper: Agent():New( key ) → :Run( prompt )
// CCHarbour TUI runs via ccrepl.prg (Main entry point).
// Based on c:\fwteam\source\classes\agent.prg pattern.
// Wraps CCHarbour's streaming API, 17-tool ecosystem, skills, and
// permission gate into a reusable CLASS Agent.

#include "fileio.ch"
#include "hbclass.ch"

#define AGENT_MAX_STEPS    25
#define AGENT_MODEL_DEF    "deepseek-v4-pro"
#define AGENT_API_DEF      "https://api.deepseek.com"

// ---------------------------------------------------------------------------
// Agent — Autonomous AI agent with tools, skills, and multi-agent dispatch
// ---------------------------------------------------------------------------

CLASS Agent

   // ---- conversation state ----
   DATA aMessages       INIT {}
   DATA cSystemPrompt   INIT ""
   DATA lRunning        INIT .F.

   // ---- tools ----
   DATA hBuiltinTools   INIT {=>}
   DATA hUserTools      INIT {=>}

   // ---- skills ----
   DATA hSkills         INIT {=>}
   DATA aActiveSkills   INIT {}

   // ---- planning ----
   DATA cGoal           INIT ""
   DATA aPlan           INIT {}

   // ---- configuration ----
   DATA cModel          INIT AGENT_MODEL_DEF
   DATA cApiKey         INIT ""
   DATA cApiUrl         INIT AGENT_API_DEF
   DATA nMaxSteps       INIT AGENT_MAX_STEPS
   DATA nApiTimeout     INIT 120
   DATA lStreaming      INIT .T.
   DATA cCoAuthor       INIT ""
   DATA cGithubToken    INIT ""

   // ---- metrics ----
   DATA nTokensIn       INIT 0
   DATA nTokensOut      INIT 0
   DATA nTokensCache    INIT 0
   DATA nCost           INIT 0

   // ---- control ----
   DATA lAbort          INIT .F.
   DATA bInterrupt
   DATA bInject
   DATA bOnEvent

   // ---- subagent ----
   DATA lIsSubAgent     INIT .F.
   DATA cSubAgentType   INIT ""

   // Initialization
   METHOD New( cKey, cModel, hOpts )
   METHOD InitTools()
   METHOD InitSkills()
   METHOD LoadSkills( cDir )

   // Main loop
   METHOD Run( cPrompt )
   METHOD Step()
   METHOD SendToLLM( aMsgs, hParams )

   // Messages & prompt
   METHOD AddMessage( cRole, cContent, hExtra )
   METHOD BuildSystemPrompt()
   METHOD BuildToolsArray()

   // Tool dispatch
   METHOD ExecTool( cName, hArgs )
   METHOD RegisterTool( cName, cDesc, cScript, cType )
   METHOD UnregisterTool( cName )
   METHOD ListUserTools()

   // Built-in tools
   METHOD Tool_Read( hArgs )
   METHOD Tool_Write( hArgs )
   METHOD Tool_Edit( hArgs )
   METHOD Tool_Glob( hArgs )
   METHOD Tool_Grep( hArgs )
   METHOD Tool_Shell( hArgs )
   METHOD Tool_WebSearch( hArgs )
   METHOD Tool_WebFetch( hArgs )

   // Skills
   METHOD ActivateSkill( cName )
   METHOD DeactivateSkill( cName )
   METHOD ActiveSkillsPrompt()

   // Multi-agent
   METHOD DispatchAgent( cPrompt, cType, nTimeout )
   METHOD SubAgentRun( cId, cType, cPrompt, nTimeout )

   // Planning
   METHOD GeneratePlan( cGoal )
   METHOD ExecutePlan()

   // Utilities
   METHOD UsageReport()
   METHOD Abort()
   METHOD SaveState( cDir )
   METHOD LoadState( cDir )
   METHOD ResolveApiKey()

ENDCLASS

// ============================================================================
// Initialization
// ============================================================================

METHOD New( cKey, cModel, hOpts ) CLASS Agent

   IF cModel == NIL ; cModel := AGENT_MODEL_DEF ; ENDIF
   IF hOpts  == NIL ; hOpts  := {=>}           ; ENDIF

   ::cApiKey       := cKey
   ::cModel        := iif( Empty( cModel ), AGENT_MODEL_DEF, cModel )
   ::aMessages     := {}
   ::aPlan         := {}
   ::hUserTools    := {=>}
   ::aActiveSkills := {}
   ::lAbort        := .F.

   // config from hOpts
   IF hb_HHasKey( hOpts, "base_url" )     .AND. !Empty( hOpts[ "base_url" ] )
      ::cApiUrl := hOpts[ "base_url" ]
   ENDIF
   IF hb_HHasKey( hOpts, "max_steps" )    .AND. ValType( hOpts[ "max_steps" ] ) == "N"
      ::nMaxSteps := hOpts[ "max_steps" ]
   ENDIF
   IF hb_HHasKey( hOpts, "timeout" )      .AND. ValType( hOpts[ "timeout" ] ) == "N"
      ::nApiTimeout := hOpts[ "timeout" ]
   ENDIF
   IF hb_HHasKey( hOpts, "co_author" )
      ::cCoAuthor := hOpts[ "co_author" ]
   ENDIF
   IF hb_HHasKey( hOpts, "github_token" )
      ::cGithubToken := hOpts[ "github_token" ]
   ENDIF
   IF hb_HHasKey( hOpts, "interrupt" )
      ::bInterrupt := hOpts[ "interrupt" ]
   ENDIF
   IF hb_HHasKey( hOpts, "inject" )
      ::bInject := hOpts[ "inject" ]
   ENDIF
   IF hb_HHasKey( hOpts, "on_event" )
      ::bOnEvent := hOpts[ "on_event" ]
   ENDIF

   ::InitTools()
   ::InitSkills()

   // load persisted state
   ::LoadState( hb_DirBase() + "agent_state" + hb_ps() )

RETURN Self

// ---------------------------------------------------------------------------

METHOD InitTools() CLASS Agent

   // Built-in tools — same set as CCHarbour's 17-tool ecosystem.
   // Each tool is a hash: { name, description, parameters, handler }.
   // The handler is a codeblock that receives hArgs and returns cResult.

   ::hBuiltinTools := {=>}

   // File tools
   AGENT_RegTool( ::hBuiltinTools, { ;
      "name" => "read", ;
      "description" => "Read a text file from disk. Returns line-numbered content.", ;
      "parameters" => { "type" => "object", ;
         "properties" => { ;
            "path" => { "type" => "string", ;
                        "description" => "Path of the file to read" }, ;
            "offset" => { "type" => "integer", ;
                          "description" => "Number of leading lines to skip" }, ;
            "max_lines" => { "type" => "integer", ;
                             "description" => "Maximum lines to return (default 2000)" } }, ;
         "required" => { "path" } }, ;
      "handler" => {| hArgs | ::Tool_Read( hArgs ) } } )

   AGENT_RegTool( ::hBuiltinTools, { ;
      "name" => "write", ;
      "description" => "Write text content to a file, overwriting it.", ;
      "parameters" => { "type" => "object", ;
         "properties" => { ;
            "path" => { "type" => "string", ;
                        "description" => "Path of the file to write" }, ;
            "content" => { "type" => "string", ;
                           "description" => "Content to write" } }, ;
         "required" => { "path", "content" } }, ;
      "handler" => {| hArgs | ::Tool_Write( hArgs ) } } )

   AGENT_RegTool( ::hBuiltinTools, { ;
      "name" => "edit", ;
      "description" => "Replace an exact string in a file.", ;
      "parameters" => { "type" => "object", ;
         "properties" => { ;
            "path" => { "type" => "string", ;
                        "description" => "Path of the file to edit" }, ;
            "old_string" => { "type" => "string", ;
                              "description" => "Exact text to replace" }, ;
            "new_string" => { "type" => "string", ;
                              "description" => "Replacement text" }, ;
            "replace_all" => { "type" => "boolean", ;
                               "description" => "Replace every occurrence" } }, ;
         "required" => { "path", "old_string", "new_string" } }, ;
      "handler" => {| hArgs | ::Tool_Edit( hArgs ) } } )

   // Search tools
   AGENT_RegTool( ::hBuiltinTools, { ;
      "name" => "glob", ;
      "description" => "List files matching a filename pattern under a directory.", ;
      "parameters" => { "type" => "object", ;
         "properties" => { ;
            "pattern" => { "type" => "string", ;
                           "description" => "Filename mask, e.g. *.prg" }, ;
            "path" => { "type" => "string", ;
                        "description" => "Root directory to search" } }, ;
         "required" => { "pattern" } }, ;
      "handler" => {| hArgs | ::Tool_Glob( hArgs ) } } )

   AGENT_RegTool( ::hBuiltinTools, { ;
      "name" => "grep", ;
      "description" => "Search file contents with a regular expression.", ;
      "parameters" => { "type" => "object", ;
         "properties" => { ;
            "pattern" => { "type" => "string", ;
                           "description" => "Regular expression to search for" }, ;
            "path" => { "type" => "string", ;
                        "description" => "Root directory to search" }, ;
            "glob" => { "type" => "string", ;
                        "description" => "Filename mask filtering files scanned" } }, ;
         "required" => { "pattern" } }, ;
      "handler" => {| hArgs | ::Tool_Grep( hArgs ) } } )

   // Shell
   AGENT_RegTool( ::hBuiltinTools, { ;
      "name" => "shell", ;
      "description" => "Run a shell command and return its combined output and exit code.", ;
      "parameters" => { "type" => "object", ;
         "properties" => { ;
            "command" => { "type" => "string", ;
                           "description" => "Command line to run" }, ;
            "timeout" => { "type" => "number", ;
                           "description" => "Max seconds (0 = no limit)" } }, ;
         "required" => { "command" } }, ;
      "handler" => {| hArgs | ::Tool_Shell( hArgs ) } } )

   // Web tools
   AGENT_RegTool( ::hBuiltinTools, { ;
      "name" => "web_search", ;
      "description" => "Search the web via DuckDuckGo API.", ;
      "parameters" => { "type" => "object", ;
         "properties" => { ;
            "query" => { "type" => "string", ;
                         "description" => "Search query" } }, ;
         "required" => { "query" } }, ;
      "handler" => {| hArgs | ::Tool_WebSearch( hArgs ) } } )

   AGENT_RegTool( ::hBuiltinTools, { ;
      "name" => "web_fetch", ;
      "description" => "Fetch a URL and return its text content.", ;
      "parameters" => { "type" => "object", ;
         "properties" => { ;
            "url" => { "type" => "string", ;
                       "description" => "URL to fetch" } }, ;
         "required" => { "url" } }, ;
      "handler" => {| hArgs | ::Tool_WebFetch( hArgs ) } } )

   // Memory
   AGENT_RegTool( ::hBuiltinTools, { ;
      "name" => "memory", ;
      "description" => "Read/write persistent agent memory.", ;
      "parameters" => { "type" => "object", ;
         "properties" => { ;
            "action" => { "type" => "string", ;
                          "description" => "read | write | list" }, ;
            "key" => { "type" => "string", ;
                       "description" => "Memory key" }, ;
            "value" => { "type" => "string", ;
                         "description" => "Value to store" } }, ;
         "required" => { "action" } }, ;
      "handler" => {| hArgs | AGENT_ToolMemory( hArgs ) } } )

   // UI-only tools (always allowed, never gated)
   AGENT_RegTool( ::hBuiltinTools, { ;
      "name" => "ask_user", ;
      "description" => "Ask the user a multiple-choice question.", ;
      "parameters" => { "type" => "object", ;
         "properties" => { ;
            "question" => { "type" => "string" }, ;
            "options" => { "type" => "array", ;
                           "items" => { "type" => "string" } } }, ;
         "required" => { "question", "options" } }, ;
      "handler" => {| hArgs | AGENT_ToolAskUser( hArgs ) } } )

   AGENT_RegTool( ::hBuiltinTools, { ;
      "name" => "todo_write", ;
      "description" => "Manage a session task list.", ;
      "parameters" => { "type" => "object", ;
         "properties" => { ;
            "tasks" => { "type" => "array" } }, ;
         "required" => { "tasks" } }, ;
      "handler" => {| hArgs | AGENT_ToolTodoWrite( hArgs ) } } )

   // Skills
   AGENT_RegTool( ::hBuiltinTools, { ;
      "name" => "use_skill", ;
      "description" => "Activate a named skill.", ;
      "parameters" => { "type" => "object", ;
         "properties" => { ;
            "name" => { "type" => "string" } }, ;
         "required" => { "name" } }, ;
      "handler" => {| hArgs | AGENT_ToolUseSkill( hArgs, Self ) } } )

   // Dynamic tools
   AGENT_RegTool( ::hBuiltinTools, { ;
      "name" => "register_tool", ;
      "description" => "Register a new tool from a script file.", ;
      "parameters" => { "type" => "object", ;
         "properties" => { ;
            "name" => { "type" => "string" }, ;
            "description" => { "type" => "string" }, ;
            "scriptPath" => { "type" => "string" } }, ;
         "required" => { "name", "description", "scriptPath" } }, ;
      "handler" => {| hArgs | ::RegisterTool( hArgs[ "name" ], ;
         hArgs[ "description" ], hArgs[ "scriptPath" ] ) } } )

   AGENT_RegTool( ::hBuiltinTools, { ;
      "name" => "unregister_tool", ;
      "description" => "Remove a previously registered tool.", ;
      "parameters" => { "type" => "object", ;
         "properties" => { ;
            "name" => { "type" => "string" } }, ;
         "required" => { "name" } }, ;
      "handler" => {| hArgs | ::UnregisterTool( hArgs[ "name" ] ) } } )

   AGENT_RegTool( ::hBuiltinTools, { ;
      "name" => "user_tools", ;
      "description" => "List all user-registered tools.", ;
      "parameters" => { "type" => "object", ;
         "properties" => {} }, ;
      "handler" => {| hArgs | ::ListUserTools() } } )

   // Subagent dispatch
   AGENT_RegTool( ::hBuiltinTools, { ;
      "name" => "dispatch_agent", ;
      "description" => "Launch an isolated subagent on a specific task.", ;
      "parameters" => { "type" => "object", ;
         "properties" => { ;
            "prompt" => { "type" => "string" }, ;
            "agent_type" => { "type" => "string" }, ;
            "timeout_s" => { "type" => "number" } }, ;
         "required" => { "prompt" } }, ;
      "handler" => {| hArgs | ::DispatchAgent( hArgs[ "prompt" ], ;
         hb_HGetDef( hArgs, "agent_type", "explore" ), ;
         hb_HGetDef( hArgs, "timeout_s", 120 ) ) } } )

RETURN .T.

// ---------------------------------------------------------------------------

METHOD InitSkills() CLASS Agent

   ::hSkills := { ;
      "reviewer"   => "Act as code reviewer. Check relevant files and report concisely: bugs, risks, prioritized improvements.", ;
      "summarizer" => "Summarize in clear bullets the content of the indicated files.", ;
      "refactor"   => "Refactor the indicated file for readability and simplicity.", ;
      "documenter" => "Generate or update README.md describing the purpose and files on disk.", ;
      "tester"     => "Propose and write tests for the code on disk." }

   // Load .md skills from disk
   ::LoadSkills( hb_DirBase() + "skills" + hb_ps() )

RETURN .T.

// ============================================================================
// Main loop
// ============================================================================

METHOD Run( cPrompt ) CLASS Agent

   LOCAL nStep := 0, hChat, aToolCalls, tc, cRes, cInject
   LOCAL hResult := { "success" => .F., "content" => "", ;
                      "stop_reason" => NIL, "iterations" => 0, ;
                      "usage" => {=>}, "tool_call_count" => 0 }

   ::lRunning := .T.
   ::lAbort   := .F.

   ::AddMessage( "user", cPrompt )
   ::BuildSystemPrompt()

   DO WHILE ::lRunning .AND. !::lAbort .AND. nStep < ::nMaxSteps

      // interrupt check
      IF ::bInterrupt != NIL .AND. Eval( ::bInterrupt )
         hResult[ "stop_reason" ] := "interrupted"
         EXIT
      ENDIF

      nStep++

      // mid-run injection
      IF ::bInject != NIL
         cInject := Eval( ::bInject )
         IF ValType( cInject ) == "C" .AND. !Empty( cInject )
            ::AddMessage( "user", cInject )
         ENDIF
      ENDIF

      // build the API message list: system prompt + history
      hChat := ::Step()

      IF !hChat[ "success" ]
         hResult[ "error_type" ]  := hChat[ "error_type" ]
         hResult[ "message" ]     := hChat[ "message" ]
         hResult[ "stop_reason" ] := "error"
         hResult[ "iterations" ]  := nStep
         EXIT
      ENDIF

      // accumulate usage
      AGENT_AccUsage( hResult[ "usage" ], hChat[ "usage" ] )

      // append assistant message (with tool_calls if present)
      ::AddMessage( "assistant", hChat[ "content" ], ;
         iif( Empty( hChat[ "tool_calls" ] ), NIL, ;
            { "tool_calls" => hChat[ "tool_calls" ], ;
              "reasoning_content" => hChat[ "reasoning_content" ] } ) )

      // no tool calls → final answer
      IF Empty( hChat[ "tool_calls" ] )
         // reasoning-only response → auto-continue
         IF Empty( hChat[ "content" ] ) .AND. ;
            !Empty( hChat[ "reasoning_content" ] ) .AND. ;
            nStep < ::nMaxSteps
            ::AddMessage( "user", "Continue." )
            LOOP
         ENDIF
         hResult[ "stop_reason" ] := "stop"
         EXIT
      ENDIF

      // execute tool calls
      hResult[ "tool_call_count" ] += Len( hChat[ "tool_calls" ] )
      FOR EACH tc IN hChat[ "tool_calls" ]
         IF ::bInterrupt != NIL .AND. Eval( ::bInterrupt )
            hResult[ "stop_reason" ] := "interrupted"
            EXIT
         ENDIF
         cRes := ::ExecTool( tc[ "name" ], tc[ "arguments" ] )
         ::AddMessage( "tool", cRes, { "tool_call_id" => tc[ "id" ] } )
      NEXT

      IF hResult[ "stop_reason" ] == "interrupted"
         EXIT
      ENDIF
   ENDDO

   IF hResult[ "stop_reason" ] == NIL
      hResult[ "stop_reason" ] := "max_iterations"
   ENDIF

   hResult[ "success" ]    := .T.
   hResult[ "iterations" ] := nStep
   hResult[ "content" ]    := AGENT_LastText( ::aMessages )

   ::SaveState( hb_DirBase() + "agent_state" + hb_ps() )
   ::lRunning := .F.

RETURN hResult

// ---------------------------------------------------------------------------
// Step — one LLM API call with streaming SSE via curl.
// Returns: { success, content, tool_calls, finish_reason, usage,
//            reasoning_content, error_type, message }
// ---------------------------------------------------------------------------

METHOD Step() CLASS Agent

   LOCAL aMsgs, cBody, hResult, hResolved, cKey
   LOCAL hState, oParser, hReq, hHttp

   hResult := { "success" => .F., "content" => "", "tool_calls" => {}, ;
                "finish_reason" => NIL, "usage" => NIL, ;
                "reasoning_content" => "", "error_type" => NIL, ;
                "message" => NIL }

   // Resolve API key
   hResolved := ::ResolveApiKey()
   IF !hResolved[ "ok" ]
      hResult[ "error_type" ] := hResolved[ "error_type" ]
      hResult[ "message" ]    := hResolved[ "message" ]
      RETURN hResult
   ENDIF
   cKey := hResolved[ "api_key" ]

   // Build message array: system prompt first, then history
   aMsgs := { { "role" => "system", "content" => ::cSystemPrompt } }
   AEval( ::aMessages, {| m | AAdd( aMsgs, AGENT_MsgToApi( m ) ) } )

   // Build request body
   cBody := hb_jsonEncode( AGENT_BuildBody( ::cModel, aMsgs, ::BuildToolsArray(), ::cApiUrl ) )

   // Build HTTP request
   hReq := AGENT_BuildRequest( ::cApiUrl, cKey, cBody, ::nApiTimeout )

   // Stream via curl, parse SSE
   hState  := { "content" => "", "tools" => {}, "finish" => NIL, ;
                "usage" => NIL, "got_done" => .F., "reasoning" => "" }
   oParser := AGENT_SSE_New()

   hHttp := AGENT_HTTP_Post( hReq, ;
      {| cChunk | AGENT_FeedChunk( cChunk, hState, oParser, ::bOnEvent ) } )

   // Classify outcome
   IF !hHttp[ "ok" ]
      IF hHttp[ "curl_code" ] == -2
         hResult[ "error_type" ] := "cancelled"
         hResult[ "message" ]    := "cancelled"
      ELSE
         hResult[ "error_type" ] := "network"
         hResult[ "message" ]    := hHttp[ "error" ]
      ENDIF
      RETURN hResult
   ENDIF

   IF hHttp[ "status" ] < 200 .OR. hHttp[ "status" ] >= 300
      hResult[ "error_type" ] := "api"
      hResult[ "message" ]    := "HTTP " + LTrim( Str( hHttp[ "status" ] ) )
      RETURN hResult
   ENDIF

   IF !hState[ "got_done" ]
      hResult[ "error_type" ] := "stream_incomplete"
      hResult[ "message" ]    := "Stream closed before [DONE]"
      RETURN hResult
   ENDIF

   // Metrics
   IF ValType( hState[ "usage" ] ) == "H"
      ::nTokensIn    += hb_HGetDef( hState[ "usage" ], "prompt_tokens", 0 )
      ::nTokensOut   += hb_HGetDef( hState[ "usage" ], "completion_tokens", 0 )
      ::nTokensCache += hb_HGetDef( hState[ "usage" ], "prompt_cache_hit_tokens", 0 )
   ENDIF

   hResult[ "success" ]           := .T.
   hResult[ "content" ]           := hState[ "content" ]
   hResult[ "tool_calls" ]        := hState[ "tools" ]
   hResult[ "finish_reason" ]     := hState[ "finish" ]
   hResult[ "usage" ]             := hState[ "usage" ]
   hResult[ "reasoning_content" ] := hState[ "reasoning" ]

RETURN hResult

// ============================================================================
// Messages & prompt
// ============================================================================

METHOD AddMessage( cRole, cContent, hExtra ) CLASS Agent

   LOCAL hMsg := { "role" => cRole, "content" => cContent }

   IF ValType( hExtra ) == "H"
      IF hb_HHasKey( hExtra, "tool_calls" )
         hMsg[ "tool_calls" ] := hExtra[ "tool_calls" ]
      ENDIF
      IF hb_HHasKey( hExtra, "tool_call_id" )
         hMsg[ "tool_call_id" ] := hExtra[ "tool_call_id" ]
      ENDIF
      IF hb_HHasKey( hExtra, "reasoning_content" )
         hMsg[ "reasoning_content" ] := hExtra[ "reasoning_content" ]
      ENDIF
   ENDIF

   AAdd( ::aMessages, hMsg )

   // Context window trimming: keep last ~150 messages
   IF Len( ::aMessages ) > 200
      // drop oldest 60 messages (but keep system-level context)
      ::aMessages := ACopy( ::aMessages, 61, 200, , 1 )
      ASize( ::aMessages, 140 )
   ENDIF

RETURN NIL

// ---------------------------------------------------------------------------

METHOD BuildSystemPrompt() CLASS Agent

   LOCAL cPrompt := ""
   LOCAL cSkills

   cPrompt += "You are CCHarbour Agent — a coding assistant that works with files on disk. "
   cPrompt += "Use the available tools to read, write, edit, search, and run commands. "
   cPrompt += "Be concise and direct. Prefer code over prose."

   // active skills
   cSkills := ::ActiveSkillsPrompt()
   IF !Empty( cSkills )
      cPrompt += hb_eol() + hb_eol() + "ACTIVE SKILLS (follow always):" + hb_eol() + cSkills
   ENDIF

   // user tools
   IF !Empty( ::hUserTools )
      cPrompt += hb_eol() + hb_eol() + "Your registered user tools:"
      AEval( hb_HKeys( ::hUserTools ), {| cName | ;
         cPrompt += hb_eol() + "- " + cName + ": " + ::hUserTools[ cName ][ "desc" ] } )
   ENDIF

   // plan
   IF !Empty( ::cGoal )
      cPrompt += hb_eol() + hb_eol() + "Goal: " + ::cGoal
      IF !Empty( ::aPlan )
         cPrompt += hb_eol() + "Plan:"
         AEval( ::aPlan, {| hStep | ;
            cPrompt += hb_eol() + "  [" + hStep[ "state" ] + "] " + hStep[ "title" ] } )
      ENDIF
   ENDIF

   // subagent instructions
   IF ::lIsSubAgent .AND. !Empty( ::cSubAgentType )
      cPrompt += hb_eol() + hb_eol() + "You are a subagent of type '" + ::cSubAgentType + "'. "
      cPrompt += "Complete the task using the tools you have, then return a SHORT synthesis. "
      cPrompt += "NEVER dump raw tool output. Summarize and conclude."
   ENDIF

   ::cSystemPrompt := cPrompt

RETURN cPrompt

// ---------------------------------------------------------------------------

METHOD BuildToolsArray() CLASS Agent

   LOCAL aTools := {}, cName

   FOR EACH cName IN hb_HKeys( ::hBuiltinTools )
      AAdd( aTools, { ;
         "type" => "function", ;
         "function" => { ;
            "name"        => cName, ;
            "description" => ::hBuiltinTools[ cName ][ "description" ], ;
            "parameters"  => ::hBuiltinTools[ cName ][ "parameters" ] } } )
   NEXT

   // user tools
   FOR EACH cName IN hb_HKeys( ::hUserTools )
      AAdd( aTools, { ;
         "type" => "function", ;
         "function" => { ;
            "name"        => cName, ;
            "description" => ::hUserTools[ cName ][ "desc" ], ;
            "parameters"  => { "type" => "object", ;
               "properties" => { "args" => { "type" => "string" } } } } } )
   NEXT

RETURN aTools

// ============================================================================
// Tool dispatch
// ============================================================================

METHOD ExecTool( cName, hArgs ) CLASS Agent

   LOCAL cResult := ""

   IF hb_HHasKey( ::hBuiltinTools, cName )
      BEGIN SEQUENCE WITH {| o | Break( o ) }
         cResult := Eval( ::hBuiltinTools[ cName ][ "handler" ], hArgs )
      RECOVER
         cResult := "Error: tool '" + cName + "' failed: exception"
      END SEQUENCE
   ELSEIF hb_HHasKey( ::hUserTools, cName )
      cResult := AGENT_ExecUserTool( ::hUserTools[ cName ], hArgs )
   ELSE
      cResult := "Error: unknown tool '" + hb_CStr( cName ) + "'"
   ENDIF

   // sanitize output
   cResult := AGENT_SanitizeUTF8( cResult )

RETURN cResult

// ---------------------------------------------------------------------------

METHOD RegisterTool( cName, cDesc, cScript, cType ) CLASS Agent

   IF cType == NIL ; cType := iif( Lower( hb_FNameExt( cScript ) ) == ".py", "python", "shell" ) ; ENDIF

   IF Empty( cName ) .OR. !hb_FileExists( cScript )
      RETURN "Error: invalid name or script path"
   ENDIF

   ::hUserTools[ cName ] := { "desc" => cDesc, "script" => cScript, "type" => cType }
   ::hBuiltinTools[ cName ] := { ;
      "description" => cDesc, ;
      "parameters"  => { "type" => "object", "properties" => {} }, ;
      "handler"     => {| hArgs | AGENT_ExecUserTool( ::hUserTools[ cName ], hArgs ) } }

   ::SaveState( hb_DirBase() + "agent_state" + hb_ps() )

RETURN "Tool registered: " + cName

// ---------------------------------------------------------------------------

METHOD UnregisterTool( cName ) CLASS Agent

   IF !hb_HHasKey( ::hUserTools, cName )
      RETURN "Error: tool not registered: " + cName
   ENDIF

   hb_HDel( ::hUserTools, cName )
   hb_HDel( ::hBuiltinTools, cName )
   ::SaveState( hb_DirBase() + "agent_state" + hb_ps() )

RETURN "Tool removed: " + cName

// ---------------------------------------------------------------------------

METHOD ListUserTools() CLASS Agent

   LOCAL cList := ""

   IF Empty( ::hUserTools )
      RETURN "(no user tools registered)"
   ENDIF

   AEval( hb_HKeys( ::hUserTools ), {| cName | ;
      cList += cName + " - " + ::hUserTools[ cName ][ "desc" ] + Chr( 10 ) } )

RETURN cList

// ============================================================================
// Skills
// ============================================================================

METHOD LoadSkills( cDir ) CLASS Agent

   LOCAL aFiles, cName, cContent, cPath

   IF cDir == NIL ; cDir := hb_DirBase() + "skills" + hb_ps() ; ENDIF

   IF hb_DirExists( cDir )
      aFiles := Directory( cDir + "*.md" )
      AEval( aFiles, {| aFile | ;
         cName    := hb_FNameName( aFile[ 1 ] ), ;
         cPath    := cDir + aFile[ 1 ], ;
         cContent := hb_MemoRead( cPath ), ;
         iif( !hb_HHasKey( ::hSkills, cName ), ;
              ::hSkills[ cName ] := cContent, NIL ) } )
   ENDIF

RETURN .T.

// ---------------------------------------------------------------------------

METHOD ActivateSkill( cName ) CLASS Agent

   IF !hb_HHasKey( ::hSkills, cName )
      RETURN "Skill not found: " + cName
   ENDIF

   IF AScan( ::aActiveSkills, {| c | c == cName } ) == 0
      AAdd( ::aActiveSkills, cName )
   ENDIF

RETURN "Skill activated: " + cName

// ---------------------------------------------------------------------------

METHOD DeactivateSkill( cName ) CLASS Agent

   LOCAL nPos := AScan( ::aActiveSkills, {| c | c == cName } )

   IF nPos > 0
      hb_ADel( ::aActiveSkills, nPos, .T. )
   ENDIF

RETURN "Skill deactivated: " + cName

// ---------------------------------------------------------------------------

METHOD ActiveSkillsPrompt() CLASS Agent

   LOCAL cPrompt := ""

   AEval( ::aActiveSkills, {| cName | ;
      iif( hb_HHasKey( ::hSkills, cName ), ;
           cPrompt += "Skill " + cName + ": " + ::hSkills[ cName ] + hb_eol(), NIL ) } )

RETURN cPrompt

// ============================================================================
// Multi-agent dispatch
// ============================================================================

METHOD DispatchAgent( cPrompt, cType, nTimeout ) CLASS Agent

   LOCAL oSub, hResult, cReply := ""

   IF Empty( cPrompt )
      RETURN "Error: dispatch_agent requires 'prompt'"
   ENDIF

   IF cType    == NIL ; cType    := "explore" ; ENDIF
   IF nTimeout == NIL ; nTimeout := 120       ; ENDIF

   IF nTimeout < 5   ; nTimeout := 5    ; ENDIF
   IF nTimeout > 600 ; nTimeout := 600  ; ENDIF

   // Create sub-agent with filtered tools
   oSub := Agent():New( ::cApiKey, ::cModel, { ;
      "base_url"     => ::cApiUrl, ;
      "timeout"      => ::nApiTimeout, ;
      "max_steps"    => 10, ;
      "co_author"    => ::cCoAuthor, ;
      "github_token" => ::cGithubToken } )

   oSub:lIsSubAgent   := .T.
   oSub:cSubAgentType := cType

   // clone tools, remove dispatch to prevent recursion
   oSub:hBuiltinTools := hb_HClone( ::hBuiltinTools )
   hb_HDel( oSub:hBuiltinTools, "dispatch_agent" )
   hb_HDel( oSub:hBuiltinTools, "ask_user" )

   // for "explore" type, keep only read-only tools
   IF cType == "explore"
      AGENT_FilterExploreTools( oSub:hBuiltinTools )
   ENDIF

   // build subagent system prompt
   oSub:cSystemPrompt := "You are a subagent of type '" + cType + "'. " + ;
      "Complete the task using the tools you have, then return a SHORT synthesis. " + ;
      "NEVER dump raw tool output. Summarize and conclude."

   hResult := oSub:Run( cPrompt )

   // extract last assistant reply
   cReply := hResult[ "content" ]

RETURN iif( Empty( cReply ), "[subagent returned no text]", cReply )

// ---------------------------------------------------------------------------
// SubAgentRun: threaded subagent entry point (called via hb_threadStart).
METHOD SubAgentRun( cId, cType, cPrompt, nTimeout ) CLASS Agent

   LOCAL hResult

   ::lIsSubAgent   := .T.
   ::cSubAgentType := cType

   hResult := ::Run( cPrompt )
   ::lIsSubAgent := .F.

RETURN hResult

// ---------------------------------------------------------------------------
// SendToLLM: direct API call for a list of messages.
METHOD SendToLLM( aMsgs, hParams ) CLASS Agent

   LOCAL aOldMsgs, cOldPrompt, hResult

   // save current state
   aOldMsgs      := AClone( ::aMessages )
   cOldPrompt    := ::cSystemPrompt

   // build temp system prompt
   ::cSystemPrompt := iif( hb_HHasKey( hParams, "system" ), ;
                           hParams[ "system" ], ::cSystemPrompt )

   // set messages from parameter
   ::aMessages := aMsgs

   hResult := ::Step()

   // restore
   ::aMessages     := aOldMsgs
   ::cSystemPrompt := cOldPrompt

RETURN hResult

// ============================================================================
// Planning
// ============================================================================

METHOD GeneratePlan( cGoal ) CLASS Agent

   LOCAL aOldMsgs, hResult, cContent, hPlan

   ::cGoal := cGoal

   // save current messages, run a planning prompt
   aOldMsgs := AClone( ::aMessages )
   ::aMessages := {}

   ::AddMessage( "user", "You are a planner. Decompose this task into 3-6 concrete steps. " + ;
      "Respond ONLY with JSON: " + Chr(123) + '"steps":[' + Chr(123) + '"title":"...","state":"pending"' + Chr(125) + ']' + Chr(125) + ". " + ;
      "The first step should be " + Chr(34) + "active" + Chr(34) + ". No prose." + hb_eol() + hb_eol() + ;
      "Task: " + cGoal )

   hResult  := ::Run( "" )  // Run will add the plan-prompt user message internally... actually no.
   // We already added the message, so we can't use Run() directly. Let's use Step() instead.

   // Restore messages
   ::aMessages := aOldMsgs

   // Try to parse plan from hResult content
   cContent := hResult[ "content" ]
   IF !Empty( cContent )
      hPlan := hb_jsonDecode( cContent )
      IF ValType( hPlan ) == "H" .AND. hb_HHasKey( hPlan, "steps" )
         ::aPlan := hPlan[ "steps" ]
      ENDIF
   ENDIF

RETURN ::aPlan

// ---------------------------------------------------------------------------

METHOD ExecutePlan() CLASS Agent

   LOCAL nStep

   FOR nStep := 1 TO Len( ::aPlan )
      IF ::aPlan[ nStep ][ "state" ] == "active"
         ::Run( "Goal: " + ::cGoal + hb_eol() + ;
                "Execute ONLY step " + hb_ntos( nStep ) + ": " + ;
                ::aPlan[ nStep ][ "title" ] )
         ::aPlan[ nStep ][ "state" ] := "done"
         IF nStep < Len( ::aPlan )
            ::aPlan[ nStep + 1 ][ "state" ] := "active"
         ENDIF
      ENDIF
   NEXT

RETURN .T.

// ============================================================================
// Utilities
// ============================================================================

METHOD UsageReport() CLASS Agent

   LOCAL nInputCost, nOutputCost, nCacheCost, nTotal

   // DeepSeek approximate pricing ($/1M tokens)
   nInputCost  := ::nTokensIn    * 0.14 / 1000000
   nOutputCost := ::nTokensOut   * 0.28 / 1000000
   nCacheCost  := ::nTokensCache * 0.0028 / 1000000
   nTotal      := nInputCost + nOutputCost + nCacheCost

RETURN nTotal

// ---------------------------------------------------------------------------

METHOD Abort() CLASS Agent

   ::lAbort   := .T.
   ::lRunning := .F.

RETURN .T.

// ---------------------------------------------------------------------------

METHOD SaveState( cDir ) CLASS Agent

   LOCAL hState, cJson, cFile

   IF !hb_vfDirExists( cDir )
      hb_vfDirMake( cDir )
   ENDIF

   hState := { "tools" => ::hUserTools, "skills_on" => ::aActiveSkills }
   hb_JsonEncode( hState, @cJson )
   cFile := cDir + "user_tools.json"
   MemoWrit( cFile, cJson )

RETURN .T.

// ---------------------------------------------------------------------------

METHOD LoadState( cDir ) CLASS Agent

   LOCAL cFile, cJson, hState

   cFile := cDir + "user_tools.json"
   IF hb_FileExists( cFile )
      cJson := hb_MemoRead( cFile )
      hState := hb_jsonDecode( cJson )
      IF ValType( hState ) == "H"
         IF hb_HHasKey( hState, "tools" )
            ::hUserTools := hState[ "tools" ]
         ENDIF
         IF hb_HHasKey( hState, "skills_on" )
            ::aActiveSkills := hState[ "skills_on" ]
         ENDIF
      ENDIF
   ENDIF

RETURN .T.

// ---------------------------------------------------------------------------

METHOD ResolveApiKey() CLASS Agent

   LOCAL hRes := { "ok" => .F., "api_key" => "", ;
                   "error_type" => NIL, "message" => NIL }
   LOCAL aEnvs := { "DEEPSEEK_API_KEY", "CCHARBOUR_API_KEY", ;
                    "GLM_API_KEY", "ZHIPU_API_KEY", ;
                    "MOONSHOT_API_KEY", "OPENAI_API_KEY" }
   LOCAL cEnv, cKey := ""

   // 1. explicit key on instance
   IF !Empty( ::cApiKey )
      cKey := ::cApiKey
   ENDIF

   // 2. environment variables
   IF Empty( cKey )
      AEval( aEnvs, {| cName | ;
         iif( Empty( cKey ), ;
              ( cEnv := hb_GetEnv( cName ), ;
                iif( !Empty( cEnv ), cKey := cEnv, NIL ) ), NIL ) } )
   ENDIF

   // 3. settings.json
   IF Empty( cKey )
      cKey := AGENT_KeyFromFile( ".agents" + hb_ps() + "settings.json" )
   ENDIF

   IF Empty( cKey )
      hRes[ "error_type" ] := "config"
      hRes[ "message" ]    := "No API key configured."
      RETURN hRes
   ENDIF

   hRes[ "api_key" ] := cKey
   hRes[ "ok" ]      := .T.

RETURN hRes

// ============================================================================
// Built-in Tool Implementations (merged from agent_tools.prg)
// ============================================================================

// read: returns line-numbered content of a text file.
METHOD Tool_Read( hArgs ) CLASS Agent

   LOCAL cPath, cText, aLines, nOffset, nMax, nFrom, nTo, i, cLine
   LOCAL cOut := "", nShown := 0

   cPath := hb_CStr( hArgs[ "path" ] )

   IF !hb_FileExists( cPath )
      RETURN "Error: file not found: " + cPath
   ENDIF

   cText  := hb_MemoRead( cPath )
   aLines := hb_ATokens( cText, Chr( 10 ) )

   FOR i := 1 TO Len( aLines )
      aLines[ i ] := StrTran( aLines[ i ], Chr( 13 ), "" )
   NEXT

   nOffset := iif( hb_HHasKey( hArgs, "offset" ) .AND. ;
                   ValType( hArgs[ "offset" ] ) == "N", Int( hArgs[ "offset" ] ), 0 )
   nMax    := iif( hb_HHasKey( hArgs, "max_lines" ) .AND. ;
                   ValType( hArgs[ "max_lines" ] ) == "N", Int( hArgs[ "max_lines" ] ), 2000 )

   nFrom := nOffset + 1
   nTo   := Min( Len( aLines ), nFrom + nMax - 1 )

   FOR i := nFrom TO nTo
      cLine := aLines[ i ]
      IF Len( cLine ) > 2000
         cLine := Left( cLine, 2000 ) + "..."
      ENDIF
      cOut += Str( i, 6 ) + Chr( 9 ) + cLine + Chr( 10 )
      nShown++
   NEXT

   IF nTo < Len( aLines )
      cOut += "[truncated: " + LTrim( Str( Len( aLines ) - nTo ) ) + ;
              " more lines]" + Chr( 10 )
   ENDIF

   IF nShown == 0
      RETURN "(empty, or offset past end of file)"
   ENDIF

RETURN cOut

// ---------------------------------------------------------------------------
// write: writes content to a file, overwriting. Shows diff on existing files.
METHOD Tool_Write( hArgs ) CLASS Agent

   LOCAL cPath, cContent, cDir, lExisted, cBefore

   cPath    := hb_CStr( hArgs[ "path" ] )
   cContent := hb_CStr( hArgs[ "content" ] )
   lExisted := hb_FileExists( cPath )
   cBefore  := iif( lExisted, hb_MemoRead( cPath ), "" )

   cDir := hb_FNameDir( cPath )
   IF !Empty( cDir ) .AND. !hb_DirExists( cDir )
      hb_DirBuild( cDir )
   ENDIF

   IF !hb_MemoWrit( cPath, cContent )
      RETURN "Error: cannot write " + cPath
   ENDIF

   IF lExisted
      RETURN AGENT_DiffLines( cBefore, cContent )
   ENDIF

RETURN "Wrote " + LTrim( Str( hb_BLen( cContent ) ) ) + " bytes to " + cPath

// ---------------------------------------------------------------------------
// edit: replaces an exact string in a file.
METHOD Tool_Edit( hArgs ) CLASS Agent

   LOCAL cPath, cOld, cNew, lAll, cBefore, cText, nCount

   cPath := hb_CStr( hArgs[ "path" ] )
   cOld  := hb_CStr( hArgs[ "old_string" ] )
   cNew  := hb_CStr( hArgs[ "new_string" ] )
   lAll  := hb_HHasKey( hArgs, "replace_all" ) .AND. ;
            hArgs[ "replace_all" ] == .T.

   IF !hb_FileExists( cPath )
      RETURN "Error: file not found: " + cPath
   ENDIF

   cBefore := hb_MemoRead( cPath )
   cText   := cBefore
   nCount  := AGENT_CountSub( cText, cOld )

   IF nCount == 0
      RETURN "Error: old_string not found in " + cPath
   ENDIF

   IF nCount > 1 .AND. !lAll
      RETURN "Error: old_string not unique (" + LTrim( Str( nCount ) ) + ;
             " matches); set replace_all or add context"
   ENDIF

   IF lAll
      cText := StrTran( cText, cOld, cNew )
   ELSE
      cText := StrTran( cText, cOld, cNew, 1, 1 )
   ENDIF

   IF !hb_MemoWrit( cPath, cText )
      RETURN "Error: cannot write " + cPath
   ENDIF

RETURN AGENT_DiffLines( cBefore, cText )

// ============================================================================
// Search Tools
// ============================================================================

// glob: lists files matching a filename pattern under a directory.
METHOD Tool_Glob( hArgs ) CLASS Agent

   LOCAL cPattern, cPath, cMask, aFiles, a1, cOut := "", nShown := 0
   LOCAL nCap := 200

   cPattern := hb_CStr( hArgs[ "pattern" ] )
   cPath    := iif( hb_HHasKey( hArgs, "path" ) .AND. ;
                    !Empty( hArgs[ "path" ] ), hb_CStr( hArgs[ "path" ] ), "." )

   IF !hb_DirExists( cPath )
      RETURN "Error: directory not found: " + cPath
   ENDIF

   // extract the file mask from the pattern
   cMask := cPattern
   IF "/" $ cMask
      cMask := SubStr( cMask, RAt( "/", cMask ) + 1 )
   ENDIF
   IF "\" $ cMask
      cMask := SubStr( cMask, RAt( "\", cMask ) + 1 )
   ENDIF

   aFiles := hb_DirScan( cPath, cMask )

   FOR EACH a1 IN aFiles
      IF "D" $ a1[ 5 ]
         LOOP
      ENDIF
      IF nShown >= nCap
         cOut += "[truncated: more matches]" + Chr( 10 )
         EXIT
      ENDIF
      cOut += a1[ 1 ] + Chr( 10 )
      nShown++
   NEXT

   IF nShown == 0
      RETURN "No matches for " + cPattern
   ENDIF

RETURN cOut

// ---------------------------------------------------------------------------
// grep: searches file contents with a regular expression.
METHOD Tool_Grep( hArgs ) CLASS Agent

   LOCAL cPattern, cPath, cGlob, pRegex, aFiles, a1, cFile, cText
   LOCAL aLines, i, cOut := "", nShown := 0, nCap := 200

   cPattern := hb_CStr( hArgs[ "pattern" ] )
   cPath    := iif( hb_HHasKey( hArgs, "path" ) .AND. ;
                    !Empty( hArgs[ "path" ] ), hb_CStr( hArgs[ "path" ] ), "." )
   cGlob    := iif( hb_HHasKey( hArgs, "glob" ) .AND. ;
                    !Empty( hArgs[ "glob" ] ), hb_CStr( hArgs[ "glob" ] ), "*" )

   IF !hb_DirExists( cPath )
      RETURN "Error: path not found: " + cPath
   ENDIF

   pRegex := hb_regexComp( cPattern )
   IF pRegex == NIL
      RETURN "Error: invalid regex: " + cPattern
   ENDIF

   aFiles := hb_DirScan( cPath, cGlob )

   FOR EACH a1 IN aFiles
      IF "D" $ a1[ 5 ]
         LOOP
      ENDIF

      cFile  := cPath + hb_ps() + a1[ 1 ]
      cText  := hb_MemoRead( cFile )
      aLines := hb_ATokens( cText, Chr( 10 ) )

      FOR i := 1 TO Len( aLines )
         IF hb_regexHas( pRegex, aLines[ i ] )
            IF nShown >= nCap
               cOut += "[truncated: more matches]" + Chr( 10 )
               RETURN cOut
            ENDIF
            cOut += a1[ 1 ] + ":" + LTrim( Str( i ) ) + ":" + ;
                    StrTran( aLines[ i ], Chr( 13 ), "" ) + Chr( 10 )
            nShown++
         ENDIF
      NEXT
   NEXT

   IF nShown == 0
      RETURN "No matches for " + cPattern
   ENDIF

RETURN cOut

// ============================================================================
// Shell Tool
// ============================================================================

// shell: runs a command through the system shell, returns output + exit code.
METHOD Tool_Shell( hArgs ) CLASS Agent

   LOCAL cCommand, cCmdLine, cOut := "", cErr := "", nExit, cResult
   LOCAL cOutFile, cScriptFile := "", hProc, hIn, hOut, hErr
   LOCAL nStart, lTimedOut := .F., nActualTimeout
   LOCAL nLeft, nShown := -1, lShow

   cCommand := hb_CStr( hArgs[ "command" ] )

   // auto-inject co-author trailer on git commit
   IF !Empty( ::cCoAuthor ) .AND. AGENT_IsGitCommit( cCommand )
      cCommand += ' --trailer "Co-authored-by: ' + ::cCoAuthor + '"'
   ENDIF

   // determine timeout
   IF hb_HHasKey( hArgs, "timeout" ) .AND. ValType( hArgs[ "timeout" ] ) == "N"
      nActualTimeout := Int( hArgs[ "timeout" ] )
      IF nActualTimeout < 0
         nActualTimeout := 0
      ENDIF
   ELSE
      nActualTimeout := AGENT_EstimateTimeout( cCommand )
   ENDIF

   IF nActualTimeout > 0
      // Timed execution: redirect to temp file, poll for completion
      cOutFile := ""
      hOut := hb_FTempCreateEx( @cOutFile, hb_DirTemp(), "atsh", ".out" )
      IF hOut != F_ERROR
         FClose( hOut )
      ENDIF

#ifdef __PLATFORM__WINDOWS
      cCmdLine := 'cmd.exe /c (' + cCommand + ') > "' + cOutFile + '" 2>&1'
#else
      cScriptFile := AGENT_ShellScript( "exec > '" + cOutFile + "' 2>&1" + ;
                                        Chr( 10 ) + cCommand + Chr( 10 ) )
      cCmdLine := "/bin/sh '" + cScriptFile + "'"
#endif

      hProc := hb_processOpen( cCmdLine, @hIn, @hOut, @hErr )

      IF hProc == F_ERROR
         RETURN "Error: cannot run shell: " + cCmdLine
      ENDIF

      FClose( hIn )
      FClose( hOut )
      FClose( hErr )

      lShow  := .T.
      nExit  := -1
      nStart := Seconds()

      DO WHILE .T.
         nExit := hb_processValue( hProc, .F. )
         IF nExit != -1
            EXIT
         ENDIF
         nLeft := nActualTimeout - ( Seconds() - nStart )
         IF nLeft <= 0
            lTimedOut := .T.
            EXIT
         ENDIF
         IF lShow .AND. Int( nLeft ) != nShown
            nShown := Int( nLeft )
         ENDIF
         hb_IdleSleep( 0.05 )
      ENDDO

      IF lTimedOut
         hb_processClose( hProc )
         nExit := -1
      ENDIF

      cResult := iif( hb_FileExists( cOutFile ), hb_MemoRead( cOutFile ), "" )
      FErase( cOutFile )
      cResult := RTrim( cResult )

      IF lTimedOut
         cResult += Chr( 10 ) + "[timed out after " + ;
                    LTrim( Str( nActualTimeout ) ) + " seconds]" + Chr( 10 )
      ENDIF
   ELSE
#ifdef __PLATFORM__WINDOWS
      cCmdLine := "cmd.exe /c " + cCommand
#else
      cScriptFile := AGENT_ShellScript( cCommand + Chr( 10 ) )
      cCmdLine := "/bin/sh '" + cScriptFile + "'"
#endif
      nExit := hb_processRun( cCmdLine, , @cOut, @cErr )
      IF nExit == -1
         RETURN "Error: cannot run shell: " + cCmdLine
      ENDIF
      cResult := cOut + cErr
   ENDIF

   // post-processing
   IF !Empty( cScriptFile )
      FErase( cScriptFile )
   ENDIF

   IF hb_BLen( cResult ) > 30000
      cResult := hb_BLeft( cResult, 30000 ) + Chr( 10 ) + ;
                 "[output truncated]" + Chr( 10 )
   ENDIF

   IF !Empty( cResult ) .AND. !( Right( cResult, 1 ) == Chr( 10 ) )
      cResult += Chr( 10 )
   ENDIF

   cResult += "[exit code: " + LTrim( Str( nExit ) ) + "]"

RETURN cResult

// ============================================================================
// Web Tools
// ============================================================================

// web_search: DuckDuckGo HTML search.
METHOD Tool_WebSearch( hArgs ) CLASS Agent

   LOCAL cQuery, cUrl, hRes, cBody, cOut := ""

   cQuery := hb_CStr( hArgs[ "query" ] )
   IF Empty( cQuery )
      RETURN "Error: query required"
   ENDIF

   cUrl := "https://html.duckduckgo.com/html/?q=" + ;
           AGENT_UrlEncode( cQuery )

   hRes := AGENT_HTTP_Fetch( { "url" => cUrl, "timeout" => 30, ;
      "headers" => { "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) " + ;
                     "AppleWebKit/537.36" } } )

   IF !hRes[ "ok" ] .OR. hRes[ "status" ] >= 400
      RETURN "Error: web search failed - " + hRes[ "error" ]
   ENDIF

   cBody := hRes[ "body" ]
   AGENT_ExtractDdgResults( cBody, @cOut )

RETURN iif( Empty( cOut ), "No results for: " + cQuery, cOut )

// ---------------------------------------------------------------------------
// web_fetch: fetches a URL and returns its content (truncated).
METHOD Tool_WebFetch( hArgs ) CLASS Agent

   LOCAL cUrl, hRes, cBody

   cUrl := hb_CStr( hArgs[ "url" ] )
   IF Empty( cUrl )
      RETURN "Error: url required"
   ENDIF

   hRes := AGENT_HTTP_Fetch( { "url" => cUrl, "timeout" => 30, ;
      "headers" => { "User-Agent: Mozilla/5.0 (compatible; CCHarbour/1.0)" } } )

   IF !hRes[ "ok" ] .OR. hRes[ "status" ] >= 400
      RETURN "Error: fetch failed - HTTP " + LTrim( Str( hRes[ "status" ] ) )
   ENDIF

   cBody := hRes[ "body" ]
   cBody := AGENT_StripHtml( cBody )

   IF hb_BLen( cBody ) > 40000
      cBody := hb_BLeft( cBody, 40000 ) + Chr( 10 ) + "[truncated]"
   ENDIF

RETURN iif( Empty( cBody ), "(empty response)", cBody )

// ============================================================================
// Tool helper functions (diff, shell, web)
// ============================================================================

// Line-level diff (ported from ccdiff.prg).
FUNCTION AGENT_DiffLines( cOld, cNew )

   LOCAL aOps, op, nAdd := 0, nDel := 0, cHdr, cOut

   aOps := AGENT_DiffOps( AGENT_DiffSplit( cOld ), AGENT_DiffSplit( cNew ) )

   FOR EACH op IN aOps
      DO CASE
      CASE op[ "t" ] == "add" ; nAdd++
      CASE op[ "t" ] == "del" ; nDel++
      ENDCASE
   NEXT

   cHdr := "Added " + LTrim( Str( nAdd ) ) + " line" + ;
           iif( nAdd == 1, "", "s" ) + ;
           ", removed " + LTrim( Str( nDel ) ) + " line" + ;
           iif( nDel == 1, "", "s" )
   cOut := AGENT_DiffFormat( aOps )

RETURN cHdr + Chr( 10 ) + cOut

STATIC FUNCTION AGENT_DiffSplit( cText )

   cText := StrTran( hb_CStr( cText ), Chr( 13 ), "" )
   IF Len( cText ) == 0
      RETURN {}
   ENDIF

RETURN hb_ATokens( cText, Chr( 10 ) )

STATIC FUNCTION AGENT_DiffOps( aOld, aNew )

   LOCAL nO := Len( aOld ), nN := Len( aNew ), aC, i, j, aOps := {}

   aC := Array( nO + 1 )
   FOR i := 1 TO nO + 1
      aC[ i ] := Array( nN + 1 )
      AFill( aC[ i ], 0 )
   NEXT

   FOR i := nO TO 1 STEP -1
      FOR j := nN TO 1 STEP -1
         IF aOld[ i ] == aNew[ j ]
            aC[ i ][ j ] := aC[ i + 1 ][ j + 1 ] + 1
         ELSE
            aC[ i ][ j ] := Max( aC[ i + 1 ][ j ], aC[ i ][ j + 1 ] )
         ENDIF
      NEXT
   NEXT

   i := 1 ; j := 1
   DO WHILE i <= nO .AND. j <= nN
      IF aOld[ i ] == aNew[ j ]
         AAdd( aOps, { "t" => "ctx", "o" => i, "n" => j, "x" => aOld[ i ] } )
         i++ ; j++
      ELSEIF aC[ i + 1 ][ j ] >= aC[ i ][ j + 1 ]
         AAdd( aOps, { "t" => "del", "o" => i, "n" => 0, "x" => aOld[ i ] } )
         i++
      ELSE
         AAdd( aOps, { "t" => "add", "o" => 0, "n" => j, "x" => aNew[ j ] } )
         j++
      ENDIF
   ENDDO

   DO WHILE i <= nO
      AAdd( aOps, { "t" => "del", "o" => i, "n" => 0, "x" => aOld[ i ] } )
      i++
   ENDDO

   DO WHILE j <= nN
      AAdd( aOps, { "t" => "add", "o" => 0, "n" => j, "x" => aNew[ j ] } )
      j++
   ENDDO

RETURN aOps

STATIC FUNCTION AGENT_DiffFormat( aOps )

   LOCAL n := Len( aOps ), aShow, i, k, cOut := "", nShown := 0
   LOCAL nCtx := 3, nCap := 60

   IF n == 0
      RETURN "(no changes)"
   ENDIF

   aShow := Array( n )
   AFill( aShow, .F. )

   FOR i := 1 TO n
      IF aOps[ i ][ "t" ] != "ctx"
         FOR k := Max( 1, i - nCtx ) TO Min( n, i + nCtx )
            aShow[ k ] := .T.
         NEXT
      ENDIF
   NEXT

   FOR i := 1 TO n
      IF !aShow[ i ] ; LOOP ; ENDIF
      IF nShown >= nCap
         cOut += "... (diff truncated)" + Chr( 10 )
         EXIT
      ENDIF
      cOut += AGENT_DiffLine( aOps[ i ] ) + Chr( 10 )
      nShown++
   NEXT

RETURN iif( Empty( cOut ), "(no changes)", cOut )

STATIC FUNCTION AGENT_DiffLine( op )

   LOCAL nNum, cMark

   DO CASE
   CASE op[ "t" ] == "add" ; nNum := op[ "n" ] ; cMark := "+"
   CASE op[ "t" ] == "del" ; nNum := op[ "o" ] ; cMark := "-"
   OTHERWISE               ; nNum := op[ "n" ] ; cMark := " "
   ENDCASE

RETURN Str( nNum, 6 ) + " " + cMark + " " + op[ "x" ]

// Counts non-overlapping occurrences of cSub in cText.
STATIC FUNCTION AGENT_CountSub( cText, cSub )

   LOCAL nCount := 0, nPos := 1, nFound

   IF Empty( cSub )
      RETURN 0
   ENDIF

   DO WHILE ( nFound := hb_At( cSub, cText, nPos ) ) > 0
      nCount++
      nPos := nFound + Len( cSub )
   ENDDO

RETURN nCount

// Detects git commit commands for co-author injection.
STATIC FUNCTION AGENT_IsGitCommit( cCmd )

   LOCAL cLow := Lower( AllTrim( cCmd ) )

   IF "co-authored-by" $ cLow .OR. "--trailer" $ cLow
      RETURN .F.
   ENDIF

RETURN "git commit" $ cLow

// Estimates a sensible timeout for a command type.
STATIC FUNCTION AGENT_EstimateTimeout( cCommand )

   LOCAL cLow := Lower( AllTrim( cCommand ) )

   DO CASE
   CASE Left( cLow, 4 ) == "echo" ; RETURN 5
   CASE Left( cLow, 3 ) == "dir"  ; RETURN 5
   CASE Left( cLow, 4 ) == "type" ; RETURN 5
   CASE Left( cLow, 4 ) == "copy" ; RETURN 10
   CASE Left( cLow, 4 ) == "move" ; RETURN 10
   CASE Left( cLow, 3 ) == "del"  ; RETURN 10
   CASE Left( cLow, 7 ) == "findstr" ; RETURN 15
   CASE Left( cLow, 4 ) == "find" ; RETURN 15
   CASE "git clone" $ cLow  ; RETURN 120
   CASE "git fetch" $ cLow  ; RETURN 60
   CASE "git pull"  $ cLow  ; RETURN 60
   CASE "git push"  $ cLow  ; RETURN 60
   CASE "git commit" $ cLow ; RETURN 15
   CASE "git add" $ cLow    ; RETURN 15
   CASE "git status" $ cLow ; RETURN 10
   CASE "git log" $ cLow    ; RETURN 10
   CASE "git diff" $ cLow   ; RETURN 10
   CASE "msbuild" $ cLow .OR. "make" $ cLow .OR. "harbour" $ cLow .OR. ;
        "hbmk2" $ cLow .OR. "gcc" $ cLow .OR. "g++" $ cLow     ; RETURN 120
   OTHERWISE                 ; RETURN 30
   ENDCASE

RETURN 30

// Writes a temp shell script (POSIX).
STATIC FUNCTION AGENT_ShellScript( cBody )

   LOCAL cFile := ""
   LOCAL hFile := hb_FTempCreateEx( @cFile, hb_DirTemp(), "atsh", ".sh" )

   IF hFile != F_ERROR
      FWrite( hFile, cBody )
      FClose( hFile )
   ENDIF

RETURN cFile

// URL-encodes a string (basic: space -> +, special chars -> %XX).
FUNCTION AGENT_UrlEncode( cText )

   LOCAL cOut := "", i, nByte, cCh

   FOR i := 1 TO hb_BLen( cText )
      nByte := hb_BCode( hb_BSubStr( cText, i, 1 ) )
      cCh   := hb_BSubStr( cText, i, 1 )

      DO CASE
      CASE nByte == 32  ; cOut += "+"
      CASE ( nByte >= 48 .AND. nByte <= 57 )  .OR. ;
           ( nByte >= 65 .AND. nByte <= 90 )  .OR. ;
           ( nByte >= 97 .AND. nByte <= 122 ) .OR. ;
           nByte == 45 .OR. nByte == 95 .OR. ;
           nByte == 46 .OR. nByte == 126
         cOut += cCh
      OTHERWISE
         cOut += "%" + hb_StrToHex( cCh )
      ENDCASE
   NEXT

RETURN cOut

// Crude extraction of DuckDuckGo HTML results.
STATIC FUNCTION AGENT_ExtractDdgResults( cHtml, cOut )

   LOCAL nPos, nEnd, cSnippet, nCount := 0

   DO WHILE ( nPos := hb_At( 'result__snippet', cHtml ) ) > 0
      cHtml := SubStr( cHtml, nPos )
      nPos   := At( '>', cHtml )
      IF nPos == 0 ; EXIT ; ENDIF
      cHtml  := SubStr( cHtml, nPos + 1 )
      nEnd   := At( '<', cHtml )
      IF nEnd == 0 ; EXIT ; ENDIF
      cSnippet := Left( cHtml, nEnd - 1 )
      cSnippet := StrTran( cSnippet, "&amp;", "&" )
      cSnippet := StrTran( cSnippet, "&lt;", "<" )
      cSnippet := StrTran( cSnippet, "&gt;", ">" )
      cSnippet := StrTran( cSnippet, "&quot;", '"' )
      cSnippet := StrTran( cSnippet, "&#x27;", "'" )
      cSnippet := AllTrim( cSnippet )
      IF !Empty( cSnippet )
         nCount++
         cOut += LTrim( Str( nCount ) ) + ". " + cSnippet + Chr( 10 )
      ENDIF
      IF nCount >= 10 ; EXIT ; ENDIF
   ENDDO

RETURN NIL

// Crude HTML tag stripper.
STATIC FUNCTION AGENT_StripHtml( cHtml )

   LOCAL cOut := "", lInTag := .F., i, cCh

   FOR i := 1 TO Len( cHtml )
      cCh := SubStr( cHtml, i, 1 )
      IF cCh == "<"
         lInTag := .T.
      ELSEIF cCh == ">"
         lInTag := .F.
      ELSEIF !lInTag
         cOut += cCh
      ENDIF
   NEXT

   cOut := StrTran( cOut, Chr( 13 ) + Chr( 10 ), Chr( 10 ) )
   cOut := StrTran( cOut, Chr( 13 ), Chr( 10 ) )

   DO WHILE Chr( 10 ) + Chr( 10 ) + Chr( 10 ) $ cOut
      cOut := StrTran( cOut, Chr( 10 ) + Chr( 10 ) + Chr( 10 ), ;
                       Chr( 10 ) + Chr( 10 ) )
   ENDDO

RETURN AllTrim( cOut )

// ============================================================================
// Helper functions (module-level)
// ============================================================================

// Registers a tool in the builtin hash
FUNCTION AGENT_RegTool( hReg, hTool )
   hReg[ hTool[ "name" ] ] := hTool
RETURN hReg

// Extracts last assistant text from message array
FUNCTION AGENT_LastText( aMsgs )
   LOCAL i
   FOR i := Len( aMsgs ) TO 1 STEP -1
      IF aMsgs[ i ][ "role" ] == "assistant"
         RETURN aMsgs[ i ][ "content" ]
      ENDIF
   NEXT
RETURN ""

// Accumulates usage totals
FUNCTION AGENT_AccUsage( hTotal, hUsage )
   LOCAL cKey
   IF ValType( hUsage ) != "H"
      RETURN NIL
   ENDIF
   FOR EACH cKey IN hb_HKeys( hUsage )
      IF ValType( hUsage[ cKey ] ) == "N"
         hTotal[ cKey ] := iif( hb_HHasKey( hTotal, cKey ), hTotal[ cKey ], 0 ) + ;
                           hUsage[ cKey ]
      ENDIF
   NEXT
RETURN NIL

// Converts internal message to API format
FUNCTION AGENT_MsgToApi( hMsg )
   LOCAL hOut := { "role" => hMsg[ "role" ], "content" => hMsg[ "content" ] }
   IF hb_HHasKey( hMsg, "tool_calls" )
      hOut[ "tool_calls" ] := hMsg[ "tool_calls" ]
   ENDIF
   IF hb_HHasKey( hMsg, "tool_call_id" )
      hOut[ "tool_call_id" ] := hMsg[ "tool_call_id" ]
   ENDIF
   IF hb_HHasKey( hMsg, "reasoning_content" )
      hOut[ "reasoning_content" ] := hMsg[ "reasoning_content" ]
   ENDIF
RETURN hOut

// Builds the request body for the chat completion API
FUNCTION AGENT_BuildBody( cModel, aMsgs, aTools, cBaseUrl )
   LOCAL hBody, lOllama := ( "11434" $ Lower( cBaseUrl ) .OR. ;
                              "ollama" $ Lower( cBaseUrl ) )
   hBody := { "model" => cModel, "messages" => aMsgs, "stream" => .T. }
   IF !lOllama
      hBody[ "stream_options" ] := { "include_usage" => .T. }
   ENDIF
   IF !Empty( aTools )
      hBody[ "tools" ] := aTools
   ENDIF
RETURN hBody

// Builds the HTTP request hash for AGENT_HTTP_Post
FUNCTION AGENT_BuildRequest( cApiUrl, cKey, cBody, nTimeout )
   LOCAL cUrl := cApiUrl
   LOCAL lOllama := ( "11434" $ Lower( cApiUrl ) .OR. "ollama" $ Lower( cApiUrl ) )

   // Ensure URL ends with /chat/completions if it doesn't already
   IF !( "/chat/completions" $ cUrl )
      IF Right( cUrl, 1 ) == "/"
         cUrl := cUrl + "chat/completions"
      ELSE
         cUrl := cUrl + "/chat/completions"
      ENDIF
   ENDIF

RETURN { "url" => cUrl, ;
         "headers" => iif( lOllama, ;
            { "Content-Type: application/json", ;
              "Authorization: Bearer ollama" }, ;
            { "Content-Type: application/json", ;
              "Accept: text/event-stream", ;
              "Authorization: Bearer " + cKey } ), ;
         "body" => cBody, ;
         "timeout" => nTimeout }

// Filters subagent tools to read-only for "explore" type
FUNCTION AGENT_FilterExploreTools( hTools )
   LOCAL aKeep := { "read", "glob", "grep", "web_search", "web_fetch", ;
                    "memory", "use_skill" }
   LOCAL aRemove := {}, cName

   FOR EACH cName IN hb_HKeys( hTools )
      IF AScan( aKeep, {| c | c == cName } ) == 0
         AAdd( aRemove, cName )
      ENDIF
   NEXT

   AEval( aRemove, {| cName | hb_HDel( hTools, cName ) } )

RETURN hTools

// Reads API key from a settings JSON file
FUNCTION AGENT_KeyFromFile( cPath )
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

// ============================================================================
// Placeholder tool handlers for UI-only tools (full implementations in agent_tools.prg)
// ============================================================================

FUNCTION AGENT_ToolMemory( hArgs )
   LOCAL cAction := hb_HGetDef( hArgs, "action", "read" )
   LOCAL cFile   := "memory.md"
   LOCAL hMemory := {=>}, cKey, cValue, cOut := ""

   IF hb_FileExists( cFile )
      AGENT_MemoryLoad( cFile, @hMemory )
   ENDIF

   DO CASE
   CASE cAction == "read"
      // return full memory
      AEval( hb_HKeys( hMemory ), {| k | ;
         cOut += k + ": " + hMemory[ k ] + Chr( 10 ) } )
      RETURN iif( Empty( cOut ), "(empty)", cOut )

   CASE cAction == "write"
      cKey   := hb_HGetDef( hArgs, "key", "" )
      cValue := hb_HGetDef( hArgs, "value", "" )
      IF Empty( cKey )
         RETURN "Error: key required for write"
      ENDIF
      hMemory[ cKey ] := cValue
      AGENT_MemorySave( cFile, hMemory )
      RETURN "Stored: " + cKey

   CASE cAction == "list"
      AEval( hb_HKeys( hMemory ), {| k | cOut += k + Chr( 10 ) } )
      RETURN iif( Empty( cOut ), "(empty)", cOut )
   ENDCASE

RETURN "Error: unknown action '" + cAction + "'"

STATIC FUNCTION AGENT_MemoryLoad( cFile, hMemory )
   LOCAL cText, aLines, cLine, nPos
   cText := hb_MemoRead( cFile )
   aLines := hb_ATokens( cText, Chr( 10 ) )
   AEval( aLines, {| cLine | ;
      iif( ( nPos := At( ":", cLine ) ) > 0, ;
           hMemory[ AllTrim( Left( cLine, nPos - 1 ) ) ] := ;
           AllTrim( SubStr( cLine, nPos + 1 ) ), NIL ) } )
RETURN NIL

STATIC FUNCTION AGENT_MemorySave( cFile, hMemory )
   LOCAL cOut := ""
   AEval( hb_HKeys( hMemory ), {| k | ;
      cOut += k + ": " + hMemory[ k ] + Chr( 10 ) } )
   MemoWrit( cFile, cOut )
RETURN NIL

FUNCTION AGENT_ToolAskUser( hArgs )
RETURN "[ask_user: " + hb_HGetDef( hArgs, "question", "?" ) + "]"

FUNCTION AGENT_ToolTodoWrite( hArgs )
RETURN "[todo_write: tasks updated]"

FUNCTION AGENT_ToolUseSkill( hArgs, oAgent )
   LOCAL cName := hb_HGetDef( hArgs, "name", "" )
   IF Empty( cName )
      RETURN "Error: skill name required"
   ENDIF
RETURN oAgent:ActivateSkill( cName )

// Executes a user-registered tool (Python or shell script)
FUNCTION AGENT_ExecUserTool( hTool, hArgs )
   LOCAL cArgs := hb_HGetDef( hArgs, "args", "" )

   IF hTool[ "type" ] == "python"
      RETURN AGENT_RunPython( hTool[ "script" ], cArgs )
   ELSE
      RETURN AGENT_RunShell( hTool[ "script" ] + " " + cArgs )
   ENDIF

STATIC FUNCTION AGENT_RunPython( cScript, cArgs )
   LOCAL cCode, cOut
   cCode := 'import sys;sys.argv=["' + cScript + '"]+' + cArgs + ;
            Chr( 10 ) + hb_MemoRead( cScript )
RETURN "[python executed]"

STATIC FUNCTION AGENT_RunShell( cCmd )
RETURN "[shell executed: " + cCmd + "]"
