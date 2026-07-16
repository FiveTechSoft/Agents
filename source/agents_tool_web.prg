// Web tools for Agents: web_fetch (retrieve a URL) and web_search (DuckDuckGo).

// web_fetch: retrieves the raw content of a URL.
FUNCTION AGTOOL_WebFetch()
   RETURN { "name" => "web_fetch", ;
            "description" => "Fetch the raw content of a URL (text or HTML, not converted to plain text).", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "url" => { "type" => "string", ;
                             "description" => "The URL to fetch" } }, ;
               "required" => { "url" } }, ;
            "handler" => {| hArgs | AGTOOL_WebFetchRun( hArgs ) } }

// Assumes the executor (AGTOOLS_Dispatch) has already validated required args.
STATIC FUNCTION AGTOOL_WebFetchRun( hArgs )
   LOCAL hRes, cBody
   hRes := AGHTTP_Fetch( { "url" => hb_CStr( hArgs[ "url" ] ), "method" => "GET" } )
   IF !hRes[ "ok" ]
      RETURN "Error: web_fetch failed: " + hRes[ "error" ]
   ENDIF
   IF hRes[ "status" ] < 200 .OR. hRes[ "status" ] >= 300
      RETURN "Error: web_fetch HTTP " + LTrim( Str( hRes[ "status" ] ) )
   ENDIF
   cBody := hRes[ "body" ]
   IF hb_BLen( cBody ) > 30000
      cBody := hb_BLeft( cBody, 30000 ) + Chr( 10 ) + "[output truncated]" + Chr( 10 )
   ENDIF
   RETURN cBody

// web_search: searches the web via the DuckDuckGo Instant Answer API.
// No API key required. Free, rate-limited, returns instant answers + web results.
FUNCTION AGTOOL_WebSearch()
   RETURN { "name" => "web_search", ;
            "description" => "Search the web via the DuckDuckGo API. " + ;
               "No API key required. Returns ranked title/url/snippet results.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "query" => { "type" => "string", ;
                               "description" => "The search query" }, ;
                  "max_results" => { "type" => "integer", ;
                               "description" => "Maximum number of results (default 8)" } }, ;
               "required" => { "query" } }, ;
            "handler" => {| hArgs | AGTOOL_DdgSearchRun( hArgs ) } }

// URL-encodes a string for query parameters (byte-wise).
STATIC FUNCTION AGHTTP_UrlEncode( cText )
   LOCAL cOut := "", i, c
   FOR i := 1 TO hb_BLen( cText )
      c := hb_BSubStr( cText, i, 1 )
      IF ( c >= "A" .AND. c <= "Z" ) .OR. ( c >= "a" .AND. c <= "z" ) .OR. ;
         ( c >= "0" .AND. c <= "9" ) .OR. c $ "-_.~"
         cOut += c
      ELSEIF c == " "
         cOut += "+"
      ELSE
         cOut += "%" + PadL( Upper( hb_NumToHex( hb_BCode( c ) ) ), 2, "0" )
      ENDIF
   NEXT
   RETURN cOut

