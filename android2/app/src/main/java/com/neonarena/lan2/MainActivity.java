package com.neonarena.lan2;

import android.app.Activity;
import android.content.Context;
import android.net.wifi.WifiManager;
import android.os.Bundle;
import android.view.Window;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.net.ServerSocket;
import java.nio.charset.StandardCharsets;
import java.util.Enumeration;
import org.json.JSONArray;
import org.json.JSONObject;

public class MainActivity extends Activity {
    private LanHttpServer http;
    private LanWsServer ws;
    private DiscoveryServer discovery;
    private WebView web;
    private boolean started=false;
    private int httpPort=8080, wsPort=8081;

    @Override public void onCreate(Bundle b){
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        super.onCreate(b);
        web=new WebView(this);
        WebSettings s=web.getSettings(); s.setJavaScriptEnabled(true); s.setDomStorageEnabled(true); s.setMediaPlaybackRequiresUserGesture(false);
        web.setWebViewClient(new WebViewClient());
        web.addJavascriptInterface(new Bridge(),"Android");
        setContentView(web); web.loadUrl("file:///android_asset/index.html");
    }
    private int freePort(int preferred){
        for(int p=preferred;p<preferred+20;p++){
            try(ServerSocket ss=new ServerSocket(p)){ss.setReuseAddress(true);return p;}catch(Exception ignored){}
        }
        try(ServerSocket ss=new ServerSocket(0)){return ss.getLocalPort();}catch(Exception e){throw new RuntimeException("Нет свободного порта",e);}
    }
    private void stopServers(){
        try{if(discovery!=null)discovery.stopServer();}catch(Exception ignored){}
        try{if(http!=null)http.stop();}catch(Exception ignored){}
        try{if(ws!=null)ws.stopServer();}catch(Exception ignored){}
        discovery=null; http=null; ws=null; started=false;
    }
    private void startServers(String playerName){
        if(started)return;
        try{
            httpPort=freePort(8080);
            wsPort=freePort(8081);
            if(wsPort==httpPort) wsPort=freePort(8082);
            http=new LanHttpServer(this,httpPort,wsPort); http.start();
            ws=new LanWsServer(wsPort); ws.start();
            discovery=new DiscoveryServer(wsPort,playerName);
            new Thread(discovery,"neon-arena-discovery").start();
            started=true;
            web.evaluateJavascript("window.serverReady && window.serverReady("+jsQuote(getLanUrl())+")",null);
        }catch(Exception e){
            stopServers();
            Toast.makeText(this,"Не удалось запустить сервер: "+e.getMessage(),Toast.LENGTH_LONG).show();
        }
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
    private String getLanUrl(){return "http://"+getLanIp()+":"+httpPort;}
    private String getWsUrl(){return "ws://"+getLanIp()+":"+wsPort;}
    private String jsQuote(String x){return "\""+x.replace("\\","\\\\").replace("\"","\\\"")+"\"";}
    private void discoverGames(){
        new Thread(()->{
            JSONArray games=new JSONArray();
            WifiManager.MulticastLock lock=null;
            try{
                WifiManager wm=(WifiManager)getApplicationContext().getSystemService(Context.WIFI_SERVICE);
                if(wm!=null){lock=wm.createMulticastLock("neon-arena-discovery");lock.setReferenceCounted(false);lock.acquire();}
                DatagramSocket sock=new DatagramSocket(); sock.setBroadcast(true); sock.setSoTimeout(1200);
                byte[] q="DISCOVER_NEON_ARENA".getBytes(StandardCharsets.UTF_8);
                DatagramPacket req=new DatagramPacket(q,q.length,InetAddress.getByName("255.255.255.255"),DiscoveryServer.PORT);
                sock.send(req);
                long end=System.currentTimeMillis()+1200;
                while(System.currentTimeMillis()<end){
                    byte[] buf=new byte[1024]; DatagramPacket p=new DatagramPacket(buf,buf.length);
                    try{sock.receive(p);}catch(Exception timeout){break;}
                    try{
                        JSONObject o=new JSONObject(new String(p.getData(),p.getOffset(),p.getLength(),StandardCharsets.UTF_8));
                        o.put("ip",p.getAddress().getHostAddress());
                        games.put(o);
                    }catch(Exception ignored){}
                }
                sock.close();
            }catch(Exception ignored){}finally{if(lock!=null)try{lock.release();}catch(Exception ignored){}}
            final String out=games.toString();
            runOnUiThread(()->web.evaluateJavascript("window.discoveryResult && window.discoveryResult("+jsQuote(out)+")",null));
        },"neon-arena-scan").start();
    }
    public class Bridge{
        @JavascriptInterface public void startServer(String name){runOnUiThread(()->startServers(name));}
        @JavascriptInterface public String getLanUrl(){return MainActivity.this.getLanUrl();}
        @JavascriptInterface public String getWsUrl(){return MainActivity.this.getWsUrl();}
        @JavascriptInterface public boolean isServerStarted(){return started;}
        @JavascriptInterface public void discoverGames(){discoverGames();}
    }
    @Override protected void onDestroy(){stopServers();super.onDestroy();}
}
