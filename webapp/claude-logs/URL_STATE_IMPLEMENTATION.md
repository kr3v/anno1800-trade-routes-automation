# URL State Management Implementation

## Overview

The webapp now persists application state in the URL query parameters, allowing:
- **Page refresh** maintains current tab, filters, and selections
- **Bookmarking** saves specific views for later
- **Sharing** links to specific states
- **Browser back/forward** navigation works correctly

## What's Persisted in URL

### Query Parameters

| Parameter | Description | Example Values |
|-----------|-------------|----------------|
| `tab` | Active tab | `trades`, `ship-usage`, `area` |
| `duration` | Trades time filter | `15m`, `1h`, `2h`, `6h`, `1d` |
| `region` | Trades region filter | `OW`, `NW` |
| `game` | Area visualizer game | `SaveGame_1` |
| `areaRegion` | Area visualizer region | `OW`, `NW`, `` (empty = all) |
| `city` | Area visualizer city | `TrRAt_SaveGame_1_area_scan_OW_City1.tsv`, `` (empty = all) |

### Example URLs

```
# Default state (trades tab, OW region)
http://localhost:5173/

# Ship usage tab
http://localhost:5173/?tab=ship-usage

# Trades tab with filters
http://localhost:5173/?tab=trades&duration=1h&region=NW

# Area visualizer with specific game/city
http://localhost:5173/?tab=area&game=SaveGame_1&areaRegion=OW&city=TrRAt_SaveGame_1_area_scan_OW_City1.tsv
```

## Implementation Details

### Files Changed

1. **`src/url-state.ts`** (NEW)
   - `readStateFromURL()` - Parse state from URL params
   - `writeStateToURL()` - Update URL params without page reload
   - `onURLStateChange()` - Listen for browser back/forward
   - `AppState` interface defining all URL state

2. **`src/main.ts`**
   - Import URL state utilities
   - Read initial state from URL on page load
   - Update URL when filters change
   - Handle browser back/forward navigation
   - Pass state to widgets for restoration

3. **`src/widgets/area-visualizer.ts`**
   - Add `restoreState()` method for browser navigation
   - Save URL state if received before directory loaded
   - Update URL when game/region/city selections change
   - Skip URL writes during restoration to avoid loops

### How It Works

#### Page Load
1. `main.ts` reads URL params via `readStateFromURL()`
2. Applies state to UI controls (dropdowns, tabs)
3. Widgets load with saved state when directory is selected

#### User Interaction
1. User changes tab/filter/selection
2. Event handler calls `writeStateToURL({ param: value })`
3. URL updates via `history.replaceState()` (no page reload)

#### Browser Back/Forward
1. Browser fires `popstate` event
2. `onURLStateChange()` callback receives new state
3. `handleURLStateChange()` updates UI and widgets
4. Widgets restore state via `restoreState()` method

#### State Restoration Flow (Area Visualizer)
```
URL has ?game=SaveGame_1&city=...
  ↓
Directory not loaded yet → save to `savedState`
  ↓
User picks folder → `loadFromDirectory()` called
  ↓
Check if `savedState` exists and game is valid
  ↓
Apply saved state to dropdowns and load visualization
  ↓
Clear `savedState` after restoration
```

## Limitations

### Directory Handle Persistence (IMPLEMENTED ✓)

**The directory handle IS now persisted using IndexedDB!**

When you select a folder:
1. The `FileSystemDirectoryHandle` is saved to IndexedDB
2. On page reload, the app automatically retrieves the handle
3. Browser may prompt for permission verification (security requirement)
4. If permission is granted, data loads automatically without re-selecting

### How It Works

- **IndexedDB Storage**: Directory handles are stored in browser's IndexedDB
- **Permission Check**: On reload, app checks if permission is still granted
- **Auto-Request**: If permission was revoked, app requests it again
- **Graceful Fallback**: If permission denied, user can manually select folder

### Browser Behavior

- **Modern browsers** (Chrome/Edge) often remember permissions between sessions
- **First time**: User must grant permission
- **Subsequent loads**: May auto-restore without prompts (browser-dependent)
- **After permission revocation**: User sees permission prompt again

This significantly improves UX - in most cases, users only select the folder once!

## Testing

### Test Scenarios

1. **Tab Persistence**
   - Switch to Ship Usage tab
   - Refresh page → Should reload on Ship Usage tab

2. **Filter Persistence**
   - Set duration to "1h" and region to "NW"
   - Refresh page → Filters should be preserved
   - Select folder → Data loads with saved filters

3. **Area Visualizer State**
   - Select Game, Region, City
   - Refresh page → Selections should be empty (no folder)
   - Select folder → Dropdowns restore to saved values

4. **Browser Navigation**
   - Switch tabs multiple times
   - Click browser back button → Previous tab appears
   - Click forward → Returns to newer tab

5. **Bookmarking**
   - Configure desired view
   - Bookmark the URL
   - Open bookmark → State is restored (after selecting folder)

## Future Enhancements

### Potential Improvements
- ~~IndexedDB cache to skip folder selection if permissions exist~~ **✓ DONE**
- Add "Share State" button to copy URL
- Support for ship usage chart filters in URL
- Canvas zoom/pan state in URL (complex)
- Clear saved directory button (for privacy-conscious users)

### Ship Usage Filters
Currently the ship usage widget has a `region` config option that's not connected to URL state. Could add:
```typescript
// URL: ?tab=ship-usage&shipRegion=NW&showRaw=false
```

## Code Style Notes

- Use `history.replaceState()` instead of `pushState()` to avoid polluting history
- Skip URL writes during state restoration (use `skipURLWrite` parameter)
- Only write non-default values to keep URLs clean
- Handle `null` vs empty string for "All" selections properly

