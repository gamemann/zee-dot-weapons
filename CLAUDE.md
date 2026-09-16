# zee-dot-weapons

A weapons pack for the Dot family. Read `../../CLAUDE.md` first for the family-wide rules — no autoloads, `DotResult` for anything fallible, ticks rather than seconds, `DotNodeRef` rather than a scene path, everything logged through `DotLog`. This file is only what is specific to this repository.

**This one is not in the `modcommunity` organisation.** Its `origin` is `git@github.com:gamemann/zee-dot-weapons.git`. Everything else about it — the layout, the conventions, the two-step check, `push-github.sh` — is the same as the rest of the tree.

## The one idea

**dot-weapon decides that a use happened and refuses to draw anything. This is the half that draws.**

That refusal is dot-weapon being right: a dedicated server resolving thirty carriers must never need a mesh, and a `DotWeaponDef` that carried one could not be validated at boot by a server with no content installed. But it leaves a real gap — a weapon nobody can see — and every game that adopted dot-weapon has been filling that gap privately and differently.

So the split here is the same split, one level out. `ZeeWeaponPack` is documents a server validates; `ZeeWeaponArtTable` is filenames a client loads; and **a headless build never touches the second one**. If `ZeeModelCache` is ever reached in a headless run, something has asked a simulation question of the art layer.

## The prefix is `Zee`, not `Dot`

`class_name` is global in Godot and these addons install side by side. `Dot` is the family's namespace and this is a third-party pack that sits on top of it, so it takes its own. A pack that squatted on `DotWeaponArt` would collide the first time dot-weapon grew one.

## Weapons are named by role, never by model

`blaster-a` through `blaster-r` is the order Kenney exported them in. It is not a name, it means nothing to a player, a server console or a loadout document, and a game that swapped the art would find every rule in it pointing at the wrong file.

So `ZeeWeaponIds` names roles — `SNIPER`, `DRUM_SHOTGUN`, `BEAMER` — and `ZeeWeaponArtTable` is the **only** file in the repository that contains a filename. Replacing the art is replacing one table.

**The roles were assigned from measurements, not from filenames.** Every model was measured — length, width, height — and given the role its silhouette can carry: the two widest short models became the revolver and the drum shotgun because width reads as a cylinder, the slimmest became the beam weapon, the 1.39 m one became the sniper, the 0.42 m one became the derringer. Assigning eighteen roles from `-a` to `-r` would have been a coin flip eighteen times.

## The muzzle is measured, never written down

`ZeeModelCache.muzzle_distance()` takes the far end of the mesh's own bounding box along its forward axis. The alternative is eighteen hand-authored offsets, which is eighteen chances to be quietly wrong — and one of them *would* have been: `blaster-e` is the only model in the kit whose origin sits at the stock rather than at its centre, so the offset correct for the other seventeen puts its muzzle somewhere behind the player's ear.

**The muzzle is for effects only.** A shot's real origin is the player's eye, decided by the server. Using the muzzle transform as a shot origin would make a weapon's reach depend on its model, and would make a player with the view model turned off shoot from somewhere else.

## Orientation, and the three ways it goes wrong

`ZeeWeaponArt.model_forward` states which way a mesh points and `orientation()` derives the rotation that fixes it. Stating both would let them drift, which is how a weapon ends up pointing backwards in the world and forwards on the screen.

The blasters point along **+Z** and Godot's forward is **-Z**. The melee models and the grenades point along **+Y**, standing on their handle with the origin exactly where a hand grips them.

Three traps, all of which were hit here:

1. **The reversed case must be handled before the general one.** Two opposite vectors have a zero cross product, so the general axis-angle formula produces a basis full of `NaN` — and a `NaN` transform draws nothing at all, with no error anywhere.
2. **A melee weapon must not also carry a `world_rotation` of -90.** `model_forward` has already turned +Y onto -Z by then, so the second rotation puts the blade through the floor. The rack render caught it: six melee weapons drawn end-on as specks.
3. **A per-model offset correction has to be scaled with the model.** The sniper's pull-back is a distance along a mesh drawn at 40% in first person; applied flat it pulled four times too far and put the stock 16 cm from the eye.

