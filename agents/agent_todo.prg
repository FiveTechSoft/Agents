// cctodo: the session todo list maintained by the todo_write tool. Holds the
// pure normaliser plus the in-memory list state. Knows nothing about
// rendering or the REPL.

STATIC s_aTodos := {}

// True when cStatus is one of the three valid task statuses.
STATIC FUNCTION CCTODO_ValidStatus( cStatus )
   RETURN cStatus == "pending" .OR. cStatus == "in_progress" .OR. ;
          cStatus == "completed"

// Returns a cleaned copy of aTodos. Each element must be a hash with a
// string "text"; others are dropped. A "status" that is missing or not one
// of the three valid values becomes "pending". Optional "id" (string,
// default ""), "active_form" (string, default "") and "blocked_by" (array
// of id strings, default {}) are preserved as-is. Returns an array of
// normalised hashes.
FUNCTION CCTODO_Norm( aTodos )
   LOCAL aOut := {}, hItem, cStatus, cId, cActive, aBlocked, aB, x
   IF ValType( aTodos ) != "A"
      RETURN aOut
   ENDIF
   FOR EACH hItem IN aTodos
      IF ValType( hItem ) != "H" .OR. !hb_HHasKey( hItem, "text" ) .OR. ;
         ValType( hItem[ "text" ] ) != "C"
         LOOP
      ENDIF
      cStatus := iif( hb_HHasKey( hItem, "status" ) .AND. ;
                      ValType( hItem[ "status" ] ) == "C", ;
                      hItem[ "status" ], "pending" )
      IF !CCTODO_ValidStatus( cStatus )
         cStatus := "pending"
      ENDIF
      cId := iif( hb_HHasKey( hItem, "id" ) .AND. ;
                  ValType( hItem[ "id" ] ) == "C", hItem[ "id" ], "" )
      cActive := iif( hb_HHasKey( hItem, "active_form" ) .AND. ;
                      ValType( hItem[ "active_form" ] ) == "C", ;
                      hItem[ "active_form" ], "" )
      aBlocked := {}
      IF hb_HHasKey( hItem, "blocked_by" ) .AND. ;
         ValType( hItem[ "blocked_by" ] ) == "A"
         aB := hItem[ "blocked_by" ]
         FOR EACH x IN aB
            IF ValType( x ) == "C" .AND. !Empty( x )
               AAdd( aBlocked, x )
            ENDIF
         NEXT
      ENDIF
      AAdd( aOut, { "text" => hItem[ "text" ], "status" => cStatus, ;
                    "id" => cId, "active_form" => cActive, ;
                    "blocked_by" => aBlocked } )
   NEXT
   RETURN aOut

// Normalises aTodos and stores it as the session list. Returns the stored list.
FUNCTION CCTODO_Set( aTodos )
   s_aTodos := CCTODO_Norm( aTodos )
   RETURN s_aTodos

// Returns a fresh copy of the stored session list (an empty array before
// the first Set). A copy, not the live STATIC, so a caller cannot mutate
// the stored state without going through CCTODO_Set.
FUNCTION CCTODO_Get()
   LOCAL aOut := {}, hItem
   FOR EACH hItem IN s_aTodos
      AAdd( aOut, { "text" => hItem[ "text" ], ;
                    "status" => hItem[ "status" ], ;
                    "id" => hItem[ "id" ], ;
                    "active_form" => hItem[ "active_form" ], ;
                    "blocked_by" => AClone( hItem[ "blocked_by" ] ) } )
   NEXT
   RETURN aOut

// True when hItem has a blocked_by id that matches another item in
// aAll which is not yet completed. Empty/missing blocked_by -> not blocked.
// Tolerant of items that came from older callers without the new keys.
FUNCTION CCTODO_IsBlocked( hItem, aAll )
   LOCAL cBlockId, hOther
   IF !hb_HHasKey( hItem, "blocked_by" ) .OR. ;
      ValType( hItem[ "blocked_by" ] ) != "A" .OR. ;
      Empty( hItem[ "blocked_by" ] )
      RETURN .F.
   ENDIF
   FOR EACH cBlockId IN hItem[ "blocked_by" ]
      FOR EACH hOther IN aAll
         IF hb_HHasKey( hOther, "id" ) .AND. ;
            hOther[ "id" ] == cBlockId .AND. ;
            hOther[ "status" ] != "completed"
            RETURN .T.
         ENDIF
      NEXT
   NEXT
   RETURN .F.

// True when the stored list is non-empty and at least one item is not done.
FUNCTION CCTODO_HasOpen()
   LOCAL hItem
   FOR EACH hItem IN s_aTodos
      IF hItem[ "status" ] != "completed"
         RETURN .T.
      ENDIF
   NEXT
   RETURN .F.
