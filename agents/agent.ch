// agent.ch — Shared CLASS Agent declaration.
// Included by agents.prg and agent_tools.prg for multi-file compilation.

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
   DATA aMessages       INIT {}        // { {role, content, ...}, ... }
   DATA cSystemPrompt   INIT ""
   DATA lRunning        INIT .F.

   // ---- tools ----
   DATA hBuiltinTools   INIT {=>}      // name => { description, parameters, handler }
   DATA hUserTools      INIT {=>}      // dynamic tools { name => { desc, script, type } }

   // ---- skills ----
   DATA hSkills         INIT {=>}      // name => content
   DATA aActiveSkills   INIT {}        // { name, name, ... }

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
   DATA bInterrupt                     // codeblock polled during loop
   DATA bInject                        // codeblock polled each iteration
   DATA bOnEvent                       // codeblock called per SSE event

   // ---- subagent ----
   DATA lIsSubAgent     INIT .F.
   DATA cSubAgentType   INIT ""

   // ========================================================================
   // Method declarations
   // ========================================================================

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

   // Built-in tools (implementations in agent_tools.prg)
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