## The alt-fire is not a fork

dot-weapon's arsenal routes exactly one button into a behaviour, and that is the arsenal being right rather than incomplete — an alt-fire is a second state machine with its own cadence and its own refusals, and folding it in would make every game built on dot-weapon pay for a feature most of them do not have.

So the bash lives in `ZeeWeaponBash` and its state machine lives in `ZeeWeaponRig`, which owns the cooldown, puts it in the snapshot and rolls it back with everything else. **The addon is not forked.** That is the extension point working.

## What the rig counts, and why it counts it

The arsenal knows exactly how far through a reload it is and keeps it private. That is correct: exposing a fraction would make an animation's needs part of a simulation's public interface, and the next game to want a different animation would want a different fraction.

So the rig listens to the signals the arsenal *does* emit and counts the ticks itself. Two things about that are not obvious:

- **`switched` fires between the holster and the deploy, not at the start of the holster.** A rig that waited for it draws the weapon at rest for the whole way down. The holster half is noticed by watching `is_switching()` go true, before the arsenal runs.
- **The previous command's buttons are simulation state and belong in the snapshot.** The bash, the reload and every semi-automatic weapon are edge-triggered against it. The arsenal does not have this problem because it is *handed* the previous command; the rig keeps one, so the rig has to save it. Left out, a restored rig thinks the alt-fire button was already down and silently refuses the next press, exactly once. The suite's rollback section is what found it.

## Presentation is never part of the netcode contract

`ZeeWeaponPose` runs on render frames, reads a delta in seconds, and never writes to anything the simulation reads. A player with the view model switched off simulates identically to one who has not. That is the line dot-player-controller draws between its motor and its view, drawn again in the same place.

Two consequences worth keeping:

- **Everything the pose is handed is clamped and checked for finiteness.** One `NaN` reaching a `Transform3D` makes the weapon vanish with no error anywhere, and it presents as "the view model broke".
- **The recoil spring is integrated semi-implicitly.** Explicit Euler adds energy at every step, so a spring that should settle grows instead; it takes a few seconds of held automatic fire to become obvious and reads as a tuning problem rather than an integration one. There is a section in the suite that holds the trigger for thirty seconds.

## Replication is a counter, not an event

The obvious design is an RPC per shot, and it is wrong three ways at once: it needs a reliable channel for something worthless if it arrives late, it costs a packet per shot per watcher, and it desynchronises from the state snapshot it belongs with — so a watcher can see the muzzle flash of a weapon the same snapshot says has been holstered.

A four-bit counter *inside* the snapshot cannot do any of those. A watcher who missed a snapshot sees it jump by two and plays one flash instead of two, which is the correct amount of wrong.

`uses_between()` is wrap-aware, and that is the whole reason it is a function: a plain subtraction goes negative every sixteen shots, and code that reads a negative as "nothing happened" makes a weapon go silent for one snapshot in sixteen.

## What running it in a game found

- **Every shot on every dedicated server came out of the world origin, pointing north.** `player_ref` was resolved inside `_resolve_presentation()`, behind that function's `role == SERVER` early return. The view model and the world model belong there — they are drawing, and a server draws nothing. The player does not: it is where `DotWeaponPlayerBridge.context_for` takes the muzzle position and the aim direction from, so a server rig built every `DotWeaponContext` with the defaults, `(0, 0, 0)` and `(0, 0, -1)`.

  **Nothing reported it and 133 checks could not.** The weapon fires, the ammunition goes down, the use counter increments and replicates, and the hit registration runs and finds nothing, because there is nothing where it looked. A game built on this has a fight in which nobody can be shot and every number about it is correct. It was found in mg-smash-copter by running bots against each other for twenty rounds: every single round ended with exactly two players alive, one per side, a draw. A number that is identical every round is a number nothing is deciding.

  The suite could not see it because `_make_rig()` never set a carrier — which is the shape of the gap rather than an oversight, since a test rig with no player is the easiest one to write. `_rig_carrier()` builds a SERVER rig under a positioned, rotated `Node3D` and asserts the shot leaves the carrier and goes where it faces. Both checks armed, both fire, with the original symptom verbatim.

