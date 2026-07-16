// ccskill: lightweight skill registry. Skills live as .md files under
// .agents/skills/ with YAML-style frontmatter (name, description). The
// model lists available skills in its system prompt and pulls the body on
// demand via the use_skill tool. Active skill names are tracked in a STATIC
// so the input box can render a status line.

#include "fileio.ch"

STATIC s_aActive := {}

// Returns the project-local skills directory ("./.agents/skills").
FUNCTION AGSKILL_Dir()
   RETURN "." + hb_ps() + ".agents" + hb_ps() + "skills"

// Lists every skill found under the skills directory. Each entry is a hash:
//   { name, description, path }. Skills missing a name/description are skipped.
FUNCTION AGSKILL_List()
   LOCAL aOut := {}, cDir := AGSKILL_Dir(), aFiles, aRow, cFile, hMeta
   IF !hb_DirExists( cDir )
      RETURN aOut
   ENDIF
   aFiles := Directory( cDir + hb_ps() + "*.md" )
   FOR EACH aRow IN aFiles
      cFile := cDir + hb_ps() + aRow[ 1 ]
      hMeta := AGSKILL_ReadFrontmatter( cFile )
      IF !Empty( hMeta[ "name" ] ) .AND. !Empty( hMeta[ "description" ] )
         AAdd( aOut, { "name"        => hMeta[ "name" ], ;
                       "description" => hMeta[ "description" ], ;
                       "triggers"    => hMeta[ "triggers" ], ;
                       "path"        => cFile } )
      ENDIF
   NEXT
   RETURN aOut

// Loads the full body of a skill (frontmatter stripped). Returns NIL when the
// skill is not found, so the caller can return an error to the model.
FUNCTION AGSKILL_Load( cName )
   LOCAL aSkills := AGSKILL_List(), hSkill, cText, nEnd
   FOR EACH hSkill IN aSkills
      IF hSkill[ "name" ] == hb_CStr( cName )
         cText := hb_MemoRead( hSkill[ "path" ] )
         // strip the leading "---\n...---\n" frontmatter block
         IF Left( cText, 4 ) == "---" + Chr(10)
            nEnd := At( Chr(10) + "---" + Chr(10), cText )
            IF nEnd > 0
               cText := SubStr( cText, nEnd + 5 )
            ENDIF
         ENDIF
         RETURN AllTrim( cText )
      ENDIF
   NEXT
   RETURN NIL

// Adds cName to the set of active skills (no-op if already active).
FUNCTION AGSKILL_Activate( cName )
   IF AScan( s_aActive, {| c | c == hb_CStr( cName ) } ) == 0
      AAdd( s_aActive, hb_CStr( cName ) )
   ENDIF
   RETURN s_aActive

// Removes cName from the active set (no-op if not active).
FUNCTION AGSKILL_Deactivate( cName )
   LOCAL n := AScan( s_aActive, {| c | c == hb_CStr( cName ) } )
   IF n > 0
      hb_ADel( s_aActive, n, .T. )
   ENDIF
   RETURN s_aActive

// Returns the array of active skill names (a copy, not the live STATIC).
FUNCTION AGSKILL_Active()
   RETURN AClone( s_aActive )

// Drops every active skill at once. Used by /load when restoring a saved
// session: the loaded skill list takes over from whatever was active.
FUNCTION AGSKILL_ClearAll()
   s_aActive := {}
   RETURN NIL

// Scans every skill's frontmatter triggers (case-insensitive regex patterns)
// against the user's input. Activates any matching skill that is not already
// active, and returns the array of newly-activated names so the caller can
// inject their bodies into the conversation and notify the user.
FUNCTION AGSKILL_AutoActivate( cInput )
   LOCAL aSkills := AGSKILL_List(), hSkill, aTriggers, cTrig, aNew := {}
   LOCAL cLow := Lower( hb_CStr( cInput ) )
   FOR EACH hSkill IN aSkills
      IF AScan( s_aActive, {| c | c == hSkill[ "name" ] } ) > 0
         LOOP   // already active -- do not re-inject
      ENDIF
      aTriggers := hSkill[ "triggers" ]
      IF ValType( aTriggers ) != "A" .OR. Empty( aTriggers )
         LOOP
      ENDIF
      FOR EACH cTrig IN aTriggers
         IF !Empty( cTrig ) .AND. ;
            hb_regexHas( Lower( hb_CStr( cTrig ) ), cLow, .T., .T. )
            AAdd( s_aActive, hSkill[ "name" ] )
            AAdd( aNew, hSkill[ "name" ] )
            EXIT
         ENDIF
      NEXT
   NEXT
   RETURN aNew

// Parses the YAML-style frontmatter at the head of cFile and returns a hash
// with name and description (empty strings when missing). Tolerates a missing
// or malformed frontmatter; the caller filters incomplete records out.
// Splits a comma-separated list of regex triggers into a trimmed array,
// dropping empty entries.
STATIC FUNCTION AGSKILL_SplitTriggers( cValue )
   LOCAL aRaw := hb_ATokens( hb_CStr( cValue ), "," ), aOut := {}, cTok
   FOR EACH cTok IN aRaw
      cTok := AllTrim( cTok )
      IF !Empty( cTok )
         AAdd( aOut, cTok )
      ENDIF
   NEXT
   RETURN aOut

STATIC FUNCTION AGSKILL_ReadFrontmatter( cFile )
   LOCAL cText, aLines, cLine, hOut, lIn := .F., cTrim
   hOut := { "name" => "", "description" => "", "triggers" => {} }
   IF !hb_FileExists( cFile )
      RETURN hOut
   ENDIF
   cText := hb_MemoRead( cFile )
   aLines := hb_ATokens( cText, Chr(10) )
   FOR EACH cLine IN aLines
      cTrim := AllTrim( cLine )
      IF cTrim == "---"
         IF !lIn
            lIn := .T.
         ELSE
            EXIT
         ENDIF
      ELSEIF lIn
         IF Left( cTrim, 5 ) == "name:"
            hOut[ "name" ] := AllTrim( SubStr( cTrim, 6 ) )
         ELSEIF Left( cTrim, 12 ) == "description:"
            hOut[ "description" ] := AllTrim( SubStr( cTrim, 13 ) )
         ELSEIF Left( cTrim, 9 ) == "triggers:"
            hOut[ "triggers" ] := AGSKILL_SplitTriggers( SubStr( cTrim, 10 ) )
         ENDIF
      ENDIF
   NEXT
   RETURN hOut
