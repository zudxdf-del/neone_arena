package com.neonarena.lan;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

public class MainActivity extends Activity {
  LanHttpServer http; LanWsServer ws; WebView web;
  @Override public void onCreate(Bundle b){ super.onCreate(b); web=new WebView(this); web.getSettings().setJavaScriptEnabled(true); web.getSettings().setDomStorageEnabled(true); web.setWebViewClient(new WebViewClient()); setContentView(web);
    try { http=new LanHttpServer(this,8080); http.start(); ws=new LanWsServer(8081); ws.start(); web.loadUrl("http://127.0.0.1:8080/"); } catch(Exception e){ Toast.makeText(this,"Не удалось запустить LAN-сервер: "+e.getMessage(),Toast.LENGTH_LONG).show(); }
  }
  @Override protected void onDestroy(){ if(http!=null) http.stop(); if(ws!=null) ws.stopServer(); super.onDestroy(); }
}
