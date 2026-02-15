# Jam Timer Screen

This document describes the Jam Timer screen in the Roller Derby Scoreboard Companion app. It covers the purpose of the Jam Timer NSO role, the controls available in the screen, how the screen is used during a game, and the technical details of how the screen interacts with the CRG Scoreboard server.

For a full, official description of the Jam Timer non-skating official position, see:
https://nonskating.club/guides/jam-timer/

## Purpose of the Jam Timer Role

The Jam Timer NSO is responsible for timing jams and lineups and ensuring the game flow stays aligned with the rules. The Jam Timer tracks when jams start and end, monitors lineup timing between jams, and supports the officials by keeping accurate, visible timing information. This app is a companion to the CRG Scoreboard server and is designed to make those timing responsibilities fast and reliable on a mobile device.

The app does not run game logic. It displays the current game state from the CRG Scoreboard server and sends timing and timeout actions back to the server.

## How the Screen Is Used

- Pre-game or between periods, the Jam Timer uses the "Start Period Lineup" control to begin the lineup clock for the next period.
- During lineups and jams, the Jam Timer uses the main Start/Stop control to start jams and end jams, with the server managing actual clock state.
- During timeouts, the Jam Timer assigns the timeout to a team or to officials, and ends the timeout when appropriate.
- If the scoreboard supports undo, the Jam Timer can undo or replace the last timing action.
- If injury continuation is enabled and applicable, the Jam Timer can mark injury continuation as upcoming.
- The Jam Timer may adjust clock time by plus or minus one second when needed for corrections.

All actions are sent to the CRG Scoreboard server and are only reflected in the app after the server confirms updates.

## Controls and Availability

### Connection Controls

- Connection status banner: shows Connected, Connecting, Reconnecting, or Error.
- Pull-to-refresh: forces a disconnect so the app can reconnect and re-register state paths.
- All action controls are disabled when the app is not connected.

### Team Panels (Team 1 and Team 2)

- Team name display (uses alternate operator name, uniform color, or name from the scoreboard).
- Timeouts remaining.
- Official Reviews remaining.
- Retained Official Review toggle.

### Clocks

Only the relevant clock group is shown at a time:

- Period or Intermission clock:
  - Shows Intermission when it is running.
  - Shows Period when not in intermission and jams are still allowed.
- Jam, Lineup, or Timeout clock:
  - Shows Timeout when the timeout clock is running and not in "Post Timeout".
  - Shows Jam when the game is in a jam.
  - Shows Lineup when not in a jam and the lineup clock is running or has a time value.

Each visible clock supports plus or minus one second adjustments.

### Start Period Lineup

Visible only in pre-period state (between periods or before the first period). The Jam Timer slides the control to start the lineup clock for the next period. This sends a `StopJam` action to the server, which the server interprets as starting the lineup clock in this pre-period state.

### Start/Stop Jam

Visible when not in the pre-period state.

- When the game is in a jam or before the first lineup, the button sends `StopJam`.
- Otherwise, the button sends `StartJam`.
- The label text comes from scoreboard labels (for example, Start or Stop).
- The button shows a pending state until the server updates the jam or lineup number.

### Timeout Control

Visible when not in the pre-period state.

- If no timeout is running, a single Timeout button starts a generic timeout.
- If a timeout is running:
  - Assign to Team 1 (Timeout or Review).
  - Assign to Officials (Timeout or Review).
  - Assign to Team 2 (Timeout or Review).
  - End Timeout.

The active selection is driven by `TimeoutOwner` and `OfficialReview` values from the server.

### Undo and Replace

Visible only if the scoreboard label for Undo is not "No Action".

- Continuation button:
  - Visible only if injury continuation is enabled by rule and Team 1 has an injury.
  - Toggles `InjuryContinuationUpcoming`.
- Show Undo toggle:
  - Reveals the Undo controls (local UI only, not sent to the server).
