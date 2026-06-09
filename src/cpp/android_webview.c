/* android_webview.c - JNI bridge for AgenticAI on Android.
 *
 * Hosts the same HTML chat panel as the desktop FWH app in an Android WebView,
 * and runs the ccharbour agent loop on Harbour VM threads (one per agent).
 *
 * PRG-callable HB_FUNCs:
 *   AWV_SetHtml( cHtml )            -> MainActivity.setHtml()  (load the page)
 *   AWV_Eval( cJs )                -> MainActivity.evalJs()   (== oWeb:Eval)
 *   AWV_WaitEvent( nAgentId )      -> blocks; returns { cAction, cText }
 *   AWV_Http( cUrl, cHdrs, cBody, nTimeout ) -> { ok, status, body }
 *
 * From Java:
 *   nativeInit()                   -> hb_vmInit( Main )   (dispatcher thread)
 *   nativeEvent( id, action, text) -> enqueue onto queue[id]
 *
 * Threading: each Harbour agent thread (hb_threadStart) calls AttachCurrentThread
 * to obtain its JNIEnv. Events are delivered through per-agent queues guarded by a
 * mutex + condvar, so there is no callback re-entrancy and agents wait independently.
 */

#include <jni.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include <android/log.h>
#include "hbapi.h"
#include "hbapiitm.h"
#include "hbvm.h"
#include "hbstack.h"

#define TAG "AgenticAI"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  TAG, __VA_ARGS__)

#define MAX_AGENTS 32

static JavaVM  * g_jvm      = NULL;
static jobject   g_activity = NULL;   /* global ref to MainActivity */
static char      g_filesDir[ 1024 ] = "";   /* app-private writable dir */
static jclass    g_actClass = NULL;
static jmethodID m_setHtml;           /* (String)V */
static jmethodID m_evalJs;            /* (String)V */
static jmethodID m_httpPost;          /* (String,String,String,I)String */

/* ---- per-agent event queue ---- */
typedef struct ev_s { char * action; char * text; struct ev_s * next; } ev_t;
typedef struct {
   pthread_mutex_t mtx;
   pthread_cond_t  cnd;
   ev_t * head, * tail;
} queue_t;
static queue_t g_q[ MAX_AGENTS ];

static void q_init( void )
{
   int i;
   for( i = 0; i < MAX_AGENTS; i++ ) {
      pthread_mutex_init( &g_q[i].mtx, NULL );
      pthread_cond_init( &g_q[i].cnd, NULL );
      g_q[i].head = g_q[i].tail = NULL;
   }
}

static void q_push( int id, const char * action, const char * text )
{
   if( id < 0 || id >= MAX_AGENTS ) return;
   ev_t * e = (ev_t *) malloc( sizeof( ev_t ) );
   e->action = strdup( action ? action : "" );
   e->text   = strdup( text   ? text   : "" );
   e->next   = NULL;
   pthread_mutex_lock( &g_q[id].mtx );
   if( g_q[id].tail ) g_q[id].tail->next = e; else g_q[id].head = e;
   g_q[id].tail = e;
   pthread_cond_signal( &g_q[id].cnd );
   pthread_mutex_unlock( &g_q[id].mtx );
}

/* blocks until an event is available; caller frees nothing (we copy to Harbour) */
static ev_t * q_pop( int id )
{
   ev_t * e;
   pthread_mutex_lock( &g_q[id].mtx );
   while( g_q[id].head == NULL )
      pthread_cond_wait( &g_q[id].cnd, &g_q[id].mtx );
   e = g_q[id].head;
   g_q[id].head = e->next;
   if( g_q[id].head == NULL ) g_q[id].tail = NULL;
   pthread_mutex_unlock( &g_q[id].mtx );
   return e;
}

/* ---- JNIEnv for the current (possibly Harbour) thread ---- */
static JNIEnv * get_env( int * attached )
{
   JNIEnv * env = NULL;
   *attached = 0;
   if( (*g_jvm)->GetEnv( g_jvm, (void **) &env, JNI_VERSION_1_6 ) == JNI_EDETACHED ) {
      if( (*g_jvm)->AttachCurrentThread( g_jvm, &env, NULL ) == JNI_OK )
         *attached = 1;
   }
   return env;
}

