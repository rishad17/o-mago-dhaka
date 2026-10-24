# ও মাগো! ঢাকা! (O Mago! Dhaka!)

*একটা রিকশা, হাজারটা বিপদ।* (One rickshaw, a thousand disasters.)

A small, colourful, Flash-game-style 3D open-world game: pedal a decorated
Bangladeshi cycle rickshaw through chaotic Dhaka streets.

Godot 4.4 · GDScript · Compatibility (OpenGL 3.3) renderer · Windows PC.

## Running the game

1. Install **Godot 4.4.x (standard, not .NET)** from https://godotengine.org/download
   (tested with 4.4.1-stable; any later 4.x should work).
2. Open Godot → **Import** → choose this folder's `project.godot`.
3. Press **F5** (Run Project). The game opens on the main menu
   (`scenes/main_menu.tscn`); press **খেলা শুরু করুন** to ride.

## Menus and settings

* **Main menu:** start, how to play (কীভাবে খেলবেন), settings, exit, and your
  records (best earnings, most trips, total trips). The backdrop is the real city
  with a rickshaw pedalling at Farmgate.
* **Pause (Esc):** this ride's stats, continue, settings, restart, main menu, exit.
* **Settings (সেটিংস)** are saved in `user://settings.cfg`:
  volume for everything / rickshaw & crashes / traffic / street ambience / menus;
  graphics quality; amount of traffic and people (applies to the next ride);
  fullscreen; mini-map; pause automatically when you switch to another window.

| Graphics (Ryzen 5 + Radeon Vega iGPU, plugged in, uncapped, busiest streets) | 1280×720 | 1920×1080 |
|---|---|---|
| **নিম্ন** (low): no shadows, no anti-aliasing | faster than medium (not re-measured) | |
| **মাঝারি** (medium, default): shadows (1024 map), no anti-aliasing | ~90–117 | ~72–88 |
| **উচ্চ** (high): shadows (4096 map) + 2× MSAA | — | ~45 |

With VSync (the normal way to play) medium holds 60 FPS at 720p on the
charger. **On battery** Windows and the Radeon driver slow the laptop down a
lot (about 35–45 FPS at 720p): plug in, or use **নিম্ন** on battery.

The game's simulation was made much cheaper so that frames are even: a
physics tick with full traffic and crowds went from ~24 ms to ~5.5 ms of CPU
time (no more stutter when lots of people are around). Far-away people and
rickshaws drop their jointed bodies from the scene, people 14–45 m away walk
as a one-mesh flip-book, distant vehicles update every third tick, and
pedestrians share one per-tick list of vehicles. `tests/perf_probe.tscn`
measures it. RAM use is about 380–400 MB. (Lowering the 3D resolution was
measured to be *slower* in the Compatibility renderer, so it is not offered.)

## Play in a browser or on a phone

**Play online: https://o-mago-dhaka.vercel.app** (free Vercel hosting; works on
phones and PCs, nothing to install). To publish a new version after changing the
game: export the **Web** preset to `build/web/`, then in that folder run
`npx vercel deploy --prod --yes` (the folder is already linked to the
`o-mago-dhaka` project on the rishad17 Vercel account).

The game runs in a web browser (Chrome, Edge, Firefox, Safari), on a PC or a
phone. The web build is in `build/web/` (export the **Web** preset in Godot to
rebuild it; it is the single-threaded build, so it needs no special server
headers).

* **On this PC or a phone on the same Wi-Fi:** double-click `tools/play_web.bat`
  (or run `python tools/play_web.py`). It prints two links: open
  `http://localhost:8060` on the PC, or the `http://192.168…:8060` link on the
  phone. If Windows asks, allow Python through the firewall on private networks.
* **For everyone, anywhere:** upload `build/o-mago-dhaka-web.zip` to a free host
  such as **itch.io** (new project → *Kind: HTML* → upload the zip → tick *This
  file will be played in the browser*). GitHub Pages or Netlify also work: put the
  files from `build/web/` online as they are.

