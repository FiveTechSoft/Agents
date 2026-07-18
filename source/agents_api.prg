// Agents API — SSE parser, HTTP transport (curl), UTF-8 sanitizer.
// Called by Agent:Step() and Agent tool methods.

#include "fileio.ch"

// ============================================================================
// SSE Parser
// ============================================================================

FUNCTION AGENT_SSE_New()
RETURN { "buffer" => "", "closed" => .F. }

FUNCTION AGENT_SSE_Feed( oP, cChunk, bEmit )
   LOCAL nPos, cLine
   oP[ "buffer" ] += cChunk
   DO WHILE ( nPos := At( Chr( 10 ), oP[ "buffer" ] ) ) > 0
      cLine := Left( oP[ "buffer" ], nPos - 1 )
      oP[ "buffer" ] := SubStr( oP[ "buffer" ], nPos + 1 )
      cLine := StrTran( cLine, Chr( 13 ), "" )
      AGENT_SSE_Line( cLine, bEmit )
   ENDDO
RETURN NIL

STATIC FUNCTION AGENT_SSE_Line( cLine, bEmit )
   LOCAL cData, xJson, hChoice, hDelta, hUsage
   IF Empty( cLine ) .OR. !( Left( cLine, 5 ) == "data:" )
      RETURN NIL
   ENDIF
   cData := AllTrim( SubStr( cLine, 6 ) )
   IF cData == "[DONE]"
      AGENT_Emit( bEmit, { "type" => "done" } )
      RETURN NIL
   ENDIF
   xJson := hb_jsonDecode( cData )
   IF !( ValType( xJson ) == "H" )
      RETURN NIL
   ENDIF
   IF hb_HHasKey( xJson, "choices" ) .AND. Len( xJson[ "choices" ] ) > 0
      hChoice := xJson[ "choices" ][ 1 ]
      IF hb_HHasKey( hChoice, "delta" )
         hDelta := hChoice[ "delta" ]
         IF hb_HHasKey( hDelta, "content" ) .AND. ValType( hDelta[ "content" ] ) == "C" .AND. !Empty( hDelta[ "content" ] )
            AGENT_Emit( bEmit, { "type" => "text_delta", "text" => hDelta[ "content" ] } )
         ENDIF
         IF hb_HHasKey( hDelta, "reasoning_content" ) .AND. ValType( hDelta[ "reasoning_content" ] ) == "C" .AND. !Empty( hDelta[ "reasoning_content" ] )
            AGENT_Emit( bEmit, { "type" => "reasoning_delta", "text" => hDelta[ "reasoning_content" ] } )
         ENDIF
         IF hb_HHasKey( hDelta, "reasoning" ) .AND. ValType( hDelta[ "reasoning" ] ) == "C" .AND. !Empty( hDelta[ "reasoning" ] )
            AGENT_Emit( bEmit, { "type" => "reasoning_delta", "text" => hDelta[ "reasoning" ] } )
         ENDIF
         IF hb_HHasKey( hDelta, "tool_calls" )
            AGENT_SSE_ToolCalls( hDelta[ "tool_calls" ], bEmit )
         ENDIF
      ENDIF
      IF hb_HHasKey( hChoice, "finish_reason" ) .AND. ValType( hChoice[ "finish_reason" ] ) == "C"
         AGENT_Emit( bEmit, { "type" => "finish", "finish_reason" => hChoice[ "finish_reason" ] } )
      ENDIF
   ENDIF
   // OpenAI usage and/or Ollama prompt_eval_count/eval_count (normalized).
   hUsage := AGSSE_NormalizeUsage( xJson )
   IF hUsage != NIL
      AGENT_Emit( bEmit, { "type" => "usage", "usage" => hUsage } )
   ENDIF
RETURN NIL

STATIC FUNCTION AGENT_SSE_ToolCalls( aCalls, bEmit )
   LOCAL hCall, hFn, hEv
   FOR EACH hCall IN aCalls
      hEv := { "type" => "tool_call_delta", "index" => 0, "id" => NIL, "name" => NIL, "arguments" => NIL }
      IF hb_HHasKey( hCall, "index" )    ; hEv[ "index" ] := hCall[ "index" ] ; ENDIF
      IF hb_HHasKey( hCall, "id" )       ; hEv[ "id" ] := hCall[ "id" ]       ; ENDIF
      IF hb_HHasKey( hCall, "function" ) .AND. ValType( hCall[ "function" ] ) == "H"
         hFn := hCall[ "function" ]
         IF hb_HHasKey( hFn, "name" )      ; hEv[ "name" ] := hFn[ "name" ]           ; ENDIF
         IF hb_HHasKey( hFn, "arguments" ) ; hEv[ "arguments" ] := hFn[ "arguments" ] ; ENDIF
      ENDIF
      AGENT_Emit( bEmit, hEv )
   NEXT
