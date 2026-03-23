# Penalty Box Rules & Scoreboard Implementation

## WFTDA Penalty Rules

### 4.1 — Earning a Penalty

A skater who commits a rule violation is assessed a penalty by a referee. The skater must immediately exit the track and report to the penalty box (§4.1.1). If the skater cannot immediately leave (e.g., jam ends while en route), they sit at the start of the next jam.

Penalty types are enumerated in §5 (contact penalties), §6 (skating out of bounds), §7 (illegal procedures), etc. Each is a single penalty regardless of severity, except:

- **Expulsion** (§4.4): a skater who commits an expulsion-worthy offense is removed from the game entirely, without serving box time.
- **Fouling Out** (§4.3.3): 7 accumulated penalties in a game result in expulsion from that game.

### 4.2 — Serving Penalty Time

- **Duration**: Each penalty is served as **30 seconds of jam time** (§4.2.1). The clock only runs during an active jam; it freezes between jams.
- **Multiple penalties**: If a skater earns additional penalties while in the box, each adds 30 seconds to their remaining time (§4.2.2). There is no upper limit specified, though JamBox caps display at 5:00.
- **Arrival between jams**: A skater who reports to the box between jams begins serving at the start of the next jam. Their clock starts when the jam starts (§4.2.3).
- **Release**: A skater is released as soon as their time reaches zero AND a jam is in progress. They may not leave between jams even if their time has expired (§4.2.5).

### 4.3 — Blocker Release

Blockers (including pivots) serve their full time and are released as soon as the clock hits zero during a jam. They leave immediately — they do not need to wait for the jam to end (§4.3.1).

If a blocker's time expires between jams, they are released at the **start** of the next jam, not immediately (§4.3.2).

### 4.4 — Jammer Synchronization ("Jammer Swap")

This is the most complex penalty box rule. When **both jammers are in the penalty box simultaneously**, their times are synchronized to prevent one team from gaining an extended power jam advantage:

1. When a second jammer arrives at the box while the first is already serving:
   - The **sitting jammer is released** (their remaining time is effectively cancelled).
   - The **arriving jammer serves only the amount of time already served** by the sitting jammer — i.e., they inherit the elapsed time, not the full 30 seconds (§4.4.1).

2. If the arriving jammer has **multiple penalties**:
   - Penalties are cancelled one-for-one against the sitting jammer's penalties.
   - Any remaining excess penalties are served normally (§4.4.2).

3. If the sitting jammer already has **reduced time** (from a previous swap):
   - The arriving jammer gets their full 30 seconds; the sitting jammer must finish their reduced time (§4.4.3). This is the "nightmare scenario" documented in CRG's source.

4. **Between jams**: If a jammer's time expires exactly at jam end, they are released at the **start** of the next jam (§4.2.5 applies). Their clock resets to zero but they stay seated until the whistle.

### 4.5 — Penalty Notation (for record-keeping)

Each penalty is logged with: skater number, period, jam number, and penalty code. The penalty box manager (PBM) role records entries; the head NSO reconciles with the scorekeeper. Penalty codes are standardized abbreviations (e.g., `B` = back block, `C` = cut track, `X` = expulsion).

---

## CRG Scoreboard Implementations

### Branch: `origin/v2025.9` (mainline)

**Architecture**: The mainline scoreboard has no dedicated server-side penalty box timer. Penalty box timing is an **overlay concern** — the `pbt` web UI reads lineup/fielding state and drives its own client-side timers, loosely coordinated with the scoreboard.

**Data model** (`BoxTripImpl`):
- A `BoxTrip` is created per skater per penalty box stint, linked to a `Fielding` (skater-in-position record for a jam).
- `BoxTrip` has its own embedded `Clock` that counts down the penalty duration.
- The clock starts when the jam starts (`startJam()`) and stops when the jam ends (`stopJam()`).
- When the clock reaches zero, `end()` is called → sets `END_FIELDING`, removes the trip from current, records `JAM_CLOCK_END`.
- Multiple penalties on one trip are tracked via `PENALTY` children on the trip; each added penalty calls `clock.changeMaximumTime(+penaltyDuration)`.

**Jammer sync** (`BoxTripImpl.itemAdded` for `PENALTY` child, ~line 261):
```java
if (getCurrentFielding().getCurrentRole() == Role.JAMMER && numberOf(PENALTY) > get(SHORTENED)) {
    Position otherPos = getTeam().getOtherTeam().getPosition(FloorPosition.JAMMER);
    if (otherPos.isPenaltyBox()) {
        BoxTrip other = otherPos.getCurrentFielding().getCurrentBoxTrip();
        if (other.numberOf(PENALTY) > other.get(SHORTENED) && other.getClock().getTimeRemaining() > 0) {
            long shorteningAmount = Math.min(..., penaltyDuration);
            other.set(SHORTENED, ...);
            set(SHORTENED, numberOf(PENALTY));
            other.getClock().changeMaximumTime(-shorteningAmount);
            clock.changeMaximumTime(-shorteningAmount);
        }
    }
}
```
Sync is triggered when a **penalty is added to a jammer's trip** while the other jammer is also in the box. Both clocks are shortened by the same amount.

**`pbt` web UI** (`html/nso/pbt/`):
- Subscribes to `ScoreBoard.CurrentGame.Team(*).Position(*).CurrentFielding`
- Reads fielding state and `PenaltyBox` flag to display who is sitting
- Requires `ScoreBoard.Settings.Setting(ScoreBoard.Penalties.UsePBT) = true` to activate
- The UI is informational + provides manual controls; it does **not** drive server-side timers
- JamBox does not integrate with this UI path (no BoxSeat paths exist on this branch)

