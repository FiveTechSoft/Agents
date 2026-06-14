/* Windows console support for Agents: console detection, raw-mode
 * toggling, and raw key reading for the line editor. */
#include "hbapi.h"
#include "hbapiitm.h"
#include <windows.h>

/* AGCON_HasConsole() -> .T. when stdin is a real interactive console. */
HB_FUNC( AGCON_HASCONSOLE )
{
   DWORD mode;
   HANDLE h = GetStdHandle( STD_INPUT_HANDLE );
   hb_retl( h != INVALID_HANDLE_VALUE && h != NULL && GetConsoleMode( h, &mode ) );
}

static DWORD    s_AGCON_savedMode = 0;
static HB_BOOL  s_AGCON_modeSaved = HB_FALSE;

/* AGCON_RawMode( lOn ) -- lOn .T. disables line-input/echo/processed-input on
 * the console (so keystrokes and Ctrl+C arrive as raw events); .F. restores
 * the previously saved mode. Returns .T. on success, .F. on any failure. */
HB_FUNC( AGCON_RAWMODE )
{
   HB_BOOL fOn = hb_parl( 1 );
   HANDLE  h   = GetStdHandle( STD_INPUT_HANDLE );
   HB_BOOL fOk = HB_FALSE;

   if( h != INVALID_HANDLE_VALUE && h != NULL )
   {
      if( fOn )
      {
         DWORD mode;
         if( GetConsoleMode( h, &mode ) )
         {
            s_AGCON_savedMode = mode;
            s_AGCON_modeSaved = HB_TRUE;
            mode &= ~( ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT );
            if( SetConsoleMode( h, mode ) )
               fOk = HB_TRUE;
         }
      }
      else if( s_AGCON_modeSaved )
      {
         if( SetConsoleMode( h, s_AGCON_modeSaved ) )
            fOk = HB_TRUE;
      }
   }

   hb_retl( fOk );
}

/* AGCON_ReadKey() -- blocks for one key-down event and returns an int:
 *   > 0  the Unicode codepoint of a printable character
 *     0  end of input
 *    -1 Enter      -2 Backspace  -3 Left    -4 Right   -5 Home  -6 End
 *    -7 Delete     -8 Ctrl+C     -9 Up      -10 Down   -11 Shift+Enter
 *   -12 Tab        -13 Esc       -14 Ctrl+E
 *   -99 an unmapped key (caller ignores it). */
HB_FUNC( AGCON_READKEY )
{
   HANDLE       h = GetStdHandle( STD_INPUT_HANDLE );
   INPUT_RECORD rec;
   DWORD        nRead;
   int          result = -99;
   HB_BOOL      done = HB_FALSE;

   if( h == INVALID_HANDLE_VALUE || h == NULL )
   {
      hb_retni( 0 );
      return;
   }

   while( ! done )
   {
      if( ! ReadConsoleInputW( h, &rec, 1, &nRead ) || nRead == 0 )
      {
         result = 0;
         break;
      }
      if( rec.EventType != KEY_EVENT || ! rec.Event.KeyEvent.bKeyDown )
         continue;
      {
         WORD  vk   = rec.Event.KeyEvent.wVirtualKeyCode;
         WCHAR ch   = rec.Event.KeyEvent.uChar.UnicodeChar;
         DWORD cks  = rec.Event.KeyEvent.dwControlKeyState;
         HB_BOOL ctrl  = ( cks & ( LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED ) ) != 0;
         HB_BOOL shift = ( cks & SHIFT_PRESSED ) != 0;

         if( ctrl && vk == 'C' )         { result = -8; done = HB_TRUE; }
         else if( ctrl && vk == 'E' )    { result = -14; done = HB_TRUE; }
         else if( vk == VK_RETURN && shift )
                                          { result = -11; done = HB_TRUE; }
         else if( vk == VK_RETURN )      { result = -1; done = HB_TRUE; }
         else if( vk == VK_BACK )        { result = -2; done = HB_TRUE; }
         else if( vk == VK_LEFT )        { result = -3; done = HB_TRUE; }
         else if( vk == VK_RIGHT )       { result = -4; done = HB_TRUE; }
         else if( vk == VK_HOME )        { result = -5; done = HB_TRUE; }
         else if( vk == VK_END )         { result = -6; done = HB_TRUE; }
         else if( vk == VK_DELETE )      { result = -7; done = HB_TRUE; }
         else if( vk == VK_UP )          { result = -9; done = HB_TRUE; }
         else if( vk == VK_DOWN )        { result = -10; done = HB_TRUE; }
         else if( vk == VK_TAB )          { result = -12; done = HB_TRUE; }
         else if( vk == VK_ESCAPE )       { result = -13; done = HB_TRUE; }
         else if( ch >= 32 )             { result = ( int ) ch; done = HB_TRUE; }
         /* else: a non-printable key with no mapping -> read the next event */
      }
   }

   hb_retni( result );
}

/* AGCON_PeekCtrlC() -> .T. when a Ctrl+C key event is pending in the
 * console input buffer. The event is consumed and discarded, so a
 * subsequent AGCON_ReadKey will not see it. Non-blocking. */
