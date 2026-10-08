This is a weapons pack to demonstrate the capabilities of the [**Dot collection**](https://moddingcommunity.com/co/4-dot-assets) built on-top of [Godot 4](https://godotengine.org/) and [TMC's gaming platform](https://moddingcommunity.com/play). It adds twenty-seven ready-made weapons on top of [dot-weapon](https://github.com/modcommunity/dot-weapon) (blasters, melee weapons, grenades and fists), along with everything a player sees and hears: first-person view models with arms, third-person world models, animation, tracers, sounds and recoil. The games in the Dot collection, such as [game-arena](https://github.com/gamemann/game-arena), use it.

**This pack and the assets under it are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license, and the art it ships is CC0, which asks for even less. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This pack, along with every asset it is built on, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** It has its own headless test suite and that suite passes, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## What is in it
Art is Kenney's **Blaster Kit**, with the melee weapons from the Weapon Pack and Survival Kit and the first-person hands from the Blocky Characters. All of it is CC0 and included, so there is nothing to download.

![the whole pack](docs/rack.png)

| Slot | Weapons |
| --- | --- |
| 1 · Melee | Fists, Knife, Shiv, Hatchet, Mallet, Pickaxe, Spade |
| 2 · Sidearm | Dart Pistol, Revolver, Machine Pistol, Derringer |
| 3 · Primary | SMG, Carbine, Assault Rifle, Bullpup, Battle Rifle, Burst Rifle, Shotgun, Drum Shotgun, Marksman Rifle |
| 4 · Heavy | Sniper Rifle, Minigun, Launcher, Beamer, Charge Rifle |
| 5 · Thrown | Frag Grenade, Sticky Charge |

Every blaster can also **bash** with the alt-fire button.

Each weapon plays differently, not just with different numbers. The knife is the fastest thing in the pack and the mallet hits hardest. The bullpup is the only weapon that stays accurate while you move. The beamer rewards keeping your aim on a target, not flicking to it, and the minigun has no magazine: it just runs out. The weapons share seven ammunition types between them, so picking up a box of darts is a real choice.

## What it adds to dot-weapon
dot-weapon decides when a weapon fires, reloads and switches, but it doesn't draw anything. This pack is the part you see and hear:

| Class | What it does |
| --- | --- |
| `ZeeWeaponPack` | The twenty-seven weapons, tuned in ticks and checked as one document. A dedicated server can validate them at boot without any art installed. |
| `ZeeWeaponArtTable` | The only file that knows a filename. Weapons are named by role, so swapping the art means editing this one table. |
| `ZeeViewModel` | The weapon in your own hands: arms, magazine, attachments, sway, bob, recoil, deploy, reload and charge. `aim(held)` brings it to the centre of the screen and reports a zoom for the camera (`aim_fov_scale()`). The sniper and marksman rifle get a scope (`ZeeScopeOverlay`). Aiming is set per weapon in the art table (`aim_enabled`, `aim_zoom`, `aim_scoped`, `aim_offset`, `aim_time`) and only changes what is drawn, never what the server simulates. |
| `ZeeWorldModel` | The weapon in somebody else's hands, attached to their character's hand. |
| `ZeeWeaponPose` | The animation maths, with no nodes in it, so the test suite can check the springs settle and nothing produces `NaN`. |
| `ZeeShotFx` | What a shot looks and sounds like: a tracer, a muzzle flash with a light, a spark and a puff where it lands, and the sound. Never built on a server. |
| `ZeeWeaponSound` | A sound for each kind of weapon (light, magnum, rifle, heavy, sniper, shotgun, minigun, launcher, beam, charge, plus swings, bashes, throws, impacts and reloads), generated on first use. The pack ships no audio files; `ZeeWeaponSound.set_stream(id, stream)` replaces any of them with a real recording. |
| `ZeeWeaponNet` | Four small replicated fields on top of dot-weapon's, so other players see your gun fire and reload. |
| `ZeeWeaponRig` | The one node a game adds per player. It sets up everything above in the right order. |

## Using it
Copy `addons/zee_weapons/` and `assets/` into your project, next to `dot_core`, `dot_combat` and `dot_weapon`, and enable the plugin.

```gdscript
var rig := ZeeWeaponRig.new()
rig.role = ZeeWeaponRig.Role.LOCAL
rig.authority = true                       # false on a client that only predicts
rig.view_model_ref = DotNodeRef.of_path(view_model.get_path())
player.add_child(rig)
rig.setup()

rig.give(ZeeWeaponIds.RIFLE)
rig.give(ZeeWeaponIds.KNIFE)
```

Once per simulation tick:

```gdscript
var outcome := rig.simulate_tick(command, tick)

for shot in outcome.shots:
    combat.resolve(shot)                   # dot-combat, on the authority only
```

Once per rendered frame, for sway, bob and the camera's share of the recoil:

```gdscript
rig.drive_view(Vector2(yaw, pitch), speed, on_floor, crouched)

var punch := rig.view_punch()              # degrees: pitch up, and yaw
fps_view.external_angles = Vector3(punch.x, punch.y, 0.0)
```

Add the punch to the camera after your controller has positioned it. Don't add it to the command's angles: the shot has already gone where the command pointed.

Tracers, flashes, impacts and sounds come with the rig. Set `rig.effects = false` if your game draws its own from the `used` signal; `rig.shot_fx()` returns the node, for its audio bus and volume.

That's the whole integration. The rig finds the player through `DotWeaponPlayerBridge`, which doesn't name any player, controller or netcode class, so it works with dot-player or with your own.

### Networking

```gdscript
# On the carrier's replicated object, once:
var specs := ZeeWeaponNet.all_specs()      # dot-weapon's three fields, plus this pack's four

# On the authority, every tick after simulating:
rig.pull_net(replicated)

# On a watcher, every snapshot:
_seen = ZeeWeaponNet.apply(replicated, world_model, _seen)["seq"]
```

A watcher's world model plays the flash, a tracer and the sound each time the shot counter moves. It stays quiet if the carrier's first-person rig is on the same machine, so your own shots aren't heard twice.

Ammunition is only sent to the weapon's owner, since exact magazine counts would help an opponent. That a shot happened is sent to everybody.

### Rollback
`rig.snapshot()` and `rig.restore()` save and restore the arsenal, the bash cooldown, the charge and the previous command's buttons. Wrap a reconciliation replay in `rig.begin_replay()` / `rig.end_replay()` so the simulation runs again without drawing anything twice.

## Requirements
Godot **4.7**, plus three addons: [dot-core](https://github.com/modcommunity/dot-core), [dot-combat](https://github.com/modcommunity/dot-combat) and [dot-weapon](https://github.com/modcommunity/dot-weapon). dot-net, dot-player, dot-player-controller and dot-player-char are optional and are used if present.

It works on desktop, mobile and in the browser from one build. Nothing in it opens a socket, reads a clock, starts a thread or writes to `user://`.

## Running it
The easiest way to get the pack and its addons is [dot-bootstrap](https://github.com/modcommunity/dot-bootstrap) (`./bootstrap.sh`, then `cd projects/zee-dot-weapons`). Then:

| Command | What it does |
| --- | --- |
| `./game.sh` | A firing range you can walk around, holding any of the twenty-seven |
| `./game.sh play -- --weapon smg --fire --capture /tmp/smg` | The range firing on its own, saving six frames from the first shot |
| `./game.sh test` | Check every script and run the test suite |
| `./game.sh shot --rack` | Every weapon at once, with a marker on each muzzle |
| `./game.sh help` | All of the options |

In the range: **WASD** to move, mouse to look, **left click** to fire, **right click** to bash, **R** to reload, **1**-**5** for the slots, **Q** for the last weapon, the wheel to cycle, and **F1** to print the rig's state.

## Credits
The art is by [Kenney](https://kenney.nl) (CC0): the [Blaster Kit](https://kenney.nl/assets/blaster-kit), the Weapon Pack, the Survival Kit and the Blocky Characters. Only the files the pack uses are included (47 models and three textures, 1.7 MB), each kit's licence next to its files in `assets/`.

## License
MIT. See [LICENSE](LICENSE). The Kenney art is CC0, which is public domain.