RETURN NIL

FUNCTION AGENT_Emit( bEmit, hEv )
   IF bEmit != NIL .AND. ValType( bEmit ) == "B"
      Eval( bEmit, hEv )
   ENDIF
RETURN NIL

// ============================================================================
// Stream accumulator
// ============================================================================

FUNCTION AGENT_FeedChunk( cChunk, hState, oParser, bOnEvent )
   LOCAL bAccum
   hState[ "raw" ] += cChunk
   bAccum := {| hEv | AGENT_OnEvent( hEv, hState, bOnEvent ) }
   AGENT_SSE_Feed( oParser, cChunk, bAccum )
RETURN NIL

FUNCTION AGENT_OnEvent( hEv, hState, bOnEvent )
   DO CASE
   CASE hEv[ "type" ] == "text_delta"      ; hState[ "content" ]    += hEv[ "text" ]
   CASE hEv[ "type" ] == "reasoning_delta" ; hState[ "reasoning" ]  += hEv[ "text" ]
   CASE hEv[ "type" ] == "tool_call_delta" ; AGENT_AccTool( hState[ "tools" ], hEv )
   CASE hEv[ "type" ] == "finish"          ; hState[ "finish" ]     := hEv[ "finish_reason" ]
   CASE hEv[ "type" ] == "usage"           ; hState[ "usage" ]      := hEv[ "usage" ]
   CASE hEv[ "type" ] == "done"            ; hState[ "got_done" ]   := .T.
   ENDCASE
   AGENT_Emit( bOnEvent, hEv )
RETURN NIL

FUNCTION AGENT_AccTool( aTools, hEv )
   LOCAL hTool, nFound := 0, i
   FOR i := 1 TO Len( aTools )
      IF aTools[ i ][ "index" ] == hEv[ "index" ] ; nFound := i ; EXIT ; ENDIF
   NEXT
   IF nFound == 0
      hTool := { "index" => hEv[ "index" ], "id" => "", "name" => "", "arguments" => "" }
      AAdd( aTools, hTool )
   ELSE
      hTool := aTools[ nFound ]
   ENDIF
   IF hEv[ "id" ] != NIL        ; hTool[ "id" ] := hEv[ "id" ]             ; ENDIF
   IF hEv[ "name" ] != NIL      ; hTool[ "name" ] := hEv[ "name" ]         ; ENDIF
   IF hEv[ "arguments" ] != NIL ; hTool[ "arguments" ] += hEv[ "arguments" ] ; ENDIF
RETURN NIL

// ============================================================================
// HTTP Transport (curl subprocess)
// ============================================================================

FUNCTION AGENT_HTTP_Post( hReq, bOnChunk )
   LOCAL hProc, hIn, hOut, hErr, hTmp, cHdrFile := "", cCmd, cHdr, nTimeout
   LOCAL cBuf := Space( 16384 ), nRead, nExit, nStatus := 0, cErr := ""
   nTimeout := iif( hb_HHasKey( hReq, "timeout" ) .AND. ValType( hReq[ "timeout" ] ) == "N", hReq[ "timeout" ], 120 )
   hTmp := hb_FTempCreateEx( @cHdrFile, hb_DirTemp(), "agt", ".hdr" )
   IF hTmp != F_ERROR ; FClose( hTmp ) ; ENDIF
   cCmd := "curl -sS -N --max-time " + LTrim( Str( nTimeout ) ) + " -X POST -D " + Chr( 34 ) + cHdrFile + Chr( 34 ) + " --data-binary @-"
   FOR EACH cHdr IN hReq[ "headers" ] ; cCmd += " -H " + Chr( 34 ) + cHdr + Chr( 34 ) ; NEXT
   cCmd += " " + Chr( 34 ) + hReq[ "url" ] + Chr( 34 )
   hProc := hb_processOpen( cCmd, @hIn, @hOut, @hErr )
   IF hProc == F_ERROR
      IF !Empty( cHdrFile ) ; FErase( cHdrFile ) ; ENDIF
      RETURN { "ok" => .F., "status" => 0, "curl_code" => -1, "error" => "failed to spawn curl" }
   ENDIF
   IF hb_HHasKey( hReq, "body" ) .AND. !Empty( hReq[ "body" ] ) ; FWrite( hIn, hReq[ "body" ] ) ; ENDIF
   FClose( hIn )
   DO WHILE ( nRead := FRead( hOut, @cBuf, hb_BLen( cBuf ) ) ) > 0
      Eval( bOnChunk, hb_BLeft( cBuf, nRead ) )
      IF InKey( 0.01 ) == 3
         hb_processClose( hProc ) ; FClose( hOut ) ; FClose( hErr )
         IF !Empty( cHdrFile ) ; FErase( cHdrFile ) ; ENDIF
         RETURN { "ok" => .F., "status" => 0, "curl_code" => -2, "error" => "cancelled" }
      ENDIF
   ENDDO
   DO WHILE ( nRead := FRead( hErr, @cBuf, hb_BLen( cBuf ) ) ) > 0 ; cErr += hb_BLeft( cBuf, nRead ) ; ENDDO
   FClose( hOut ) ; FClose( hErr ) ; nExit := hb_processValue( hProc )
   nStatus := AGENT_HTTP_ParseStatus( cHdrFile ) ; FErase( cHdrFile )
