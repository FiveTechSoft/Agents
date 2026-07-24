#include "hbapi.h"
#include "hbapiitm.h"
#include <windows.h>

HB_FUNC( AGCON_GETCONMODE )
{
   DWORD dwMode = 0;
   if( GetConsoleMode( GetStdHandle( STD_INPUT_HANDLE ), &dwMode ) )
      hb_retnl( ( long ) dwMode );
   else
      hb_retnl( -1 );
}

HB_FUNC( AGCON_SETCONMODE )
{
   DWORD dwOld = 0;
   GetConsoleMode( GetStdHandle( STD_INPUT_HANDLE ), &dwOld );
   if( SetConsoleMode( GetStdHandle( STD_INPUT_HANDLE ), ( DWORD ) hb_parnl( 1 ) ) )
      hb_retnl( ( long ) dwOld );
   else
      hb_retnl( -1 );
}

/* AGCON_PEEKWHEEL -- Non-blocking peek at the console input buffer
 * for a MOUSE_WHEELED event.
 *
 * gtwin does not translate MOUSE_WHEELED records into K_MWFORWARD /
 * K_MWBACKWARD key codes, so Inkey() never returns them.  This C
 * helper fills the gap: it peeks at the head of the raw input queue,
 * and when the first event is a MOUSE_WHEELED record, consumes it
 * and returns the wheel direction.
 *
 * Returns:
 *    1  = wheel forward (away from user)  -> K_MWFORWARD
 *   -1  = wheel backward (toward user)    -> K_MWBACKWARD
 *    0  = no wheel event pending
 *
 * Non-wheel events are left in the buffer for gtwin to process
 * normally via ReadConsoleInput / Inkey().
 */
HB_FUNC( AGCON_PEEKWHEEL )
{
   HANDLE hStdIn = GetStdHandle( STD_INPUT_HANDLE );
   DWORD nEvents = 0;
   INPUT_RECORD pRecs[64];
   DWORD nRead = 0;
   DWORD i;

   if( hStdIn == INVALID_HANDLE_VALUE ||
       !GetNumberOfConsoleInputEvents( hStdIn, &nEvents ) || nEvents == 0 )
   {
      hb_retni( 0 );
      return;
   }

   if( nEvents > 64 )
      nEvents = 64;

   if( !PeekConsoleInput( hStdIn, pRecs, nEvents, &nRead ) || nRead == 0 )
   {
      hb_retni( 0 );
      return;
   }

   for( i = 0; i < nRead; i++ )
   {
      if( pRecs[i].EventType == MOUSE_EVENT &&
          ( pRecs[i].Event.MouseEvent.dwEventFlags & MOUSE_WHEELED ) )
      {
         short zDelta = (short) HIWORD( pRecs[i].Event.MouseEvent.dwButtonState );
         INPUT_RECORD trash[64];
         DWORD nRemoved = 0;
         /* Remove all records up to and including the wheel event */
         ReadConsoleInput( hStdIn, trash, i + 1, &nRemoved );
         hb_retni( ( zDelta > 0 ) ? 1 : -1 );
         return;
      }
   }

   hb_retni( 0 );
}
/* AGCON_PEEKMOUSE -- Non-blocking peek at console input for mouse button
 * and drag events.  Consumes mouse events from the raw input queue and
 * returns an array { nType, nRow, nCol } or NIL if nothing pending.
 *
 * nType:  1 = left button down   2 = left button up
 *         3 = mouse move with left button held (drag)
 *
 * nRow, nCol: 1-based screen coordinates.
 *
 * Wheel events are NOT consumed here (handled by AGCON_PEEKWHEEL).
 * Non-mouse events are left in the buffer for gtwin/Inkey().
 */
HB_FUNC( AGCON_PEEKMOUSE )
{
   HANDLE hStdIn = GetStdHandle( STD_INPUT_HANDLE );
   DWORD nEvents = 0;
   INPUT_RECORD pRecs[64];
   DWORD nRead = 0;
   DWORD i;

   if( hStdIn == INVALID_HANDLE_VALUE ||
       !GetNumberOfConsoleInputEvents( hStdIn, &nEvents ) || nEvents == 0 )
   {
      hb_ret();
      return;
   }

   if( nEvents > 64 )
      nEvents = 64;

   if( !PeekConsoleInput( hStdIn, pRecs, nEvents, &nRead ) || nRead == 0 )
   {
      hb_ret();
      return;
   }

   for( i = 0; i < nRead; i++ )
   {
      if( pRecs[i].EventType == MOUSE_EVENT )
      {
         DWORD dwFlags = pRecs[i].Event.MouseEvent.dwEventFlags;
         DWORD dwBtns  = pRecs[i].Event.MouseEvent.dwButtonState;
         COORD  coord  = pRecs[i].Event.MouseEvent.dwMousePosition;
         int nType = 0;

         /* Skip wheel events -- handled by AGCON_PEEKWHEEL */
         if( dwFlags & MOUSE_WHEELED )
            continue;

         if( dwFlags & MOUSE_MOVED )
         {
            /* Mouse move: only care if a button is held (drag) */
            if( dwBtns & FROM_LEFT_1ST_BUTTON_PRESSED )
               nType = 3;
         }
         else
         {
            /* Button press/release (no MOUSE_MOVED flag) */
            if( dwBtns & FROM_LEFT_1ST_BUTTON_PRESSED )
               nType = 1;  /* left down */
            else
               nType = 2;  /* left up (button released) */
         }

         if( nType != 0 )
         {
            INPUT_RECORD trash[64];
            DWORD nRemoved = 0;
            /* Remove all records up to and including this mouse event */
            ReadConsoleInput( hStdIn, trash, i + 1, &nRemoved );
            /* Return array { nType, nRow, nCol } -- 1-based row/col */
            {
               PHB_ITEM pArray = hb_itemArrayNew( 3 );
               hb_arraySetNI( pArray, 1, nType );
               hb_arraySetNI( pArray, 2, ( int ) coord.Y + 1 );
               hb_arraySetNI( pArray, 3, ( int ) coord.X + 1 );
               hb_itemReturn( pArray );
            }
            return;
         }
         /* nType == 0 (plain motion without button): skip, don't consume */
      }
   }

   hb_ret();
}

/* AGCON_SETCLIP -- Copy a string to the Windows clipboard.
 * Usage:  AGCON_SETCLIP( cText )
 * Returns:  .T. on success, .F. on failure.
 */
HB_FUNC( AGCON_SETCLIP )
{
   const char * szText = hb_parc( 1 );
   HGLOBAL hMem;
   char * pDst;
   int nLen;

   if( szText == NULL )
   {
      hb_retl( 0 );
      return;
   }

   nLen = strlen( szText );
   hMem = GlobalAlloc( GMEM_MOVEABLE, ( SIZE_T ) ( nLen + 1 ) );
   if( hMem == NULL )
   {
      hb_retl( 0 );
      return;
   }

   pDst = ( char * ) GlobalLock( hMem );
   memcpy( pDst, szText, nLen );
   pDst[ nLen ] = '\0';
   GlobalUnlock( hMem );

   if( !OpenClipboard( NULL ) )
   {
      GlobalFree( hMem );
      hb_retl( 0 );
      return;
   }

   EmptyClipboard();
   SetClipboardData( CF_TEXT, hMem );
   CloseClipboard();

   hb_retl( 1 );
}