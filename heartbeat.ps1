# discord-heartbeat (windows).
# a tiny heartbeat that holds a discord gateway connection open so your bot
# appears online whenever this pc is awake and you're logged in.
# auto-reconnects forever. no server, no hosting, pure .net (no installs).
#
# it exists for bots with no home: bots driven by an ai assistant (like muse)
# through the discord rest api, where there is no bot process running
# anywhere to hold presence. this script is the pulse.
#
# token: $env:USERPROFILE\.discord-heartbeat\token  (or $env:DISCORD_BOT_TOKEN)
# logs:  $env:USERPROFILE\.discord-heartbeat\keeper.log
#
# multiple machines: give each machine its own shard so their sessions never
# fight. set $env:HEARTBEAT_SHARD_ID and $env:HEARTBEAT_SHARD_COUNT.

$ErrorActionPreference = "Stop"
$base = Join-Path $env:USERPROFILE ".discord-heartbeat"
$tokenFile = Join-Path $base "token"
$logFile = Join-Path $base "keeper.log"
$gateway = "wss://gateway.discord.gg/?v=10&encoding=json"

$shardId = if ($env:HEARTBEAT_SHARD_ID) { [int]$env:HEARTBEAT_SHARD_ID } else { 0 }
$shardCount = if ($env:HEARTBEAT_SHARD_COUNT) { [int]$env:HEARTBEAT_SHARD_COUNT } else { 1 }

function Write-KeeperLog($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    try { Add-Content -Path $logFile -Value $line } catch {}
}

function Get-KeeperToken {
    if ($env:DISCORD_BOT_TOKEN) { return $env:DISCORD_BOT_TOKEN.Trim() }
    if (Test-Path $tokenFile) {
        $t = (Get-Content $tokenFile -Raw).Trim()
        if ($t) { return $t }
    }
    return $null
}

function Send-WsJson($ws, $obj) {
    $json = ConvertTo-Json $obj -Depth 10 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $seg = New-Object System.ArraySegment[byte] (, $bytes)
    $ct = [System.Threading.CancellationToken]::None
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
}

function Read-WsHello($ws, $seg, $buf) {
    # single outstanding receive for the hello frame (tiny, one frame).
    $ct = [System.Threading.CancellationToken]::None
    $task = $ws.ReceiveAsync($seg, $ct)
    if (-not $task.Wait(15000)) { throw "no hello from gateway" }
    $res = $task.Result
    if ($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { throw "gateway closed during hello" }
    return [System.Text.Encoding]::UTF8.GetString($buf, 0, $res.Count)
}

function Handle-WsMessage($msg, [ref]$seq) {
    $data = $msg | ConvertFrom-Json
    if ($null -ne $data.s) { $seq.Value = $data.s }
    if ($data.op -eq 9) { throw "invalid session" }
    if ($data.op -eq 7) { throw "server asked to reconnect" }
}

New-Item -ItemType Directory -Force $base | Out-Null
Write-KeeperLog "presence keeper starting"

while ($true) {
    $token = Get-KeeperToken
    if (-not $token) {
        Write-KeeperLog "no token: put the bot token in $tokenFile (or set DISCORD_BOT_TOKEN); retrying in 60s"
        Start-Sleep 60
        continue
    }
    try {
        $ws = New-Object System.Net.WebSockets.ClientWebSocket
        if (-not $ws.ConnectAsync($gateway, [System.Threading.CancellationToken]::None).Wait(20000)) {
            throw "gateway connect timed out after 20s"
        }
        $buf = New-Object byte[] 65536
        $seg = New-Object System.ArraySegment[byte] (, $buf)
        $ct = [System.Threading.CancellationToken]::None

        $helloRaw = Read-WsHello $ws $seg $buf
        $interval = ($helloRaw | ConvertFrom-Json).d.heartbeat_interval
        $d = @{
            token = $token
            intents = 0
            properties = @{ os = "windows"; browser = "discord-heartbeat"; device = "discord-heartbeat" }
            presence = @{ status = "online"; afk = $false; activities = @(); since = 0 }
        }
        if ($shardCount -gt 1) {
            # distinct shards let several machines hold sessions at once.
            $d.shard = @($shardId, $shardCount)
        }
        Send-WsJson $ws @{ op = 2; d = $d }
        $seq = $null
        $nextBeat = [DateTime]::UtcNow.AddMilliseconds($interval)
        Write-KeeperLog "connected; heartbeat every ${interval}ms"

        # one outstanding ReceiveAsync at a time: keep the same task pending
        # across loop iterations; only start a new one after it completes.
        # (two overlapping receives throw InvalidOperationException.)
        $sb = New-Object System.Text.StringBuilder
        $recvTask = $ws.ReceiveAsync($seg, $ct)
        while ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            if ([DateTime]::UtcNow -ge $nextBeat) {
                Send-WsJson $ws @{ op = 1; d = $seq }
                $nextBeat = [DateTime]::UtcNow.AddMilliseconds($interval)
            }
            if ($recvTask.Wait(250)) {
                $res = $recvTask.Result
                if ($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { break }
                $sb.Append([System.Text.Encoding]::UTF8.GetString($buf, 0, $res.Count)) | Out-Null
                if ($res.EndOfMessage) {
                    $msg = $sb.ToString()
                    $sb.Length = 0
                    Handle-WsMessage $msg ([ref]$seq)
                }
                $recvTask = $ws.ReceiveAsync($seg, $ct)
            }
        }
        try { $ws.Dispose() } catch {}
        Write-KeeperLog "disconnected; reconnecting in 5s"
    } catch {
        Write-KeeperLog "error: $($_.Exception.Message); retrying in 5s"
    }
    Start-Sleep 5
}
