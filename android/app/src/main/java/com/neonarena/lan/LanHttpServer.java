package com.neonarena.lan;

import android.content.Context;
import fi.iki.elonen.NanoHTTPD;
import java.io.InputStream;
import java.net.NetworkInterface;
import java.net.InetAddress;
import java.util.Enumeration;

public class LanHttpServer extends NanoHTTPD {
  private final Context ctx;
  public LanHttpServer(Context c,int port){super(port);ctx=c;}
  private String ips(){StringBuilder s=new StringBuilder();try{Enumeration<NetworkInterface> ns=NetworkInterface.getNetworkInterfaces();while(ns.hasMoreElements()){NetworkInterface n=ns.nextElement();Enumeration<InetAddress> as=n.getInetAddresses();while(as.hasMoreElements()){InetAddress a=as.nextElement();if(!a.isLoopbackAddress() && a instanceof java.net.Inet4Address){if(s.length()>0)s.append("\\n");s.append("http://").append(a.getHostAddress()).append(":8080");}}}}catch(Exception ignored){}return s.toString();}
  @Override public Response serve(IHTTPSession q){try{if(q.getUri().equals("/info"))return newFixedLengthResponse(Response.Status.OK,"application/json","{\"ok\":true,\"port\":8080,\"wsPort\":8081,\"addresses\":[\""+ips().replace("http://","http://").replace(":8080","\":8080,\"ws\":\"")+"\"]}");
      String name=q.getUri().equals("/")?"index.html":q.getUri().substring(1); InputStream in=ctx.getAssets().open(name); String mime=name.endsWith(".html")?"text/html":"text/plain";return newChunkedResponse(Response.Status.OK,mime,in);
    }catch(Exception e){return newFixedLengthResponse(Response.Status.NOT_FOUND,"text/plain","Not found");}}
}
