// GitHub tools for Agents: github_read (queries) and github_write (mutations).

// Builds the standard GitHub API request headers; adds auth when a token is set.
STATIC FUNCTION AGGITHUB_Headers( cToken )
   LOCAL aHdr := { "Accept: application/vnd.github+json", ;
                   "User-Agent: Agents", ;
                   "Content-Type: application/json" }
   IF !Empty( cToken )
      AAdd( aHdr, "Authorization: Bearer " + cToken )
   ENDIF
   RETURN aHdr

// Percent-encodes a string for use in a URL query component. Byte-wise so
// multi-byte (UTF-8) input is encoded one octet at a time.
STATIC FUNCTION AGGITHUB_UrlEncode( cText )
   LOCAL cOut := "", i, c
   FOR i := 1 TO hb_BLen( cText )
      c := hb_BSubStr( cText, i, 1 )
      IF ( c >= "A" .AND. c <= "Z" ) .OR. ( c >= "a" .AND. c <= "z" ) .OR. ;
         ( c >= "0" .AND. c <= "9" ) .OR. c $ "-_.~"
         cOut += c
      ELSE
         cOut += "%" + PadL( Upper( hb_NumToHex( hb_BCode( c ) ) ), 2, "0" )
      ENDIF
   NEXT
   RETURN cOut

// Percent-encodes a file path for a URL, preserving the "/" separators.
STATIC FUNCTION AGGITHUB_UrlEncodePath( cPath )
   LOCAL aSeg := hb_ATokens( cPath, "/" ), cOut := "", i
   FOR i := 1 TO Len( aSeg )
      cOut += iif( i > 1, "/", "" ) + AGGITHUB_UrlEncode( aSeg[ i ] )
   NEXT
   RETURN cOut

// Extracts the "message" field from a GitHub error JSON body, or "".
STATIC FUNCTION AGGITHUB_ApiMessage( cBody )
   LOCAL xJson := hb_jsonDecode( cBody )
   IF ValType( xJson ) == "H" .AND. hb_HHasKey( xJson, "message" )
      RETURN hb_CStr( xJson[ "message" ] )
   ENDIF
   RETURN ""

// github_read: read-only GitHub queries. cToken is optional (unauthenticated
// requests work but are rate-limited).
FUNCTION AGTOOL_GithubRead( cToken )
   RETURN { "name" => "github_read", ;
            "description" => "Read from GitHub: repo info, file content, directory listing, issues, pull requests, code search.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "operation" => { "type" => "string", ;
                     "description" => "One of: repo, file, list, issues, issue, prs, pr, search" }, ;
                  "repo" => { "type" => "string", ;
                     "description" => "Repository as owner/name (every operation except search)" }, ;
                  "path" => { "type" => "string", ;
                     "description" => "File or directory path (file, list)" }, ;
                  "number" => { "type" => "integer", ;
                     "description" => "Issue or PR number (issue, pr)" }, ;
                  "query" => { "type" => "string", ;
                     "description" => "Code search query (search)" } }, ;
               "required" => { "operation" } }, ;
            "handler" => {| hArgs | AGTOOL_GithubReadRun( hArgs, cToken ) } }

