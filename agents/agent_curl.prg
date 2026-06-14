// HTTP transport for the DeepSeek client.
//
// Transport path: curl subprocess (NOT hbcurl).
// The installed hbcurl contrib exposes no per-chunk Harbour write callback
// -- HB_CURLOPT_WRITEFUNCTION is hidden at the Harbour level (see
// contrib/hbcurl/core.c: only file/fhandle/buffer download setups exist).
// Real incremental streaming therefore uses the libcurl CLI: curl is
// spawned per request, the body is fed to its stdin, and its stdout is read
// chunk-by-chunk. curl ships with Windows 10/11 (system32). Each call
// spawns its own process -> pool-safe, no shared state.

#include "fileio.ch"

// Module-level test transport. When set (and no per-request transport is
// given), CCHTTP_Fetch routes through it instead of curl. Tests only.
STATIC s_bTestTransport := NIL

// Performs a streaming POST. hReq: { url, headers (array of "K: V"), body, timeout }.
// bOnChunk is called with each received raw text chunk.
// bTransport (optional codeblock {|hReq,bOnChunk| -> hResult }) overrides curl;
// when NIL the real curl transport (CCHTTP_CurlPost) is used.
// Returns: { ok, status, curl_code, error }
FUNCTION CCHTTP_Post( hReq, bOnChunk, bTransport )
   IF bTransport != NIL
      RETURN Eval( bTransport, hReq, bOnChunk )
   ENDIF
   RETURN CCHTTP_CurlPost( hReq, bOnChunk )

// Real transport: spawns curl and streams its stdout to bOnChunk.
FUNCTION CCHTTP_CurlPost( hReq, bOnChunk )
   LOCAL hProc, hIn, hOut, hErr, hTmp
   LOCAL cHdrFile := "", cCmd, cHdr, nTimeout
   LOCAL cBuf := Space( 16384 ), nRead
   LOCAL nExit, nStatus := 0, cErr := ""

   nTimeout := iif( hb_HHasKey( hReq, "timeout" ) .AND. ;
                    ValType( hReq[ "timeout" ] ) == "N", hReq[ "timeout" ], 120 )

   // unique header dump file (pool-safe)
   hTmp := hb_FTempCreateEx( @cHdrFile, hb_DirTemp(), "dsh", ".hdr" )
   IF hTmp != F_ERROR
      FClose( hTmp )
   ENDIF

   cCmd := "curl -sS -N --max-time " + LTrim( Str( nTimeout ) ) + ;
           " -X POST -D " + Chr( 34 ) + cHdrFile + Chr( 34 ) + ;
           " --data-binary @-"
   FOR EACH cHdr IN hReq[ "headers" ]
      cCmd += " -H " + Chr( 34 ) + cHdr + Chr( 34 )
   NEXT
   cCmd += " " + Chr( 34 ) + hReq[ "url" ] + Chr( 34 )

   hProc := hb_processOpen( cCmd, @hIn, @hOut, @hErr )
   IF hProc == F_ERROR
      IF !Empty( cHdrFile )
         FErase( cHdrFile )
      ENDIF
      RETURN { "ok" => .F., "status" => 0, "curl_code" => -1, ;
               "error" => "failed to spawn curl" }
   ENDIF

   // feed the request body to curl's stdin, then close it so curl proceeds
   IF hb_HHasKey( hReq, "body" ) .AND. !Empty( hReq[ "body" ] )
      FWrite( hIn, hReq[ "body" ] )
   ENDIF
   FClose( hIn )

   // stream stdout chunk-by-chunk as curl delivers it
   // check for Ctrl+C between chunks to allow cancellation
   DO WHILE ( nRead := FRead( hOut, @cBuf, hb_BLen( cBuf ) ) ) > 0
      Eval( bOnChunk, hb_BLeft( cBuf, nRead ) )
      IF CCCON_PeekCtrlC()
         hb_processClose( hProc )
         FClose( hOut )
         FClose( hErr )
         IF !Empty( cHdrFile )
            FErase( cHdrFile )
         ENDIF
         RETURN { "ok" => .F., "status" => 0, "curl_code" => -2, ;
                  "error" => "cancelled" }
      ENDIF
   ENDDO

   // drain stderr for diagnostics
   DO WHILE ( nRead := FRead( hErr, @cBuf, hb_BLen( cBuf ) ) ) > 0
      cErr += hb_BLeft( cBuf, nRead )
   ENDDO

   FClose( hOut )
   FClose( hErr )
   nExit := hb_processValue( hProc )

   nStatus := CCHTTP_ParseStatus( cHdrFile )
   FErase( cHdrFile )

   RETURN { "ok" => ( nExit == 0 ), ;
            "status" => nStatus, ;
            "curl_code" => nExit, ;
            "error" => iif( nExit == 0, "", ;
               iif( Empty( cErr ), "curl exit " + LTrim( Str( nExit ) ), ;
                    AllTrim( cErr ) ) ) }

