/* Harbour-standard console backend for Agents (hbIDE style).
 *
 * Keyboard: blocking Inkey() + hb_keyStd() / hb_keyChar() -- the same
 * path hbIDE uses in editor.prg / Activate(). No custom termios, no
 * parallel TTY byte parser, no hb_keyVal() for printable characters
 * (on gtstd/gttrm Unix, hb_keyVal of a plain ASCII code is 0).
 *
 * Screen size: MaxRow/MaxCol from the GT (gttrm on Linux, gtwin/gtwvt
 * on Windows), with COLUMNS/LINES as a soft override when set.
 *
 * The Agents TUI still paints the prompt box with ANSI via FWrite; only
 * the *input* path is pure Harbour GT, matching hbIDE.
 */

#include "inkey.ch"
#include "hbgtinfo.ch"
#include "set.ch"

#define AGCON_INKEY_MASK  ( INKEY_ALL + HB_INKEY_GTEVENT )

STATIC s_nPending  := NIL   // one already-mapped AGCON code, or NIL
STATIC s_cLastChar := ""    // hb_keyChar() text of last printable key
STATIC s_lInit     := .F.

/* One-time GT setup, same spirit as hbIDE: New() / Activate(). */
STATIC FUNCTION _Init()
   IF ! s_lInit
      // Accept keyboard + GT events (resize, mouse wheel / motion)
      Set( _SET_EVENTMASK, hb_bitOr( INKEY_KEYBOARD, HB_INKEY_GTEVENT, INKEY_ALL ) )
      // Enable mouse so wheel events report a row/col (content vs prompt box).
      BEGIN SEQUENCE WITH {| o | Break( o ) }
         hb_gtInfo( HB_GTI_MOUSESTATUS, 1 )
      RECOVER
      END SEQUENCE
      s_lInit := .T.
   ENDIF
   RETURN NIL

/* Interactive console assumed when a real GT is linked (not gtnul).
 * Same stance as the original Agents comment and as hbIDE. */
FUNCTION AGCON_HasConsole()
   _Init()
   RETURN .T.

/* Suppress runtime Ctrl+C abort while the editor owns the keys.
 * The GT already puts the TTY in cbreak/raw; we do not touch termios. */
FUNCTION AGCON_RawMode( lOn )
   _Init()
   Set( _SET_CANCEL, ! lOn )
   IF ! lOn
      s_nPending  := NIL
      s_cLastChar := ""
   ENDIF
   RETURN .T.

/* Map a raw Inkey code to AGCON codes, hbIDE-style:
 *   specials via hb_keyStd(), printables via hb_keyChar(). */
