// read: returns the line-numbered content of a text file.
FUNCTION CCTool_Read()
   RETURN { "name" => "read", ;
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
            "handler" => {| hArgs | CCTool_ReadRun( hArgs ) } }

STATIC FUNCTION CCTool_ReadRun( hArgs )
   LOCAL cPath, cText, aLines, nOffset, nMax, nFrom, nTo, i, cLine
   LOCAL cOut := "", nShown := 0
   cPath := hb_CStr( hArgs[ "path" ] )
   IF !hb_FileExists( cPath )
      RETURN "Error: file not found: " + cPath
   ENDIF
   cText  := hb_MemoRead( cPath )
   aLines := hb_ATokens( cText, Chr(10) )
   FOR i := 1 TO Len( aLines )
      aLines[ i ] := StrTran( aLines[ i ], Chr(13), "" )
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
      cOut += Str( i, 6 ) + Chr(9) + cLine + Chr(10)
      nShown++
   NEXT
   IF nTo < Len( aLines )
      cOut += "[truncated: " + LTrim( Str( Len( aLines ) - nTo ) ) + " more lines]" + Chr(10)
   ENDIF
   IF nShown == 0
      RETURN "(empty, or offset past end of file)"
   ENDIF
   RETURN cOut

// write: writes content to a file, overwriting, creating parent directories.
FUNCTION CCTool_Write()
   RETURN { "name" => "write", ;
            "description" => "Write text content to a file, overwriting it.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "path" => { "type" => "string", ;
                              "description" => "Path of the file to write" }, ;
                  "content" => { "type" => "string", ;
                                 "description" => "Content to write" } }, ;
               "required" => { "path", "content" } }, ;
            "handler" => {| hArgs | CCTool_WriteRun( hArgs ) } }

STATIC FUNCTION CCTool_WriteRun( hArgs )
   LOCAL cPath, cContent, cDir, lExisted, cBefore
   cPath    := hb_CStr( hArgs[ "path" ] )
   cContent := hb_CStr( hArgs[ "content" ] )
   lExisted := hb_FileExists( cPath )
   cBefore  := iif( lExisted, hb_MemoRead( cPath ), "" )
   cDir     := hb_FNameDir( cPath )
   IF !Empty( cDir ) .AND. !hb_DirExists( cDir )
      hb_DirBuild( cDir )
   ENDIF
   IF !hb_MemoWrit( cPath, cContent )
      RETURN "Error: cannot write " + cPath
   ENDIF
   // overwriting an existing file -> show the diff; a brand-new file -> note
   IF lExisted
      RETURN CCDIFF_Lines( cBefore, cContent )
   ENDIF
   RETURN "Wrote " + LTrim( Str( hb_BLen( cContent ) ) ) + " bytes to " + cPath

// edit: replaces an exact string in a file.
FUNCTION CCTool_Edit()
   RETURN { "name" => "edit", ;
            "description" => "Replace an exact string in a file. old_string must be unique unless replace_all is set.", ;
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
            "handler" => {| hArgs | CCTool_EditRun( hArgs ) } }

STATIC FUNCTION CCTool_EditRun( hArgs )
   LOCAL cPath, cOld, cNew, lAll, cBefore, cText, nCount
   cPath := hb_CStr( hArgs[ "path" ] )
   cOld  := hb_CStr( hArgs[ "old_string" ] )
   cNew  := hb_CStr( hArgs[ "new_string" ] )
   lAll  := hb_HHasKey( hArgs, "replace_all" ) .AND. hArgs[ "replace_all" ] == .T.
   IF !hb_FileExists( cPath )
      RETURN "Error: file not found: " + cPath
   ENDIF
   cBefore := hb_MemoRead( cPath )
   cText   := cBefore
   nCount  := CCTool_CountSub( cText, cOld )
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
   RETURN CCDIFF_Lines( cBefore, cText )

// Counts non-overlapping occurrences of cSub in cText.
STATIC FUNCTION CCTool_CountSub( cText, cSub )
   LOCAL nCount := 0, nPos := 1, nFound
   IF Empty( cSub )
      RETURN 0
   ENDIF
   DO WHILE ( nFound := hb_At( cSub, cText, nPos ) ) > 0
      nCount++
      nPos := nFound + Len( cSub )
   ENDDO
   RETURN nCount
