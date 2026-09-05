package com.neonarena.lan2;

import android.content.Context;
import fi.iki.elonen.NanoHTTPD;
import java.io.InputStream;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.Enumeration;

public class LanHttpServer extends NanoHTTPD {
    private final Context ctx;
    private final int wsPort;
    private final String playerName;
    public LanHttpServer(Context c, int port, int websocketPort, String name) { super(port); ctx = c; wsPort = websocketPort; playerName = name == null ? "Игрок" : name; }

    public String getLanIp() {
        try {
            Enumeration<NetworkInterface> ns = NetworkInterface.getNetworkInterfaces();
            String fallback = null;
            while (ns.hasMoreElements()) {
                NetworkInterface n = ns.nextElement();
                String name = n.getName().toLowerCase();
                Enumeration<InetAddress> as = n.getInetAddresses();
                while (as.hasMoreElements()) {
                    InetAddress a = as.nextElement();
                    if (!(a instanceof Inet4Address) || a.isLoopbackAddress()) continue;
                    String ip = a.getHostAddress();
                    if (ip.startsWith("192.168.") || ip.startsWith("10.") || ip.matches("172\\.(1[6-9]|2[0-9]|3[0-1])\\..*")) {
                        if (name.contains("wlan") || name.contains("wifi") || name.contains("ap") || name.contains("swlan")) return ip;
                        if (fallback == null) fallback = ip;
                    }
                }
            }
            return fallback == null ? "127.0.0.1" : fallback;
        } catch (Exception e) { return "127.0.0.1"; }
    }

    private String json(String s){ return s.replace("\\","\\\\").replace("\"","\\\"").replace("\n"," "); }

    @Override public Response serve(IHTTPSession session) {
        try {
            String uri = session.getUri();
            if ("/info".equals(uri)) {
                String ip = getLanIp();
                String json = "{\"ok\":true,\"game\":true,\"name\":\"" + json(playerName) + "\",\"port\":" + getListeningPort() + ",\"wsPort\":" + wsPort + ",\"ip\":\"" + ip + "\",\"url\":\"http://" + ip + ":" + getListeningPort() + "\"}";
                return newFixedLengthResponse(Response.Status.OK, "application/json; charset=utf-8", json);
            }
            String name = "/".equals(uri) ? "index.html" : uri.substring(1);
            if (name.contains("..")) return newFixedLengthResponse(Response.Status.FORBIDDEN, "text/plain", "Forbidden");
            InputStream in = ctx.getAssets().open(name);
            String mime = name.endsWith(".html") ? "text/html; charset=utf-8" : "text/plain; charset=utf-8";
            return newChunkedResponse(Response.Status.OK, mime, in);
        } catch (Exception e) {
            return newFixedLengthResponse(Response.Status.NOT_FOUND, "text/plain; charset=utf-8", "Not found");
        }
    }
}
