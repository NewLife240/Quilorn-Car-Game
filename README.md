# Rusty Roads

A single-player first-person car-building, hauling and business sim set in the Ukrainian countryside
of the 90s. Built with **Godot 4.7** (GDScript, Jolt physics, Forward+) and **Blender 4.5** (procedural
buildings, trees, car parts and vehicle processing via Python).

Inspired by the mechanics of the car-assembly, off-road and logistics/industry genres, with original content.

## What's in the game

- **Car assembly (Jalopy-style + My Summer Car bolts).** Open the hood, carry parts in your hands and fit
  them into highlighted slots: engine block, gearbox, radiator, battery, ignition coil, carburettor,
  air filter, spark plugs, alternator, starter, fuel tank, exhaust, wheels. Every part has condition and
  bolts (R tighten / T loosen). Loose parts work worse and wear faster.
- **Fluids & electrics.** Fuel, oil and coolant levels, engine temperature, battery charge, alternator charging,
  starter cranking, misfires from worn plugs, overheating and seizing engines.
- **Vehicle physics.** Raycast suspension with anti-roll bars, Pacejka tyre model, simulated engine,
  clutch, gearbox (auto / manual), open or locked differentials, 2WD/AWD/low range, tyre types,
  mud that sinks the wheels and leaves persistent ruts, water fording. First- and third-person cameras,
  working gauges and steering wheel.
- **12 vehicles**: Kombi wagon (starter), Klasyka sedan, Hatch GT, Nordic sedan, Cruiser, Bobyk 4x4,
  Bukhanka 4x4 van, Astra van, step van, Ranger pickup, Trekker SUV, 6x6 timber truck.
- **Jobs (MotorTown-style).** Parcel, crate, bulk and log deliveries between 12 sites; pay depends on distance
  and cargo condition. Load/unload in marked zones with **J**.
- **Industry (Rise of Industry-style).** 9 production sites in chains (logs → planks → furniture,
  wheat → flour → bread, sunflower → oil, gravel). Buy and upgrade them, haul your own goods, hire drivers,
  and watch prices react to supply.
- **Flipping.** Buy worn cars at the car market, buy cheap used parts at the junkyard, fix them and sell for profit.
- **World.** 2 × 2 km map: village with khatas, church and shop, a Soviet panel-block town, collective farm with
  wheat and sunflower fields, a muddy logging forest, river, gas stations, AI traffic, day/night cycle and rain.

## Controls

| On foot | |
|---|---|
| WASD / Shift / Space / C | move / sprint / jump / crouch |
| LMB | grab, drop, install part on the highlighted slot |
| RMB | throw |
| E | interact (doors, hood, trunk, shops, pumps, bed); hold to pour fluids / use repair kit |
| R / T | tighten / loosen bolts |
| Tab / M / Esc | tablet / map / pause |

| Driving | |
|---|---|
| W / S / A / D | throttle / brake (auto reverses) / steer |
| Space | handbrake |
| F | tap: ignition, hold: crank the starter |
| V / B | first-third person / look back |
| G | automatic / manual gearbox; Shift / Ctrl shift up / down |
| Z / X | 2WD-AWD-LOW / differential lock |
| L / H | lights / horn |
| J | load / unload cargo in a marker |
| E | get out |
| Backspace | put the car back on its wheels (slow speed only) |

## Performance

Settings → quality presets (Low / Medium / High / Ultra), render scale with FSR 2, shadow quality, SSAO, glow,
volumetric fog, view distance, grass density, FPS limit. Built-in optimisations: GPU-displaced LOD terrain chunks,
MultiMesh trees in 256 m chunks with server-side collision, GPU-particle grass/crops around the camera,
per-size visibility ranges, sleeping idle vehicles, 60 Hz physics with sub-stepped drivetrain.

## Project layout

- `scripts/` - game code (`vehicle/`, `player/`, `world/`, `gameplay/`, `ui/`, `autoload/`)
- `shaders/` - terrain, water, grass, vegetation particles
- `assets/` - generated models (`vehicles/`, `parts/`, `buildings/`, `nature/`), textures, sounds, world data
- `tools/` - Blender and Python generators (`bl_vehicles.py`, `bl_parts.py`, `bl_buildings.py`, `world_gen.py`)
- `tests/` - headless test scenes (driving, assembly + save/load, interaction, economy rules, screenshots)
- `tools/economy_sim.py` - economy balance simulator: replays the first game days with sensible / careless /
  bad-investor / min-maxer strategies on the real road network (`python3 tools/economy_sim.py --days 16`)

## Tests

`tests/run_tests.sh` runs every headless test (about 2 minutes on 4 cores) and exits non-zero if one fails.
Set `GODOT=/path/to/godot` if Godot 4.7 is not on your `PATH`; pass a name part to run a subset,
e.g. `tests/run_tests.sh hill`. The driving tests check that the automatic gearbox upshifts and that
the car keeps its speed on the steepest hill, on worn (48% and 70%) and new parts. GitHub Actions runs
the same script on every pull request.

Regenerate content: `python3 tools/world_gen.py`, `blender -b --python tools/bl_buildings.py`, etc.

## Credits (all free licenses)

- Car models: *PSX Style Cars* by GGBot (CC0), *Free Low Poly Vehicles Pack* by rgsdev (CC0),
  *Extremely low poly Soviet vehicles* pack (CC0) - via OpenGameArt.org
- Car sound effects: GGBot PSX Style Cars pack (CC0)
- Footsteps, impacts, river, thunder: *100 CC0 SFX #2* (OpenGameArt, CC0)
- Rain: *Rain loopable* (OpenGameArt, CC0); birds & wind: *Park ambiences* (CC0); crickets: *Crickets ambient noise* (CC0)
- UI clicks: *51 UI sound effects* (CC0)
- PBR textures: ambientCG.com (CC0)
- Font: DejaVu Sans (Bitstream Vera license)
- Everything else (buildings, trees, parts, interiors, world, code) generated for this project.
