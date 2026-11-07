# 08-Ethan-project-03-Steal-a-pet

A Roblox game. You sneak through five guarded stages (House, Forest, Lab, Snow, Volcano), steal eggs and pet boxes from the guards' loot heaps, and run back to your pen. In your pen the eggs hatch into pets, and the pets earn cash. You use the cash to unlock more nests and to upgrade your treadmill, which levels up your speed so you can outrun the tougher guards.

## Scripts

| File | Roblox location | Type |
|------|-----------------|------|
| `src/ServerScriptService/EggHeistServer.server.lua` | `ServerScriptService.EggHeistServer` | Script |
| `src/StarterPlayer/StarterPlayerScripts/EggHeistClient.client.lua` | `StarterPlayer.StarterPlayerScripts.EggHeistClient` | LocalScript |
| `src/ReplicatedStorage/GameConfig.lua` | `ReplicatedStorage.GameConfig` | ModuleScript |

`GameConfig` holds the tunable settings: pets, eggs, guards and stages, the day/night timing, and the Robux product and game pass IDs.

Place ID: 94068383423593