// The executor validates only `operation`; this handler validates the
// per-operation arguments (repo, path, number, query).
STATIC FUNCTION AGTOOL_GithubReadRun( hArgs, cToken )
   LOCAL cOp, cRepo, cUrl, hRes
   cOp := Lower( hb_CStr( hArgs[ "operation" ] ) )
   IF cOp == "search"
      IF !hb_HHasKey( hArgs, "query" ) .OR. Empty( hArgs[ "query" ] )
         RETURN "Error: github_read 'search' requires 'query'"
      ENDIF
      cUrl := "https://api.github.com/search/code?q=" + ;
              AGGITHUB_UrlEncode( hb_CStr( hArgs[ "query" ] ) )
   ELSE
      IF !hb_HHasKey( hArgs, "repo" ) .OR. Empty( hArgs[ "repo" ] )
         RETURN "Error: github_read '" + cOp + "' requires 'repo'"
      ENDIF
      cRepo := hb_CStr( hArgs[ "repo" ] )
      DO CASE
      CASE cOp == "repo"
         cUrl := "https://api.github.com/repos/" + cRepo
      CASE cOp == "file" .OR. cOp == "list"
         IF !hb_HHasKey( hArgs, "path" ) .OR. Empty( hArgs[ "path" ] )
            RETURN "Error: github_read '" + cOp + "' requires 'path'"
         ENDIF
         cUrl := "https://api.github.com/repos/" + cRepo + "/contents/" + ;
                 AGGITHUB_UrlEncodePath( hb_CStr( hArgs[ "path" ] ) )
      CASE cOp == "issues"
         cUrl := "https://api.github.com/repos/" + cRepo + "/issues"
      CASE cOp == "issue"
         IF !hb_HHasKey( hArgs, "number" ) .OR. ValType( hArgs[ "number" ] ) != "N"
            RETURN "Error: github_read 'issue' requires a numeric 'number'"
         ENDIF
         cUrl := "https://api.github.com/repos/" + cRepo + "/issues/" + ;
                 LTrim( Str( hArgs[ "number" ] ) )
      CASE cOp == "prs"
         cUrl := "https://api.github.com/repos/" + cRepo + "/pulls"
      CASE cOp == "pr"
         IF !hb_HHasKey( hArgs, "number" ) .OR. ValType( hArgs[ "number" ] ) != "N"
            RETURN "Error: github_read 'pr' requires a numeric 'number'"
         ENDIF
         cUrl := "https://api.github.com/repos/" + cRepo + "/pulls/" + ;
                 LTrim( Str( hArgs[ "number" ] ) )
      OTHERWISE
         RETURN "Error: github_read: unknown operation '" + cOp + "'"
      ENDCASE
   ENDIF
   hRes := AGHTTP_Fetch( { "url" => cUrl, "method" => "GET", ;
                           "headers" => AGGITHUB_Headers( cToken ) } )
   IF !hRes[ "ok" ]
      RETURN "Error: github_read failed: " + hRes[ "error" ]
   ENDIF
   IF hRes[ "status" ] < 200 .OR. hRes[ "status" ] >= 300
      RETURN "Error: github_read HTTP " + LTrim( Str( hRes[ "status" ] ) ) + ": " + ;
             AGGITHUB_ApiMessage( hRes[ "body" ] )
   ENDIF
   RETURN AGGITHUB_FormatRead( cOp, hRes[ "body" ] )

// Caps a string at 30000 bytes, appending a marker when it had to be cut.
STATIC FUNCTION AGGITHUB_Cap( cText )
   IF hb_BLen( cText ) > 30000
      RETURN hb_BLeft( cText, 30000 ) + Chr( 10 ) + "[output truncated]" + Chr( 10 )
   ENDIF
   RETURN cText

// Formats a successful github_read response by operation.
STATIC FUNCTION AGGITHUB_FormatRead( cOp, cBody )
   LOCAL xJson, cText, h1
   DO CASE
   CASE cOp == "file"
      xJson := hb_jsonDecode( cBody )
      IF ValType( xJson ) == "H" .AND. hb_HHasKey( xJson, "content" )
         RETURN AGGITHUB_Cap( hb_base64Decode( StrTran( hb_CStr( xJson[ "content" ] ), Chr( 10 ), "" ) ) )
      ENDIF
      RETURN AGGITHUB_Cap( cBody )
   CASE cOp == "list"
      xJson := hb_jsonDecode( cBody )
      IF ValType( xJson ) == "A"
         cText := ""
         FOR EACH h1 IN xJson
            IF ValType( h1 ) == "H" .AND. hb_HHasKey( h1, "name" )
               cText += hb_CStr( hb_HGetDef( h1, "type", "" ) ) + "  " + ;
                        hb_CStr( h1[ "name" ] ) + Chr( 10 )
            ENDIF
         NEXT
         RETURN AGGITHUB_Cap( cText )
      ENDIF
      RETURN AGGITHUB_Cap( cBody )
   ENDCASE
   RETURN AGGITHUB_Cap( cBody )