JNIEXPORT jint JNICALL JNI_OnLoad( JavaVM * vm, void * reserved )
{
   ( void ) reserved;
   g_jvm = vm;
   q_init();
   return JNI_VERSION_1_6;
}

/* ================= Harbour-callable functions ================= */

/* AWV_SetHtml( cHtml ) */
HB_FUNC( AWV_SETHTML )
{
   int att; JNIEnv * env = get_env( &att );
   jstring js = (*env)->NewStringUTF( env, hb_parcx( 1 ) );
   (*env)->CallVoidMethod( env, g_activity, m_setHtml, js );
   (*env)->DeleteLocalRef( env, js );
   if( att ) (*g_jvm)->DetachCurrentThread( g_jvm );
}

/* AWV_Eval( cJs ) - run JS in the page (UI thread, marshalled in Java) */
HB_FUNC( AWV_EVAL )
{
   int att; JNIEnv * env;
   jstring js;
   env = get_env( &att );
   js = (*env)->NewStringUTF( env, hb_parcx( 1 ) );
   (*env)->CallVoidMethod( env, g_activity, m_evalJs, js );
   (*env)->DeleteLocalRef( env, js );
   if( att ) (*g_jvm)->DetachCurrentThread( g_jvm );
}

/* AWV_WaitEvent( nAgentId ) -> { cAction, cText }   (blocks)
   Release the MT VM lock around the blocking wait, otherwise a thread parked in
   pthread_cond_wait keeps the VM locked and other Harbour threads (e.g. a newly
   hb_threadStart'ed agent) can never reach a safe point -> deadlock. */
HB_FUNC( AWV_WAITEVENT )
{
   int id = hb_parni( 1 );
   ev_t * e;
   hb_vmUnlock();
   e = q_pop( id );
   hb_vmLock();
   PHB_ITEM aRet = hb_itemArrayNew( 2 );
   hb_arraySetC( aRet, 1, e->action );
   hb_arraySetC( aRet, 2, e->text );
   hb_itemReturnRelease( aRet );
   free( e->action ); free( e->text ); free( e );
}

/* AWV_Http( cUrl, cHeaders, cBody, nTimeout ) -> { ok, status, body }
   cHeaders is a single string, one "Key: Value" per line. */
HB_FUNC( AWV_HTTP )
{
   int att; JNIEnv * env = get_env( &att );
   jstring jUrl = (*env)->NewStringUTF( env, hb_parcx( 1 ) );
   jstring jHdr = (*env)->NewStringUTF( env, hb_parcx( 2 ) );
   jstring jBody= (*env)->NewStringUTF( env, hb_parcx( 3 ) );
   jstring jRes = (jstring) (*env)->CallObjectMethod( env, g_activity, m_httpPost,
                              jUrl, jHdr, jBody, hb_parni( 4 ) );
   const char * res = jRes ? (*env)->GetStringUTFChars( env, jRes, NULL ) : "0\n";

   /* res = "<status>\n<body...>" */
   int status = atoi( res );
   const char * nl = strchr( res, '\n' );
   const char * body = nl ? nl + 1 : "";

   PHB_ITEM hRes = hb_hashNew( NULL );
   PHB_ITEM k, v;

   k = hb_itemPutC( NULL, "ok" );     v = hb_itemPutL( NULL, status >= 200 && status < 400 );
   hb_hashAdd( hRes, k, v ); hb_itemRelease( k ); hb_itemRelease( v );
   k = hb_itemPutC( NULL, "status" ); v = hb_itemPutNI( NULL, status );
   hb_hashAdd( hRes, k, v ); hb_itemRelease( k ); hb_itemRelease( v );
   k = hb_itemPutC( NULL, "body" );   v = hb_itemPutC( NULL, body );
   hb_hashAdd( hRes, k, v ); hb_itemRelease( k ); hb_itemRelease( v );

   if( jRes ) { (*env)->ReleaseStringUTFChars( env, jRes, res ); (*env)->DeleteLocalRef( env, jRes ); }
   (*env)->DeleteLocalRef( env, jUrl );
   (*env)->DeleteLocalRef( env, jHdr );
   (*env)->DeleteLocalRef( env, jBody );
   if( att ) (*g_jvm)->DetachCurrentThread( g_jvm );

   hb_itemReturnRelease( hRes );
}

