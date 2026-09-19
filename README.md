# discord-heartbeat

a tiny heartbeat that keeps your discord bot online from your own machines. no server, no hosting, no bot process running anywhere.

most discord bots live on a vps that never sleeps, so presence is trivial. but some bots have no home at all: bots driven by an ai assistant (like [muse](https://muse.ai)) through the discord rest api, where no code runs on a schedule and nothing holds a connection open. this is the pulse for a bot like that.

run it on your laptop, your desktop, or both. while a machine is awake and you're logged in, the bot shows online. when every machine sleeps, it goes offline by itself.

## how it works

one small script per os (python on macos/linux, powershell on windows). it reads your bot token from a file, opens one discord gateway websocket with `intents: 0` (it receives nothing, it just exists), sends a heartbeat every ~41 seconds, and reconnects forever if anything drops.

~25mb ram on mac, ~100mb on windows (that's powershell itself), effectively zero cpu.

## use

you need a bot token. yours, from your own app: [discord.com/developers/applications](https://discord.com/developers/applications), bot section, reset token / copy. paste it into a file on your machine in the next step, never into a chat, never into this repo.

### macos

```sh
git clone https://github.com/javiergusart/discord-heartbeat.git
cd discord-heartbeat
./install.sh
printf '%s' 'YOUR_BOT_TOKEN' > ~/.discord-heartbeat/token && chmod 600 ~/.discord-heartbeat/token
```

the installer registers a launchagent (starts at login, restarts if it dies). the heartbeat picks up the token within a minute. check `~/.discord-heartbeat/keeper.log` for `gateway connected, bot is online`.

### windows

1. copy `heartbeat.ps1` to `%USERPROFILE%\.discord-heartbeat\heartbeat.ps1` (create the folder).
2. save your token:
   ```powershell
   Set-Content $env:USERPROFILE\.discord-heartbeat\token 'YOUR_BOT_TOKEN' -NoNewline
   ```
3. make it start at logon: `win+r`, type `shell:startup`, create `DiscordHeartbeat.bat`:
   ```bat
   @echo off
   start "" /min powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "%USERPROFILE%\.discord-heartbeat\heartbeat.ps1"
   ```
4. double-click the `.bat` once to start it now. check `%USERPROFILE%\.discord-heartbeat\keeper.log` for `connected; heartbeat every`.

### linux

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

## multiple machines

two machines can hold sessions for the same bot at once, as long as each identifies as a different shard. otherwise they fight over one session and knock each other off.

give each machine a shard id (0, 1, 2...) and use the same shard count everywhere. two machines: `0 of 2` and `1 of 2`.

- macos: `./install.sh 0 2` and `./install.sh 1 2`
- windows: add to the top of `DiscordHeartbeat.bat`:
  ```bat
  set HEARTBEAT_SHARD_ID=1
  set HEARTBEAT_SHARD_COUNT=2
  ```
- linux: uncomment and set the `Environment=` lines in `discord-heartbeat.service`

the scripts also accept `DISCORD_BOT_TOKEN` as an env var instead of the token file.

## security

your token is the only secret here and it never leaves your machines. `chmod 600` on the file, or use the env var. the `.gitignore` excludes `token` and all logs so you can't accidentally commit them. never paste your token into a chat or an issue; if one leaks, reset it in the developer portal.

the scripts make exactly one outbound tls connection, to `wss://gateway.discord.gg`. they read nothing else on your system and need no admin rights after install.

this uses a normal bot token (not a user token). self-bots are against discord's terms; this isn't one.

## uninstall

- macos: `./uninstall.sh`
- windows: delete `%USERPROFILE%\.discord-heartbeat` and remove `DiscordHeartbeat.bat` from `shell:startup`
- linux: `systemctl --user disable --now discord-heartbeat`, then delete `~/.discord-heartbeat` and the service file

## troubleshooting

- log repeats `no token`: token file missing or empty. re-run the `printf`/`Set-Content` step.
- `connected` then immediate `error`, looping: two machines on the same shard (or no shard). give each its own `HEARTBEAT_SHARD_ID` with the same `HEARTBEAT_SHARD_COUNT`.
- bot stays offline: token invalid (was it reset?). reset it in the developer portal and update the file.
- macos `websockets` import error: the package went to a different python. run `python3 -m pip install --user websockets` with the same `python3` that runs the script.

## for ai assistants

if you're an ai assistant reading this repo to set it up for your user, the contract:

- scripts: `heartbeat.py` (macos/linux, needs `websockets`), `heartbeat.ps1` (windows, no dependencies).
- token sources, in order: `DISCORD_BOT_TOKEN` env var, then the `token` file (`~/.discord-heartbeat/token` on unix, `%USERPROFILE%\.discord-heartbeat\token` on windows). never ask the user to paste the token into chat; have them write it to the file with the commands above.
- sharding: `HEARTBEAT_SHARD_ID` (default `0`), `HEARTBEAT_SHARD_COUNT` (default `1`). the `shard` field is omitted from identify when count is 1. for n machines, ids `0..n-1`, count `n`.
- macos persistence: `./install.sh [shard_id] [shard_count]` installs launchagent `com.discord.heartbeat` (runatload + keepalive). log: `~/.discord-heartbeat/keeper.log`.
- windows persistence: `DiscordHeartbeat.bat` in `shell:startup` launching the `.ps1` hidden. log: `%USERPROFILE%\.discord-heartbeat\keeper.log`.
- success: log line `gateway connected, bot is online` (python) or `connected; heartbeat every` (powershell), no `error`/`disconnected` after it.
- safety: never commit tokens; `.gitignore` covers `token` and `*.log`. treat the token as a secret you must never see or repeat.

## license

mit, see [LICENSE](./LICENSE).