## Validating

```bash
cd godot/zee-dot-weapons

godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done

timeout 300 godot --headless --path . res://examples/zee_selftest.tscn
```

**15 sections, 137 checks.** The suite counts both, and the second is the one that catches what the first cannot: a script error aborts the section it is in, and the section counter is already satisfied because the section announced itself on the way in.

### And then look at it, because the suite cannot

**Everything about this pack that can be wrong is invisible to every assertion in it.** The suite proves all twenty-seven weapons load, measure, simulate, replicate and roll back. Not one of its checks can tell you that a weapon is held at the wrong angle, that an arm is drawn over the gun it is holding, that a knife is pointing directly away from the eye, or that the view model is casting a shadow on the ground.

Every one of those was a real bug here, and every one was found by rendering a frame and looking at it.

```bash
tools/screenshot.sh --rack          # all twenty-seven, with a pip on each muzzle
tools/screenshot.sh sniper          # one weapon, first person
tools/screenshot.sh --all           # one frame per weapon
```

The rack render is the sharpest of the three: each weapon gets a red pip at its measured muzzle and there are three green pips laid along Godot's forward as a reference. Every red pip must sit on the same side of its weapon as the green ones sit of the rack. That single comparison is what proved the orientation correct, and it is what would catch it breaking.

`tools/screenshot.sh` is **not** `--headless`. Godot's headless display driver does no rendering at all, so a capture under it is a black PNG — which is worse than no screenshot, because it looks like one.

## Numbers that were measured, so nobody has to measure them again

| | |
| --- | --- |
| Blasters | 18, from 0.42 m (`blaster-b`) to 1.39 m (`blaster-e`) |
| `blaster-e` | the only one whose mesh origin is at the stock rather than the centre |
| Blocky character | **2.7 m tall, 1.6 m wide** — a stylised giant, not a person |
| One arm | a 0.4 × 1.1 × 0.4 box, pivot at the shoulder, mesh hanging to `y = -1` |
| Melee tools | 0.15 m to 0.35 m tall, origin at the butt of the handle, pointing +Y |
| Target discs | modelled in the YZ plane, 0.34 m across — they need turning and scaling |
| Vendored art | 47 models, 3 textures, 1.7 MB |

The arm measurements are why `arm_scale` is 0.20 rather than 1.0: the shoulders sit about 0.35 m out and the grip about 0.45 m out, so a fifth of a metre is the distance between them. The box is 0.4 wide in its own units, so that scale sets the forearm's thickness as well as its length — 8 cm, which at a third of a metre from a 90-degree camera is about a seventh of the screen.

## Two hazards this repository walked into

Both are in `../../docs/gdscript-hazards.md` and both were hit anyway.

**A GDScript lambda captures locals by value.** A counter incremented inside a signal handler stays zero outside it. The suite's bash section did exactly this and reported a failure for a signal that had fired perfectly; worse, the rollback section beside it *passed*, because the value it was initialised with happened to be the answer it asserted. Accumulate into an `Array`, never into a captured scalar.

**A clipping plane does not hide an object, it slices it.** The first arm placement used anatomically sensible shoulders, which are behind the eye — so the shoulders sat behind the near plane and what drew was the cut face: a pale slab across the lower half of the screen that reads as a broken model. Every shoulder in `ZeeViewArms` is in front of the camera.
