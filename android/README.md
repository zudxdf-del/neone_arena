# NEON ARENA Android LAN

APK starts the local HTTP server on port 8080 and the WebSocket game server on port 8081 automatically. No Termux and no PeerJS are required.

1. Install the APK on the phone that will host the game.
2. Turn on Android hotspot and let the second phone connect to it.
3. Open NEON ARENA on the host phone. The app starts its server automatically and shows a LAN URL.
4. Open that URL on the second phone and press `Подключиться`.

The APK build is available through GitHub Actions (`Android APK` -> `Run workflow` -> artifact `neon-arena-apk`).
