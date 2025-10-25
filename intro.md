## Problem Statement

Anno 1800 is a computer game where a player manages a set of islands.
Each island has an 'inventory' of items.
Some island produce items, some island consume items, and some island do both.

Sending items from one island to another happens using ships.

Classic approach is to have a 'trade route', where a set of ships have a fixed set of instructions like:
- load "50 x item A, 50 x item B" from island 1
- unload "50 x item A, 50 x item B" at island 2
- load "50 x item A, 50 x item B" from island 1
- unload "50 x item A, 50 x item B" at island 3
etc

This approach is very tedious for players, as they have to manually create and maintain these trade routes.

## Current Exploration

Apparently, Anno 1800 has certain Lua scripting capabilities.

The current goal is to explore the following:
- trade routes
  - is there access to a create/update/remove/list methods? anything resembling that?
- islands
  - is there access to their inventory?
- ships
  - is it possible to control ships from API? e.g. load/unload items, move to island, etc
