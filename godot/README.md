# NEON ARENA — Godot 4 rebuild

This directory is the native 3D client rewrite of NEON ARENA.

## Current milestone
- Godot 4 native 3D scene.
- Bright arena with obstacles.
- First-person camera.
- Visible local/enemy characters and weapons.
- Visible bullets.
- Mobile-oriented FIRE / RELOAD / WEAPON controls.
- WebSocket connection to the existing Layero room server.
- Existing create/join room protocol is reused.
- Android is the target platform.

## Open the project
Open `godot/project.godot` with Godot 4.x.

## Online server
The prototype connects to:
`wss://neone-arena.layero.app`

The server still owns movement, bullets, HP, rooms and weapon state. The Godot client is being introduced without throwing away the working online backend.

## Next milestones
1. Replace primitive player/weapon meshes with polished assets.
2. Add real mobile dual-stick controls.
3. Add muzzle flash, recoil, hit effects, shadows and footsteps.
4. Add proper FPS collision/camera/weapon handling.
5. Improve server reconciliation and interpolation.
6. Add Android export preset and automated APK build.
7. Move authoritative gameplay fully to a Godot-compatible production protocol if needed.
