// HTTP transport for the DeepSeek client.
//
// curl CLI subprocess (not hbcurl). Interactive-safe on Windows:
//
//   * Body on disk (--data-binary @file) — no stdin pipe deadlock.
//   * Response on STDOUT pipe.
//   * NEVER block on FRead unless PeekNamedPipe says bytes are waiting.
//   * When the pipe is empty: run on_idle (spinner + keyboard) + sleep.
//   * Process liveness via GetExitCodeProcess (STILL_ACTIVE=259).
//   * NO reader threads — they deadlock with Harbour GT on this build.
//
// Verified: blocking FRead works; threaded reader hung; Peek+idle produces
// dots while waiting and stars for each chunk.

#include "fileio.ch"
#include "hbdyn.ch"

STATIC s_bTestTransport := NIL

#define AGHTTP_STILL_ACTIVE  259

// Normalizes an hb_dynCall BOOL result. The call may return a logical OR
// a numeric depending on the ABI wrapper; comparing a logical against a
// number ("xOk == 1") throws BASE/1 Argument error in Harbour — that
// crash killed /plan whenever PeekNamedPipe failed on a closed pipe.
STATIC FUNCTION AGHTTP_DynBool( xVal )
   DO CASE
   CASE ValType( xVal ) == "L" ; RETURN xVal
   CASE ValType( xVal ) == "N" ; RETURN xVal != 0
   ENDCASE
   RETURN .F.

FUNCTION AGHTTP_Post( hReq, bOnChunk, bTransport )
   IF bTransport != NIL
      RETURN Eval( bTransport, hReq, bOnChunk )
   ENDIF
   RETURN AGHTTP_CurlPost( hReq, bOnChunk )

