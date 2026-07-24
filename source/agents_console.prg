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
STATIC s_aMouseEvent := NIL   // last peeked mouse event {nType,nRow,nCol}
STATIC s_lMouseBtnHeld := .F.

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
   AGCON_FixMouse()
   RETURN .T.

/* Fix the Windows Console input mode for mouse wheel support.
 * gtwin sets ENABLE_MOUSE_INPUT but Windows Terminal on Win11 may
 * override it or need VT input disabled. This uses C helpers to
 * diagnose and fix the mode AFTER gtwin's own init.
 * Also removes ENABLE_VIRTUAL_TERMINAL_INPUT (0x0200) which causes
 * Windows Terminal to send mouse events as VT escape sequences
 * instead of classic MOUSE_EVENT records via ReadConsoleInput. */
FUNCTION AGCON_FixMouse()
   LOCAL nMode := -1, nNew, cLog
   cLog := "AGCON_FixMouse called" + Chr(13) + Chr(10)
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      nMode := AGCON_GETCONMODE()
   RECOVER
      cLog += "  C call failed (exception)" + Chr(13) + Chr(10)
   END SEQUENCE
   cLog += "  nMode=" + LTrim(Str(nMode)) + " 0x" + hb_NumToHex( nMode, 8 ) + Chr(13) + Chr(10)
   IF nMode >= 0
      cLog += "  MOUSE=" + iif( hb_bitAnd( nMode, 0x0010 ) != 0, "Y", "N" )
      cLog += " VT=" + iif( hb_bitAnd( nMode, 0x0200 ) != 0, "Y", "N" )
      cLog += " QEDIT=" + iif( hb_bitAnd( nMode, 0x0040 ) != 0, "Y", "N" )
      cLog += " EXT=" + iif( hb_bitAnd( nMode, 0x0080 ) != 0, "Y", "N" ) + Chr(13) + Chr(10)
      // Set ENABLE_MOUSE_INPUT (0x10) + ENABLE_EXTENDED_FLAGS (0x80)
      // Clear ENABLE_QUICK_EDIT_MODE (0x40) + ENABLE_VIRTUAL_TERMINAL_INPUT (0x200)
      nNew := hb_bitOr( hb_bitAnd( nMode, hb_bitNot( 0x0240 ) ), 0x0090 )
      IF nNew != nMode
         BEGIN SEQUENCE WITH {| o | Break( o ) }
            AGCON_SETCONMODE( nNew )
         RECOVER
            cLog += "  SetConMode FAILED" + Chr(13) + Chr(10)
         END SEQUENCE
         cLog += "  FIXED -> 0x" + hb_NumToHex( nNew, 8 ) + Chr(13) + Chr(10)
      ELSE
         cLog += "  Mode OK" + Chr(13) + Chr(10)
      ENDIF
   ELSE
      cLog += "  C function returned error" + Chr(13) + Chr(10)
   ENDIF
   hb_MemoWrit( "C:\agents\wheel.log", cLog, .F. )
   RETURN nMode >= 0

FUNCTION AGCON_RawMode( lOn )
   _Init()
   Set( _SET_CANCEL, ! lOn )
   IF ! lOn
      s_nPending  := NIL
      s_cLastChar := ""
   ENDIF
   RETURN .T.


/* Safely read mouse coordinates.  Returns { nType, nRow, nCol } or
 * { nType, 0, 0 } when MRow/MCol fails. */
STATIC FUNCTION _MouseCoord( nType )
   LOCAL nRow := 0, nCol := 0
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      nRow := MRow() + 1
      nCol := MCol() + 1
   RECOVER
      nRow := 0
      nCol := 0
   END SEQUENCE
   RETURN { nType, nRow, nCol }
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
      // Ctrl+Up -> scroll transcript; plain Up -> history
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
   CASE nStd == K_MWFORWARD  .OR. nRaw == K_MWFORWARD  .OR. nRaw == 1014
      RETURN -15
   CASE nStd == K_MWBACKWARD .OR. nRaw == K_MWBACKWARD .OR. nRaw == 1015
      RETURN -16
   // Left button down/up -> route to selection handler with coordinates
   CASE nStd == K_LBUTTONDOWN
      s_lMouseBtnHeld := .T.
      s_aMouseEvent := { 1, MRow() + 1, MCol() + 1 }
      RETURN -19
   CASE nStd == K_LBUTTONUP
      s_lMouseBtnHeld := .F.
      s_aMouseEvent := { 2, MRow() + 1, MCol() + 1 }
      RETURN -19
   // Mouse move while left button held (drag) -> selection handler
   CASE nStd == K_MOUSEMOVE .AND. s_lMouseBtnHeld
      s_aMouseEvent := { 3, MRow() + 1, MCol() + 1 }
      RETURN -19
   // Other mouse events: ignore (never return 0 -- it means EOF/exit)
   CASE nStd == K_RBUTTONDOWN .OR. nStd == K_RBUTTONUP .OR. ;
        nStd == K_MOUSEMOVE .OR. ;
        ( nRaw >= K_MINMOUSE .AND. nRaw <= 1018 )
      RETURN -99
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