**JamBox behavior on v2025.9**: JamBox connects and receives jam clock, roster, team names, and period/jam numbers normally. `_boxSeatMode` never activates (no BoxClock paths arrive). All penalty box timing is local, driven by the on-device `LocalPenaltyEngine`.

---

### Branch: `katpet/feature-pbt`

**Architecture**: This branch adds a **server-authoritative penalty box timer** system. The server owns all timer state; clients (including JamBox) send commands and receive clock updates via WebSocket.

**Data model**:

| Class | Role |
|-------|------|
| `BoxSeat` | One per floor position per team: `Jammer`, `Blocker1`, `Blocker2`, `Blocker3` |
| `BoxClock` | One dedicated countdown clock per `BoxSeat`, named `Team{N}{SeatId}` (e.g. `Team1Jammer`) |
| `BoxTrip` | Still exists; created by `BoxSeatImpl` when a seat is started; records the official penalty trip for statsbook |

**Server-side timer lifecycle** (`BoxSeatImpl`):

```
StartBox command
  └─ if jam running  → creates BoxTrip, starts BoxClock, applies jammer sync
  └─ if jam stopped  → creates BoxTrip, resets clock to 30s, immediately stops (paused state)

BoxClock reaches 0
  └─ endBox() → records penalty count on skater, marks BoxTrip ended, calls resetBox()

ResetBox command
  └─ stops clock, resets to penaltyDuration, clears skater/fielding reference

StopBox command
  └─ pauses clock (used at jam end automatically)

BoxTimeChange value (integer seconds)
  └─ adjusts BoxClock time and MaximumTime; also increments/decrements penalty count
     if the delta is exactly ±penaltyDuration

Jam start → StartBox (resume) on all occupied seats
Jam end   → StopBox on all running seats
```

**Jammer sync** (`BoxSeatImpl.doJammerLogic`, called from `restartBox()`):

When a jammer's seat is started (or resumed at jam start), the server checks if the other team's jammer seat is also active. If so, it calculates new times for both clocks implementing §4.4:

- **Simple case** (both clocks have same max time): sitting jammer gets `~1ms` (effectively released), arriving jammer gets `elapsed_by_sitting_jammer`.
- **Multi-penalty cases**: penalties cancelled one-for-one; remaining difference redistributed.
- **Nightmare scenario**: sitting jammer already has reduced time from prior swap → arriving jammer gets full penalty duration, sitting jammer keeps their remaining time.

The server handles all five cases from §4.4 including the multi-penalty edge cases.

**WebSocket protocol** (client ↔ server):

Subscribe (server → client):
```
ScoreBoard.CurrentGame.BoxClock(Team{N}{SeatId}).Time      — milliseconds remaining
ScoreBoard.CurrentGame.BoxClock(Team{N}{SeatId}).Running   — bool
ScoreBoard.CurrentGame.Team(N).BoxSeat(SeatId).Started     — bool (occupied, survives jam end)
ScoreBoard.CurrentGame.Team(N).BoxSeat(SeatId).BoxSkater   — skater number string (blockers)
ScoreBoard.CurrentGame.Team(N).Skater(*).Role              — "Jammer" when fielded as jammer
```

Commands (client → server):
```json
{"action":"Set","key":"...Team(N).BoxSeat(SeatId).StartBox","value":true,"flag":""}
{"action":"Set","key":"...Team(N).BoxSeat(SeatId).ResetBox","value":true,"flag":""}
{"action":"Set","key":"...Team(N).BoxSeat(SeatId).BoxTimeChange","value":30,"flag":""}
{"action":"Set","key":"...Team(N).BoxSeat(SeatId).BoxSkater","value":"123","flag":""}
```

**`pbt2` web UI** (`html/nso/pbt2/`):
- Dedicated UI for BoxSeat-mode operation
- Separate pages for jammers, team blockers, and combined view
- Three blocker seats per team (Blocker1, Blocker2, Blocker3 = overflow/queue)
- Skater assignment via dropdown select for blockers; jammer auto-populated from fielding role

**JamBox behavior on katpet/feature-pbt**: On first `BoxClock(*)` update received, `_boxSeatMode` is set to `true`, the local ticker is paused (server owns all timer math), and action callbacks are wired up. All seat actions (start, clear, time adjust, skater assign) send WS commands to the server; server echoes back updated state within ~100ms. Jammer numbers are populated via `Skater(*).Role` subscription rather than `BoxSkater` (which is blocker-only on this branch).

---

## Key Differences Between Branches

| Aspect | v2025.9 | katpet/feature-pbt |
|--------|---------|-------------------|
| Timer authority | Client (browser or JamBox) | Server (`BoxSeat`/`BoxClock`) |
| Jammer sync | Client-triggered via `PENALTY` add | Server-triggered on `StartBox` |
| Box seats | Implicit (derived from fielding) | Explicit named seats (1J + 6B) |
| Skater assignment | Via lineup tracking (`Fielding`) | Via `BoxSkater` WS command or role |
| JamBox mode | Local timer (`LocalPenaltyEngine`) | Remote sync (`_boxSeatMode = true`) |
| Between-jam state | BoxTrip ends/restarts each jam | `BoxSeat.Started = true` persists |
| Multi-penalty tracking | BoxTrip `PENALTY` children + `SHORTENED` | `BoxTimeChange` + `numPenalties` counter |
| Blocker queue (3rd+) | JamBox-local queue widget | Blocker3 seat on server |
| Penalty record creation | Automatic on `BoxTrip` creation | `endBox()` when clock reaches zero |
