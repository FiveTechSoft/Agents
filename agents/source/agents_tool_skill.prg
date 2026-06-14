// use_skill: loads a project-local skill and activates it for the current
// session. The skill body is returned to the model so its checklist becomes
// part of the agent's context for the rest of the turn; the name also lands
// in the active-skills status line under the input box.

FUNCTION CCTool_UseSkill()
   RETURN { "name" => "use_skill", ;
            "description" => "Activate a project skill: returns its " + ;
               "checklist/instructions and pins its name to the status " + ;
               "line. Use only when its description matches the task.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "name" => { "type" => "string", ;
                              "description" => "The skill name (see the " + ;
                                 "skills section of the system prompt)" } }, ;
               "required" => { "name" } }, ;
            "handler" => {| hArgs | CCTool_UseSkillRun( hArgs ) } }

STATIC FUNCTION CCTool_UseSkillRun( hArgs )
   LOCAL cName, cBody
   cName := hb_CStr( hArgs[ "name" ] )
   IF Empty( cName )
      RETURN "Error: use_skill requires 'name'"
   ENDIF
   cBody := CCSKILL_Load( cName )
   IF cBody == NIL
      RETURN "Error: skill '" + cName + "' not found in .agents/skills/"
   ENDIF
   CCSKILL_Activate( cName )
   RETURN "Skill '" + cName + "' activated. Follow these instructions:" + ;
          Chr(10) + Chr(10) + cBody
