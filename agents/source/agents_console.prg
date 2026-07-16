/* Harbour-native console backend for Agents (cross-platform).
 *
 * Replaces the old Win32-only agents_console.c. It uses Harbour's own
 * keyboard/screen subsystem (Inkey()/hb_KeyGet()/hb_gtInfo()), which is
 * available on every platform, so no OS-specific C code is needed.
 *
 * This requires a real console GT (-gtwin on Windows, -gtstd/-gtcrs on
 * Linux/macOS) instead of -gtnul, because the keyboard/screen API lives
 * in the GT layer (gtnul disables it, which is why the previous code had
 * to drop down to raw Win32 calls). */

#include "inkey.ch"
#include "hbgtinfo.ch"
#include "set.ch"

/* AGCON_HasConsole() -> .T.
 * We assume an interactive console, exactly like hbide does: Harbour's
 * console GT (gtwin/gtstd) does not expose a native isatty()/TTY test at
 * PRG level, and the keyboard/screen API we use (Inkey()/hb_gtInfo()) is
 * always available under a real GT. There is no separate non-interactive
 * code path. */
FUNCTION AGCON_HasConsole()
   RETURN .T.

/* AGCON_RawMode( lOn ) -> .T.
 * No-op for the terminal: Harbour's console GT already puts the terminal
 * in raw/cbreak mode and routes Ctrl+C into the keyboard buffer. We use
 * this hook only to suppress the runtime's Ctrl+C abort so the app can
 * intercept it as a key. */
FUNCTION AGCON_RawMode( lOn )
   Set( _SET_CANCEL, ! lOn )
   RETURN .T.

/* Blocking read of one raw key event (Inkey() returns the extended code,
 * which hb_keyVal()/hb_keyMod() decompose into value + modifiers).
 * Terminal resize events (HB_K_RESIZE) are consumed and ignored so they
 * never surface to the caller (the TUI re-reads AGCON_Size every cycle). */
STATIC FUNCTION _KeyRaw()
   LOCAL nRaw
   DO WHILE .T.
      nRaw := Inkey( 0.05, HB_INKEY_ALL )
      IF nRaw == 0
         LOOP
      ENDIF
      IF nRaw == HB_K_RESIZE
         LOOP
      ENDIF
      RETURN nRaw
   ENDDO
   RETURN 0

/* Non-blocking peek of one pending key (standard code, modifiers
 * stripped - enough for Ctrl+C / Esc detection). Resize events are
 * consumed and dropped rather than pushed back, to avoid a busy loop. */
STATIC FUNCTION _KeyPeek()
   LOCAL n
   DO WHILE .T.
      n := Inkey( 0, HB_INKEY_ALL )
      IF n == 0
         RETURN 0
      ENDIF
      IF n == HB_K_RESIZE
         LOOP
      ENDIF
      RETURN n
   ENDDO
   RETURN 0

/* AGCON_ReadKey() -- blocks for one key event and returns an int:
 *   > 0  the Unicode codepoint of a printable character
 *     0  end of input
 *    -1 Enter      -2 Backspace  -3 Left    -4 Right   -5 Home  -6 End
 *    -7 Delete     -8 Ctrl+C     -9 Up      -10 Down   -11 Shift+Enter
 *   -12 Tab        -13 Esc       -14 Ctrl+E
 *   -99 an unmapped key (caller ignores it). */
FUNCTION AGCON_ReadKey()
   LOCAL nRaw := _KeyRaw()
   LOCAL nVal := hb_keyVal( nRaw )
   LOCAL nMod := hb_keyMod( nRaw )

   DO CASE
   CASE nVal == K_ENTER
      RETURN iif( hb_bitAnd( nMod, HB_GTI_KBD_SHIFT ) != 0, -11, -1 )
   CASE nVal == K_BS
      RETURN -2
   CASE nVal == K_LEFT
      RETURN -3
   CASE nVal == K_RIGHT
      RETURN -4
   CASE nVal == K_HOME
      RETURN -5
   CASE nVal == K_END
      RETURN -6
   CASE nVal == K_DEL
      RETURN -7
   CASE nVal == K_CTRL_C
      RETURN -8
   CASE nVal == K_UP
      RETURN iif( hb_bitAnd( nMod, HB_GTI_KBD_CTRL ) != 0, -14, -9 )
   CASE nVal == K_DOWN
      RETURN -10
   CASE nVal == K_TAB
      RETURN -12
   CASE nVal == K_ESC
      RETURN -13
   CASE nVal >= 32
      RETURN nVal
   OTHERWISE
      RETURN -99
   ENDCASE

/* AGCON_PeekCtrlC() -> .T. when a Ctrl+C is pending; the event is
 * consumed and discarded. Non-blocking. */
FUNCTION AGCON_PeekCtrlC()
   LOCAL nRaw := _KeyPeek()
   IF nRaw != 0
      IF hb_keyVal( nRaw ) == K_CTRL_C
         RETURN .T.
      ENDIF
      hb_keyPut( nRaw )
   ENDIF
   RETURN .F.

/* AGCON_PeekEsc() -> .T. when an Esc is pending; consumed. Non-blocking. */
FUNCTION AGCON_PeekEsc()
   LOCAL nRaw := _KeyPeek()
   IF nRaw != 0
      IF hb_keyVal( nRaw ) == K_ESC
         RETURN .T.
      ENDIF
      hb_keyPut( nRaw )
   ENDIF
   RETURN .F.

/* AGCON_Size() -> { "rows" => <n>, "cols" => <n> } */
FUNCTION AGCON_Size()
   RETURN { "rows" => MaxRow() + 1, "cols" => MaxCol() + 1 }

/* AGCON_StdInWait( nMs ) -> .T. when a key is ready within nMs ms. */
FUNCTION AGCON_StdInWait( nMs )
   LOCAL nEnd := hb_milliSeconds() + nMs
   LOCAL nRaw
   DO WHILE hb_milliSeconds() < nEnd
      nRaw := _KeyPeek()
      IF nRaw != 0
         hb_keyPut( nRaw )
         RETURN .T.
      ENDIF
      hb_idleSleep( 0.01 )
   ENDDO
   RETURN .F.

/* AGCON_KeyPending() -> .T. when a key is waiting. Non-blocking. */
FUNCTION AGCON_KeyPending()
   LOCAL nRaw := _KeyPeek()
   IF nRaw != 0
      hb_keyPut( nRaw )
      RETURN .T.
   ENDIF
   RETURN .F.
