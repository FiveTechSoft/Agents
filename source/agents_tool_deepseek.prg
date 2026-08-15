/*
 * agents_tool_deepseek.prg - DeepSeek tool definitions
 *
 * Tools:
 *   deepseek_chat  - Send a message to DeepSeek AI
 *   deepseek_list  - List available DeepSeek models
 */

#include "hbclass.ch"
#include "common.ch"

/* ------------------------------------------------------------------ */
/* deepseek_chat tool (registration helper)                           */
/* ------------------------------------------------------------------ */

FUNCTION AGTOOL_DeepSeekChat()
   RETURN { "name" => "deepseek_chat", ;
            "description" => "Chat with DeepSeek AI. Supports web search " + ;
               "and DeepThink (reasoning) modes.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "message" => { "type" => "string", ;
                                 "description" => "Message to send to DeepSeek" }, ;
                  "search" => { "type" => "boolean", ;
                                "description" => "Enable web search (default: false)" }, ;
                  "think" => { "type" => "boolean", ;
                               "description" => "Enable DeepThink reasoning (default: false)" } }, ;
               "required" => { "message" } }, ;
            "handler" => {| hArgs | AGTOOL_DeepSeekChatRun( hArgs ) } }

/* ------------------------------------------------------------------ */
/* deepseek_list tool (registration helper)                           */
/* ------------------------------------------------------------------ */

FUNCTION AGTOOL_DeepSeekList()
   RETURN { "name" => "deepseek_list", ;
            "description" => "List available DeepSeek chat models and options.", ;
            "parameters" => { "type" => "object", ;
               "properties" => {}, "required" => {} }, ;
            "handler" => {| hArgs | AGTOOL_DeepSeekListRun( hArgs ) } }

/* ------------------------------------------------------------------ */
/* Handlers                                                            */
/* ------------------------------------------------------------------ */

STATIC FUNCTION AGTOOL_DeepSeekChatRun( hArgs )
   LOCAL cMsg, lSearch, lThink
   LOCAL cToken    := ""
   LOCAL cCookie   := ""
   LOCAL oDS, aResult, cText
   LOCAL cConfigFile := HB_DirBase() + ".." + hb_ps() + ".agents" + hb_ps() + "deepseek.json"
   LOCAL oConfig
   LOCAL cSessionID

   cMsg := hb_CStr( hArgs[ "message" ] )
   lSearch := iif( hb_HHasKey( hArgs, "search" ), hArgs[ "search" ], .F. )
   lThink  := iif( hb_HHasKey( hArgs, "think" ),  hArgs[ "think" ],  .F. )

   IF Empty( cMsg )
      RETURN "Error: message required."
   ENDIF

   /* Load config from .agents/deepseek.json */
   IF File( cConfigFile )
      oConfig := hb_jsonDecode( hb_MemoRead( cConfigFile ) )
      IF ValType( oConfig ) == "H"
         cToken  := HB_HGetDef( oConfig, "token", "" )
         cCookie := HB_HGetDef( oConfig, "cookie", "" )
      ENDIF
   ENDIF

   IF Empty( cToken ) .OR. Empty( cCookie )
      RETURN "Error: token and cookie required. Set in .agents/deepseek.json"
   ENDIF

   /* Create client and send */
   oDS := DSClient():New( cToken, cCookie )

   ? "  [DeepSeek] Creating session..."
   cSessionID := oDS:CreateSession()
   IF Empty( cSessionID )
      RETURN "Error: Failed to create DeepSeek session. Check token/cookie."
   ENDIF
   ? "  [DeepSeek] Session: " + Left( cSessionID, 20 ) + "..."

   ? "  [DeepSeek] Solving PoW challenge..."
   aResult := oDS:SendMessage( cMsg, cSessionID, NIL, lSearch, lThink )

   IF aResult == NIL
      RETURN "Error: No response from DeepSeek. PoW may have failed."
   ENDIF

   cText := aResult[1]
   IF Empty( cText )
      RETURN "Error: Empty response from DeepSeek."
   ENDIF

   RETURN cText

STATIC FUNCTION AGTOOL_DeepSeekListRun( hArgs )
   HB_SYMBOL_UNUSED( hArgs )

   RETURN "DeepSeek Chat Models:" + HB_EOL() + ;
      HB_EOL() + ;
      "  default  - Fast response (DeepSeek-V3)" + HB_EOL() + ;
      "  expert   - Stronger reasoning (DeepSeek-R1)" + HB_EOL() + ;
      HB_EOL() + ;
      "Options:" + HB_EOL() + ;
      "  search   - Enable web search" + HB_EOL() + ;
      "  think    - Enable DeepThink (reasoning)" + HB_EOL() + ;
      HB_EOL() + ;
      "Parameters:" + HB_EOL() + ;
      "  message  - Message to send (required)" + HB_EOL() + ;
      "  search   - Enable web search (boolean)" + HB_EOL() + ;
      "  think    - Enable DeepThink (boolean)"