**On a phone** the game notices it is a phone and shows round touch buttons:
◀ ▶ steering under your left thumb; **প্যাডেল**, **ব্রেক / পেছনে** and **জোরে
ব্রেক** under your right; **যাত্রী (E)**, **ঘণ্টি**, **রিসেট**, **ম্যাপ**,
**বিরতি** and **পূর্ণ পর্দা** (full screen). Drag a finger anywhere else to turn
the camera. Play with the phone **sideways or upright**: the screen, buttons
and camera adapt (upright gets a wider view so you still see the road).

Phones are made lighter so the game runs smoothly: low graphics and light
traffic to start with (change it in **সেটিংস**), the 3D world drawn at about
0.9 megapixels and scaled up (phone screens are very sharp; text stays sharp),
the city simulated 30 times a second instead of 60 (less than half the work;
the picture stays smooth), lighting worked out per vertex instead of per pixel
(much cheaper for phone GPUs such as the Helio G99's Mali-G57), fewer people and
vehicles kept around you and fewer detailed ones, a 160 m view distance, and
shop signs drawn only nearby. On low graphics the 3D world is drawn at about
0.5 megapixels.

**Loading:** the city is built once per visit and handed from the menu to the
ride (and back, and on restarts) instead of being rebuilt each time, and the
mesh building was made about 2.4x faster. The first load
downloads up to about 50 MB (mostly the game engine; less from hosts that compress
files), so it takes a little while on mobile data.
A touchscreen laptop gets the touch buttons as soon as you touch the screen.

## Controls

| Key | Action |
|-----|--------|
| W / ↑ | প্যাডেল — pedal forward |
| S / ↓ | ব্রেক — brake, then reverse when stopped |
| A / D (← / →) | মোড় — steer left / right |
| Space | জোরে ব্রেক — strong brake |
| H | ঘণ্টি — rickshaw bell (hold to keep ringing) |
| E | যাত্রী তোলা / নামানো — pick up / drop off a passenger; মেরামত — repair at the mechanic |
| R | রিসেট — back to a recent free spot, facing along the road |
| M | ম্যাপ — show / hide the mini-map |
| Mouse | look around the rickshaw (GTA-style; recentres while riding); wheel zooms |
| Esc / P | বিরতি — pause menu |

Keys use *physical* key positions, so they still work with Bangla keyboard
layouts (Avro, Bijoy). Remap them in **Project → Project Settings → Input Map**.

## Project layout

```
project.godot
scenes/
  main_menu.tscn         main menu (start scene)
  main_world.tscn        a ride: sky, sun, city, player, camera, managers, HUD, pause menu
  player_rickshaw.tscn   CharacterBody3D + collision box + procedural model
  ui/hud.tscn            Bangla HUD
  ui/pause_menu.tscn     pause menu
  ui/settings_menu.tscn  settings panel (used by both menus)
  vehicles/traffic_vehicle.tscn  AI vehicle (type chosen at spawn)
  pedestrians/pedestrian.tscn    pedestrian (also used for passengers)
scripts/
  game_manager.gd        autoload: earnings, trips, accidents, damage, Bangla digits, pause/restart/menu
  settings.gd            autoload: saved settings, graphics quality, records
  main_menu.gd, settings_menu.gd, minimap.gd
  player_rickshaw.gd     arcade driving, collisions, horn, safe reset
  rickshaw_model.gd      builds the rickshaw from parts; wheel/fork/pedal/driver animation
  camera_controller.gd   smooth chase camera, wall avoidance, crash shake
  city_layout.gd         map data: roads, districts, landmarks, passenger destinations
  city_builder.gd        builds the neighbourhood from city_layout (buildings, landmarks, signs, wires)
  destination_zone.gd    one drop-off zone (Area3D + hidden marker)
  destination_manager.gd creates the zones; picks destinations for passengers
  mesh_kit.gd            merges boxes/cylinders/etc. into one mesh (few draw calls)
  traffic_network.gd     lane graph (left-hand traffic) and turn paths through intersections
  traffic_controller.gd  spawns/recycles traffic, shared obstacle list, horn limiter, ambience
  traffic_vehicle.gd     one AI vehicle: path following, sensing, honking, weaving, overtaking
  vehicle_models.gd      procedural bus, CNG, car, microbus and motorcycle models
  pedestrian_network.gd  sidewalk walking lines and road crossings
  pedestrian_manager.gd  spawns/updates people, hits by player/traffic, crossing safety
  pedestrian.gd          one person: walking, crossing, waiting for a rickshaw, knocked down
  person_model.gd        low-poly people in lungi, saree, salwar kameez, panjabi, borka…
  passenger_manager.gd   the passenger job: pickup, trip, drop-off, fares (state machine)
  collision_manager.gd   crash effects, damage (রিকশার অবস্থা), stuck hint, repairs
  breakable_manager.gd   smashing stalls/tea stalls/benches on the footpath, debris, repairs
  mugging_manager.gd     knife muggers in Mohammadpur: robbing pedestrians or you, chases
  day_night.gd           game clock, sun/moon, sky colours, headlamp
default_bus_layout.tres  audio buses: SFX, Traffic, Ambience, UI
  hud.gd, pause_menu.gd, main_world.gd
assets/
  fonts/NotoSansBengali.ttf   SIL Open Font License 1.1 (see OFL.txt)
  textures/                   rickshaw art (generated by tools/generate_textures.py)
  audio/                      bell, bump, crash, freewheel (generated by tools/generate_audio.py)
tools/                   Python asset generators (standard library only)
tests/drive_test.tscn    automated driving test (Milestone 1)
tests/world_test.tscn    automated map/navigation test (Milestone 2)
tests/traffic_test.tscn  automated traffic test (Milestone 3)
tests/passenger_test.tscn  automated pedestrian & passenger test (Milestone 4)
tests/collision_test.tscn  automated collision, damage, repair & sound test (Milestone 5)
tests/ui_test.tscn       automated menus / settings / HUD test (Milestone 6)
tests/street_test.tscn   footpaths, breakable stalls, motorbike crashes
tests/mugging_test.tscn  Mohammadpur muggings
tests/kallyanpur_hatirjheel_test.tscn  Kallyanpur, Hatirjheel lake, bigger map
tests/day_night_test.tscn  day/night cycle, clock, headlamp
tests/mob_test.tscn      the angry crowd after hitting someone
tests/perf_probe.tscn    FPS, frame-time spikes and where the time goes (windowed;
                         -- --vsync, --size=1920x1080, --quality=0|1|2)
```

All art and sounds are generated for this project. The only third-party
asset is the Noto Sans Bengali font (OFL, redistribution allowed).

## The map

A fictional part of Dhaka, about 720 m × 666 m, with 124 intersections and no dead ends:

* **The city** (ফার্মগেট, নিউ মার্কেট, কারওয়ান বাজার, ধানমন্ডি, লালমাটিয়া…) in the middle.
* **কল্যাণপুর (Kallyanpur)** in the north, where মিরপুর রোড continues past
  কল্যাণপুর মেইন রোড to দারুস সালাম রোড.
* **মোহাম্মদপুর (Mohammadpur)** in the west, with its own streets (নূরজাহান রোড,
  শাহজাহান রোড, বেড়িবাঁধ সড়ক, তাজমহল রোড, সলিমুল্লাহ রোড, জাকির হোসেন রোড, হুমায়ুন রোড).
  A row of buildings separates it from the city; only রিং রোড, **আসাদ এভিনিউ** (with
  a "মোহাম্মদপুরে স্বাগতম" arch) and বছিলা রোড cross over, plus the Kallyanpur roads.
* **হাতিরঝিল (Hatirjheel)**: a long lake east of the city with a raised lakeside
  promenade you can ride on, railings, lamp posts, water taxis and a fountain.
  The ring roads and **হাতিরঝিল সেতু** (Farmgate Road's causeway) cross it.
* **গুলশান লেক পার্ক** in the north-east: a big fenced park with grass, footpaths,
  benches, many trees and a pond with boats (entrance gate on বাড্ডা লিংক রোড).
* **আড়ং (Aarong)** on ধানমন্ডি ২৭ in Dhanmondi: a three-storey showroom with
  terracotta fins, saris and kurtas in the windows, and "aarong" in red over the door and
  on the roof.
* **The south**: **শাহবাগ** (with the ফুলের বাজার flower market), **আজিমপুর** (bus stand)
  and **মগবাজার** (মোড়ের চা), along কাঁটাবন রোড and আজিমপুর রোড.
* **বাড্ডা (Badda)** east of the lake, with **ব্র্যাক বিশ্ববিদ্যালয়** on **প্রগতি সরণি**.
  The campus is a low-poly take on the real WOHA-designed Merul Badda campus: a public
  Campus Park on pilotis with a reflecting pond, nine academic floors in a dark ash
  concrete grid, garden terraces, sky-garden voids, a green wall, a curved outdoor
  staircase and a solar-panel roof "umbrella".

Passenger destinations (23): নিউ মার্কেট, ফার্মগেট, ব্র্যাক বিশ্ববিদ্যালয়, বাসস্ট্যান্ড,
কারওয়ান বাজার, চায়ের দোকান, আবাসিক এলাকা, মিরপুর রোড (by the mosque),
স্থানীয় বাজার, ধানমন্ডি কাঁচাবাজার, মামার চা, লালমাটিয়া, মোহাম্মদপুর টাউন হল, সাত গম্বুজ মসজিদ, মোহাম্মদপুর বাসস্ট্যান্ড,
কল্যাণপুর বাসস্ট্যান্ড, কল্যাণপুর বাজার, হাতিরঝিল (water taxi jetty), গুলশান লেক পার্ক, শাহবাগ, আজিমপুর, মগবাজার, আড়ং ধানমন্ডি.
About 68 vehicles and 130 pedestrians fill the streets; the game keeps about 24 vehicles
and 65 people close around you (bringing them in out of sight), so your street is always busy.
To change the layout, edit `scripts/city_layout.gd`.

## Automated tests

```
godot --path . res://tests/drive_test.tscn              # with screenshots and an FPS probe
godot --headless --path . res://tests/drive_test.tscn   # logic only
godot --path . res://tests/world_test.tscn              # map, reachability, zones, autopilot loop
godot --headless --fixed-fps 60 --path . res://tests/traffic_test.tscn   # traffic behaviour (fast)
godot --path . res://tests/traffic_test.tscn            # traffic screenshots + FPS
godot --headless --fixed-fps 60 --path . res://tests/passenger_test.tscn # full passenger loop
godot --headless --fixed-fps 60 --path . res://tests/collision_test.tscn # crashes, damage, repairs
godot --headless --fixed-fps 60 --path . res://tests/ui_test.tscn        # menus, settings, HUD
godot --path . res://tests/ui_test.tscn                 # + FPS at 1920x1080 per quality
```
Traffic and passenger tests accept `-- --seed=N` to try other random situations.
`--fixed-fps 60` makes headless runs simulate as fast as possible. In windowed
test runs, don't click away from or type into the game window: Godot releases held
keys when the window loses focus.

It loads the real world, presses the real input actions, and checks driving,
steering, braking, reversing, the bell, collisions, the accident counter,
reset, pause and Bangla number formatting. The exit code is 0 when every check passes.
Screenshots are saved to `user://test_shots` (or `-- --shots=<folder>`).

## Traffic

About 30 vehicles: local buses, green CNGs, cars, microbuses, motorcycles and other
pedal rickshaws. They keep left, follow lanes and curved turn paths (so they never
drive into buildings), and look ahead along their own route for other vehicles and
for you. They slow down, stop at junctions, pull over, wait at the bus stand, weave,
cut in front of slow rickshaws, brake for no reason, overtake through the other lane
and honk a lot (with a limit, so it stays bearable). Deadlocks are broken by letting
one vehicle push through, and vehicles stuck out of sight are recycled. Hitting a
bus hurts more than hitting a rickshaw. Tune the numbers in `TrafficController.counts`
and `traffic_vehicle.gd` (`TYPES`).

## Passengers (যাত্রী)

Some pedestrians decide to take a rickshaw: they step to the kerb near a
landmark or corner and wave (green **▼ যাত্রী ▼** badge, "রিকশা! রিকশা!").
1. Stop next to them (under ~5 km/h): **যাত্রী নিতে E চাপুন** → press **E**.
2. They climb on and ask "… যাবেন?". The HUD shows **গন্তব্য**, the estimated
   **ভাড়া** and **দূরত্ব**; a yellow arrow at the top points the way and a light
   beam marks the drop-off spot. Choose your own route.
3. Stop inside the ring: **যাত্রী নামাতে E চাপুন** → press **E** → **যাত্রা সম্পন্ন!**

Fare (illustrative game values): ৳২০ + ৳০.১ per metre of street distance,
+৳১০ tip for a quick trip without accidents, −৳৫ per medium crash on the way.
A heavy crash ends the trip with no fare. Jobs are optional: ignore passengers
and just ride around if you like. Up to 4 people wait at a time; nobody waits forever.

## Pedestrians

About 40 people in lungi, panjabi and tupi, saree, salwar kameez with orna, borka,
or school clothes walk the sidewalks, wait at kerbs, look before crossing (or
don't), cross mid-block, hurry when something comes, and stop rather than walk
into a passing vehicle. Traffic stops for them. Hitting someone is cartoonish:
they fly back, lie dazed with stars, complain in Bangla and walk off.

## Day and night

A ride starts at **সকাল ৮:০০**. Time passes while you play (one game hour = 40
seconds, a full day ≈ 16 minutes): the sun crosses the sky, the light turns golden
in the afternoon, the sky glows orange at sunset (সন্ধ্যা), and at night (রাত) the
city is lit by dim blue moonlight while your rickshaw's headlamp lights the road.
The clock (e.g. "রাত ৯:৩০") is shown under the area name. Tune it in
`scripts/day_night.gd` (`SECONDS_PER_HOUR`, `START_HOUR`, the colour `KEYS`).

## Mohammadpur and its muggers (ছিনতাইকারী)

**মোহাম্মদপুর** is a separate area west of the city, with **টাউন হল বাজার**,
**সাত গম্বুজ মসজিদ** and **মোহাম্মদপুর বাসস্ট্যান্ড** as destinations, and a "ছিনতাই থেকে সাবধান!" sign; you're warned once when you ride in.
Muggings are a common sight there: while you're around Mohammadpur a new mugger in
dark clothes and a cap, holding a knife, turns up every 6–14 seconds (red dot on
the mini-map), and up to three muggings can be going on around you at once (about
five a minute). Only one at a time comes for your own money:

* **He mugs a pedestrian:** sneaks up, the victim freezes with hands up ("বাঁচাও!
  ছিনতাই!"), he grabs the bag and runs. Ride into him to catch him: the victim
  gives you **৳৫০**.
* **He comes for you** when you're stopped: "টাকা দে!". Pedal away fast and you
  escape; if he reaches you he takes 40% of today's earnings (at most ৳২০০) and runs.
  Catch him to get it back plus **৳২০**.

Catching a mugger is not counted as an accident. Cartoon style: he only threatens
with the knife; nobody gets hurt.

## Footpaths, stalls and motorbikes

The rickshaw can ride up onto the footpath (it rises over the kerb with a bump
and a tilt). Buildings, electric poles, tree trunks, the bus shelter, the
footbridge stairs and New Market's columns are solid. Vegetable stalls, tea
stalls, benches (also the ones in the park) and bins are not: ride into one and it smashes (**চুরমার!**),
vegetables and planks fly, the shopkeeper shouts ("হায় হায়! আমার দোকান!"),
the rickshaw slows down and gets a little damage. Smashing a shop at speed
counts as an accident. Broken shops are rebuilt after a while, out of sight.
Hit a motorbike and it falls over: the rider and passenger fly off, lie dazed,
shout ("ও মাগো!", "আমার বাইক!"), then pick the bike up and ride on.
Pedestrians you hit often cry **"ও মাগো!"** besides their usual complaints.

**Hit someone, or knock a motorbike over, and the street turns on you.** Up to three bystanders nearby
(five if you keep hitting people) come running for the rickshaw-wala shouting
**"ধর শালারে!"** and **"তুই আজকে শেষ!"** ("লোকজন খেপে গেছে! পালান!"). Stand
still and they surround you and thump the rickshaw (**ধুম! ঠাস!**, 1.5% damage
each, "মাইর খাচ্ছেন! পালান!") until they've made their point after eight
thumps. They run at about 16 km/h, so pedal away quickly and they give up
("পালাইলি কই!"). Either way they then walk back to the footpath.

## Crashes, damage and repairs

How hard a crash is depends on the speed going *into* the obstacle (a fast
glancing scrape stays light) and on what you hit (a bus hurts most):

| | Feel | Sound | Effects |
|---|---|---|---|
| light | small jolt, **ঠক!** | thud / metal knock | dust |
| medium | wobble, **ধাম!**, "সাবধানে চালান!", accident +1 | thud / clang | dust, sparks on vehicles |
| heavy | hop, white flash, **ধড়াম!**, dizzy stars, "দুর্ঘটনা!" | crash | dust, sparks, big shake |

Drivers you hit shout at you in Bangla and honk. Each crash wears the rickshaw
down (**রিকশার অবস্থা**). A battered rickshaw is up to 25% slower and its front
wheel wobbles, but it always keeps going. Repair it at **রিকশা মেরামত** on Mirpur
Road (east side, just south of Rajabazar Lane): stop in the yellow bay and press E.
It costs ৳১ per 2% damage; with too little money you get what you can pay for,
and a broke puller gets some help for free.
At **0% condition the rickshaw is wrecked**: it stops dead, slumps on a broken
wheel and smokes, any passenger gets off without paying, and a breakdown screen
(**রিকশা নষ্ট হয়ে গেছে!**) offers a tow to the mechanic (৳৫০, or whatever you
have; free if you're broke), a new ride, or the main menu. Pushing against a wall for a few
seconds suggests **R**, which puts you back on the road facing the right way.

## Sound

All sounds are generated by `tools/generate_audio.py` (short 22 kHz WAVs,
about 0.6 MB in total) and play on four buses for balancing: **SFX** (bell,
pedalling and chain, freewheel, brake squeal, scraping, crashes), **Traffic**
(bus, CNG, car and motorbike horns, engines, bumps), **Ambience** (street noise)
and **UI** (chime, coins, menu clicks). Missing sound files are skipped silently.

Tests always use default settings and never overwrite your saved settings or records.

## Exporting the Windows .exe (when you are ready)

1. In Godot: **Editor → Manage Export Templates → Download and Install** (4.4).
2. **Project → Export → Add… → Windows Desktop**. Tick **Embed PCK** for a single .exe.
3. **Export Project** (Release) → e.g. `build/DhakarRickshaw.exe`.

Notes:
* Bangla shaping needs Godot's text server data; `internationalization/locale/include_text_server_data`
  is already enabled in `project.godot`, so it is bundled with the export.
* Size: the game data is about 2 MB (the sounds are under 1 MB); the Godot 4.4
  Windows release runtime adds roughly 70–90 MB, so the download should stay
  under the 100 MB target. Zipping it shrinks it further.
* Keep the Compatibility renderer for integrated GPUs.

## Milestones

1. **Playable driving prototype**: done
2. **Dhaka environment**: done
3. **Traffic**: done
4. **Pedestrians and passengers**: done
5. **Collisions and sound**: done
6. **Main menu, UI polish, optimisation**: done
