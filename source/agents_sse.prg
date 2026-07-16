FUNCTION AGSSE_New()
   RETURN { "buffer" => "", "closed" => .F. }

FUNCTION AGSSE_Feed( oP, cChunk, bEmit )
   LOCAL nPos, cLine
   oP[ "buffer" ] += cChunk
   DO WHILE ( nPos := At( Chr(10), oP[ "buffer" ] ) ) > 0
      cLine := Left( oP[ "buffer" ], nPos - 1 )
      oP[ "buffer" ] := SubStr( oP[ "buffer" ], nPos + 1 )
      cLine := StrTran( cLine, Chr(13), "" )
      AGSSE_Line( cLine, bEmit )
   ENDDO
   RETURN NIL

STATIC FUNCTION AGSSE_Line( cLine, bEmit )
   LOCAL cData, xJson, hChoice, hDelta
   IF Empty( cLine ) .OR. !( Left( cLine, 5 ) == "data:" )
      RETURN NIL   // comments, blank keep-alive lines, event: lines -> ignored
   ENDIF
   cData := AllTrim( SubStr( cLine, 6 ) )
   IF cData == "[DONE]"
      Eval( bEmit, { "type" => "done" } )
      RETURN NIL
   ENDIF
   xJson := hb_jsonDecode( cData )
   IF !( ValType( xJson ) == "H" )
      RETURN NIL   // unparseable / non-object -> skip silently
   ENDIF
   IF hb_HHasKey( xJson, "choices" ) .AND. Len( xJson[ "choices" ] ) > 0
      hChoice := xJson[ "choices" ][ 1 ]
      IF hb_HHasKey( hChoice, "delta" )
         hDelta := hChoice[ "delta" ]
         IF hb_HHasKey( hDelta, "content" ) .AND. ;
            ValType( hDelta[ "content" ] ) == "C" .AND. ;
            !Empty( hDelta[ "content" ] )
            Eval( bEmit, { "type" => "text_delta", "text" => hDelta[ "content" ] } )
         ENDIF
         IF hb_HHasKey( hDelta, "reasoning_content" ) .AND. ;
            ValType( hDelta[ "reasoning_content" ] ) == "C" .AND. ;
            !Empty( hDelta[ "reasoning_content" ] )
            Eval( bEmit, { "type" => "reasoning_delta", ;
                           "text" => hDelta[ "reasoning_content" ] } )
         ENDIF
         // Gemma (and other Google-origin models via Ollama) emit "reasoning"
         // instead of OpenAI's "reasoning_content" key.
         IF hb_HHasKey( hDelta, "reasoning" ) .AND. ;
            ValType( hDelta[ "reasoning" ] ) == "C" .AND. ;
            !Empty( hDelta[ "reasoning" ] )
            Eval( bEmit, { "type" => "reasoning_delta", ;
                           "text" => hDelta[ "reasoning" ] } )
         ENDIF
         IF hb_HHasKey( hDelta, "tool_calls" )
            AGSSE_ToolCalls( hDelta[ "tool_calls" ], bEmit )
         ENDIF
      ENDIF
      IF hb_HHasKey( hChoice, "finish_reason" ) .AND. ;
         ValType( hChoice[ "finish_reason" ] ) == "C"
         Eval( bEmit, { "type" => "finish", ;
                        "finish_reason" => hChoice[ "finish_reason" ] } )
      ENDIF
   ENDIF
   IF hb_HHasKey( xJson, "usage" ) .AND. ValType( xJson[ "usage" ] ) == "H"
      Eval( bEmit, { "type" => "usage", "usage" => xJson[ "usage" ] } )
   ENDIF
   RETURN NIL

STATIC FUNCTION AGSSE_ToolCalls( aCalls, bEmit )
   LOCAL hCall, hFn, hEv
   FOR EACH hCall IN aCalls
      hEv := { "type" => "tool_call_delta", "index" => 0, ;
               "id" => NIL, "name" => NIL, "arguments" => NIL }
      IF hb_HHasKey( hCall, "index" )
         hEv[ "index" ] := hCall[ "index" ]
      ENDIF
      IF hb_HHasKey( hCall, "id" )
         hEv[ "id" ] := hCall[ "id" ]
      ENDIF
      IF hb_HHasKey( hCall, "function" ) .AND. ValType( hCall[ "function" ] ) == "H"
         hFn := hCall[ "function" ]
         IF hb_HHasKey( hFn, "name" )
            hEv[ "name" ] := hFn[ "name" ]
         ENDIF
         IF hb_HHasKey( hFn, "arguments" )
            hEv[ "arguments" ] := hFn[ "arguments" ]
         ENDIF
      ENDIF
      Eval( bEmit, hEv )
   NEXT
   RETURN NIL
