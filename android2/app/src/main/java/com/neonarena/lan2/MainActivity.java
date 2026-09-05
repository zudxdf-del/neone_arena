package com.neonarena.lan2;

import android.app.Activity;
import android.os.Bundle;
import android.view.Window;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;
import java.net.NetworkInterface;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.util.Enumeration;

public class MainActivity extends Activity {
    private LanHttpServer http;
    private LanWsServer ws;
    private WebView web;
    private boolean started=false;
    private final int HTTP_PORT=8080, WS_PORT=8081;

    @Override public void onCreate(Bundle b){
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        super.onCreate(b);
        web=new WebView(this);
        WebSettings s=web.getSettings(); s.setJavaScriptEnabled(true); s.setDomStorageEnabled(true); s.setMediaPlaybackRequiresUserGesture(false);
        web.setWebViewClient(new WebViewClient());
        web.addJavascriptInterface(new Bridge(),"Android");
        setContentView(web); web.loadUrl("file:///android_asset/index.html");
    }
    private void startServers(){
        if(started)return;
        try{ http=new LanHttpServer(this,HTTP_PORT); http.start(); ws=new LanWsServer(WS_PORT); ws.start(); started=true;
            web.evaluateJavascript("window.serverReady && window.serverReady("+jsQuote(getLanUrl())+")",null);
        }catch(Exception e){ Toast.makeText(this,"Не удалось запустить сервер: "+e.getMessage(),Toast.LENGTH_LONG).show(); }
    }
    private String getLanIp(){
        try{ Enumeration<NetworkInterface> ns=NetworkInterface.getNetworkInterfaces(); String fallback=null;
            while(ns.hasMoreElements()){ NetworkInterface n=ns.nextElement(); String name=n.getName().toLowerCase(); Enumeration<InetAddress> as=n.getInetAddresses();
                while(as.hasMoreElements()){ InetAddress a=as.nextElement(); if(!(a instanceof Inet4Address)||a.isLoopbackAddress())continue; String ip=a.getHostAddress();
                    if(ip.startsWith("192.168.")||ip.startsWith("10.")||ip.matches("172\\.(1[6-9]|2[0-9]|3[0-1])\\..*")){ if(name.contains("wlan")||name.contains("wifi")||name.contains("ap")||name.contains("swlan"))return ip; if(fallback==null)fallback=ip; }
                }
            } return fallback==null?"127.0.0.1":fallback;
        }catch(Exception e){return "127.0.0.1";}
    }
    private String getLanUrl(){return "http://"+getLanIp()+":"+HTTP_PORT;}
    private String getWsUrl(){return "ws://"+getLanIp()+":"+WS_PORT;}
    private String jsQuote(String x){return "\""+x.replace("\\","\\\\").replace("\"","\\\"")+"\"";}
    public class Bridge{
        @JavascriptInterface public void startServer(){runOnUiThread(()->startServers());}
        @JavascriptInterface public String getLanUrl(){return MainActivity.this.getLanUrl();}
        @JavascriptInterface public String getWsUrl(){return MainActivity.this.getWsUrl();}
        @JavascriptInterface public boolean isServerStarted(){return started;}
    }
    @Override protected void onDestroy(){if(http!=null)http.stop();if(ws!=null)ws.stopServer();super.onDestroy();}
}