STATIC FUNCTION _MapRaw( nRaw )
   LOCAL nStd, cKey, nCP, nMod
   s_cLastChar := ""
   IF nRaw == 0
      RETURN 0
   ENDIF
   // Enter FIRST -- raw codes before keyStd/keyChar can mis-classify them.
   // 13 = CR, 10 = LF, K_ENTER = 13. Always submit (-1). Ctrl+Enter = newline.
   IF nRaw == 13 .OR. nRaw == 10 .OR. nRaw == K_ENTER
      nMod := hb_keyMod( nRaw )
      IF hb_bitAnd( nMod, HB_GTI_KBD_CTRL ) != 0
         RETURN -11
      ENDIF
      RETURN -1
   ENDIF
   nStd := hb_keyStd( nRaw )
   nMod := hb_keyMod( nRaw )
   DO CASE
   CASE nStd == K_ENTER .OR. nStd == 10
      IF hb_bitAnd( nMod, HB_GTI_KBD_CTRL ) != 0
         RETURN -11
      ENDIF
      RETURN -1
   CASE nStd == K_BS     ; RETURN -2
   CASE nStd == K_LEFT   ; RETURN -3
   CASE nStd == K_RIGHT  ; RETURN -4
   CASE nStd == K_HOME   ; RETURN -5
   CASE nStd == K_END    ; RETURN -6
   CASE nStd == K_DEL    ; RETURN -7
   CASE nStd == K_CTRL_C .OR. nRaw == 3
      // K_PGDN is also 3 in Clipper; prefer Ctrl+C when raw is plain 3.
      // Extended PageDown usually arrives with nStd == K_PGDN and nRaw != 3.
      IF nStd == K_PGDN .AND. nRaw != 3 .AND. nRaw != K_CTRL_C
         RETURN -18
      ENDIF
      RETURN -8
   CASE nStd == K_CTRL_E ; RETURN -14   // selector "explain"
   CASE nStd == K_UP
      // Ctrl+Up → scroll transcript; plain Up → history
      RETURN iif( hb_bitAnd( nMod, HB_GTI_KBD_CTRL ) != 0, -17, -9 )
   CASE nStd == K_DOWN
      RETURN iif( hb_bitAnd( nMod, HB_GTI_KBD_CTRL ) != 0, -18, -10 )
   CASE nStd == K_CTRL_UP   ; RETURN -17
   CASE nStd == K_CTRL_DOWN ; RETURN -18
   CASE nStd == K_PGUP .OR. nRaw == K_PGUP ; RETURN -17
   CASE nStd == K_PGDN .OR. nRaw == K_PGDN
      // Avoid clobbering Ctrl+C (same base code 3 on some GTs).
      IF nRaw == 3 .OR. nRaw == K_CTRL_C
         RETURN -8
      ENDIF
      RETURN -18
   CASE nStd == K_TAB    ; RETURN -12
   CASE nStd == K_ESC    ; RETURN -13
   // Mouse wheel (gtwin/Windows Terminal). Some GTs leave them on nRaw.
   CASE nStd == K_MWFORWARD  .OR. nRaw == K_MWFORWARD  ; RETURN -15
   CASE nStd == K_MWBACKWARD .OR. nRaw == K_MWBACKWARD ; RETURN -16
   ENDCASE
   // Printable: hbIDE inserts with hb_keyChar(nKey), never hb_keyVal()
   cKey := hb_keyChar( nRaw )
   IF ! Empty( cKey )
      // Never insert CR/LF as text -- always submit
      IF cKey == Chr(13) .OR. cKey == Chr(10) .OR. Left( cKey, 1 ) == Chr(13)
         RETURN -1
      ENDIF
      s_cLastChar := cKey
      nCP := hb_UCode( cKey )
      IF nCP <= 0
         nCP := Asc( cKey )
      ENDIF
      IF nCP <= 0
         nCP := 1
      ENDIF
      RETURN nCP
   ENDIF
   // Fallback: plain ASCII code delivered as the raw inkey value itself
   // (gtstd/gttrm on Unix often return 97 for "a" without EXT bits).
   IF nRaw >= 32 .AND. nRaw < 127
      s_cLastChar := Chr( nRaw )
      RETURN nRaw
   ENDIF
   IF nRaw == 3
      RETURN -8
   ENDIF
   RETURN -99

/* Text of the last printable key (full UTF-8 string from hb_keyChar).
 * Callers that insert into the editor should prefer this over re-encoding
 * the codepoint, so multi-byte characters stay intact. */
FUNCTION AGCON_KeyText()
   RETURN s_cLastChar

/* Resolve what to insert for a positive AGCON code. */
FUNCTION AGCON_PrintableText( nKey )
   // If last MapRaw stored text for THIS codepoint, use it (UTF-8 safe).
   // Otherwise derive from the numeric code so PushKey/pending paths work
   // even when s_cLastChar is stale or empty.
   IF ValType( nKey ) != "N" .OR. nKey <= 0
      RETURN ""
   ENDIF
   IF ! Empty( s_cLastChar )
      // Accept only if it matches the codepoint (avoid stale char after pending)
      IF hb_UCode( s_cLastChar ) == nKey .OR. Asc( s_cLastChar ) == nKey
         RETURN s_cLastChar
      ENDIF
   ENDIF
   RETURN AGIN_Utf8Chr( nKey )

/* Push one already-mapped key so the next ReadKey/Poll sees it. */
FUNCTION AGCON_PushKey( nKey )
   s_nPending := nKey
   RETURN NIL

/* Non-blocking peek of one raw key -> mapped, or NIL.
 * IMPORTANT: Inkey(0) waits FOREVER, and so does any timeout below one
 * hundredth of a second: hbgtcore.c hb_gt_def_InkeyGet() computes
 *   timeout = ( fWait && dSeconds * 100 >= 1 ) ? dSeconds * 1000 : -1
 * so Inkey(0.001) -> timeout -1 -> infinite wait (this froze the whole
 * agent turn: first AGPROMPT_Poll blocked before curl ever spawned).
 * A true no-wait poll omits the timeout argument: Inkey( , mask ) sets
 * fWait = .F. and returns 0 immediately when no key is pending. */
STATIC FUNCTION _ReadKeyNB()
   LOCAL nRaw
   _Init()
   nRaw := Inkey( , AGCON_INKEY_MASK )
   DO WHILE nRaw == HB_K_RESIZE
      nRaw := Inkey( , AGCON_INKEY_MASK )
   ENDDO
   IF nRaw == 0
      RETURN NIL
   ENDIF
   RETURN _MapRaw( nRaw )

