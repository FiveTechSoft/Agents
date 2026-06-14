// ask_user: asks the user a multiple-choice question through an interactive
// selector and returns their chosen answer to the model.
FUNCTION CCTool_AskUser()
   RETURN { "name" => "ask_user", ;
            "description" => "Ask the user a multiple-choice question and " + ;
               "return their selected answer. Use this when you need the " + ;
               "user to make a decision before continuing. Provide 2 to 4 " + ;
               "short, distinct options.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "question" => { "type" => "string", ;
                                  "description" => "The question to ask the user" }, ;
                  "options" => { "type" => "array", ;
                                 "items" => { "type" => "string" }, ;
                                 "description" => "2 to 4 answer choices" } }, ;
               "required" => { "question", "options" } }, ;
            "handler" => {| hArgs | CCTool_AskUserRun( hArgs ) } }

STATIC FUNCTION CCTool_AskUserRun( hArgs )
   LOCAL oSel, cAnswer
   IF ValType( hArgs[ "options" ] ) != "A" .OR. Len( hArgs[ "options" ] ) < 2
      RETURN "Error: 'options' must be an array of at least 2 strings"
   ENDIF
   oSel := CCSEL_New( hb_CStr( hArgs[ "question" ] ), hArgs[ "options" ] )
   cAnswer := CCSEL_Run( oSel )
   // with no console the selector cannot prompt and defaults to option 1 --
   // say so, so the model does not treat it as a deliberate user choice
   IF !CCCON_HasConsole()
      RETURN "No console available to prompt the user; auto-selected the " + ;
             "first option: " + cAnswer
   ENDIF
   IF Empty( cAnswer )
      RETURN "User cancelled the question with Esc. Drop this line of " + ;
             "questioning and wait for the user's next instruction."
   ENDIF
   IF cAnswer == "__CCSEL_EXPLAIN__"
      RETURN "User pressed Ctrl+E asking for an explanation. Elaborate on " + ;
             "the question and each option in 1-2 short lines, then re-ask " + ;
             "with the ask_user tool."
   ENDIF
   RETURN "The user selected: " + cAnswer
