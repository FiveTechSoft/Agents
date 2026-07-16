// Wraps a raw tool executor with a permission gate.
// bInner       : the raw executor, {|cName,cArgsJson| -> cString}.
// hPermissions : { toolName => "allow"|"deny"|"ask" }.
// bAsk         : optional {|cName,cArgsJson| -> "y"|"n"|"a"}.
// Returns a gated executor with the same {|cName,cArgsJson| -> cString} contract.
FUNCTION AGPERM_Gate( bInner, hPermissions, bAsk )
   LOCAL hPerm := AGPERM_CloneModes( hPermissions )
   RETURN {| cName, cArgsJson | ;
      AGPERM_Decide( hPerm, bInner, bAsk, cName, cArgsJson ) }

// Copies the caller's permission hash so an "a" upgrade never mutates it.
STATIC FUNCTION AGPERM_CloneModes( hPermissions )
   LOCAL hOut := {=>}, cKey
   IF ValType( hPermissions ) == "H"
      FOR EACH cKey IN hb_HKeys( hPermissions )
         hOut[ cKey ] := hPermissions[ cKey ]
      NEXT
   ENDIF
   RETURN hOut

// Decides allow/deny for one call; "a" upgrades the tool to allow for the session.
STATIC FUNCTION AGPERM_Decide( hPerm, bInner, bAsk, cName, cArgsJson )
   LOCAL cMode, cAns
   // ask_user / todo_write only drive the UI; use_skill and dispatch_agent
   // are dispatchers of work the user already requested -- inherently
   // consented, never gated
   IF cName == "ask_user" .OR. cName == "todo_write" .OR. ;
      cName == "use_skill" .OR. cName == "dispatch_agent" .OR. ;
      cName == "dispatch_agent_background" .OR. cName == "propose_agents"
      RETURN Eval( bInner, cName, cArgsJson )
   ENDIF
   // Plan mode locks every codebase-mutating or shell-running tool until the
   // user types /plan accept. Read-only tools (read, glob, grep, github_read,
   // memory, web_fetch, web_search, use_skill) are unaffected so the agent
   // can still gather context while planning.
   IF AGREPL_PlanMode() .AND. ;
      ( cName == "write" .OR. cName == "edit" .OR. cName == "shell" .OR. ;
        cName == "github_write" )
      RETURN "Error: plan mode is active. '" + cName + "' is locked until " + ;
             "the user types '/plan accept'. Continue the plan as text only."
   ENDIF
   cMode := iif( hb_HHasKey( hPerm, cName ), hPerm[ cName ], "ask" )
   IF !( cMode == "allow" .OR. cMode == "deny" .OR. cMode == "ask" )
      cMode := "ask"
   ENDIF
   DO CASE
   CASE cMode == "allow"
      RETURN Eval( bInner, cName, cArgsJson )
   CASE cMode == "deny"
      RETURN "Error: tool '" + hb_CStr( cName ) + "' denied by policy"
   ENDCASE
   // cMode == "ask"
   cAns := iif( bAsk == NIL, "n", AGPERM_Norm( Eval( bAsk, cName, cArgsJson ) ) )
   DO CASE
   CASE cAns == "y"
      RETURN Eval( bInner, cName, cArgsJson )
   CASE cAns == "a"
      hPerm[ cName ] := "allow"
      RETURN Eval( bInner, cName, cArgsJson )
   ENDCASE
   RETURN "Error: tool '" + hb_CStr( cName ) + "' denied by user"

// Normalises an ask answer to a single lowercase character; non-strings -> "n".
STATIC FUNCTION AGPERM_Norm( xAns )
   LOCAL cAns
   IF ValType( xAns ) != "C"
      RETURN "n"
   ENDIF
   cAns := Lower( AllTrim( xAns ) )
   RETURN iif( Empty( cAns ), "n", Left( cAns, 1 ) )
