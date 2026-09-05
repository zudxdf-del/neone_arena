package com.neonarena.lan;

import org.java_websocket.WebSocket;
import org.java_websocket.handshake.ClientHandshake;
import org.java_websocket.server.WebSocketServer;
import org.json.*;
import java.net.InetSocketAddress;
import java.util.*;

public class LanWsServer extends WebSocketServer {
 static class P { WebSocket ws; double x,y,hp=100,ix,iy; int score; long last; }
 final P[] p={new P(),new P()}; boolean running=false; long lastTick=System.nanoTime();
 public LanWsServer(int port){super(new InetSocketAddress("0.0.0.0",port));}
 public void onOpen(WebSocket c,ClientHandshake h){}
 public void onClose(WebSocket c,int code,String reason,boolean remote){for(int i=0;i<2;i++)if(p[i].ws==c){p[i]=new P();running=false;}}
 public void onError(WebSocket c,Exception e){}
 public void onStart(){new Thread(()->{while(!isClosed()){try{Thread.sleep(50);tick();}catch(Exception ignored){}}}).start();}
 public void onMessage(WebSocket c,String s){try{JSONObject m=new JSONObject(s);String t=m.optString("type"); if(t.equals("create")){if(p[0].ws==null){p[0].ws=c;p[0].x=250;p[0].y=350;c.send(new JSONObject().put("type","waiting").toString());}return;} if(t.equals("join")){if(p[0].ws!=null&&p[1].ws==null){p[1].ws=c;p[1].x=750;p[1].y=350;running=true;p[0].ws.send("{\"type\":\"started\",\"player\":0}");p[1].ws.send("{\"type\":\"started\",\"player\":1}");}return;} for(int i=0;i<2;i++)if(p[i].ws==c){if(t.equals("input")){p[i].ix=Math.max(-1,Math.min(1,m.optDouble("x")));p[i].iy=Math.max(-1,Math.min(1,m.optDouble("y")));} if(t.equals("shoot"))fire(i);}}catch(Exception ignored){}}
 void fire(int i){if(!running||p[i].ws==null)return;long n=System.currentTimeMillis();if(n-p[i].last<220)return;p[i].last=n;int j=1-i;double dx=p[j].x-p[i].x,dy=p[j].y-p[i].y,l=Math.hypot(dx,dy);shots.add(new B(i,p[i].x,p[i].y,dx/l*650,dy/l*650));}
 static class B{int o;double x,y,vx,vy,life=1.6;B(int o,double x,double y,double vx,double vy){this.o=o;this.x=x;this.y=y;this.vx=vx;this.vy=vy;}}
 final List<B> shots=new ArrayList<>();
 void tick(){if(!running)return;double dt=.05;for(P a:p){double l=Math.hypot(a.ix,a.iy);if(l>0){a.x=Math.max(25,Math.min(975,a.x+a.ix/l*300*dt));a.y=Math.max(70,Math.min(675,a.y+a.iy/l*300*dt));}}for(Iterator<B> it=shots.iterator();it.hasNext();){B b=it.next();b.x+=b.vx*dt;b.y+=b.vy*dt;b.life-=dt;P t=p[1-b.o];if(Math.hypot(b.x-t.x,b.y-t.y)<28){it.remove();t.hp-=20;if(t.hp<=0){p[b.o].score++;p[0].hp=p[1].hp=100;p[0].x=250;p[1].x=750;shots.clear();}}else if(b.life<=0)it.remove();}try{JSONObject d=new JSONObject();d.put("type","snap");d.put("players",new JSONArray().put(obj(p[0])).put(obj(p[1])));JSONArray a=new JSONArray();for(B b:shots)a.put(new JSONObject().put("x",b.x).put("y",b.y).put("owner",b.o));d.put("bullets",a);for(P q:p)if(q.ws!=null&&q.ws.isOpen())q.ws.send(d.toString());}catch(Exception ignored){}}
 JSONObject obj(P q)throws Exception{return new JSONObject().put("x",q.x).put("y",q.y).put("hp",q.hp).put("score",q.score);}
}
