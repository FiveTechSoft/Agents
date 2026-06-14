// propose_agents: a gate the agent calls BEFORE dispatching 2+ subagents.
// It opens an interactive multi-row selector so the user can review every
// proposal, drop ones they do not want, and confirm or cancel the whole
// batch. The tool returns the approved list as a JSON array of
// { agent_type, prompt } items; the agent then iterates and invokes
// dispatch_agent for each.

FUNCTION CCTool_ProposeAgents()
   RETURN { "name" => "propose_agents", ;
            "description" => "Propose a batch of subagents (2+) to the user " + ;
               "BEFORE dispatching any of them. Use this whenever you would " + ;
               "otherwise call dispatch_agent two or more times in a row. " + ;
               "An interactive selector lets the user toggle each proposal " + ;
               "on/off and confirm; the tool returns the approved list as a " + ;
               "JSON array of { agent_type, prompt } items, or " + ;
               "'[cancelled]' if the user rejected the batch. After " + ;
               "approval, iterate over the result and call dispatch_agent " + ;
               "once per item. Example: { agents: [ " + ;
               "{ agent_type: 'explore', prompt: 'List every .prg under " + ;
               "src/' }, { agent_type: 'explore', prompt: 'Find every " + ;
               "STATIC FUNCTION across src/' } ] }", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "agents" => { "type" => "array", ;
                                "description" => "The proposed subagents", ;
                                "items" => { "type" => "object", ;
                                   "properties" => { ;
                                      "agent_type" => { "type" => "string", ;
                                         "description" => "explore or general" }, ;
                                      "prompt" => { "type" => "string", ;
                                         "description" => "The task for this subagent" } }, ;
                                   "required" => { "agent_type", "prompt" } } } }, ;
               "required" => { "agents" } }, ;
            "handler" => {| hArgs | CCTool_ProposeAgentsRun( hArgs ) } }

STATIC FUNCTION CCTool_ProposeAgentsRun( hArgs )
   LOCAL oSel, aApproved, cOut, h, n
   IF !hb_HHasKey( hArgs, "agents" ) .OR. ValType( hArgs[ "agents" ] ) != "A"
      RETURN "Error: propose_agents requires 'agents' (array)"
   ENDIF
   IF Empty( hArgs[ "agents" ] )
      RETURN "Error: propose_agents needs at least one proposal"
   ENDIF
   oSel := CCPROPOSE_New( hArgs[ "agents" ] )
   IF Empty( oSel[ "items" ] )
      RETURN "Error: no valid proposals (each needs agent_type and prompt)"
   ENDIF
   aApproved := CCPROPOSE_Run( oSel )
   IF aApproved == NIL
      RETURN "[cancelled] User cancelled the batch. Wait for new " + ;
             "instructions; do not dispatch anything."
   ENDIF
   IF Empty( aApproved )
      RETURN "[empty] User confirmed but rejected every proposal. Do not " + ;
             "dispatch. Ask the user how to proceed."
   ENDIF
   // top up dispatch_agent's per-turn allowance so the approved batch
   // dispatches without the second-call gate kicking in
   CCTool_DispatchGrantAllowance( Len( aApproved ) )
   // build a JSON array so the model can iterate it deterministically
   cOut := "User approved " + LTrim( Str( Len( aApproved ) ) ) + " of " + ;
           LTrim( Str( Len( oSel[ "items" ] ) ) ) + " proposals. " + ;
           "Call dispatch_agent ONCE per item below, in order:" + Chr(10) + "["
   n := 0
   FOR EACH h IN aApproved
      IF ++n > 1
         cOut += ","
      ENDIF
      cOut += Chr(10) + "  { " + ;
              Chr(34) + "agent_type" + Chr(34) + ": " + ;
              Chr(34) + h[ "agent_type" ] + Chr(34) + ", " + ;
              Chr(34) + "prompt" + Chr(34) + ": " + ;
              hb_jsonEncode( h[ "prompt" ] ) + " }"
   NEXT
   cOut += Chr(10) + "]"
   RETURN cOut
