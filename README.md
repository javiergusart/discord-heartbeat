# discord-heartbeat

A tiny heartbeat that keeps your Discord bot **online** with no server, no hosting, and no bot process running anywhere.

## The idea

Most Discord bots live on a VPS that never sleeps, so presence is trivial. But some bots have no home at all: bots driven by an AI assistant (like [Muse](https://muse.ai)) through the Discord REST API, where there is no code running on a schedule, just an assistant that acts when you ask it to. For a bot like that, *appearing online* is its own problem.

`discord-heartbeat` solves it from your own machines. Run it on your laptop, your desktop, or both. While a machine is awake and you're logged in, it holds a quiet Discord gateway connection open and your bot shows online. When every machine sleeps, the bot goes offline by itself. Presence follows *you*, not a data center.

## How it works

One small script per OS (Python on macOS/Linux, PowerShell on Windows, both under 150 lines). It:

1. Reads your bot token from a file (or env var).
2. Opens a single Discord gateway WebSocket and identifies with `intents: 0` (it receives nothing, it just exists).
3. Sends a heartbeat every ~41 seconds and reconnects forever if anything drops.

That's it. ~25MB RAM on macOS, ~100MB on Windows (that's PowerShell itself), effectively zero CPU, a few dozen bytes of network every 41 seconds.

## Requirements

- A Discord bot token. Yours, from your own app. Nothing here works without one, and nothing here asks you to share it.
- macOS/Linux: Python 3.8+ and the `websockets` package (`pip install websockets`). The installer handles this.
- Windows: nothing to install. PowerShell 5.1+ is built in.

## Quick start

### 1. Get your bot token

1. Go to [discord.com/developers/applications](https://discord.com/developers/applications) and select your app (or create one).
2. Open the **Bot** section, then **Reset Token** (or **Copy**).
3. Copy it somewhere safe. You will paste it into a file on *your* machine in the next step, never into a chat, never into this repo.

### 2a. macOS

```sh
git clone https://github.com/javiergusart/discord-heartbeat.git
cd discord-heartbeat
./install.sh
printf '%s' 'YOUR_BOT_TOKEN' > ~/.discord-heartbeat/token && chmod 600 ~/.discord-heartbeat/token
```

The installer copies the script, registers a LaunchAgent (starts at login, restarts if it ever dies), and the heartbeat picks up the token within a minute. Check `~/.discord-heartbeat/keeper.log` for `gateway connected, bot is online`.

### 2b. Windows

1. Copy `heartbeat.ps1` to `%USERPROFILE%\.discord-heartbeat\heartbeat.ps1` (create the folder).
2. Save your token: open PowerShell and run
   ```powershell
   Set-Content $env:USERPROFILE\.discord-heartbeat\token 'YOUR_BOT_TOKEN' -NoNewline
   ```
3. Make it start at logon: press `Win+R`, type `shell:startup`, and create a file named `DiscordHeartbeat.bat` containing:
   ```bat
   @echo off
   start "" /min powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "%USERPROFILE%\.discord-heartbeat\heartbeat.ps1"
   ```
4. Double-click the `.bat` once to start it now (it also starts on every future logon). Check `%USERPROFILE%\.discord-heartbeat\keeper.log` for `connected; heartbeat every`.

### 2c. Linux

```sh
git clone https://github.com/javiergusart/discord-heartbeat.git
cd discord-heartbeat
mkdir -p ~/.discord-heartbeat
cp heartbeat.py ~/.discord-heartbeat/
pip install --user websockets
printf '%s' 'YOUR_BOT_TOKEN' > ~/.discord-heartbeat/token && chmod 600 ~/.discord-heartbeat/token
cp discord-heartbeat.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now discord-heartbeat
```

## Multiple computers

Two machines can hold sessions for the same bot at the same time, as long as each identifies as a **different shard**. Otherwise they fight over one session and knock each other off.

Pick a shard id per machine (0, 1, 2...) and use the same shard count everywhere. For two machines, that's shards `0 of 2` and `1 of 2`.

**macOS:** pass them to the installer:

```sh
./install.sh 0 2   # machine one
./install.sh 1 2   # machine two
```

Or set the env vars yourself: `HEARTBEAT_SHARD_ID` and `HEARTBEAT_SHARD_COUNT`.

**Windows:** add two lines to the top of your `DiscordHeartbeat.bat`, before the `start` line:

```bat
set HEARTBEAT_SHARD_ID=1
set HEARTBEAT_SHARD_COUNT=2
```

**Linux:** uncomment and set the `Environment=` lines in `discord-heartbeat.service`.

The scripts also accept `DISCORD_BOT_TOKEN` as an env var instead of the token file.

## Security notes

- Your token is the *only* secret here, and it never leaves your machines. It goes into a `token` file with `chmod 600` (owner-only) or an env var. The `.gitignore` in this repo excludes `token` and all logs, so you can't accidentally commit them.
- Never paste your token into a chat, an issue, or a prompt. If a token ever leaks, reset it in the developer portal (Bot section, Reset Token) and update the file.
- The scripts make exactly one outbound TLS connection, to `wss://gateway.discord.gg`. They read nothing else on your system and need no admin rights after install.
- This uses a normal bot token (not a user token). Self-bots are against Discord's terms; this isn't one.

## Uninstall

**macOS:** `./uninstall.sh` (removes the LaunchAgent and `~/.discord-heartbeat` entirely).

**Windows:** delete `%USERPROFILE%\.discord-heartbeat` and remove `DiscordHeartbeat.bat` from `shell:startup`.

**Linux:** `systemctl --user disable --now discord-heartbeat`, then delete `~/.discord-heartbeat` and the service file.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Log repeats `no token` | Token file missing or empty | Re-run the `printf`/`Set-Content` step; check the path |
| `connected` then immediate `error`, looping | Two machines using the same shard (or no shard) | Give each machine its own `HEARTBEAT_SHARD_ID` with the same `HEARTBEAT_SHARD_COUNT` |
| Bot stays offline | Token invalid (was reset?) | Reset the token in the developer portal and update the file |
| macOS: `websockets` import error | Package installed for a different Python | `python3 -m pip install --user websockets` with the same `python3` that runs the script |

## For AI assistants

If you're an AI assistant (like Muse) reading this repo to set it up for your user, here is the exact contract:

- **Scripts:** `heartbeat.py` (macOS/Linux, needs `websockets`), `heartbeat.ps1` (Windows, no dependencies).
- **Token sources, in order:** `DISCORD_BOT_TOKEN` env var, then the `token` file (`~/.discord-heartbeat/token` on Unix, `%USERPROFILE%\.discord-heartbeat\token` on Windows). Never ask the user to paste the token into chat; have them write it to the file with the commands in this README.
- **Sharding:** env vars `HEARTBEAT_SHARD_ID` (default `0`) and `HEARTBEAT_SHARD_COUNT` (default `1`). The `shard` field is omitted from identify when count is 1. For N machines, assign ids `0..N-1` with count `N`.
- **macOS persistence:** `./install.sh [shard_id] [shard_count]` installs LaunchAgent `com.discord.heartbeat` (RunAtLoad + KeepAlive). Log: `~/.discord-heartbeat/keeper.log`.
- **Windows persistence:** `DiscordHeartbeat.bat` in `shell:startup` launching the `.ps1` hidden. Log: `%USERPROFILE%\.discord-heartbeat\keeper.log`.
- **Success looks like:** log line `gateway connected, bot is online` (Python) or `connected; heartbeat every` (PowerShell), and no `error`/`disconnected` lines after it. The bot then appears online in Discord whenever that machine is awake and logged in.
- **Safety:** do not commit tokens; the `.gitignore` covers `token` and `*.log`. Treat the token as a secret you must never see or repeat.

## License

MIT. See [LICENSE](LICENSE).