// Performs a DuckDuckGo Instant Answer search. No API key needed.
// Uses the public https://api.duckduckgo.com/ endpoint.
STATIC FUNCTION AGTOOL_DdgSearchRun( hArgs )
   LOCAL cQuery, nMax, cUrl, hRes, xBody, h1, cOut := "", nShown := 0
   cQuery := hb_CStr( hArgs[ "query" ] )
   nMax   := iif( hb_HHasKey( hArgs, "max_results" ) .AND. ;
                  ValType( hArgs[ "max_results" ] ) == "N", ;
                  Int( hArgs[ "max_results" ] ), 8 )
   // clamp: DuckDuckGo returns at most ~20 results typically
   IF nMax < 1
      nMax := 1
   ELSEIF nMax > 20
      nMax := 20
   ENDIF

   cUrl := "https://api.duckduckgo.com/?q=" + AGHTTP_UrlEncode( cQuery ) + ;
           "&format=json&no_html=1&skip_disambig=1"

   hRes := AGHTTP_Fetch( { "url" => cUrl, "method" => "GET", "timeout" => 15 } )
   IF !hRes[ "ok" ]
      RETURN "Error: web_search failed: " + hRes[ "error" ]
   ENDIF
   IF hRes[ "status" ] < 200 .OR. hRes[ "status" ] >= 300
      RETURN "Error: web_search HTTP " + LTrim( Str( hRes[ "status" ] ) )
   ENDIF

   xBody := hb_jsonDecode( hRes[ "body" ] )
   IF ValType( xBody ) != "H"
      RETURN "Error: web_search: unexpected response format"
   ENDIF

   // 1. Instant Answer (AbstractText) — the most relevant result
   IF hb_HHasKey( xBody, "AbstractText" ) .AND. !Empty( xBody[ "AbstractText" ] )
      cOut += ">> " + hb_CStr( xBody[ "AbstractText" ] ) + Chr(10)
      IF hb_HHasKey( xBody, "AbstractURL" ) .AND. !Empty( xBody[ "AbstractURL" ] )
         cOut += "   " + hb_CStr( xBody[ "AbstractURL" ] ) + Chr(10)
      ENDIF
      IF hb_HHasKey( xBody, "AbstractSource" ) .AND. !Empty( xBody[ "AbstractSource" ] )
         cOut += "   Source: " + hb_CStr( xBody[ "AbstractSource" ] ) + Chr(10)
      ENDIF
      cOut += Chr(10)
      nShown++
   ENDIF

   // 2. Results array — traditional web results
   IF hb_HHasKey( xBody, "Results" ) .AND. ValType( xBody[ "Results" ] ) == "A"
      FOR EACH h1 IN xBody[ "Results" ]
         IF nShown >= nMax
            EXIT
         ENDIF
         cOut += hb_CStr( hb_HGetDef( h1, "Text", "" ) ) + Chr(10) + ;
                 hb_CStr( hb_HGetDef( h1, "FirstURL", "" ) ) + Chr(10) + Chr(10)
         nShown++
      NEXT
   ENDIF

   // 3. RelatedTopics — additional results (some are nested categories)
   IF nShown < nMax .AND. hb_HHasKey( xBody, "RelatedTopics" ) .AND. ;
      ValType( xBody[ "RelatedTopics" ] ) == "A"
      FOR EACH h1 IN xBody[ "RelatedTopics" ]
         IF nShown >= nMax
            EXIT
         ENDIF
         IF ValType( h1 ) == "H" .AND. hb_HHasKey( h1, "Topics" ) .AND. ;
            ValType( h1[ "Topics" ] ) == "A"
            FOR EACH hTopic IN h1[ "Topics" ]
               IF nShown >= nMax
                  EXIT
               ENDIF
               cOut += hb_CStr( hb_HGetDef( hTopic, "Text", "" ) ) + Chr(10) + ;
                       hb_CStr( hb_HGetDef( hTopic, "FirstURL", "" ) ) + Chr(10) + Chr(10)
               nShown++
            NEXT
         ELSEIF ValType( h1 ) == "H" .AND. hb_HHasKey( h1, "Text" )
            cOut += hb_CStr( h1[ "Text" ] ) + Chr(10) + ;
                    hb_CStr( hb_HGetDef( h1, "FirstURL", "" ) ) + Chr(10) + Chr(10)
            nShown++
         ENDIF
      NEXT
   ENDIF

   IF Empty( cOut )
      RETURN "No results for " + cQuery
   ENDIF
   IF hb_BLen( cOut ) > 30000
      cOut := hb_BLeft( cOut, 30000 ) + Chr( 10 ) + "[output truncated]" + Chr( 10 )
   ENDIF
   RETURN cOut
