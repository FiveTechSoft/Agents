// agents_screenbuf.prg — Ring buffer for terminal scroll-back.
//
// Every line of output that passes through AGREPL_Out is appended to this
// ring buffer.  When the user scrolls up (mouse wheel / PgUp), the viewport
// is repainted from the buffer instead of using SaveScreen/RestScreen (which
// can only see the currently visible rows).
//
// Design:
//   s_aLines   — fixed-size array (ring buffer), s_nMaxLines capacity.
//   s_nHead    — index of the MOST RECENT line written (1-based).
//   s_nCount   — total valid lines in the buffer (<= s_nMaxLines).
//   s_nScroll  — scroll offset: 0 = at the bottom (latest), >0 = scrolled up.
//                s_nScroll == s_nCount means the very oldest line is at top.
//
// When the ring wraps, the oldest lines are silently dropped.
// Memory: 5000 lines * ~200 bytes avg = ~1 MB.

#include "inkey.ch"

// Buffer state
STATIC s_aLines   := {}       // the ring buffer array
STATIC s_nMax     := 5000     // max lines before oldest are dropped
STATIC s_nHead    := 0        // index of the newest line (1..s_nMax)
STATIC s_nCount   := 0        // how many valid lines (0..s_nMax)
STATIC s_nScroll  := 0        // scroll offset (0 = bottom)
STATIC s_lActive  := .F.      // .T. after AGSB_Init

// Initialise (or reinitialise) the buffer.  nMax defaults to 5000.
FUNCTION AGSB_Init( nMax )
   IF ValType( nMax ) != "N" .OR. nMax < 100
      nMax := 5000
   ENDIF
   s_nMax    := nMax
   s_aLines  := Array( nMax )
   AEval( s_aLines, {|x,i| s_aLines[i] := "" } )
   s_nHead   := 0
   s_nCount  := 0
   s_nScroll := 0
   s_lActive := .T.
   RETURN NIL

// Empty the buffer and reset scroll.
FUNCTION AGSB_Clear()
   AEval( s_aLines, {|x,i| s_aLines[i] := "" } )
   s_nHead   := 0
   s_nCount  := 0
   s_nScroll := 0
   RETURN NIL

// Append one display row to the buffer.  A "row" is the text between
// two line-feeds as it would appear on screen (may contain ANSI escapes).
FUNCTION AGSB_Append( cLine )
   IF !s_lActive
      RETURN NIL
   ENDIF
   cLine := hb_CStr( cLine )
   // advance head
   s_nHead++
   IF s_nHead > s_nMax
      s_nHead := 1
   ENDIF
   s_aLines[ s_nHead ] := cLine
   IF s_nCount < s_nMax
      s_nCount++
   ENDIF
   // if we are at the bottom, stay at the bottom (new content visible)
   IF s_nScroll > 0
      // when new lines arrive while scrolled, keep the same relative
      // position so the user view does not jump — but clamp so we
      // never exceed the new total.
      IF s_nScroll > s_nCount - 1
         s_nScroll := s_nCount - 1
      ENDIF
   ENDIF
   RETURN NIL

// Number of lines currently in the buffer.
FUNCTION AGSB_Count()
   RETURN s_nCount

// Current scroll offset (0 = bottom).
FUNCTION AGSB_ScrollOffset()
   RETURN s_nScroll

// True when the user has scrolled away from the bottom.
FUNCTION AGSB_IsScrolling()
   RETURN s_nScroll > 0

// Scroll up (reveal older lines).  nLines defaults to 3.
FUNCTION AGSB_ScrollUp( nLines )
   IF ValType( nLines ) != "N" .OR. nLines < 1
      nLines := 3
   ENDIF
   s_nScroll := Min( s_nScroll + nLines, Max( 0, s_nCount - 1 ) )
   RETURN s_nScroll

// Scroll down (reveal newer lines).  nLines defaults to 3.
FUNCTION AGSB_ScrollDown( nLines )
   IF ValType( nLines ) != "N" .OR. nLines < 1
      nLines := 3
   ENDIF
   s_nScroll := Max( s_nScroll - nLines, 0 )
   RETURN s_nScroll

// Jump to the very bottom (latest output).
FUNCTION AGSB_ScrollToBottom()
   s_nScroll := 0
   RETURN NIL

// Absolute line access.
// Lines are numbered 1 (oldest) .. s_nCount (newest).

// Return the ring-buffer index for logical position nPos.
FUNCTION AGSB_AbsIndex( nPos )
   LOCAL nHead
   IF nPos < 1 .OR. nPos > s_nCount
      RETURN 0
   ENDIF
   // s_nHead points at the newest; going back s_nCount - nPos from newest.
   nHead := s_nHead - ( s_nCount - nPos )
   IF nHead < 1
      nHead += s_nMax
   ENDIF
   RETURN nHead

// Get the text of line at logical position nPos (1=oldest, s_nCount=newest).
FUNCTION AGSB_GetLine( nPos )
   LOCAL nIdx
   IF !s_lActive .OR. nPos < 1 .OR. nPos > s_nCount
      RETURN ""
   ENDIF
   nIdx := AGSB_AbsIndex( nPos )
   RETURN iif( nIdx > 0, s_aLines[ nIdx ], "" )
