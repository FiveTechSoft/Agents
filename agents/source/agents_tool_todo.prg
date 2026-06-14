// todo_write: the agent maintains a visible session task list. Each call
// replaces the whole list; the rendered list is returned so the model and
// the user both see the current state.
FUNCTION AGTOOL_TodoWrite()
   RETURN { "name" => "todo_write", ;
            "description" => "Maintain a visible task list for multi-step " + ;
               "work. Call with the full list every time -- it replaces the " + ;
               "previous list. Mark each item pending, in_progress or " + ;
               "completed; keep exactly one item in_progress while working. " + ;
               "Optional 'id' lets later items list blockers in 'blocked_by'; " + ;
               "optional 'active_form' is the present-continuous label shown " + ;
               "in the rendered list while the item is in_progress. " + ;
               "Example arguments (real JSON uses double quotes): " + ;
               "{ todos: [ " + ;
               "{ id: 'build', text: 'Build the binary', " + ;
               "active_form: 'Building the binary', " + ;
               "status: 'in_progress' }, " + ;
               "{ id: 'test', text: 'Run the test suite', " + ;
               "active_form: 'Running tests', " + ;
               "status: 'pending', " + ;
               "blocked_by: ['build'] } ] }", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "todos" => { "type" => "array", ;
                     "description" => "The full task list", ;
                     "items" => { "type" => "object", ;
                        "properties" => { ;
                           "text" => { "type" => "string", ;
                              "description" => "The task description" }, ;
                           "status" => { "type" => "string", ;
                              "description" => "pending, in_progress or completed" }, ;
                           "id" => { "type" => "string", ;
                              "description" => "Optional identifier used by " + ;
                                 "blocked_by on other items" }, ;
                           "active_form" => { "type" => "string", ;
                              "description" => "Optional present-continuous " + ;
                                 "label shown while this item is in_progress " + ;
                                 "(e.g. 'Running tests')" }, ;
                           "blocked_by" => { "type" => "array", ;
                              "description" => "Optional list of ids this " + ;
                                 "item is blocked by", ;
                              "items" => { "type" => "string" } } }, ;
                        "required" => { "text", "status" } } } }, ;
               "required" => { "todos" } }, ;
            "handler" => {| hArgs | AGTOOL_TodoWriteRun( hArgs ) } }

STATIC FUNCTION AGTOOL_TodoWriteRun( hArgs )
   IF ValType( hArgs[ "todos" ] ) != "A"
      RETURN "Error: 'todos' must be an array"
   ENDIF
   AGTODO_Set( hArgs[ "todos" ] )
   RETURN AGUI_TodoBlock( AGTODO_Get() )
