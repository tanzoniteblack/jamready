#!/usr/bin/env python3
"""
Connects to the CRG scoreboard WebSocket, registers the same paths as the
Flutter app, collects the initial state dump, and prints it as JSON to stdout.

Usage:
    python3 scripts/fetch_state.py [host:port]

    Default host:port is localhost:8000.

Requires: pip install websockets
"""

import asyncio
import json
import sys

try:
    import websockets
except ImportError:
    print("Missing dependency: pip install websockets", file=sys.stderr)
    sys.exit(1)

PATHS = [
    "ScoreBoard.CurrentGame.Game",
    "ScoreBoard.CurrentGame.Clock(Period).Time",
    "ScoreBoard.CurrentGame.Clock(Period).Running",
    "ScoreBoard.CurrentGame.Clock(Period).Name",
    "ScoreBoard.CurrentGame.Clock(Period).Number",
    "ScoreBoard.CurrentGame.Clock(Jam).Time",
    "ScoreBoard.CurrentGame.Clock(Jam).Running",
    "ScoreBoard.CurrentGame.Clock(Jam).Number",
    "ScoreBoard.CurrentGame.Clock(Jam).Name",
    "ScoreBoard.CurrentGame.Clock(Lineup).Time",
    "ScoreBoard.CurrentGame.Clock(Lineup).Running",
    "ScoreBoard.CurrentGame.Clock(Lineup).Name",
    "ScoreBoard.CurrentGame.Clock(Lineup).Number",
    "ScoreBoard.CurrentGame.Rule(Lineup.Duration)",
    "ScoreBoard.CurrentGame.Rule(Lineup.OvertimeDuration)",
    "ScoreBoard.CurrentGame.Clock(Timeout).Time",
    "ScoreBoard.CurrentGame.Clock(Timeout).Running",
    "ScoreBoard.CurrentGame.Clock(Timeout).Name",
    "ScoreBoard.CurrentGame.Clock(Intermission).Time",
    "ScoreBoard.CurrentGame.Clock(Intermission).Running",
    "ScoreBoard.CurrentGame.Clock(Intermission).Name",
    "ScoreBoard.CurrentGame.Clock(Intermission).Number",
    "ScoreBoard.CurrentGame.InJam",
    "ScoreBoard.CurrentGame.NoMoreJam",
    "ScoreBoard.CurrentGame.InOvertime",
    "ScoreBoard.CurrentGame.TimeoutOwner",
    "ScoreBoard.CurrentGame.OfficialReview",
    "ScoreBoard.CurrentGame.InjuryContinuationUpcoming",
    "ScoreBoard.CurrentGame.Rule(Jam.InjuryContinuation)",
    "ScoreBoard.CurrentGame.Team(1).Name",
    "ScoreBoard.CurrentGame.Team(1).AlternateName(Operator)",
    "ScoreBoard.CurrentGame.Team(1).UniformColor",
    "ScoreBoard.CurrentGame.Team(1).Color(operator.fg)",
    "ScoreBoard.CurrentGame.Team(1).Color(operator.bg)",
    "ScoreBoard.CurrentGame.Team(1).Score",
    "ScoreBoard.CurrentGame.Team(1).Timeouts",
    "ScoreBoard.CurrentGame.Team(1).OfficialReviews",
    "ScoreBoard.CurrentGame.Team(1).RetainedOfficialReview",
    "ScoreBoard.CurrentGame.Team(1).Id",
    "ScoreBoard.CurrentGame.Team(1).Injury",
    "ScoreBoard.CurrentGame.Team(2).Name",
    "ScoreBoard.CurrentGame.Team(2).AlternateName(Operator)",
    "ScoreBoard.CurrentGame.Team(2).UniformColor",
    "ScoreBoard.CurrentGame.Team(2).Color(operator.fg)",
    "ScoreBoard.CurrentGame.Team(2).Color(operator.bg)",
    "ScoreBoard.CurrentGame.Team(2).Score",
    "ScoreBoard.CurrentGame.Team(2).Timeouts",
    "ScoreBoard.CurrentGame.Team(2).OfficialReviews",
    "ScoreBoard.CurrentGame.Team(2).RetainedOfficialReview",
    "ScoreBoard.CurrentGame.Team(2).Id",
    "ScoreBoard.CurrentGame.Team(2).Injury",
    "ScoreBoard.CurrentGame.Label(Start)",
    "ScoreBoard.CurrentGame.Label(Stop)",
    "ScoreBoard.CurrentGame.Label(Timeout)",
    "ScoreBoard.CurrentGame.Label(Undo)",
    "ScoreBoard.CurrentGame.Label(Replaced)",
]

# How long to keep collecting after the first message arrives, in seconds.
# CRG typically dumps all registered path values in a burst on connect.
SETTLE_TIMEOUT = 1.0


def extract_state(data: dict) -> dict:
    """Mirror the Flutter _handleMessage logic."""
    if "state" in data:
        return data["state"]
    if "updates" in data:
        return data["updates"]
    if "data" in data and isinstance(data["data"], dict) and "state" in data["data"]:
        return data["data"]["state"]
    return data


async def fetch(host_port: str) -> None:
    url = f"ws://{host_port}/WS/?source=companion&platform=mobile"
    print(f"Connecting to {url} ...", file=sys.stderr)

    async with websockets.connect(url) as ws:
        await ws.send(json.dumps({"action": "Register", "paths": PATHS}))
        print("Registered paths, waiting for state...", file=sys.stderr)

        state: dict = {}
        got_first = False
        deadline = None

        while True:
            remaining = None
            if deadline is not None:
                remaining = deadline - asyncio.get_event_loop().time()
                if remaining <= 0:
                    break

            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=remaining or 10.0)
            except asyncio.TimeoutError:
                if got_first:
                    break  # settle period expired, we're done
                print("Timed out waiting for initial message.", file=sys.stderr)
                sys.exit(1)

            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                continue

            if isinstance(data, dict):
                state.update(extract_state(data))
                if not got_first:
                    got_first = True
                    deadline = asyncio.get_event_loop().time() + SETTLE_TIMEOUT
                    print("Receiving state...", file=sys.stderr)

    print(f"Done. {len(state)} keys collected.", file=sys.stderr)
    print(json.dumps(state, indent=2, sort_keys=True))


def main() -> None:
    host_port = sys.argv[1] if len(sys.argv) > 1 else "localhost:8000"
    asyncio.run(fetch(host_port))


if __name__ == "__main__":
    main()
