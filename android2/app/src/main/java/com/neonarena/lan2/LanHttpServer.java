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
    public LanHttpServer(Context c, int port) { super(port); ctx = c; }

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
                    if (ip.startsWith("192.168.") || ip.startsWith("10.") || ip.startsWith("172.")) {
                        if (name.contains("wlan") || name.contains("wifi") || name.contains("ap") || name.contains("swlan")) return ip;
                        if (fallback == null) fallback = ip;
                    }
                }
            }
            return fallback == null ? "127.0.0.1" : fallback;
        } catch (Exception e) { return "127.0.0.1"; }
    }

    @Override public Response serve(IHTTPSession session) {
        try {
            String uri = session.getUri();
            if ("/info".equals(uri)) {
                String ip = getLanIp();
                String json = "{\"ok\":true,\"port\":8080,\"wsPort\":8081,\"ip\":\"" + ip + "\",\"url\":\"http://" + ip + ":8080\"}";
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