/* AWV_FilesDir() -> the app's private writable directory */
HB_FUNC( AWV_FILESDIR )
{
   hb_retc( g_filesDir );
}

static HB_SYMB s_symbols[] = {   /* NOT const: hb_vmProcessSymbols writes back dynsym ptrs */
   { "AWV_SETHTML",   { HB_FS_PUBLIC }, { HB_FUNCNAME( AWV_SETHTML   ) }, NULL },
   { "AWV_EVAL",      { HB_FS_PUBLIC }, { HB_FUNCNAME( AWV_EVAL      ) }, NULL },
   { "AWV_WAITEVENT", { HB_FS_PUBLIC }, { HB_FUNCNAME( AWV_WAITEVENT ) }, NULL },
   { "AWV_HTTP",      { HB_FS_PUBLIC }, { HB_FUNCNAME( AWV_HTTP      ) }, NULL },
   { "AWV_FILESDIR",  { HB_FS_PUBLIC }, { HB_FUNCNAME( AWV_FILESDIR  ) }, NULL }
};

static void register_awv( void )
{
   hb_vmProcessSymbols( (HB_SYMB *) s_symbols,
                        sizeof( s_symbols ) / sizeof( HB_SYMB ),
                        "ANDROID_WEBVIEW", 0, HB_PCODE_VER );
}

/* ================= JNI entry points ================= */

JNIEXPORT void JNICALL
Java_com_harbour_agenticai_MainActivity_nativeInit( JNIEnv * env, jobject thiz, jstring filesDir )
{
   if( filesDir ) {
      const char * fd = (*env)->GetStringUTFChars( env, filesDir, NULL );
      strncpy( g_filesDir, fd, sizeof( g_filesDir ) - 1 );
      (*env)->ReleaseStringUTFChars( env, filesDir, fd );
      /* Android process CWD is "/" (read-only). Move to the app's private dir so
         the memory tool and write/edit work. Done in C: HB_FUN_HB_DIRCHANGE is
         not in the linked libs. */
      if( g_filesDir[ 0 ] )
         chdir( g_filesDir );
   }

   g_activity = (*env)->NewGlobalRef( env, thiz );
   jclass cls = (*env)->GetObjectClass( env, thiz );
   g_actClass = (jclass) (*env)->NewGlobalRef( env, cls );

   m_setHtml  = (*env)->GetMethodID( env, cls, "setHtml",  "(Ljava/lang/String;)V" );
   m_evalJs   = (*env)->GetMethodID( env, cls, "evalJs",   "(Ljava/lang/String;)V" );
   m_httpPost = (*env)->GetMethodID( env, cls, "httpPost",
                  "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;I)Ljava/lang/String;" );
   (*env)->DeleteLocalRef( env, cls );

   /* Register our extra C symbols (s_symbols is non-const so hb_vmProcessSymbols
      can write back the dynsym pointers), then hb_vmInit(HB_TRUE) initializes the
      full MT VM and runs MAIN. (The earlier hb_dynsymNew crash was the const
      table, not the order; vmInit(HB_FALSE)+manual MAIN left MT half-initialized
      so hb_threadStart never ran the agent threads.) */
   register_awv();
   hb_vmInit( HB_TRUE );
   LOGI( "Harbour Main() returned" );
}

JNIEXPORT void JNICALL
Java_com_harbour_agenticai_MainActivity_nativeEvent( JNIEnv * env, jobject thiz,
                                                     jint agentId, jstring action, jstring text )
{
   ( void ) thiz;
   const char * a = action ? (*env)->GetStringUTFChars( env, action, NULL ) : "";
   const char * t = text   ? (*env)->GetStringUTFChars( env, text,   NULL ) : "";
   q_push( agentId, a, t );
   if( action ) (*env)->ReleaseStringUTFChars( env, action, a );
   if( text )   (*env)->ReleaseStringUTFChars( env, text,   t );
}