FUNCTION AGHTTP_CurlPost( hReq, bOnChunk )
   LOCAL hProc, hIn, hOut, hErr, hTmp
   LOCAL cHdrFile := "", cBodyFile := "", cCmd, cHdr, nTimeout
   LOCAL nExit := -1, nStatus := 0, cErr := "", cBody, cBuf
   LOCAL bIdle, nStart, nLastIdle := 0, nNow, nAvail, nRead
   LOCAL nLimit, lDone := .F., nLastByte := 0, nTotal := 0
   LOCAL lKilled := .F., lOk := .F., lTimedOut := .F.

   nTimeout := iif( hb_HHasKey( hReq, "timeout" ) .AND. ;
                    ValType( hReq[ "timeout" ] ) == "N", hReq[ "timeout" ], 120 )
   bIdle := iif( hb_HHasKey( hReq, "on_idle" ), hReq[ "on_idle" ], NIL )
   cBody := iif( hb_HHasKey( hReq, "body" ), hb_CStr( hReq[ "body" ] ), "" )
   nLimit := nTimeout * 1000 + 8000

   hTmp := hb_FTempCreateEx( @cHdrFile, hb_DirTemp(), "dsh", ".hdr" )
   IF hTmp != F_ERROR ; FClose( hTmp ) ; ENDIF
   hTmp := hb_FTempCreateEx( @cBodyFile, hb_DirTemp(), "dsb", ".json" )
   IF hTmp != F_ERROR ; FClose( hTmp ) ; ENDIF
   hb_MemoWrit( cBodyFile, cBody )

   cCmd := "curl -sS -N --max-time " + LTrim( Str( nTimeout ) ) + ;
           " -X POST -D " + Chr( 34 ) + cHdrFile + Chr( 34 ) + ;
           " --data-binary @" + Chr( 34 ) + cBodyFile + Chr( 34 )
   FOR EACH cHdr IN hReq[ "headers" ]
      cCmd += " -H " + Chr( 34 ) + cHdr + Chr( 34 )
   NEXT
   cCmd += " " + Chr( 34 ) + hReq[ "url" ] + Chr( 34 )

   hProc := hb_processOpen( cCmd, @hIn, @hOut, @hErr )
   IF hProc == F_ERROR
      IF !Empty( cHdrFile )  ; FErase( cHdrFile )  ; ENDIF
      IF !Empty( cBodyFile ) ; FErase( cBodyFile ) ; ENDIF
      RETURN { "ok" => .F., "status" => 0, "curl_code" => -1, ;
               "error" => "failed to spawn curl" }
   ENDIF
   FClose( hIn )

   cBuf := Space( 16384 )
   nStart := hb_MilliSeconds()

   DO WHILE !lDone
      nNow := hb_MilliSeconds()
      IF ( nNow - nStart ) > nLimit
         cErr := "timeout"
         lTimedOut := .T.
         AGHTTP_KillProc( hProc )
         lKilled := .T.
         lDone := .T.
         LOOP
      ENDIF

      nAvail := AGHTTP_PipeAvail( hOut )

      IF nAvail > 0
         // Only read what Peek says is waiting — never block the TUI.
         nRead := FRead( hOut, @cBuf, Min( nAvail, hb_BLen( cBuf ) ) )
         IF nRead > 0
            nTotal += nRead
            nLastByte := nNow
            IF bOnChunk != NIL
               Eval( bOnChunk, hb_BLeft( cBuf, nRead ) )
            ENDIF
         ELSE
            lDone := .T.
         ENDIF
      ELSEIF nTotal > 0 .AND. nLastByte > 0 .AND. ;
             ( nNow - nLastByte ) >= 4000
         // 4s silence after bytes: stream finished (or keep-alive hang).
         // Kill curl *before* closing the pipe so we don't get a noisy
         // CURLE_WRITE_ERROR (exit 23) from a broken pipe.
         // GetExitCodeProcess is unreliable on some Harbour process handles.
         IF AGHTTP_ProcRunning( hProc )
            AGHTTP_KillProc( hProc )
            lKilled := .T.
         ENDIF
         DO WHILE ( nRead := FRead( hOut, @cBuf, hb_BLen( cBuf ) ) ) > 0
            nTotal += nRead
            nLastByte := nNow
            IF bOnChunk != NIL
               Eval( bOnChunk, hb_BLeft( cBuf, nRead ) )
            ENDIF
         ENDDO
         lDone := .T.
      ELSEIF !AGHTTP_ProcRunning( hProc )
         // curl exited. Drain whatever remains (writer is dead — safe).
         DO WHILE ( nRead := FRead( hOut, @cBuf, hb_BLen( cBuf ) ) ) > 0
            nTotal += nRead
            IF bOnChunk != NIL
               Eval( bOnChunk, hb_BLeft( cBuf, nRead ) )
            ENDIF
         ENDDO
         lDone := .T.
      ELSE
         // Still running, no bytes → animate + accept keys
         IF bIdle != NIL .AND. ( nNow - nLastIdle ) >= 80
            nLastIdle := nNow
            Eval( bIdle )
         ENDIF
         hb_idleSleep( 0.04 )
      ENDIF
   ENDDO

   // Best-effort stderr (peek only — never block)
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      nAvail := AGHTTP_PipeAvail( hErr )
      IF nAvail > 0
         nRead := FRead( hErr, @cBuf, Min( nAvail, hb_BLen( cBuf ) ) )
         IF nRead > 0
            // Prefer structured timeout flag over raw stderr noise.
            IF !lTimedOut
               cErr += hb_BLeft( cBuf, nRead )
            ENDIF
         ENDIF
      ENDIF
      FClose( hOut )
      FClose( hErr )
   RECOVER
   END SEQUENCE

   // Reap child; should return quickly if already dead / killed
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      nExit := hb_processValue( hProc )
   RECOVER
      nExit := iif( Empty( cErr ), -1, 0 )
   END SEQUENCE

   nStatus := AGHTTP_ParseStatus( cHdrFile )
   IF !Empty( cHdrFile )  ; FErase( cHdrFile )  ; ENDIF
   IF !Empty( cBodyFile ) ; FErase( cBodyFile ) ; ENDIF

   // Classify exit. curl 23 = CURLE_WRITE_ERROR (broken pipe to our reader).
   // After a successful stream we often close/kill first → 23 is benign.
   // TerminateProcess after silence end → exit 1; also benign if we got body.
   lOk := AGHTTP_CurlOk( nExit, nTotal, lKilled, lTimedOut )
   IF lTimedOut
      cErr := "timeout"
   ELSEIF lOk
      cErr := ""
   ELSEIF Empty( cErr )
      cErr := "curl exit " + LTrim( Str( nExit ) )
   ENDIF

   RETURN { "ok" => lOk, ;
            "status" => nStatus, ;
            "curl_code" => nExit, ;
            "error" => iif( lOk, "", AllTrim( cErr ) ) }

// True when curl's non-zero exit should not fail the request.
// nExit 23: write/pipe error after we already drained response bytes.
// lKilled + body: we terminated curl after intentional stream end (silence).
STATIC FUNCTION AGHTTP_CurlOk( nExit, nTotal, lKilled, lTimedOut )
   IF lTimedOut
      RETURN .F.
   ENDIF
   IF nExit == 0
      RETURN .T.
   ENDIF
   IF nTotal <= 0
      RETURN .F.
   ENDIF
   // CURLE_WRITE_ERROR — pipe closed while curl still flushing.
   IF nExit == 23
      RETURN .T.
   ENDIF
   // We killed curl after receiving a body (silence end / shutdown).
   IF lKilled
      RETURN .T.
   ENDIF
   RETURN .F.