RETURN { "ok" => ( nExit == 0 ), "status" => nStatus, "curl_code" => nExit, "error" => iif( nExit == 0, "", iif( Empty( cErr ), "curl exit " + LTrim( Str( nExit ) ), AllTrim( cErr ) ) ) }

STATIC FUNCTION AGENT_HTTP_ParseStatus( cHdrFile )
   LOCAL cText, cLine, nStatus := 0, aTok
   IF Empty( cHdrFile ) .OR. !hb_FileExists( cHdrFile ) ; RETURN 0 ; ENDIF
   cText := hb_MemoRead( cHdrFile )
   FOR EACH cLine IN hb_ATokens( cText, Chr( 10 ) )
      IF Left( cLine, 5 ) == "HTTP/"
         aTok := hb_ATokens( AllTrim( cLine ), " " )
         IF Len( aTok ) >= 2 .AND. IsDigit( Left( aTok[ 2 ], 1 ) ) ; nStatus := Val( aTok[ 2 ] ) ; ENDIF
      ENDIF
   NEXT
RETURN nStatus

FUNCTION AGENT_HTTP_Fetch( hReq )
   LOCAL hProc, hIn, hOut, hErr, hTmp, cHdrFile := "", cCmd, cHdr, nTimeout, cMethod
   LOCAL cBuf := Space( 16384 ), nRead, nExit, nStatus := 0, cErr := "", cBody := "", cReqBody, lHasBody
   IF !hb_HHasKey( hReq, "url" ) .OR. Empty( hReq[ "url" ] )
      RETURN { "ok" => .F., "status" => 0, "body" => "", "error" => "missing url" }
   ENDIF
   cMethod  := iif( hb_HHasKey( hReq, "method" ), Upper( hb_CStr( hReq[ "method" ] ) ), "GET" )
   nTimeout := iif( hb_HHasKey( hReq, "timeout" ) .AND. ValType( hReq[ "timeout" ] ) == "N", hReq[ "timeout" ], 60 )
   cReqBody := iif( hb_HHasKey( hReq, "body" ) .AND. ValType( hReq[ "body" ] ) == "C", hReq[ "body" ], "" )
   lHasBody := !Empty( cReqBody ) .AND. ( cMethod == "POST" .OR. cMethod == "PATCH" )
   hTmp := hb_FTempCreateEx( @cHdrFile, hb_DirTemp(), "agf", ".hdr" )
   IF hTmp != F_ERROR ; FClose( hTmp ) ; ENDIF
   cCmd := "curl -sS --max-time " + LTrim( Str( nTimeout ) ) + " -X " + cMethod + " -D " + Chr( 34 ) + cHdrFile + Chr( 34 )
   IF lHasBody ; cCmd += " --data-binary @-" ; ENDIF
   IF hb_HHasKey( hReq, "headers" ) .AND. ValType( hReq[ "headers" ] ) == "A"
      FOR EACH cHdr IN hReq[ "headers" ] ; cCmd += " -H " + Chr( 34 ) + cHdr + Chr( 34 ) ; NEXT
   ENDIF
   cCmd += " " + Chr( 34 ) + hReq[ "url" ] + Chr( 34 )
   hProc := hb_processOpen( cCmd, @hIn, @hOut, @hErr )
   IF hProc == F_ERROR
      IF !Empty( cHdrFile ) ; FErase( cHdrFile ) ; ENDIF
      RETURN { "ok" => .F., "status" => 0, "body" => "", "error" => "failed to spawn curl" }
   ENDIF
   IF lHasBody ; FWrite( hIn, cReqBody ) ; ENDIF
   FClose( hIn )
   DO WHILE ( nRead := FRead( hOut, @cBuf, hb_BLen( cBuf ) ) ) > 0 ; cBody += hb_BLeft( cBuf, nRead ) ; ENDDO
   DO WHILE ( nRead := FRead( hErr, @cBuf, hb_BLen( cBuf ) ) ) > 0 ; cErr += hb_BLeft( cBuf, nRead ) ; ENDDO
   FClose( hOut ) ; FClose( hErr ) ; nExit := hb_processValue( hProc )
   nStatus := AGENT_HTTP_ParseStatus( cHdrFile ) ; FErase( cHdrFile )
