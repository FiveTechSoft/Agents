package com.harbour.agenticai;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.view.ViewGroup;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebSettings;
import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

/**
 * AgenticAI Android host.
 *
 * The whole UI is the same HTML chat panel as the desktop FWH app, hosted in a
 * full-screen Android WebView. Harbour runs on its own background thread (the
 * "harbour" HandlerThread); it must NOT run on the UI thread because the agent
 * turn does blocking network I/O (which would ANR).
 *
 * Bridge (mirrors the desktop TWebView2 glue):
 *   PRG -> page : AWV_Eval(js)  -> nativeEval -> evalJs() on the UI thread
 *                                  == oWeb:Eval(js) / evaluateJavascript
 *   page -> PRG : Android.send(action, text)  (@JavascriptInterface)
 *                                  == SendToFWH(...) / bOnBind
 *
 * Unlike WebView2, Android WebView delivers JS->native calls on a binder thread,
 * so there is no bOnBind re-entrancy problem: the Harbour worker simply blocks on
 * a native event queue (AWV_WaitEvent) and the binder thread enqueues. That makes
 * the desktop TTimer deferral unnecessary here.
 */
public class MainActivity extends Activity {

    static { System.loadLibrary( "agenticai" ); }

    /* implemented in android_webview.c */
    private native void nativeInit( String filesDir );         // runs Harbour Main() (dispatcher)
    private native void nativeEvent( int agentId, String action, String text );

    private WebView web;
    private HandlerThread hbThread;
    private Handler hbHandler;
    private final Handler ui = new Handler();

    @Override
    protected void onCreate( Bundle savedInstanceState ) {
        super.onCreate( savedInstanceState );

        web = new WebView( this );
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled( true );
        s.setDomStorageEnabled( true );
        web.setWebViewClient( new WebViewClient() );   // keep navigation in-app
        s.setMediaPlaybackRequiresUserGesture( false );
        web.setWebChromeClient( new WebChromeClient() {
            @Override public void onPermissionRequest( final PermissionRequest request ) {
                runOnUiThread( new Runnable() { @Override public void run() {
                    request.grant( request.getResources() );   // allow mic for speech input
                }});
            }
        });
        web.addJavascriptInterface( new Bridge(), "Android" );

        if( checkSelfPermission( Manifest.permission.RECORD_AUDIO ) != PackageManager.PERMISSION_GRANTED )
            requestPermissions( new String[]{ Manifest.permission.RECORD_AUDIO }, 1 );
        setContentView( web, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT ) );

        /* Start Harbour on its own thread. Main() builds the HTML, calls
           setHtml(), then blocks on AWV_WaitEvent() processing turns. */
        hbThread = new HandlerThread( "harbour" );
        hbThread.start();
        hbHandler = new Handler( hbThread.getLooper() );
        final String filesDir = getFilesDir().getAbsolutePath();   // app-private, writable
        hbHandler.post( new Runnable() { @Override public void run() {
            nativeInit( filesDir );
        }});
    }

    /* ---- called from native (any thread) ---- */

    /** Load the HTML document produced by ChatHtml() in Harbour. */
    public void setHtml( final String html ) {
        ui.post( new Runnable() { @Override public void run() {
            web.loadDataWithBaseURL( "https://appassets.local/", html,
                                     "text/html", "utf-8", null );
        }});
    }

    /** Run a JS snippet in the page (== oWeb:Eval). Must hit the UI thread. */
    public void evalJs( final String js ) {
        ui.post( new Runnable() { @Override public void run() {
            web.evaluateJavascript( js, null );
        }});
    }

    /* ---- called from the page (JS), on a binder thread ---- */

    private class Bridge {
        /** agentId 0 is the dispatcher (new-agent / global commands); 1..N are
         *  the running agents, each on its own Harbour thread with its own event
         *  queue. The UI is a single WebView with one tab/panel per agent. */
        @JavascriptInterface
        public void send( int agentId, String action, String text ) {
            nativeEvent( agentId, action, text == null ? "" : text );
        }
    }

    /* ---- HTTP transport, called from a Harbour agent thread (never the UI
       thread, so blocking network here is fine). Plugged into ccharbour via
       hOpts["transport"]. Non-streaming first cut: returns the whole body and
       the status as "<status>\n<body>". ---- */
    public String httpPost( String url, String headers, String body, int timeoutSec ) {
        HttpURLConnection c = null;
        try {
            c = (HttpURLConnection) new URL( url ).openConnection();
            c.setRequestMethod( "POST" );
            c.setDoOutput( true );
            c.setConnectTimeout( timeoutSec * 1000 );
            c.setReadTimeout( timeoutSec * 1000 );
            if( headers != null ) {
                for( String h : headers.split( "\n" ) ) {
                    int p = h.indexOf( ':' );
                    if( p > 0 ) c.setRequestProperty( h.substring( 0, p ).trim(),
                                                      h.substring( p + 1 ).trim() );
                }
            }
            byte[] payload = body.getBytes( StandardCharsets.UTF_8 );
            OutputStream os = c.getOutputStream();
            os.write( payload );
            os.close();

            int status = c.getResponseCode();
            InputStream is = ( status >= 200 && status < 400 )
                    ? c.getInputStream() : c.getErrorStream();
            StringBuilder sb = new StringBuilder();
            if( is != null ) {
                BufferedReader r = new BufferedReader(
                        new InputStreamReader( is, StandardCharsets.UTF_8 ) );
                String line;
                while( ( line = r.readLine() ) != null ) sb.append( line ).append( '\n' );
                r.close();
            }
            return status + "\n" + sb.toString();
        } catch( Exception e ) {
            return "0\n" + e.toString();
        } finally {
            if( c != null ) c.disconnect();
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if( hbThread != null ) hbThread.quitSafely();
    }
}
