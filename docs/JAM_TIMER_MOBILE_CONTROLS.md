# Jam Timer Mobile Controls Documentation

This document describes the jam timer mobile controls interface (`/nso/jt/`) that's included by default with the scoreboard software, including all buttons available based on game state, WebSocket subscriptions, and WebSocket messages sent.

## Overview

The jam timer mobile controls page provides a mobile-friendly interface for controlling game timing in roller derby. The interface is context-bound to `ScoreBoard.CurrentGame`.

## Page Sections

### 1. Clocks Display

The clocks section displays two clock groups that show/hide based on game state.

#### Period/Intermission Clock Group

| Element | Visibility Condition | Display |
|---------|---------------------|---------|
| Period Clock | Hidden when Intermission is running OR when Period clock is running OR when NoMoreJam is true | Period name + number, time (mm:ss) |
| Intermission Clock | Hidden when Intermission is NOT running OR when Period clock is running | Intermission name + number, time (mm:ss) |

**Clock Time Adjustment Buttons (±):**
- `-` button: Decreases clock time by 1 second
- `+` button: Increases clock time by 1 second

#### Jam/Lineup/Timeout Clock Group

Uses `sbForeach` to iterate over clocks: `Jam`, `Lineup`, `Timeout`

| Element | Visibility Condition | CSS Classes Applied |
|---------|---------------------|---------------------|
| Clock container | Only the currently running clock is shown | `Running` when clock is running, `InJam` when game is in jam, `NoMoreJam` when no more jams allowed |

**Clock Time Adjustment Buttons (±):**
- `-` button: Decreases clock time by 1 second
- `+` button: Increases clock time by 1 second

### 2. Timeout Type Section

#### Per-Team Controls (Team 1 and Team 2)

| Button | Active State Condition | Action |
|--------|----------------------|--------|
| **Timeout** | Active when this team owns the timeout AND it's NOT an Official Review | Calls team timeout |
| **Review** | Active when this team owns the timeout AND it IS an Official Review | Calls Official Review for this team |
| **Retained** | Toggle button, active when `RetainedOfficialReview` is true | Toggles `RetainedOfficialReview` for this team |

**Display Elements:**
- Team Name (with operator colors)
- Timeouts remaining count
- Official Reviews remaining count

#### Official Timeout

| Button | Active State Condition | Action |
|--------|----------------------|--------|
| **Official TO** | Active when `TimeoutOwner === 'O'` | Calls Official Timeout |

### 3. Main Buttons Section

#### Settings Row (Hidden when `Label(Undo) === 'No Action'`)

| Button | Visibility Condition | Action |
|--------|---------------------|--------|
| **Continuation Upcoming** | Hidden unless `Rule(Jam.InjuryContinuation)` is true AND `Team(1).Injury` is true | Toggles `InjuryContinuationUpcoming` |
| **Show Undo** | Always visible in settings row | Toggles visibility of Undo button and Replace setting |
| **Use Replace on Undo** | Visible only when "Show Undo" is active | Toggles replace mode for undo (local toggle, not sent to server) |

#### Replace Info Row (Visible when `Label(Undo) !== 'No Action'`)
Displays: `Replace "[Label(Replaced)]" with`

#### Main Control Buttons

| Button | Label Source | Visual Alert Condition | Action |
|--------|-------------|----------------------|--------|
| **Undo** | `Label(Undo)` | None | Sends `ClockUndo` or `ClockReplace` (depending on "Use Replace" setting) |
| **Start** | `Label(Start)` | Highlighted (`sbClickMe`) when lineup clock has run longer than allowed duration | Sets `StartJam` |
| **Stop** | `Label(Stop)` | Highlighted (`sbClickMe`) when `InJam` is true but Jam clock is NOT running | Sets `StopJam` |
| **Timeout** | `Label(Timeout)` | Highlighted (`sbClickMe`) when lineup clock has run longer than allowed duration | Sets `Timeout` |

## WebSocket Subscriptions

The page subscribes to the following values (all prefixed with `ScoreBoard.CurrentGame.`):

### Clock Data

