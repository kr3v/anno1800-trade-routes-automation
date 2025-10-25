## RPC server

### opt 1

```
const root = "lua/trade-automation";
const stopme = root + "/" + "stopme";
const execute = root + "/" + "execute.lua";

function executor_manager() {
    while true {
        if os.exists(stopme) {
            return
        }
        if os.exists(execute) {
            dofile(execute)
        }
        sleep(0.1) -- 100ms
    }
}
```

### opt 2

figure out a way to build an http server inside Anno's Lua

## API

1. List of islands.
2. Island:
    1. generic info
        1. "world type" - aka old/new, enbesa, arctic, etc
        2. "island name"
        3. "approximate location"?
    2. inventory
        1. item name -> quantity
3. list of ships

# Proposed TODO list

1. "good enough" API server
    1. a lua file that self-loads into a thread
2. "good enough" object deduplicated inspection
    - Object : CGameObject
    - Object.Palace.Object <- again CGameObject, no printing 
2. given an object id of a ship, figure out how to:
    1. move it to an island
    2. load items from an island
    3. unload items to an island