// Bytes waiting on the pipe (0 = none). Never blocks.
STATIC FUNCTION AGHTTP_PipeAvail( hPipe )
   LOCAL nAvail := 0
   LOCAL xOk
#ifdef __PLATFORM__WINDOWS
   IF ValType( hPipe ) != "N" .OR. hPipe == 0 .OR. hPipe == F_ERROR
      RETURN 0
   ENDIF
   // BOOL PeekNamedPipe(h, buf, size, pRead, pAvail, pLeft)
   xOk := hb_dynCall( { "PeekNamedPipe", "kernel32.dll", ;
      hb_bitOr( HB_DYN_CALLCONV_STDCALL, HB_DYN_CTYPE_BOOL ), ;
      { HB_DYN_CTYPE_VOID_PTR, ;
        HB_DYN_CTYPE_VOID_PTR, ;
        HB_DYN_CTYPE_LONG_UNSIGNED, ;
        HB_DYN_CTYPE_VOID_PTR, ;
        HB_DYN_CTYPE_INT_PTR, ;
        HB_DYN_CTYPE_VOID_PTR } }, ;
      hPipe, 0, 0, 0, @nAvail, 0 )
   IF AGHTTP_DynBool( xOk ) .AND. ValType( nAvail ) == "N" .AND. nAvail > 0
      RETURN nAvail
   ENDIF
   RETURN 0
#else
   HB_SYMBOL_UNUSED( hPipe )
   HB_SYMBOL_UNUSED( nAvail )
   RETURN 0
#endif

// .T. if process is still alive (GetExitCodeProcess == STILL_ACTIVE).
STATIC FUNCTION AGHTTP_ProcRunning( hProc )
   LOCAL nCode := 0
   LOCAL xOk
#ifdef __PLATFORM__WINDOWS
   IF ValType( hProc ) != "N" .OR. hProc == 0
      RETURN .F.
   ENDIF
   xOk := hb_dynCall( { "GetExitCodeProcess", "kernel32.dll", ;
      hb_bitOr( HB_DYN_CALLCONV_STDCALL, HB_DYN_CTYPE_BOOL ), ;
      { HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_INT_PTR } }, ;
      hProc, @nCode )
   IF AGHTTP_DynBool( xOk )
      RETURN ( ValType( nCode ) == "N" .AND. nCode == AGHTTP_STILL_ACTIVE )
   ENDIF
   // API failed — assume still running (idle until hard timeout).
   RETURN .T.
#else
   HB_SYMBOL_UNUSED( hProc )
   RETURN .T.
#endif

STATIC FUNCTION AGHTTP_KillProc( hProc )
#ifdef __PLATFORM__WINDOWS
   IF ValType( hProc ) == "N" .AND. hProc != 0
      hb_dynCall( { "TerminateProcess", "kernel32.dll", ;
         hb_bitOr( HB_DYN_CALLCONV_STDCALL, HB_DYN_CTYPE_BOOL ), ;
         { HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_LONG_UNSIGNED } }, ;
         hProc, 1 )
   ENDIF
#else
   HB_SYMBOL_UNUSED( hProc )
#endif
   RETURN NIL

FUNCTION AGHTTP_SetTestTransport( bBlock )
   s_bTestTransport := bBlock
   RETURN NIL

FUNCTION AGHTTP_Fetch( hReq )
   IF hb_HHasKey( hReq, "transport" ) .AND. hReq[ "transport" ] != NIL
      RETURN Eval( hReq[ "transport" ], hReq )
   ENDIF
   IF s_bTestTransport != NIL
      RETURN Eval( s_bTestTransport, hReq )
   ENDIF
   RETURN AGHTTP_CurlFetch( hReq )

STATIC FUNCTION AGHTTP_UnsafeUrl( cUrl )
   LOCAL i, nByte
   FOR i := 1 TO hb_BLen( cUrl )
      nByte := hb_BCode( hb_BSubStr( cUrl, i, 1 ) )
      IF nByte <= 32 .OR. nByte == 34
         RETURN .T.
      ENDIF
   NEXT
   RETURN .F.

