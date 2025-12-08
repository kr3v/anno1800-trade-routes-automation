# Profile Selector Implementation

## Summary

Successfully implemented profile name selection for the Trade Routes Analyzer webapp. The system now supports multiple game profiles, automatically discovering them from log files and allowing users to select which profile to view.

## Changes Made

### 1. Parser Layer (`src/parsers/deficit-surplus.ts`)

- **Updated `loadDeficitSurplus`**: Added `profileName` parameter
  - Now constructs file paths as: `TrRAt_{profileName}_{region}_remaining-deficit.json`
  - Signature: `loadDeficitSurplus(dirHandle, profileName, region, goodsNames)`

- **Added `scanProfileNames`**: New function to discover available profiles
  - Scans directory for files matching: `TrRAt_{ProfileName}_{Region}_remaining-*.json`
  - Extracts unique profile names from filenames
  - Returns sorted array of profile names
  - Example: `['Frances_Farthorp', 'GameProfile2']`

### 2. Widget Layer (`src/widgets/deficit-surplus.ts`)

- **Updated `DeficitSurplusWidget.load`**: Now requires `profileName` parameter
  - Signature: `load(dirHandle, profileName, region)`
  - Passes profile name to parser

### 3. State Management (`src/url-state.ts`)

- **Added `profileName` to `AppState` interface**
  - Type: `string | null`
  - Default: `null`
  
- **Updated URL state functions**:
  - `readStateFromURL()`: Reads `profileName` query parameter
  - `writeStateToURL()`: Writes `profileName` to URL if set
  - Enables bookmarking specific profiles

### 4. UI Layer (`index.html`)

- **Added Profile Selector**: New dropdown before time/region filters
  ```html
  <div class="control-group">
    <label for="profile-filter">Profile:</label>
    <select id="profile-filter" disabled>
      <option value="">Select folder first</option>
    </select>
  </div>
  ```
  - Initially disabled until folder is selected
  - Positioned first in control group for logical flow

### 5. Main Application (`src/main.ts`)

#### State Management
- Added `currentProfileName: string | null` to app state
- Added `profileFilter: HTMLSelectElement` DOM reference

#### New Function: `populateProfileSelector()`
- Calls `scanProfileNames()` to discover available profiles
- Populates dropdown with discovered profiles
- Auto-selects first profile if none is selected
- Restores profile from URL state if available
- Handles error states (no profiles found, scan errors)

#### Updated Functions

**`init()`**:
- Initializes `profileFilter` DOM element
- Reads `currentProfileName` from URL state
- Adds change listener for profile selector
- Updates URL state when profile changes

**`loadAllTabs()`**:
- Calls `populateProfileSelector()` before loading data
- Ensures profile is selected before loading trades

**`loadTradesTab()`**:
- Checks that both `dirHandle` and `currentProfileName` exist
- Passes profile name to `deficitSurplusWidget.load()`

**`handleURLStateChange()`**:
- Handles profile changes from browser back/forward
- Updates profile selector when URL changes
- Reloads data when profile changes

## File Naming Convention

The system expects deficit/surplus files to follow this pattern:
```
TrRAt_{ProfileName}_{Region}_remaining-deficit.json
TrRAt_{ProfileName}_{Region}_remaining-surplus.json
```

Examples:
- `TrRAt_Frances_Farthorp_NW_remaining-deficit.json`
- `TrRAt_Frances_Farthorp_NW_remaining-surplus.json`
- `TrRAt_Frances_Farthorp_OW_remaining-deficit.json`
- `TrRAt_Frances_Farthorp_OW_remaining-surplus.json`

## User Flow

1. User selects log folder
2. System scans for profile names in deficit/surplus files
3. Profile dropdown is populated and first profile auto-selected
4. Deficit/surplus data loads for selected profile + region
5. User can change profile via dropdown
6. Data reloads for new profile
7. Profile selection is saved in URL for bookmarking

## URL State

Profile selection is persisted in URL query parameters:
```
?tab=trades&profileName=Frances_Farthorp&region=OW
```

This enables:
- Bookmarking specific profiles
- Browser back/forward navigation
- Sharing links to specific profiles

## Error Handling

- **No profiles found**: Selector shows "No profiles found" and is disabled
- **Scan error**: Selector shows "Error loading profiles" and is disabled
- **Missing profile**: Data loading is skipped if no profile is selected
- **Invalid profile in URL**: Falls back to first available profile

## Build Status

✅ TypeScript compilation successful
✅ Vite build successful
✅ No runtime errors

## Testing Recommendations

1. Test with folder containing single profile
2. Test with folder containing multiple profiles
3. Test profile switching between different profiles
4. Test region switching with different profiles
5. Test URL bookmarking with profile parameter
6. Test browser back/forward with profile changes
7. Test with folder containing no deficit/surplus files

