#include "hbapi.h"
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