- Use Replace on Undo toggle:
  - When enabled, Undo sends `ClockReplace` instead of `ClockUndo` (local UI only).
- Undo button:
  - Sends `ClockUndo` or `ClockReplace` to the server.
  - Uses the scoreboard-provided Undo label text.

### Optional Haptic Feedback

If haptics are enabled in settings, the app provides tactile cues:

- Jam start and stop.
- Jam time thresholds (warning, danger, critical).
- Lineup time thresholds based on rule duration.

## CRG Scoreboard WebSocket Connection

The Jam Timer screen is a thin client on top of the CRG Scoreboard server. The server is authoritative for game state and timing. The app only mirrors server state and sends commands to change state.

### Connection Details

- Server address is provided by the user in Settings.
- The address is sanitized to `ws://` or `wss://` and trailing slashes are removed.
- WebSocket URL format:
  - `{serverAddress}/WS/?source=companion&platform=mobile`
- Heartbeat:
  - Sends `{ "action": "Ping" }` every 30 seconds while connected.
- Reconnect:
  - Exponential backoff starting at 1 second, capped at 10 seconds.

### Registering State Paths

On connection, the app registers all state paths needed by the app. For the Jam Timer screen, the relevant paths are:

- `ScoreBoard.CurrentGame.Game`
- `ScoreBoard.CurrentGame.Clock(Period).Time`
- `ScoreBoard.CurrentGame.Clock(Period).Running`
- `ScoreBoard.CurrentGame.Clock(Period).Name`
- `ScoreBoard.CurrentGame.Clock(Period).Number`
- `ScoreBoard.CurrentGame.Clock(Jam).Time`
- `ScoreBoard.CurrentGame.Clock(Jam).Running`
- `ScoreBoard.CurrentGame.Clock(Jam).Number`
- `ScoreBoard.CurrentGame.Clock(Jam).Name`
- `ScoreBoard.CurrentGame.Clock(Lineup).Time`
- `ScoreBoard.CurrentGame.Clock(Lineup).Running`
- `ScoreBoard.CurrentGame.Clock(Lineup).Name`
- `ScoreBoard.CurrentGame.Clock(Lineup).Number`
- `ScoreBoard.CurrentGame.Rule(Lineup.Duration)`
- `ScoreBoard.CurrentGame.Rule(Lineup.OvertimeDuration)`
- `ScoreBoard.CurrentGame.Clock(Timeout).Time`
- `ScoreBoard.CurrentGame.Clock(Timeout).Running`
- `ScoreBoard.CurrentGame.Clock(Timeout).Name`
- `ScoreBoard.CurrentGame.Clock(Intermission).Time`
- `ScoreBoard.CurrentGame.Clock(Intermission).Running`
- `ScoreBoard.CurrentGame.Clock(Intermission).Name`
- `ScoreBoard.CurrentGame.Clock(Intermission).Number`
- `ScoreBoard.CurrentGame.InJam`
- `ScoreBoard.CurrentGame.NoMoreJam`
- `ScoreBoard.CurrentGame.InOvertime`
- `ScoreBoard.CurrentGame.TimeoutOwner`
- `ScoreBoard.CurrentGame.OfficialReview`
- `ScoreBoard.CurrentGame.InjuryContinuationUpcoming`
- `ScoreBoard.CurrentGame.Rule(Jam.InjuryContinuation)`
- `ScoreBoard.CurrentGame.Team(1).Name`
- `ScoreBoard.CurrentGame.Team(1).AlternateName(Operator)`
- `ScoreBoard.CurrentGame.Team(1).UniformColor`
- `ScoreBoard.CurrentGame.Team(1).Color(operator.fg)`
- `ScoreBoard.CurrentGame.Team(1).Color(operator.bg)`
- `ScoreBoard.CurrentGame.Team(1).Score`
- `ScoreBoard.CurrentGame.Team(1).Timeouts`
- `ScoreBoard.CurrentGame.Team(1).OfficialReviews`
- `ScoreBoard.CurrentGame.Team(1).RetainedOfficialReview`
- `ScoreBoard.CurrentGame.Team(1).Id`
- `ScoreBoard.CurrentGame.Team(1).Injury`
- `ScoreBoard.CurrentGame.Team(2).Name`
- `ScoreBoard.CurrentGame.Team(2).AlternateName(Operator)`
- `ScoreBoard.CurrentGame.Team(2).UniformColor`
- `ScoreBoard.CurrentGame.Team(2).Color(operator.fg)`
- `ScoreBoard.CurrentGame.Team(2).Color(operator.bg)`
- `ScoreBoard.CurrentGame.Team(2).Score`
- `ScoreBoard.CurrentGame.Team(2).Timeouts`
- `ScoreBoard.CurrentGame.Team(2).OfficialReviews`
- `ScoreBoard.CurrentGame.Team(2).RetainedOfficialReview`
- `ScoreBoard.CurrentGame.Team(2).Id`
- `ScoreBoard.CurrentGame.Team(2).Injury`
- `ScoreBoard.CurrentGame.Label(Start)`
- `ScoreBoard.CurrentGame.Label(Stop)`
- `ScoreBoard.CurrentGame.Label(Timeout)`
- `ScoreBoard.CurrentGame.Label(Undo)`
- `ScoreBoard.CurrentGame.Label(Replaced)`