| Path | Usage |
|------|-------|
| `Clock(Period).Running` | Show/hide Period clock, apply Running style |
| `Clock(Period).Name` | Display clock name |
| `Clock(Period).Number` | Display period number |
| `Clock(Period).Time` | Display/adjust period time |
| `Clock(Intermission).Running` | Show/hide Intermission clock, apply Running style |
| `Clock(Intermission).Name` | Display clock name |
| `Clock(Intermission).Number` | Display intermission number |
| `Clock(Intermission).Time` | Display/adjust intermission time |
| `Clock(Jam).Running` | Apply Running style to Jam clock |
| `Clock(Jam).Name` | Display clock name |
| `Clock(Jam).Number` | Display jam number |
| `Clock(Jam).Time` | Display/adjust jam time |
| `Clock(Lineup).Running` | Apply Running style, check lineup duration |
| `Clock(Lineup).Name` | Display clock name |
| `Clock(Lineup).Time` | Display/adjust lineup time, check duration |
| `Clock(Timeout).Running` | Apply Running style to Timeout clock |
| `Clock(Timeout).Name` | Display clock name |
| `Clock(Timeout).Time` | Display/adjust timeout time |

### Game State

| Path | Usage |
|------|-------|
| `InJam` | Apply InJam style to Jam clock, check if jam is too long |
| `NoMoreJam` | Apply NoMoreJam style, hide Period clock |
| `InOvertime` | Determine which lineup duration rule to use |
| `TimeoutOwner` | Highlight active timeout owner button |
| `OfficialReview` | Determine if current timeout is an Official Review |

### Team Data (for each team 1 and 2)

| Path | Usage |
|------|-------|
| `Team(N).AlternateName(Operator)` | Display team name (fallback chain) |
| `Team(N).UniformColor` | Display team name (fallback chain) |
| `Team(N).Name` | Display team name (fallback chain) |
| `Team(N).Color(operator.fg)` | Team name text color |
| `Team(N).Color(operator.bg)` | Team name background color |
| `Team(N).Color(operator.glow)` | Team name text shadow |
| `Team(N).Timeouts` | Display remaining timeouts count |
| `Team(N).OfficialReviews` | Display remaining official reviews count |
| `Team(N).RetainedOfficialReview` | Toggle button state |
| `Team(N).Id` | Used to check if this team owns the timeout |
| `Team(N).Injury` | Check for injury continuation possibility |

### Rules

| Path | Usage |
|------|-------|
| `Rule(Jam.InjuryContinuation)` | Show/hide continuation upcoming button |
| `Rule(Lineup.Duration)` | Check if lineup is too long |
| `Rule(Lineup.OvertimeDuration)` | Check if overtime lineup is too long |

### Labels (Dynamic button text)

| Path | Usage |
|------|-------|
| `Label(Undo)` | Undo button text, determines visibility of settings/replace rows |
| `Label(Replaced)` | Shows what action will be replaced |
| `Label(Start)` | Start button text |
| `Label(Stop)` | Stop button text |
| `Label(Timeout)` | Timeout button text |

### Other

| Path | Usage |
|------|-------|
| `InjuryContinuationUpcoming` | Toggle button state |

## WebSocket Messages Sent

### Clock Time Adjustments

When clicking clock `+`/`-` buttons:

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.Clock(ClockType).Time",
  "value": "+1000 or -1000",
  "flag": "change"
}
```

Where `ClockType` is one of: `Period`, `Intermission`, `Jam`, `Lineup`, `Timeout`

### Team Timeout

When clicking team Timeout button:

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.Team(N).Timeout",
  "value": true,
  "flag": ""
}
```

### Team Official Review

When clicking team Review button:

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.Team(N).OfficialReview",
  "value": true,
  "flag": ""
}
```

### Retained Official Review Toggle

When clicking Retained button:

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.Team(N).RetainedOfficialReview",
  "value": true/false,
  "flag": ""
}
```

Value toggles based on current state.

### Official Timeout

When clicking Official TO button:

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.OfficialTimeout",
  "value": true,
  "flag": ""
}
```

### Injury Continuation Upcoming Toggle

When clicking Continuation Upcoming button:

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.InjuryContinuationUpcoming",
  "value": true/false,
  "flag": ""
}
```