// Installs (or clears, with NIL) the module-level test transport.
FUNCTION CCHTTP_SetTestTransport( bBlock )
   s_bTestTransport := bBlock
   RETURN NIL

// Performs a non-streaming HTTP request.
// hReq: { url, method ("GET"/"POST"/"PATCH", default GET), headers (array of
//         "K: V"), body (string, sent for POST/PATCH), timeout (seconds,
//         default 60), transport (optional {|hReq| -> hResult} override) }.
// Returns: { ok, status, body, error }.
// ok indicates the transport succeeded (curl ran); check status for the HTTP result.
FUNCTION CCHTTP_Fetch( hReq )
   IF hb_HHasKey( hReq, "transport" ) .AND. hReq[ "transport" ] != NIL
      RETURN Eval( hReq[ "transport" ], hReq )
   ENDIF
   IF s_bTestTransport != NIL
      RETURN Eval( s_bTestTransport, hReq )
   ENDIF
   RETURN CCHTTP_CurlFetch( hReq )

// True when a URL contains characters unsafe on the curl command line:
// a double-quote, whitespace, or any control character (byte <= 32).
STATIC FUNCTION CCHTTP_UnsafeUrl( cUrl )
   LOCAL i, nByte
   FOR i := 1 TO hb_BLen( cUrl )
      nByte := hb_BCode( hb_BSubStr( cUrl, i, 1 ) )
      IF nByte <= 32 .OR. nByte == 34
         RETURN .T.
      ENDIF
   NEXT
   RETURN .F.

// Real transport: spawns curl and accumulates its whole stdout.
STATIC FUNCTION CCHTTP_CurlFetch( hReq )
   LOCAL hProc, hIn, hOut, hErr, hTmp
   LOCAL cHdrFile := "", cCmd, cHdr, nTimeout, cMethod
   LOCAL cBuf := Space( 16384 ), nRead
   LOCAL nExit, nStatus := 0, cErr := "", cBody := ""
   LOCAL aHeaders, cReqBody, lHasBody

   IF !hb_HHasKey( hReq, "url" ) .OR. Empty( hReq[ "url" ] )
      RETURN { "ok" => .F., "status" => 0, "body" => "", ;
               "error" => "missing url" }
   ENDIF

   IF CCHTTP_UnsafeUrl( hb_CStr( hReq[ "url" ] ) )
      RETURN { "ok" => .F., "status" => 0, "body" => "", ;
               "error" => "invalid url" }
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
   IF hTmp != F_ERROR
      FClose( hTmp )
   ENDIF

   cCmd := "curl -sS --max-time " + LTrim( Str( nTimeout ) ) + ;
           " -X " + cMethod + " -D " + Chr( 34 ) + cHdrFile + Chr( 34 )
   IF lHasBody
      cCmd += " --data-binary @-"
   ENDIF
   FOR EACH cHdr IN aHeaders
      cCmd += " -H " + Chr( 34 ) + cHdr + Chr( 34 )
   NEXT
   cCmd += " " + Chr( 34 ) + hReq[ "url" ] + Chr( 34 )

   hProc := hb_processOpen( cCmd, @hIn, @hOut, @hErr )
   IF hProc == F_ERROR
      IF !Empty( cHdrFile )
         FErase( cHdrFile )
      ENDIF
      RETURN { "ok" => .F., "status" => 0, "body" => "", ;
               "error" => "failed to spawn curl" }
   ENDIF

   IF lHasBody
      FWrite( hIn, cReqBody )
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

   nStatus := CCHTTP_ParseStatus( cHdrFile )
   FErase( cHdrFile )

   RETURN { "ok" => ( nExit == 0 ), "status" => nStatus, "body" => cBody, ;
            "error" => iif( nExit == 0, "", ;
               iif( Empty( cErr ), "curl exit " + LTrim( Str( nExit ) ), ;
                    AllTrim( cErr ) ) ) }

// Reads the curl -D header dump and returns the last HTTP status line code.
STATIC FUNCTION CCHTTP_ParseStatus( cHdrFile )
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
