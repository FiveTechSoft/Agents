// The memory tool: a persistent agent memory file the model maintains across
// sessions. cMemPath (the path to memory.md) is captured at registry-build
// time, so it is injectable for tests.

FUNCTION AGTOOL_Memory( cMemPath )
   RETURN { "name" => "memory", ;
            "description" => "Your persistent memory across sessions. " + ;
               "operation 'append' adds a fact, 'read' returns the whole " + ;
               "memory, 'clear' empties it.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "operation" => { "type" => "string", ;
                     "description" => "One of: append, read, clear" }, ;
                  "text" => { "type" => "string", ;
                     "description" => "The memory entry to add (operation append)" } }, ;
               "required" => { "operation" } }, ;
            "handler" => {| hArgs | AGTOOL_MemoryRun( hArgs, cMemPath ) } }

STATIC FUNCTION AGTOOL_MemoryRun( hArgs, cMemPath )
   LOCAL cOp, cCur
   cOp := Lower( hb_CStr( hArgs[ "operation" ] ) )
   DO CASE
   CASE cOp == "append"
      IF !hb_HHasKey( hArgs, "text" ) .OR. Empty( hArgs[ "text" ] )
         RETURN "Error: memory 'append' requires 'text'"
      ENDIF
      cCur := iif( hb_FileExists( cMemPath ), hb_MemoRead( cMemPath ), "" )
      IF !Empty( cCur ) .AND. !( Right( cCur, 1 ) == Chr(10) )
         cCur += Chr(10)
      ENDIF
      IF !hb_MemoWrit( cMemPath, cCur + hb_CStr( hArgs[ "text" ] ) + Chr(10) )
         RETURN "Error: memory: cannot write " + cMemPath
      ENDIF
      RETURN "Remembered."
   CASE cOp == "read"
      cCur := iif( hb_FileExists( cMemPath ), ;
                   AllTrim( hb_CStr( hb_MemoRead( cMemPath ) ) ), "" )
      RETURN iif( Empty( cCur ), "(memory is empty)", cCur )
   CASE cOp == "clear"
      IF !hb_MemoWrit( cMemPath, "" )
         RETURN "Error: memory: cannot write " + cMemPath
      ENDIF
      RETURN "Memory cleared."
   ENDCASE
   RETURN "Error: memory: unknown operation '" + cOp + "'"