/* Check for a mouse wheel event via the C helper (AGCON_PEEKWHEEL).
 * gtwin does not translate MOUSE_WHEELED records into K_MWFORWARD /
 * K_MWBACKWARD, so Inkey() never returns them.  This peeks at the raw
 * console input buffer and consumes any wheel event before gtwin sees it.
 * Returns -15 (wheel up) / -16 (wheel down), or NIL when nothing pending. */
STATIC FUNCTION _CheckWheel()
   LOCAL nWheel := 0
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      nWheel := AGCON_PEEKWHEEL()
   RECOVER
      RETURN NIL
   END SEQUENCE
   IF ValType( nWheel ) != "N" .OR. nWheel == 0
      RETURN NIL
   ENDIF
   RETURN iif( nWheel > 0, -15, -16 )
/* Check for mouse button/drag events via the C helper (AGCON_PEEKMOUSE).
 * gtwin maps these to -99 which is useless, so we peek at the raw queue
 * before Inkey() can consume them.  Returns -19 when a mouse event is
 * pending, storing the event data in s_aMouseEvent for AGCON_MouseEvent().
 * Returns NIL when nothing pending. */
STATIC FUNCTION _CheckMouseEvent()
   LOCAL aEvt
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      aEvt := AGCON_PEEKMOUSE()
   RECOVER
      RETURN NIL
   END SEQUENCE
   IF aEvt == NIL .OR. ValType( aEvt ) != "A" .OR. Len( aEvt ) < 3
      RETURN NIL
   ENDIF
   s_aMouseEvent := aEvt
   RETURN -19

/* Return the last peeked mouse event {nType, nRow, nCol} or NIL. */
FUNCTION AGCON_MouseEvent()
   LOCAL aEvt := s_aMouseEvent
   s_aMouseEvent := NIL
   RETURN aEvt

/* Non-blocking peek of one raw key -> mapped, or NIL.
 * IMPORTANT: Inkey(0) waits FOREVER, and so does any timeout below one
 * hundredth of a second: hbgtcore.c hb_gt_def_InkeyGet() computes
 *   timeout = ( fWait && dSeconds * 100 >= 1 ) ? dSeconds * 1000 : -1
 * so Inkey(0.001) -> timeout -1 -> infinite wait (this froze the whole
 * agent turn: first AGPROMPT_Poll blocked before curl ever spawned).
 * A true no-wait poll omits the timeout argument: Inkey( , mask ) sets
 * fWait = .F. and returns 0 immediately when no key is pending. */
STATIC FUNCTION _ReadKeyNB()
   LOCAL nRaw, nWheel
   _Init()
   // Check for mouse wheel first (gtwin drops these)
   nWheel := _CheckWheel()
   IF nWheel != NIL
      RETURN nWheel
   ENDIF
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
   LOCAL nKey, nRaw, nWheel
   _Init()
   IF s_nPending != NIL
      nKey := s_nPending
      s_nPending := NIL
      RETURN nKey
   ENDIF
   DO WHILE .T.
      // Check for mouse wheel before blocking on Inkey (gtwin drops these)
      nWheel := _CheckWheel()
      IF nWheel != NIL
         RETURN nWheel
      ENDIF
      // Use a short timeout instead of Inkey(0) so we can periodically
      // check for mouse wheel events that gtwin ignores.
      nRaw := Inkey( 0.05, AGCON_INKEY_MASK )
      IF nRaw == HB_K_RESIZE
         LOOP
      ENDIF
      IF nRaw != 0
         RETURN _MapRaw( nRaw )
      ENDIF
      // nRaw == 0: timeout with no key -- loop back to check wheel
   ENDDO
   RETURN 0


/* Wait up to nMs ms for a key; leave it in s_nPending. */
FUNCTION AGCON_WaitKey( nMs )
   LOCAL nRaw, nSec, nWheel
   _Init()
   IF s_nPending != NIL
      RETURN .T.
   ENDIF
   // Check for mouse wheel first (gtwin drops these)
   nWheel := _CheckWheel()
   IF nWheel != NIL
      s_nPending := nWheel
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