// github_write: GitHub mutations. cToken is mandatory — an empty token yields
// a clear error at call time.
FUNCTION AGTOOL_GithubWrite( cToken )
   RETURN { "name" => "github_write", ;
            "description" => "Write to GitHub: create an issue, comment on an issue, or open a pull request. Requires GITHUB_TOKEN.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "operation" => { "type" => "string", ;
                     "description" => "One of: create_issue, comment, create_pr" }, ;
                  "repo" => { "type" => "string", ;
                     "description" => "Repository as owner/name" }, ;
                  "number" => { "type" => "integer", ;
                     "description" => "Issue number (comment)" }, ;
                  "title" => { "type" => "string", ;
                     "description" => "Title (create_issue, create_pr)" }, ;
                  "body" => { "type" => "string", ;
                     "description" => "Body text (issue, comment, or PR description)" }, ;
                  "head" => { "type" => "string", ;
                     "description" => "Source branch (create_pr)" }, ;
                  "base" => { "type" => "string", ;
                     "description" => "Target branch (create_pr)" } }, ;
               "required" => { "operation", "repo" } }, ;
            "handler" => {| hArgs | AGTOOL_GithubWriteRun( hArgs, cToken ) } }

// The executor validates only `operation` and `repo`; this handler validates
// the per-operation arguments (title, number, head, base).
STATIC FUNCTION AGTOOL_GithubWriteRun( hArgs, cToken )
   LOCAL cOp, cRepo, cUrl, cReqBody, hRes, xJson
   IF Empty( cToken )
      RETURN "Error: GITHUB_TOKEN not set"
   ENDIF
   cOp := Lower( hb_CStr( hArgs[ "operation" ] ) )
   cRepo := hb_CStr( hArgs[ "repo" ] )
   DO CASE
   CASE cOp == "create_issue"
      IF !hb_HHasKey( hArgs, "title" ) .OR. Empty( hArgs[ "title" ] )
         RETURN "Error: github_write 'create_issue' requires 'title'"
      ENDIF
      cUrl := "https://api.github.com/repos/" + cRepo + "/issues"
      cReqBody := hb_jsonEncode( { "title" => hb_CStr( hArgs[ "title" ] ), ;
         "body" => iif( hb_HHasKey( hArgs, "body" ), hb_CStr( hArgs[ "body" ] ), "" ) } )
   CASE cOp == "comment"
      IF !hb_HHasKey( hArgs, "number" ) .OR. ValType( hArgs[ "number" ] ) != "N"
         RETURN "Error: github_write 'comment' requires 'number'"
      ENDIF
      cUrl := "https://api.github.com/repos/" + cRepo + "/issues/" + ;
              LTrim( Str( hArgs[ "number" ] ) ) + "/comments"
      cReqBody := hb_jsonEncode( { "body" => ;
         iif( hb_HHasKey( hArgs, "body" ), hb_CStr( hArgs[ "body" ] ), "" ) } )
   CASE cOp == "create_pr"
      IF !hb_HHasKey( hArgs, "title" ) .OR. Empty( hArgs[ "title" ] ) .OR. ;
         !hb_HHasKey( hArgs, "head" ) .OR. Empty( hArgs[ "head" ] ) .OR. ;
         !hb_HHasKey( hArgs, "base" ) .OR. Empty( hArgs[ "base" ] )
         RETURN "Error: github_write 'create_pr' requires 'title', 'head', 'base'"
      ENDIF
      cUrl := "https://api.github.com/repos/" + cRepo + "/pulls"
      cReqBody := hb_jsonEncode( { "title" => hb_CStr( hArgs[ "title" ] ), ;
         "head" => hb_CStr( hArgs[ "head" ] ), "base" => hb_CStr( hArgs[ "base" ] ), ;
         "body" => iif( hb_HHasKey( hArgs, "body" ), hb_CStr( hArgs[ "body" ] ), "" ) } )
   OTHERWISE
      RETURN "Error: github_write: unknown operation '" + cOp + "'"
   ENDCASE
   hRes := AGHTTP_Fetch( { "url" => cUrl, "method" => "POST", ;
      "headers" => AGGITHUB_Headers( cToken ), "body" => cReqBody } )
   IF !hRes[ "ok" ]
      RETURN "Error: github_write failed: " + hRes[ "error" ]
   ENDIF
   IF hRes[ "status" ] < 200 .OR. hRes[ "status" ] >= 300
      RETURN "Error: github_write HTTP " + LTrim( Str( hRes[ "status" ] ) ) + ": " + ;
             AGGITHUB_ApiMessage( hRes[ "body" ] )
   ENDIF
   xJson := hb_jsonDecode( hRes[ "body" ] )
   IF ValType( xJson ) == "H" .AND. hb_HHasKey( xJson, "html_url" )
      RETURN "Created: " + hb_CStr( xJson[ "html_url" ] )
   ENDIF
   RETURN "OK"