### Start Jam

When clicking Start button:

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.StartJam",
  "value": true,
  "flag": ""
}
```

### Stop Jam

When clicking Stop button:

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.StopJam",
  "value": true,
  "flag": ""
}
```

### Timeout (Generic)

When clicking main Timeout button:

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.Timeout",
  "value": true,
  "flag": ""
}
```

### Undo / Replace

When clicking Undo button (behavior depends on "Use Replace on Undo" toggle):

**If "Use Replace on Undo" is NOT active:**
```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.ClockUndo",
  "value": true,
  "flag": ""
}
```

**If "Use Replace on Undo" IS active:**
```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.ClockReplace",
  "value": true,
  "flag": ""
}
```

## Visual State Indicators

### Clock Styling

| Condition | Applied Style |
|-----------|--------------|
| Clock is running | Green background (`--element-active-bg`) |
| Clock is running AND NoMoreJam | Different background (`--element-inbox-bg`) |
| Jam clock showing AND InJam | Green background (`--element-active-bg`) |

### Button Highlighting (`sbClickMe` class)

The Start and Timeout buttons will be visually highlighted when:
- Lineup clock is running AND
- Lineup time exceeds the allowed duration (normal or overtime depending on `InOvertime` state)

The Stop button will be visually highlighted when:
- `InJam` is true AND
- Jam clock is NOT running (jam ended but InJam flag not cleared)

### Active Button States (`sbActive` class)

| Button | Active When |
|--------|------------|
| Team Timeout | This team's ID matches TimeoutOwner AND OfficialReview is false |
| Team Review | This team's ID matches TimeoutOwner AND OfficialReview is true |
| Retained | Team's RetainedOfficialReview is true |
| Official TO | TimeoutOwner === 'O' |
| Show Undo | Toggled on by user (local state) |
| Use Replace on Undo | Toggled on by user (local state) |
| Continuation Upcoming | InjuryContinuationUpcoming is true |

## Button Availability by Game State

### Pre-Game / Intermission (Clock(Intermission).Running = true)

| Button | Available |
|--------|-----------|
| Clock adjustments (Intermission) | Yes |
| Start | Yes |
| Stop | Yes |
| Timeout (main) | Yes |
| Team Timeout | Yes |
| Official Review | Yes |
| Retained | Yes |
| Official TO | Yes |

### Lineup (Clock(Lineup).Running = true)

| Button | Available |
|--------|-----------|
| Clock adjustments (Period, Lineup) | Yes |
| Start | Yes (highlighted if lineup too long) |
| Stop | Yes |
| Timeout (main) | Yes (highlighted if lineup too long) |
| Team Timeout | Yes |
| Official Review | Yes |
| Retained | Yes |
| Official TO | Yes |

### In Jam (Clock(Jam).Running = true)

| Button | Available |
|--------|-----------|
| Clock adjustments (Period, Jam) | Yes |
| Start | Yes |
| Stop | Yes (highlighted if InJam but clock not running) |
| Timeout (main) | Yes |
| Team Timeout | Yes |
| Official Review | Yes |
| Retained | Yes |
| Official TO | Yes |

### During Timeout (Clock(Timeout).Running = true)

| Button | Available |
|--------|-----------|
| Clock adjustments (Period, Timeout) | Yes |
| Start | Yes |
| Stop | Yes |
| Timeout (main) | Yes |
| Team Timeout | Yes (active state shows current owner) |
| Official Review | Yes (active state shows current owner) |
| Retained | Yes |
| Official TO | Yes (active state shows if official timeout) |

## Notes

- All buttons are always present in the DOM; visibility is controlled via CSS classes (`sbHide`)
- The Undo button is hidden by default and must be revealed via "Show Undo" toggle
- Clock time adjustments use the `change` flag which performs relative adjustments rather than absolute sets
- Team name display follows a fallback chain: `AlternateName(Operator)` → `UniformColor` → `Name`
- The `sbClickMe` class provides visual emphasis for time-sensitive actions (lineup too long, jam ended but not stopped)