RETURN { "ok" => ( nExit == 0 ), "status" => nStatus, "body" => cBody, "error" => iif( nExit == 0, "", iif( Empty( cErr ), "curl exit " + LTrim( Str( nExit ) ), AllTrim( cErr ) ) ) }

// ============================================================================
// UTF-8 Sanitization
// ============================================================================

FUNCTION AGENT_SanitizeUTF8( cText )
   LOCAL cOut := "", i := 1, nLen, nByte, nCont, nNeed
   IF ValType( cText ) != "C" ; RETURN "?" ; ENDIF
   nLen := hb_BLen( cText )
   DO WHILE i <= nLen
      nByte := hb_BCode( hb_BSubStr( cText, i, 1 ) )
      DO CASE
      CASE nByte < 32
         IF nByte == 9 .OR. nByte == 10 .OR. nByte == 13 ; cOut += hb_BSubStr( cText, i, 1 )
         ELSE ; cOut += "?" ; ENDIF ; i++
      CASE nByte < 128 ; cOut += hb_BSubStr( cText, i, 1 ) ; i++
      CASE nByte < 192 ; cOut += "?" ; i++
      CASE nByte < 224 ; nNeed := 1
         IF i + nNeed <= nLen
            nCont := hb_BCode( hb_BSubStr( cText, i + 1, 1 ) )
            IF nCont >= 128 .AND. nCont < 192 ; cOut += hb_BSubStr( cText, i, 2 ) ; i += 2
            ELSE ; cOut += "?" ; i++ ; ENDIF
         ELSE ; cOut += "?" ; i++ ; ENDIF
      CASE nByte < 240 ; nNeed := 2
         IF i + nNeed <= nLen
            nCont := hb_BCode( hb_BSubStr( cText, i + 1, 1 ) )
            IF nCont >= 128 .AND. nCont < 192
               nCont := hb_BCode( hb_BSubStr( cText, i + 2, 1 ) )
               IF nCont >= 128 .AND. nCont < 192 ; cOut += hb_BSubStr( cText, i, 3 ) ; i += 3
               ELSE ; cOut += "?" ; i++ ; ENDIF
            ELSE ; cOut += "?" ; i++ ; ENDIF
         ELSE ; cOut += "?" ; i++ ; ENDIF
      CASE nByte < 248 ; nNeed := 3
         IF i + nNeed <= nLen
            nCont := hb_BCode( hb_BSubStr( cText, i + 1, 1 ) )
            IF nCont >= 128 .AND. nCont < 192
               nCont := hb_BCode( hb_BSubStr( cText, i + 2, 1 ) )
               IF nCont >= 128 .AND. nCont < 192
                  nCont := hb_BCode( hb_BSubStr( cText, i + 3, 1 ) )
                  IF nCont >= 128 .AND. nCont < 192 ; cOut += hb_BSubStr( cText, i, 4 ) ; i += 4
                  ELSE ; cOut += "?" ; i++ ; ENDIF
               ELSE ; cOut += "?" ; i++ ; ENDIF
            ELSE ; cOut += "?" ; i++ ; ENDIF
         ELSE ; cOut += "?" ; i++ ; ENDIF
      OTHERWISE ; cOut += "?" ; i++
      ENDCASE
   ENDDO
RETURN cOut
