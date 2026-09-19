#!/usr/bin/env python3
"""discord-heartbeat (macOS / Linux).

A tiny heartbeat that holds a Discord gateway connection open so your bot
appears online whenever this machine is awake and you're logged in.
Auto-reconnects forever. No server, no hosting, no dependencies beyond
the `websockets` package.

It exists for bots with no home: bots driven by an AI assistant (like Muse)
through the Discord REST API, where there is no bot process running
anywhere to hold presence. This script is the pulse.

Token: ~/.discord-heartbeat/token (chmod 600), or DISCORD_BOT_TOKEN env var.
Logs:  ~/.discord-heartbeat/keeper.log

Multiple machines: give each machine its own shard so their sessions never
fight. See HEARTBEAT_SHARD_ID / HEARTBEAT_SHARD_COUNT below.
"""
import asyncio
import json
import os
import sys
from datetime import datetime

BASE = os.path.join(os.path.expanduser("~"), ".discord-heartbeat")
TOKEN_FILE = os.path.join(BASE, "token")
LOG_FILE = os.path.join(BASE, "keeper.log")
GATEWAY = "wss://gateway.discord.gg/?v=10&encoding=json"

SHARD_ID = int(os.environ.get("HEARTBEAT_SHARD_ID", "0"))
SHARD_COUNT = int(os.environ.get("HEARTBEAT_SHARD_COUNT", "1"))

if sys.platform == "darwin":
    OS_NAME = "darwin"
elif sys.platform.startswith("linux"):
    OS_NAME = "linux"
else:
    OS_NAME = sys.platform


def log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except OSError:
        pass


def get_token():
    env = os.environ.get("DISCORD_BOT_TOKEN", "").strip()
    if env:
        return env
    try:
        with open(TOKEN_FILE) as f:
            tok = f.read().strip()
        if tok:
            return tok
    except OSError:
        pass
    return None


async def run_once(token):
    import websockets

    async with await asyncio.wait_for(
        websockets.connect(GATEWAY, max_size=4 * 1024 * 1024), timeout=20
    ) as ws:
        hello = json.loads(await asyncio.wait_for(ws.recv(), timeout=15))
        interval = hello["d"]["heartbeat_interval"] / 1000
        identify = {
            "op": 2,
            "d": {
                "token": token,
                "intents": 0,
                "properties": {
                    "os": OS_NAME,
                    "browser": "discord-heartbeat",
                    "device": "discord-heartbeat",
                },
                "presence": {"status": "online", "afk": False, "activities": [], "since": 0},
            },
        }
        if SHARD_COUNT > 1:
            # Distinct shards let several machines hold sessions at once.
            identify["d"]["shard"] = [SHARD_ID, SHARD_COUNT]
        await ws.send(json.dumps(identify))
        seq = None

        async def heartbeat():
            while True:
                await asyncio.sleep(interval)
                await ws.send(json.dumps({"op": 1, "d": seq}))

        hb = asyncio.create_task(heartbeat())
        logged_ready = False
        try:
            async for raw in ws:
                data = json.loads(raw)
                if data.get("s") is not None:
                    seq = data["s"]
                op = data.get("op")
                if not logged_ready and op == 0 and data.get("t") == "READY":
                    logged_ready = True
                    log("gateway connected, bot is online")
                if op == 9:
                    raise RuntimeError("invalid session")
                if op == 7:
                    raise RuntimeError("server asked to reconnect")
        finally:
            hb.cancel()


async def main():
    os.makedirs(BASE, exist_ok=True)
    import websockets  # noqa: F401 - fail fast if missing

    while True:
        token = get_token()
        if not token:
            log("no token: put the bot token in ~/.discord-heartbeat/token (chmod 600) "
                "or set DISCORD_BOT_TOKEN; will pick it up automatically")
            await asyncio.sleep(60)
            continue
        try:
            await run_once(token)
        except Exception as e:  # noqa: BLE001 - keeper must never die
            log(f"disconnected ({e}); retrying in 5s")
        await asyncio.sleep(5)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