### Incoming Messages

The server sends state updates as JSON. The app accepts several envelope formats and extracts key-value updates from any of these:

- `{ "state": { "ScoreBoard.CurrentGame.InJam": true, ... } }`
- `{ "updates": { "ScoreBoard.CurrentGame.InJam": true, ... } }`
- `{ "data": { "state": { "ScoreBoard.CurrentGame.InJam": true, ... } } }`
- `{ "ScoreBoard.CurrentGame.InJam": true, ... }`

Each key is a scoreboard path, and each value is the current state for that path.

### Outgoing Messages

All control actions use WebSocket messages with `action: "Set"` unless noted otherwise.

#### Start Jam

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.StartJam",
  "value": true,
  "flag": ""
}
```

#### Stop Jam

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.StopJam",
  "value": true,
  "flag": ""
}
```

Note: `StopJam` is also used to start the lineup clock in pre-period state and to end a timeout. The server decides the correct state transition.

#### Start Generic Timeout

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.Timeout",
  "value": true,
  "flag": ""
}
```

#### Start Official Timeout

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.OfficialTimeout",
  "value": true,
  "flag": ""
}
```

#### Start Team Timeout

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.Team(N).Timeout",
  "value": true,
  "flag": ""
}
```

#### Start Official Review

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.OfficialReview",
  "value": true,
  "flag": ""
}
```

#### Start Team Review

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.Team(N).OfficialReview",
  "value": true,
  "flag": ""
}
```

#### Retained Official Review Toggle

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.Team(N).RetainedOfficialReview",
  "value": true,
  "flag": ""
}
```

Value is toggled based on current state.

#### Injury Continuation Upcoming Toggle

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.InjuryContinuationUpcoming",
  "value": true,
  "flag": ""
}
```

Value is toggled based on current state.

#### Undo or Replace

Undo:

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.ClockUndo",
  "value": true,
  "flag": ""
}
```

Replace:

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.ClockReplace",
  "value": true,
  "flag": ""
}
```

#### Clock Adjustments (Plus or Minus 1 Second)

```json
{
  "action": "Set",
  "key": "ScoreBoard.CurrentGame.Clock(ClockType).Time",
  "value": "+1000",
  "flag": "change"
}
```

Use `"-1000"` to subtract one second. `ClockType` is one of `Period`, `Intermission`, `Jam`, `Lineup`, or `Timeout`.

## Notes and Assumptions

- The server is the source of truth; this screen only mirrors server state and sends inputs.
- Any labels or allowed actions may change based on ruleset and server configuration.
- The Undo section is only shown when the server provides an actionable Undo label.
