# Anno 1800 mod that automates goods management between islands

The script ([sample1.lua](sample1.lua):

1. Finds available ships
2. Finds islands that have a single good in surplus (>= 400 units)
3. Finds islands that have a single good in deficit (<= 150 units)
4. Builds a list of available 'trades' (from surplus islands to deficit islands).
5. Picks a random ship and assigns it to the most optimal trade (shortest distance).

So it is not a full automation, but a proof of concept that can be extended further.

Some details regarding the script:

1. It automatically finds all the islands in the region, as well as their piers' locations.
   Note: the process is quite slow and stupid (it moves camera around to find islands). It took me 7 minutes for the Old
   World region where I had 9 islands (incl. big ones).
   Note: the computation is cached, kept on disk, but not associated with a specific game or save.
2. Ship management is also automated - ships are found, moved from/to piers, loaded/unloaded fully automatically.

## TODO list

- Cross-region management (manage ships in OW while game is active in NW region).
- Code cleanup, it is a big mess right now.
- Further automate - atm it is just "execute first trade for one resource", should be extended to:
    - multiple trades for single resource,
    - multiple resources for multiple resources,
    - continuously generate trades to be executed.
- Maintain the state between game saves (save/load). Atm all is in memory.
- Maintain the state per game save (atm the island discovery is global, not per save).
- Cross-region trades - I did not see any good functions to move ships between regions yet;
  I read somewhere that ships are 'deleted' and 'recreated' when moving between regions,
  so I wonder if it that would be possible to do from Lua/XML.
- Figure out reasonable user interface to control the automation (start/stop, configure,
  view current trades/ship assignments, etc).