HB_FUNC( AGCON_PEEKCTRLC )
{
   HANDLE h = GetStdHandle( STD_INPUT_HANDLE );
   DWORD nEvents = 0;
   INPUT_RECORD rec;
   DWORD nRead;
   WORD  vk;
   DWORD cks;
   HB_BOOL ctrl;

   if( h == INVALID_HANDLE_VALUE || h == NULL )
   {
      hb_retl( 0 );
      return;
   }

   if( ! GetNumberOfConsoleInputEvents( h, &nEvents ) || nEvents == 0 )
   {
      hb_retl( 0 );
      return;
   }

   /* Peek at the first pending event */
   if( PeekConsoleInputW( h, &rec, 1, &nRead ) && nRead > 0 )
   {
      if( rec.EventType == KEY_EVENT && rec.Event.KeyEvent.bKeyDown )
      {
         vk   = rec.Event.KeyEvent.wVirtualKeyCode;
         cks  = rec.Event.KeyEvent.dwControlKeyState;
         ctrl = ( cks & ( LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED ) ) != 0;

         if( ctrl && vk == 'C' )
         {
            /* Consume the event so it does not reach ReadLine */
            ReadConsoleInputW( h, &rec, 1, &nRead );
            hb_retl( 1 );
            return;
         }
      }
   }

   hb_retl( 0 );
}

/* AGCON_PeekEsc() -> .T. when an Escape key press is pending in the
 * console input buffer. The event IS consumed and discarded, so a later
 * ReadLine / AGCON_ReadKey will not see it. Non-blocking. */
HB_FUNC( AGCON_PEEKESC )
{
   HANDLE h = GetStdHandle( STD_INPUT_HANDLE );
   DWORD nEvents = 0;
   INPUT_RECORD rec;
   DWORD nRead;

   if( h == INVALID_HANDLE_VALUE || h == NULL )
   {
      hb_retl( 0 );
      return;
   }

   if( ! GetNumberOfConsoleInputEvents( h, &nEvents ) || nEvents == 0 )
   {
      hb_retl( 0 );
      return;
   }

   /* Peek at the first pending event */
   if( PeekConsoleInputW( h, &rec, 1, &nRead ) && nRead > 0 )
   {
      if( rec.EventType == KEY_EVENT && rec.Event.KeyEvent.bKeyDown &&
          rec.Event.KeyEvent.wVirtualKeyCode == VK_ESCAPE )
      {
         /* Consume the event so it does not interfere with later reads */
         ReadConsoleInputW( h, &rec, 1, &nRead );
         hb_retl( 1 );
         return;
      }
   }

   hb_retl( 0 );
}

/* AGCON_Size() -> { "rows" => <n>, "cols" => <n> } : the visible console
 * window size. Falls back to 24x80 when there is no console. */
HB_FUNC( AGCON_SIZE )
{
   HANDLE h = GetStdHandle( STD_OUTPUT_HANDLE );
   CONSOLE_SCREEN_BUFFER_INFO csbi;
   int rows = 24, cols = 80;
   PHB_ITEM pHash;
   PHB_ITEM pKey;
   PHB_ITEM pVal;

   if( h != INVALID_HANDLE_VALUE && h != NULL &&
       GetConsoleScreenBufferInfo( h, &csbi ) )
   {
      rows = csbi.srWindow.Bottom - csbi.srWindow.Top + 1;
      cols = csbi.srWindow.Right  - csbi.srWindow.Left + 1;
      if( rows < 1 ) rows = 24;
      if( cols < 1 ) cols = 80;
   }

   pHash = hb_hashNew( NULL );
   pKey  = hb_itemNew( NULL );
   pVal  = hb_itemNew( NULL );
   hb_hashAdd( pHash, hb_itemPutC( pKey, "rows" ), hb_itemPutNI( pVal, rows ) );
   hb_hashAdd( pHash, hb_itemPutC( pKey, "cols" ), hb_itemPutNI( pVal, cols ) );
   hb_itemRelease( pKey );
   hb_itemRelease( pVal );
   hb_itemReturnRelease( pHash );
}

/* AGCON_StdInWait( nMs ) -> .T. when stdin signals readiness within nMs
 * milliseconds. Used by the permission prompt (and any other reader that
 * wants a non-blocking timed wait on stdin). Returns .F. on timeout or
 * error. Console handles signal on any input event so the caller may
 * still see a 0-byte FRead and loop; redirected/piped stdin signals on
 * actual data. */
HB_FUNC( AGCON_STDINWAIT )
{
   int    nMs = hb_parni( 1 );
   HANDLE h   = GetStdHandle( STD_INPUT_HANDLE );
   DWORD  r;
   if( nMs < 0 ) nMs = 0;
   if( h == INVALID_HANDLE_VALUE || h == NULL )
   {
      hb_retl( HB_FALSE );
      return;
   }
   r = WaitForSingleObject( h, ( DWORD ) nMs );
   hb_retl( r == WAIT_OBJECT_0 );
}

/* AGCON_KeyPending() -> .T. when a key-down event is waiting in the console
 * input queue. Non-blocking; does NOT consume the event. */
HB_FUNC( AGCON_KEYPENDING )
{
   HANDLE h = GetStdHandle( STD_INPUT_HANDLE );
   DWORD  nEvents = 0, nRead, i;
   INPUT_RECORD recs[ 32 ];

   if( h == INVALID_HANDLE_VALUE || h == NULL ||
       ! GetNumberOfConsoleInputEvents( h, &nEvents ) || nEvents == 0 )
   {
      hb_retl( HB_FALSE );
      return;
   }
   if( nEvents > 32 ) nEvents = 32;
   if( PeekConsoleInputW( h, recs, nEvents, &nRead ) && nRead > 0 )
   {
      for( i = 0; i < nRead; i++ )
      {
         if( recs[ i ].EventType == KEY_EVENT && recs[ i ].Event.KeyEvent.bKeyDown )
         {
            hb_retl( HB_TRUE );
            return;
         }
      }
   }
   hb_retl( HB_FALSE );
}
