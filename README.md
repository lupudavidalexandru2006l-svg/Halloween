# Ice Ray a Pet

A Roblox pet-catching game I'm building as a personal project.

You get an ice ray, freeze wild pets solid, and carry the ice cube home before it melts. Back at your pen the Thaw Machine wakes the pet up and it starts earning coins, which buy better rays. You train Cold Power in the Training Rink to open the next island, and every island is hotter than the last, so cubes melt faster on the trip home.

## What's in the game

- **10 islands** in one long tunnel from the hub, each with its own pets and landmarks
- **Pets in 7 rarities** (Common to Secret), made as 3D models, split into parts and rigged with their own idle animations
- **The carry loop:** freeze, carry, bank, thaw, earn
- **Guns and upgrades**, Cold Power training, rebirths
- **Social bits:** a hub with six pens, booths and leaderboards, a one-time free gift for joining the group
- Chunky, colourful UI built from Roblox UI parts (no emoji icons)

## Repo layout

| Folder | What's there |
| --- | --- |
| `roblox/` | The game itself: Luau code synced into Roblox Studio with [Rojo](https://rojo.space) (`default.project.json`) |
| `roblox/src/server` | Server services (saving, freezing, thawing, rebirths, shops) |
| `roblox/src/client` | Controllers, HUD and UI |
| `roblox/src/shared` | Config, pet definitions, world and theme data |
| `roblox/tools` | Scripts for Studio sync, pet splitting/rigging and art prep |
| `prototype/ice-ray-for-pets/` | The browser prototype the game started as (plain JavaScript), plus its art and playtest tools |

## Running it

1. Install [Rojo](https://rojo.space) and the Rojo plugin for Roblox Studio.
2. From `roblox/`, run `rojo serve` and connect from the plugin in Studio.
3. Press Play.

Some map pieces and pet models live only in the Studio place file, so a fresh place from this repo has the code but not every model.

The prototype runs in a browser: serve `prototype/ice-ray-for-pets/` with any static file server and open `index.html`.

## Status

Work in progress. Ten islands are built; pets for the later islands are still being finished in 3D.
