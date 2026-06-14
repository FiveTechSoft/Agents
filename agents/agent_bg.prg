// ccbg: background-task registry. Holds the in-memory hash of every
// dispatch_agent_background invocation so the /tasks slash command can
// inspect them while they run in worker threads. Threads MUST NOT write
// to the terminal directly (that corrupts the dynamic input box) -- they
// only mutate the per-task record here, and the main REPL polls via the
// /tasks helpers.
//
// All public functions acquire s_mLock before touching s_hTasks, so the
// worker thread and the main REPL can hit the registry concurrently
// without races.

STATIC s_hTasks   := {=>}              // id (string) -> task record (hash)
STATIC s_nNextId  := 0                 // monotonic counter for ids
STATIC s_mLock    := NIL               // hb_mutexCreate, lazy-initialised

// Initialises the mutex on first use. hb_mutexCreate is cheap, but doing
// it once keeps the static initialisation order predictable.
STATIC FUNCTION CCBG_Lock()
   IF s_mLock == NIL
      s_mLock := hb_mutexCreate()
   ENDIF
   RETURN s_mLock

// Returns the next unique task id as a short string ("bg1", "bg2", ...).
// Holding the lock keeps the counter race-free even when multiple
// threads spawn through dispatch_agent_background at the same time.
FUNCTION CCBG_NextId()
   LOCAL cId
   hb_mutexLock( CCBG_Lock() )
   s_nNextId++
   cId := "bg" + LTrim( Str( s_nNextId ) )
   hb_mutexUnlock( CCBG_Lock() )
   RETURN cId

// Registers a new task. cId comes from CCBG_NextId; the caller is the
// worker thread's parent (the synchronous handler), which fills in the
// fixed-at-launch fields (prompt, type, timeout) and leaves the dynamic
// ones (status / started_ms / ended_ms / reply / error / iterations /
// cancel_requested) for CCBG_Update.
FUNCTION CCBG_Add( cId, cType, cPrompt, nTimeout )
   LOCAL hTask
   hTask := { "id"               => cId, ;
              "type"             => hb_CStr( cType ), ;
              "prompt"           => hb_CStr( cPrompt ), ;
              "timeout"          => iif( ValType( nTimeout ) == "N", nTimeout, 120 ), ;
              "status"           => "queued", ;
              "started_ms"       => 0, ;
              "ended_ms"         => 0, ;
              "iterations"       => 0, ;
              "reply"            => "", ;
              "error"            => "", ;
              "cancel_requested" => .F. }
   hb_mutexLock( CCBG_Lock() )
   s_hTasks[ cId ] := hTask
   hb_mutexUnlock( CCBG_Lock() )
   RETURN hTask

// Merges hPatch into the record stored under cId. Missing fields are
// added; existing fields are overwritten. No-op when the id is unknown
// (so a late update from a cancelled worker cannot resurrect a record
// that was already removed).
FUNCTION CCBG_Update( cId, hPatch )
   LOCAL hTask, cKey
   IF ValType( hPatch ) != "H"
      RETURN NIL
   ENDIF
   hb_mutexLock( CCBG_Lock() )
   IF hb_HHasKey( s_hTasks, cId )
      hTask := s_hTasks[ cId ]
      FOR EACH cKey IN hb_HKeys( hPatch )
         hTask[ cKey ] := hPatch[ cKey ]
      NEXT
   ENDIF
   hb_mutexUnlock( CCBG_Lock() )
   RETURN NIL

// Returns a clone of the task record under cId, or NIL when unknown.
// The clone keeps the caller from racing the worker thread's writes.
FUNCTION CCBG_Get( cId )
   LOCAL hTask := NIL
   hb_mutexLock( CCBG_Lock() )
   IF hb_HHasKey( s_hTasks, cId )
      hTask := hb_HClone( s_hTasks[ cId ] )
   ENDIF
   hb_mutexUnlock( CCBG_Lock() )
   RETURN hTask

// Snapshot of every task record (clones, ordered by id). Used by /tasks
// to render the table without holding the lock across the printout.
FUNCTION CCBG_List()
   LOCAL aOut := {}, cId
   hb_mutexLock( CCBG_Lock() )
   FOR EACH cId IN hb_HKeys( s_hTasks )
      AAdd( aOut, hb_HClone( s_hTasks[ cId ] ) )
   NEXT
   hb_mutexUnlock( CCBG_Lock() )
   // sort by numeric suffix of the id so "bg2" sorts before "bg10"
   ASort( aOut,,, {| a, b | Val( SubStr( a[ "id" ], 3 ) ) < Val( SubStr( b[ "id" ], 3 ) ) } )
   RETURN aOut

// Marks a task as cancel-requested. The worker thread sees the flag
// through its interrupt_check callback and bails out at the next agent-
// loop boundary; the final state ("cancelled") is then written by the
// dispatch wrapper. Returns .T. if the id existed and was running,
// .F. otherwise.
FUNCTION CCBG_Kill( cId )
   LOCAL lOk := .F.
   hb_mutexLock( CCBG_Lock() )
   IF hb_HHasKey( s_hTasks, cId ) .AND. ;
      ( s_hTasks[ cId ][ "status" ] == "running" .OR. ;
        s_hTasks[ cId ][ "status" ] == "queued" )
      s_hTasks[ cId ][ "cancel_requested" ] := .T.
      lOk := .T.
   ENDIF
   hb_mutexUnlock( CCBG_Lock() )
   RETURN lOk

// True when the worker for cId has been asked to cancel. Used by the
// worker's interrupt_check closure -- a single read under the lock to
// avoid torn reads on the logical flag.
FUNCTION CCBG_CancelRequested( cId )
   LOCAL lFlag := .F.
   hb_mutexLock( CCBG_Lock() )
   IF hb_HHasKey( s_hTasks, cId )
      lFlag := s_hTasks[ cId ][ "cancel_requested" ]
   ENDIF
   hb_mutexUnlock( CCBG_Lock() )
   RETURN lFlag

// Drops every task whose status is "done" / "failed" / "cancelled" /
// "timed_out". Running and queued tasks are kept. Returns the count of
// records removed so /tasks clear can confirm "[N tasks cleared]".
FUNCTION CCBG_ClearFinished()
   LOCAL nGone := 0, cId, cStatus
   hb_mutexLock( CCBG_Lock() )
   FOR EACH cId IN hb_HKeys( s_hTasks )
      cStatus := s_hTasks[ cId ][ "status" ]
      IF cStatus == "done" .OR. cStatus == "failed" .OR. ;
         cStatus == "cancelled" .OR. cStatus == "timed_out"
         hb_HDel( s_hTasks, cId )
         nGone++
      ENDIF
   NEXT
   hb_mutexUnlock( CCBG_Lock() )
   RETURN nGone
