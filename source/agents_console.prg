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
      // Accept keyboard + GT events (resize, mouse if the GT supports it)
      Set( _SET_EVENTMASK, hb_bitOr( INKEY_KEYBOARD, HB_INKEY_GTEVENT, INKEY_ALL ) )
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
   CASE nStd == K_CTRL_C ; RETURN -8
   CASE nStd == K_UP
      RETURN iif( hb_bitAnd( nMod, HB_GTI_KBD_CTRL ) != 0, -14, -9 )
   CASE nStd == K_DOWN   ; RETURN -10
   CASE nStd == K_TAB    ; RETURN -12
   CASE nStd == K_ESC    ; RETURN -13
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

/* Non-blocking: one raw key -> mapped, or NIL.
 * CRITICAL: must never block. Inkey(0) waits forever; that made
 * AGCON_KeyPending hang after Enter (no trailing LF yet) and broke
 * single-Enter /exit and every Poll drain when the queue was empty. */
STATIC FUNCTION _ReadKeyNB()
   LOCAL nRaw
   _Init()
   // Peek first -- NextKey does not wait
   nRaw := NextKey( AGCON_INKEY_MASK )
   IF nRaw == 0
      RETURN NIL
   ENDIF
   // Consume the peeked key
   nRaw := Inkey( 0, AGCON_INKEY_MASK )
   DO WHILE nRaw == HB_K_RESIZE
      nRaw := NextKey( AGCON_INKEY_MASK )
      IF nRaw == 0
         RETURN NIL
      ENDIF
      nRaw := Inkey( 0, AGCON_INKEY_MASK )
   ENDDO
   IF nRaw == 0
      RETURN NIL
   ENDIF
   RETURN _MapRaw( nRaw )

/* AGCON_ReadKey() -- blocks for one key (hbIDE: InKey(0, ...)):
 *   >0 codepoint  0 EOF  -1 Enter  -2 BS  -3 Left  -4 Right  -5 Home
 *   -6 End  -7 Del  -8 Ctrl+C  -9 Up  -10 Down  -11 S-Enter  -12 Tab
 *   -13 Esc  -14 Ctrl+E  -99 unmapped */
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
   IF nSec <= 0
      nSec := 0.001
   ENDIF
   nRaw := Inkey( nSec, AGCON_INKEY_MASK )
   DO WHILE nRaw == HB_K_RESIZE
      // Non-blocking: do not hang if only a resize was pending
      IF NextKey( AGCON_INKEY_MASK ) == 0
         RETURN .F.
      ENDIF
      nRaw := Inkey( 0, AGCON_INKEY_MASK )
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