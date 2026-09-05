package com.neonarena.lan2;

import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.nio.charset.StandardCharsets;

public class DiscoveryServer implements Runnable {
    public static final int PORT = 45454;
    private final int wsPort;
    private final String playerName;
    private volatile boolean running = true;
    private DatagramSocket socket;

    public DiscoveryServer(int wsPort, String playerName) { this.wsPort = wsPort; this.playerName = playerName; }
    public void stopServer(){ running=false; if(socket!=null) socket.close(); }
    private String json(String s){ return s.replace("\\","\\\\").replace("\"","\\\""); }
    @Override public void run(){
        try{
            socket=new DatagramSocket(PORT);
            socket.setBroadcast(true);
            byte[] buf=new byte[512];
            while(running){
                DatagramPacket p=new DatagramPacket(buf,buf.length);
                socket.receive(p);
                String q=new String(p.getData(),p.getOffset(),p.getLength(),StandardCharsets.UTF_8);
                if(!"DISCOVER_NEON_ARENA".equals(q)) continue;
                String out="{\"name\":\""+json(playerName)+"\",\"port\":"+wsPort+"}";
                byte[] data=out.getBytes(StandardCharsets.UTF_8);
                DatagramPacket r=new DatagramPacket(data,data.length,p.getAddress(),p.getPort());
                socket.send(r);
            }
        }catch(Exception ignored){}
    }
}