/* Last mouse row (0-based GT row) after a mouse/wheel event. -1 if unknown. */
FUNCTION AGCON_MouseRow()
   LOCAL nRow := -1
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      nRow := MRow()
   RECOVER
      nRow := -1
   END SEQUENCE
   IF ValType( nRow ) != "N"
      nRow := -1
   ENDIF
   RETURN nRow

/* AGCON_ReadKey() -- blocks for one key (hbIDE: InKey(0, ...)):
 *   >0 codepoint  0 EOF  -1 Enter  -2 BS  -3 Left  -4 Right  -5 Home
 *   -6 End  -7 Del  -8 Ctrl+C  -9 Up  -10 Down  -11 S-Enter  -12 Tab
 *   -13 Esc  -14 Ctrl+E  -15 WheelUp  -16 WheelDown
 *   -17 ScrollUp (PgUp / Ctrl+Up)  -18 ScrollDown (PgDn / Ctrl+Down)
 *   -99 unmapped */
FUNCTION AGCON_ReadKey()
   LOCAL nKey, nRaw
   _Init()
   IF s_nPending != NIL
      nKey := s_nPending
      s_nPending := NIL
      RETURN nKey
   ENDIF
   DO WHILE .T.
      nRaw := Inkey( 0, AGCON_INKEY_MASK )
      IF nRaw == 0
         RETURN 0
      ENDIF
      IF nRaw == HB_K_RESIZE
         LOOP
      ENDIF
      RETURN _MapRaw( nRaw )
   ENDDO
   RETURN 0

/* Wait up to nMs ms for a key; leave it in s_nPending. */
FUNCTION AGCON_WaitKey( nMs )
   LOCAL nRaw, nSec
   _Init()
   IF s_nPending != NIL
      RETURN .T.
   ENDIF
   IF ValType( nMs ) != "N" .OR. nMs < 0
      nMs := 200
   ENDIF
   nSec := nMs / 1000
   // Below 0.01s Harbour treats the timeout as infinite (see _ReadKeyNB
   // comment); clamp to the smallest wait Inkey can actually honour.
   IF nSec < 0.01
      nSec := 0.01
   ENDIF
   nRaw := Inkey( nSec, AGCON_INKEY_MASK )
   DO WHILE nRaw == HB_K_RESIZE
      nRaw := Inkey( , AGCON_INKEY_MASK )
   ENDDO
   IF nRaw == 0
      RETURN .F.
   ENDIF
   s_nPending := _MapRaw( nRaw )
   RETURN .T.

FUNCTION AGCON_PeekCtrlC()
   LOCAL nKey
   nKey := _ReadKeyNB()
   IF nKey == NIL
      RETURN .F.
   ENDIF
   IF nKey == -8
      RETURN .T.
   ENDIF
   s_nPending := nKey
   RETURN .F.

FUNCTION AGCON_PeekEsc()
   LOCAL nKey
   nKey := _ReadKeyNB()
   IF nKey == NIL
      RETURN .F.
   ENDIF
   IF nKey == -13
      RETURN .T.
   ENDIF
   s_nPending := nKey
   RETURN .F.

/* Terminal size from the GT; optional COLUMNS/LINES override. */
FUNCTION AGCON_Size()
   LOCAL nRows, nCols, cEnv
   _Init()
   nRows := MaxRow() + 1
   nCols := MaxCol() + 1
   cEnv := hb_GetEnv( "LINES" )
   IF ! Empty( cEnv ) .AND. Val( cEnv ) >= 8
      nRows := Int( Val( cEnv ) )
   ENDIF
   cEnv := hb_GetEnv( "COLUMNS" )
   IF ! Empty( cEnv ) .AND. Val( cEnv ) >= 20
      nCols := Int( Val( cEnv ) )
   ENDIF
   IF nRows < 8  ; nRows := 24 ; ENDIF
   IF nCols < 20 ; nCols := 80 ; ENDIF
   RETURN { "rows" => nRows, "cols" => nCols }

FUNCTION AGCON_StdInWait( nMs )
   RETURN AGCON_WaitKey( nMs )

FUNCTION AGCON_KeyPending()
   LOCAL nKey
   IF s_nPending != NIL
      RETURN .T.
   ENDIF
   nKey := _ReadKeyNB()
   IF nKey != NIL
      s_nPending := nKey
      RETURN .T.
   ENDIF
   RETURN .F.

/* No-op flush kept so AGPROMPT_Raw can call it; GT stdio is unbuffered
 * enough for interactive use, and we avoid a custom C helper. */
FUNCTION AGCON_TTY_FLUSH()
   RETURN NIL