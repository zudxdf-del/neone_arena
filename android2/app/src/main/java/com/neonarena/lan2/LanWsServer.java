package com.neonarena.lan2;

import org.java_websocket.WebSocket;
import org.java_websocket.handshake.ClientHandshake;
import org.java_websocket.server.WebSocketServer;
import org.json.JSONArray;
import org.json.JSONObject;
import java.net.InetSocketAddress;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

public class LanWsServer extends WebSocketServer {
    static class P { WebSocket ws; double x,y,hp=100,ix,iy; int score; long lastShot; }
    static class B { int owner; double x,y,vx,vy,life=1.6; B(int o,double a,double b,double c,double d){owner=o;x=a;y=b;vx=c;vy=d;} }
    final P[] p={new P(),new P()}; final List<B> shots=new ArrayList<>(); volatile boolean running; volatile boolean loop=true;
    public LanWsServer(int port){super(new InetSocketAddress("0.0.0.0",port));}
    @Override public void onOpen(WebSocket c, ClientHandshake h){}
    @Override public void onClose(WebSocket c,int code,String reason,boolean remote){for(int i=0;i<2;i++)if(p[i].ws==c){p[i]=new P();running=false;shots.clear();if(p[1-i].ws!=null)p[1-i].ws.send("{\"type\":\"opponent_left\"}");}}
    @Override public void onError(WebSocket c,Exception e){}
    @Override public void onStart(){new Thread(()->{while(loop){try{Thread.sleep(50);tick();}catch(InterruptedException e){Thread.currentThread().interrupt();break;}catch(Exception ignored){}}},"neon-arena-tick").start();}
    public void stopServer(){loop=false;try{stop();}catch(Exception ignored){}}
    void send(WebSocket c,String s){if(c!=null&&c.isOpen())c.send(s);}
    @Override public void onMessage(WebSocket c,String text){try{
        JSONObject m=new JSONObject(text); String t=m.optString("type");
        if("create".equals(t)){if(p[0].ws==null){p[0].ws=c;p[0].x=250;p[0].y=350;send(c,"{\"type\":\"waiting\"}");}return;}
        if("join".equals(t)){if(p[0].ws!=null&&p[1].ws==null){p[1].ws=c;p[1].x=750;p[1].y=350;p[0].hp=p[1].hp=100;running=true;send(p[0].ws,"{\"type\":\"started\",\"player\":0}");send(p[1].ws,"{\"type\":\"started\",\"player\":1}");}else send(c,"{\"type\":\"error\",\"message\":\"Игра уже занята или ещё не создана.\"}");return;}
        for(int i=0;i<2;i++)if(p[i].ws==c){if("input".equals(t)){p[i].ix=clamp(m.optDouble("x"));p[i].iy=clamp(m.optDouble("y"));}else if("shoot".equals(t))fire(i);}
    }catch(Exception ignored){}}
    double clamp(double v){return Math.max(-1,Math.min(1,v));}
    void fire(int i){if(!running||p[i].ws==null||p[1-i].ws==null)return;long n=System.currentTimeMillis();if(n-p[i].lastShot<220)return;p[i].lastShot=n;double dx=p[1-i].x-p[i].x,dy=p[1-i].y-p[i].y,l=Math.hypot(dx,dy);if(l<1)l=1;shots.add(new B(i,p[i].x,p[i].y,dx/l*650,dy/l*650));}
    void tick(){if(!running||p[0].ws==null||p[1].ws==null)return;double dt=.05;for(P a:p){double l=Math.hypot(a.ix,a.iy);if(l>0){a.x=Math.max(25,Math.min(975,a.x+a.ix/l*300*dt));a.y=Math.max(70,Math.min(675,a.y+a.iy/l*300*dt));}}Iterator<B> it=shots.iterator();while(it.hasNext()){B b=it.next();b.x+=b.vx*dt;b.y+=b.vy*dt;b.life-=dt;P target=p[1-b.owner];if(Math.hypot(b.x-target.x,b.y-target.y)<28){it.remove();target.hp-=20;if(target.hp<=0){p[b.owner].score++;p[0].hp=p[1].hp=100;p[0].x=250;p[1].x=750;shots.clear();}}else if(b.life<=0||b.x<-50||b.x>1050||b.y<20||b.y>750)it.remove();}try{JSONObject d=new JSONObject().put("type","snap");JSONArray ps=new JSONArray();for(P q:p)ps.put(new JSONObject().put("x",q.x).put("y",q.y).put("hp",q.hp).put("score",q.score));d.put("players",ps);JSONArray bs=new JSONArray();for(B b:shots)bs.put(new JSONObject().put("x",b.x).put("y",b.y).put("owner",b.owner));d.put("bullets",bs);for(P q:p)send(q.ws,d.toString());}catch(Exception ignored){}}
}
