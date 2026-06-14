// glob: lists files matching a filename mask under a directory, recursively.
FUNCTION CCTool_Glob()
   RETURN { "name" => "glob", ;
            "description" => "List files matching a filename pattern (e.g. *.prg) under a directory, recursively.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "pattern" => { "type" => "string", ;
                                 "description" => "Filename mask, e.g. *.prg or **/*.txt" }, ;
                  "path" => { "type" => "string", ;
                              "description" => "Root directory to search (default current directory)" } }, ;
               "required" => { "pattern" } }, ;
            "handler" => {| hArgs | CCTool_GlobRun( hArgs ) } }

STATIC FUNCTION CCTool_GlobRun( hArgs )
   LOCAL cPattern, cPath, cMask, aFiles, a1, cOut := "", nShown := 0
   LOCAL nCap := 200
   cPattern := hb_CStr( hArgs[ "pattern" ] )
   cPath := iif( hb_HHasKey( hArgs, "path" ) .AND. !Empty( hArgs[ "path" ] ), ;
                 hb_CStr( hArgs[ "path" ] ), "." )
   IF !hb_DirExists( cPath )
      RETURN "Error: directory not found: " + cPath
   ENDIF
   // accept "**/mask" or "dir/mask" — the last path segment is the file mask
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
         cOut += "[truncated: more matches]" + Chr(10)
         EXIT
      ENDIF
      cOut += a1[ 1 ] + Chr(10)
      nShown++
   NEXT
   IF nShown == 0
      RETURN "No matches for " + cPattern
   ENDIF
   RETURN cOut

// grep: searches file contents with a regular expression.
FUNCTION CCTool_Grep()
   RETURN { "name" => "grep", ;
            "description" => "Search file contents with a regular expression. Returns file:line:text matches.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "pattern" => { "type" => "string", ;
                                 "description" => "Regular expression to search for" }, ;
                  "path" => { "type" => "string", ;
                              "description" => "Root directory to search (default current directory)" }, ;
                  "glob" => { "type" => "string", ;
                              "description" => "Filename mask filtering which files are scanned" } }, ;
               "required" => { "pattern" } }, ;
            "handler" => {| hArgs | CCTool_GrepRun( hArgs ) } }

STATIC FUNCTION CCTool_GrepRun( hArgs )
   LOCAL cPattern, cPath, cGlob, pRegex, aFiles, a1, cFile, cText, aLines, i
   LOCAL cOut := "", nShown := 0, nCap := 200
   cPattern := hb_CStr( hArgs[ "pattern" ] )
   cPath := iif( hb_HHasKey( hArgs, "path" ) .AND. !Empty( hArgs[ "path" ] ), ;
                 hb_CStr( hArgs[ "path" ] ), "." )
   cGlob := iif( hb_HHasKey( hArgs, "glob" ) .AND. !Empty( hArgs[ "glob" ] ), ;
                 hb_CStr( hArgs[ "glob" ] ), "*" )
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
      aLines := hb_ATokens( cText, Chr(10) )
      FOR i := 1 TO Len( aLines )
         IF hb_regexHas( pRegex, aLines[ i ] )
            IF nShown >= nCap
               cOut += "[truncated: more matches]" + Chr(10)
               RETURN cOut
            ENDIF
            cOut += a1[ 1 ] + ":" + LTrim( Str( i ) ) + ":" + ;
                    StrTran( aLines[ i ], Chr(13), "" ) + Chr(10)
            nShown++
         ENDIF
      NEXT
   NEXT
   IF nShown == 0
      RETURN "No matches for " + cPattern
   ENDIF
   RETURN cOut