STATIC FUNCTION AGHTTP_CurlFetch( hReq )
   LOCAL hProc, hIn, hOut, hErr, hTmp
   LOCAL cHdrFile := "", cBodyFile := "", cCmd, cHdr, nTimeout, cMethod
   LOCAL cBuf := Space( 16384 ), nRead
   LOCAL nExit, nStatus := 0, cErr := "", cBody := ""
   LOCAL aHeaders, cReqBody, lHasBody

   IF !hb_HHasKey( hReq, "url" ) .OR. Empty( hReq[ "url" ] )
      RETURN { "ok" => .F., "status" => 0, "body" => "", "error" => "missing url" }
   ENDIF
   IF AGHTTP_UnsafeUrl( hb_CStr( hReq[ "url" ] ) )
      RETURN { "ok" => .F., "status" => 0, "body" => "", "error" => "invalid url" }
   ENDIF

   cMethod := iif( hb_HHasKey( hReq, "method" ) .AND. !Empty( hReq[ "method" ] ), ;
                   Upper( hb_CStr( hReq[ "method" ] ) ), "GET" )
   nTimeout := iif( hb_HHasKey( hReq, "timeout" ) .AND. ;
                    ValType( hReq[ "timeout" ] ) == "N", hReq[ "timeout" ], 60 )
   aHeaders := iif( hb_HHasKey( hReq, "headers" ) .AND. ;
                    ValType( hReq[ "headers" ] ) == "A", hReq[ "headers" ], {} )
   cReqBody := iif( hb_HHasKey( hReq, "body" ) .AND. ;
                    ValType( hReq[ "body" ] ) == "C", hReq[ "body" ], "" )
   lHasBody := !Empty( cReqBody ) .AND. ( cMethod == "POST" .OR. cMethod == "PATCH" )

   hTmp := hb_FTempCreateEx( @cHdrFile, hb_DirTemp(), "dsf", ".hdr" )
   IF hTmp != F_ERROR ; FClose( hTmp ) ; ENDIF

   cCmd := "curl -sS --max-time " + LTrim( Str( nTimeout ) ) + ;
           " -X " + cMethod + " -D " + Chr( 34 ) + cHdrFile + Chr( 34 )
   IF lHasBody
      hTmp := hb_FTempCreateEx( @cBodyFile, hb_DirTemp(), "dsfb", ".bin" )
      IF hTmp != F_ERROR ; FClose( hTmp ) ; ENDIF
      hb_MemoWrit( cBodyFile, cReqBody )
      cCmd += " --data-binary @" + Chr( 34 ) + cBodyFile + Chr( 34 )
   ENDIF
   FOR EACH cHdr IN aHeaders
      cCmd += " -H " + Chr( 34 ) + cHdr + Chr( 34 )
   NEXT
   cCmd += " " + Chr( 34 ) + hReq[ "url" ] + Chr( 34 )

   hProc := hb_processOpen( cCmd, @hIn, @hOut, @hErr )
   IF hProc == F_ERROR
      IF !Empty( cHdrFile )  ; FErase( cHdrFile )  ; ENDIF
      IF !Empty( cBodyFile ) ; FErase( cBodyFile ) ; ENDIF
      RETURN { "ok" => .F., "status" => 0, "body" => "", "error" => "failed to spawn curl" }
   ENDIF
   FClose( hIn )

   DO WHILE ( nRead := FRead( hOut, @cBuf, hb_BLen( cBuf ) ) ) > 0
      cBody += hb_BLeft( cBuf, nRead )
   ENDDO
   DO WHILE ( nRead := FRead( hErr, @cBuf, hb_BLen( cBuf ) ) ) > 0
      cErr += hb_BLeft( cBuf, nRead )
   ENDDO
   FClose( hOut )
   FClose( hErr )
   nExit := hb_processValue( hProc )
   nStatus := AGHTTP_ParseStatus( cHdrFile )
   IF !Empty( cHdrFile )  ; FErase( cHdrFile )  ; ENDIF
   IF !Empty( cBodyFile ) ; FErase( cBodyFile ) ; ENDIF

   // Same benign write-error rule as streaming POST (exit 23 + body).
   IF nExit == 0 .OR. ( nExit == 23 .AND. !Empty( cBody ) )
      RETURN { "ok" => .T., "status" => nStatus, "body" => cBody, "error" => "" }
   ENDIF
   RETURN { "ok" => .F., "status" => nStatus, "body" => cBody, ;
            "error" => iif( Empty( cErr ), "curl exit " + LTrim( Str( nExit ) ), AllTrim( cErr ) ) }

STATIC FUNCTION AGHTTP_ParseStatus( cHdrFile )
   LOCAL cText, cLine, nStatus := 0, aTok
   IF Empty( cHdrFile ) .OR. !hb_FileExists( cHdrFile )
      RETURN 0
   ENDIF
   cText := hb_MemoRead( cHdrFile )
   FOR EACH cLine IN hb_ATokens( cText, Chr( 10 ) )
      IF Left( cLine, 5 ) == "HTTP/"
         aTok := hb_ATokens( AllTrim( cLine ), " " )
         IF Len( aTok ) >= 2 .AND. IsDigit( Left( aTok[ 2 ], 1 ) )
            nStatus := Val( aTok[ 2 ] )
         ENDIF
      ENDIF
   NEXT
   RETURN nStatus
