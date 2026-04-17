# =============================================================================
# Validate Azure Migrate database credentials FROM the appliance VM
#
# Zero external dependencies — uses raw .NET socket protocol-level auth
# testing for both PostgreSQL (MD5) and MySQL (native + caching_sha2).
# No psql.exe, mysql.exe, or choco required.
#
# Usage (run as Administrator on the appliance):
#   .\validate-db-creds.ps1 -User "azmigrateuser" -Password "YourPassword"
#
# Optional: test a single host
#   .\validate-db-creds.ps1 -User "azmigrateuser" -Password "YourPassword" -TargetHost "10.1.3.22"
# =============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$User,

    [Parameter(Mandatory=$true)]
    [string]$Password,

    [string]$TargetHost = ""
)

# ── Define your database hosts (from ansible/inventory/hosts.ini) ──
$pgHosts = @(
    # PostgreSQL Linux 1-tier (java_servers)
    @{ Name = "lin-java-1t-old";         IP = "10.1.2.7";  Port = 5432 }
    @{ Name = "lin-java-1t-new";         IP = "10.1.3.32"; Port = 5432 }
    # PostgreSQL Linux 3-tier (java_database)
    @{ Name = "lin-java-db-3t";          IP = "10.1.3.22"; Port = 5432 }
    # PostgreSQL Windows 1-tier (win_java_servers)
    @{ Name = "win-java-1t-old";         IP = "10.1.2.11"; Port = 5432 }
    @{ Name = "win-java-1t-new";         IP = "10.1.3.35"; Port = 5432 }
    # PostgreSQL Windows 3-tier (win_java_database)
    @{ Name = "win-java-db-3t-old";      IP = "10.1.3.13"; Port = 5432 }
    @{ Name = "win-java-db-3t-new";      IP = "10.1.3.25"; Port = 5432 }
)

$mysqlHosts = @(
    # MySQL Linux 1-tier (php_servers)
    @{ Name = "lin-php-1t-old";          IP = "10.1.2.9";  Port = 3306 }
    @{ Name = "lin-php-1t-new";          IP = "10.1.3.34"; Port = 3306 }
    # MySQL Linux 3-tier (php_database)
    @{ Name = "lin-php-db-3t";           IP = "10.1.3.31"; Port = 3306 }
    # MySQL Windows 1-tier (win_php_servers)
    @{ Name = "win-php-1t-old";          IP = "10.1.2.13"; Port = 3306 }
    @{ Name = "win-php-1t-new";          IP = "10.1.3.37"; Port = 3306 }
    # MySQL Windows 3-tier (win_php_database)
    @{ Name = "win-php-db-3t";           IP = "10.1.3.19"; Port = 3306 }
)

# ═══════════════════════════════════════════════════════════════════════════
# Helper functions
# ═══════════════════════════════════════════════════════════════════════════

function Test-TcpPort {
    param([string]$IP, [int]$Port, [int]$Timeout = 3)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ar  = $tcp.BeginConnect($IP, $Port, $null, $null)
        $ok  = $ar.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($Timeout))
        if ($ok) { $tcp.EndConnect($ar) }
        $tcp.Close()
        return $ok
    } catch { return $false }
}

function Read-StreamBytes {
    param([System.IO.Stream]$S, [int]$Count)
    $buf = New-Object byte[] $Count
    $off = 0
    while ($off -lt $Count) {
        $n = $S.Read($buf, $off, $Count - $off)
        if ($n -eq 0) { throw "Connection closed by remote host" }
        $off += $n
    }
    return ,$buf
}

function Get-PBKDF2SHA256 {
    param([byte[]]$Pw, [byte[]]$Salt, [int]$Iter)
    try {
        $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
            $Pw, $Salt, $Iter, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
        $r = $kdf.GetBytes(32); $kdf.Dispose(); return ,$r
    } catch {
        # Manual PBKDF2-HMAC-SHA256 fallback for older .NET
        $hm = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList @(,$Pw)
        $blk = New-Object byte[] ($Salt.Length + 4)
        [Array]::Copy($Salt, $blk, $Salt.Length); $blk[$blk.Length - 1] = 1
        $U = $hm.ComputeHash($blk); $dk = [byte[]]$U.Clone()
        for ($j = 1; $j -lt $Iter; $j++) {
            $U = $hm.ComputeHash($U)
            for ($k = 0; $k -lt 32; $k++) { $dk[$k] = $dk[$k] -bxor $U[$k] }
        }
        $hm.Dispose(); return ,$dk
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# PostgreSQL wire-protocol v3 auth test (MD5 + SCRAM-SHA-256)
# ═══════════════════════════════════════════════════════════════════════════

function Test-PgAuth {
    param([string]$IP, [int]$Port, [string]$User, [string]$Password)
    $tcp = $null
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect($IP, $Port)
        $st = $tcp.GetStream()
        $st.ReadTimeout  = 5000
        $st.WriteTimeout = 5000
        $enc = [System.Text.Encoding]::UTF8

        # ── Send StartupMessage (protocol 3.0) ──
        $body = New-Object System.IO.MemoryStream
        $ver  = [BitConverter]::GetBytes([int]196608); [Array]::Reverse($ver)
        $body.Write($ver, 0, 4)
        $prm = $enc.GetBytes("user`0$User`0database`0postgres`0`0")
        $body.Write($prm, 0, $prm.Length)
        $payload = $body.ToArray()
        $len = [BitConverter]::GetBytes([int]($payload.Length + 4)); [Array]::Reverse($len)
        $st.Write($len, 0, 4)
        $st.Write($payload, 0, $payload.Length)
        $st.Flush()

        # ── Read response ──
        $msgType = $st.ReadByte()
        if ($msgType -lt 0) { throw "Connection closed" }

        $lb = Read-StreamBytes $st 4; [Array]::Reverse($lb)
        $msgLen = [BitConverter]::ToInt32($lb, 0) - 4   # body length

        if ([char]$msgType -eq 'E') {
            $errBytes = Read-StreamBytes $st $msgLen
            $errStr   = $enc.GetString($errBytes)
            $parts    = $errStr -split "`0"
            $mField   = ($parts | Where-Object { $_.Length -gt 0 -and $_[0] -eq 'M' } | Select-Object -First 1)
            $msg      = if ($mField) { $mField.Substring(1) } else { "server error" }
            if ($errStr -match 'no pg_hba.conf entry') { $msg = "pg_hba.conf missing entry for appliance IP" }
            if ($errStr -match 'does not exist')       { $msg = "user '$User' does not exist" }
            return @{ OK=$false; Msg=$msg }
        }
        if ([char]$msgType -ne 'R') {
            return @{ OK=$false; Msg="unexpected response type: $([char]$msgType)" }
        }

        # Auth type
        $atb = Read-StreamBytes $st 4; [Array]::Reverse($atb)
        $authType  = [BitConverter]::ToInt32($atb, 0)
        $remaining = $msgLen - 4
        $extra = if ($remaining -gt 0) { Read-StreamBytes $st $remaining } else { @() }

        if ($authType -eq 0) { return @{ OK=$true; Msg="authenticated (trust)" } }
        if ($authType -eq 10) {
            # ── SCRAM-SHA-256 authentication ──
            $mechs = @(); $mp = 0
            while ($mp -lt $extra.Length) {
                $mn = [Array]::IndexOf($extra, [byte]0, $mp)
                if ($mn -lt 0 -or $mn -eq $mp) { break }
                $mechs += $enc.GetString($extra, $mp, $mn - $mp); $mp = $mn + 1
            }
            if ($mechs -notcontains "SCRAM-SHA-256") {
                return @{ OK=$false; Msg="no SCRAM-SHA-256 in offered mechanisms: $($mechs -join ', ')" }
            }

            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            $nonceBuf = New-Object byte[] 18; $rng.GetBytes($nonceBuf)
            $cNonce = [Convert]::ToBase64String($nonceBuf)

            $gs2 = "n,,"; $cfmBare = "n=$User,r=$cNonce"
            $cfm = "$gs2$cfmBare"; $cfmB = $enc.GetBytes($cfm)

            # Send SASLInitialResponse (type 'p')
            $sr = New-Object System.IO.MemoryStream
            $mechB = $enc.GetBytes("SCRAM-SHA-256`0"); $sr.Write($mechB, 0, $mechB.Length)
            $cl = [BitConverter]::GetBytes([int]$cfmB.Length); [Array]::Reverse($cl)
            $sr.Write($cl, 0, 4); $sr.Write($cfmB, 0, $cfmB.Length)
            $sp2 = $sr.ToArray()
            $st.WriteByte(112)
            $spl = [BitConverter]::GetBytes([int]($sp2.Length + 4)); [Array]::Reverse($spl)
            $st.Write($spl, 0, 4); $st.Write($sp2, 0, $sp2.Length); $st.Flush()

            # Read SASLContinue (R, subtype 11)
            $c1t = $st.ReadByte()
            if ($c1t -lt 0) { return @{ OK=$false; Msg="connection closed during SCRAM" } }
            $c1l = Read-StreamBytes $st 4; [Array]::Reverse($c1l)
            $c1Len = [BitConverter]::ToInt32($c1l, 0) - 4
            $c1d = if ($c1Len -gt 0) { Read-StreamBytes $st $c1Len } else { @() }

            if ([char]$c1t -eq 'E') {
                $eStr = $enc.GetString($c1d); $eParts = $eStr -split "`0"
                $eM = ($eParts | Where-Object { $_.Length -gt 0 -and $_[0] -eq 'M' } | Select-Object -First 1)
                $msg = if ($eM) { $eM.Substring(1) } else { "SCRAM error" }
                if ($eStr -match 'password authentication failed') { $msg = "wrong password" }
                if ($eStr -match 'does not exist') { $msg = "user '$User' does not exist" }
                return @{ OK=$false; Msg=$msg }
            }

            $c1sb = $c1d[0..3]; [Array]::Reverse($c1sb)
            if ([BitConverter]::ToInt32($c1sb, 0) -ne 11) {
                return @{ OK=$false; Msg="expected SASLContinue(11), got $([BitConverter]::ToInt32($c1sb, 0))" }
            }

            $sfm = $enc.GetString($c1d, 4, $c1d.Length - 4)
            $sfmParts = $sfm -split ','
            $cNonce2 = ($sfmParts | Where-Object { $_ -like 'r=*' } | Select-Object -First 1).Substring(2)
            $saltB64 = ($sfmParts | Where-Object { $_ -like 's=*' } | Select-Object -First 1).Substring(2)
            $iter    = [int]($sfmParts | Where-Object { $_ -like 'i=*' } | Select-Object -First 1).Substring(2)
            $scSalt  = [Convert]::FromBase64String($saltB64)

            if (-not $cNonce2.StartsWith($cNonce)) {
                return @{ OK=$false; Msg="server nonce mismatch" }
            }

            # Compute SCRAM proof
            $saltedPw = Get-PBKDF2SHA256 -Pw $enc.GetBytes($Password) -Salt $scSalt -Iter $iter

            $hmac1 = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList @(,$saltedPw)
            $clientKey = $hmac1.ComputeHash($enc.GetBytes("Client Key"))
            $serverKey = $hmac1.ComputeHash($enc.GetBytes("Server Key"))
            $hmac1.Dispose()

            $sha = [System.Security.Cryptography.SHA256]::Create()
            $storedKey = $sha.ComputeHash($clientKey)

            $cbind = [Convert]::ToBase64String($enc.GetBytes($gs2))
            $cfmNP = "c=$cbind,r=$cNonce2"
            $authMsg = "$cfmBare,$sfm,$cfmNP"

            $hmac2 = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList @(,$storedKey)
            $clientSig = $hmac2.ComputeHash($enc.GetBytes($authMsg)); $hmac2.Dispose()

            $proof = New-Object byte[] 32
            for ($pi = 0; $pi -lt 32; $pi++) { $proof[$pi] = $clientKey[$pi] -bxor $clientSig[$pi] }
            $cfmFinal = "$cfmNP,p=$([Convert]::ToBase64String($proof))"
            $cfmFinalB = $enc.GetBytes($cfmFinal)

            # Send SASLResponse (type 'p')
            $st.WriteByte(112)
            $fl = [BitConverter]::GetBytes([int]($cfmFinalB.Length + 4)); [Array]::Reverse($fl)
            $st.Write($fl, 0, 4); $st.Write($cfmFinalB, 0, $cfmFinalB.Length); $st.Flush()

            # Read SASLFinal (R, subtype 12) or Error
            $c2t = $st.ReadByte()
            $c2l = Read-StreamBytes $st 4; [Array]::Reverse($c2l)
            $c2Len = [BitConverter]::ToInt32($c2l, 0) - 4
            $c2d = if ($c2Len -gt 0) { Read-StreamBytes $st $c2Len } else { @() }

            if ([char]$c2t -eq 'E') {
                $eStr2 = $enc.GetString($c2d)
                if ($eStr2 -match 'password authentication failed') { return @{ OK=$false; Msg="wrong password" } }
                $eParts2 = $eStr2 -split "`0"
                $eM2 = ($eParts2 | Where-Object { $_.Length -gt 0 -and $_[0] -eq 'M' } | Select-Object -First 1)
                return @{ OK=$false; Msg=$(if ($eM2) { $eM2.Substring(1) } else { "SCRAM auth failed" }) }
            }

            $c2sb = $c2d[0..3]; [Array]::Reverse($c2sb)
            $c2st = [BitConverter]::ToInt32($c2sb, 0)
            if ($c2st -eq 12) {
                # SASLFinal received — read the following AuthOk
                $c3t = $st.ReadByte()
                $c3l = Read-StreamBytes $st 4; [Array]::Reverse($c3l)
                $c3Len = [BitConverter]::ToInt32($c3l, 0) - 4
                if ($c3Len -gt 0) { $null = Read-StreamBytes $st $c3Len }
                return @{ OK=$true; Msg="authenticated (scram-sha-256)" }
            }
            if ($c2st -eq 0) { return @{ OK=$true; Msg="authenticated (scram-sha-256)" } }
            return @{ OK=$false; Msg="unexpected SCRAM response subtype: $c2st" }
        }
        if ($authType -ne 5) {
            return @{ OK=$false; Msg="unsupported auth type: $authType" }
        }

        # ── MD5 auth (type 5) ──
        $salt = $extra[0..3]
        $md5  = [System.Security.Cryptography.MD5]::Create()
        $h1     = $md5.ComputeHash($enc.GetBytes($Password + $User))
        $h1hex  = -join ($h1 | ForEach-Object { $_.ToString("x2") })
        $h2     = $md5.ComputeHash([byte[]]($enc.GetBytes($h1hex) + $salt))
        $h2hex  = -join ($h2 | ForEach-Object { $_.ToString("x2") })
        $pwMsg  = $enc.GetBytes("md5$h2hex`0")

        # Send PasswordMessage
        $st.WriteByte(112) # 'p'
        $pl = [BitConverter]::GetBytes([int]($pwMsg.Length + 4)); [Array]::Reverse($pl)
        $st.Write($pl, 0, 4)
        $st.Write($pwMsg, 0, $pwMsg.Length)
        $st.Flush()

        # Read auth result
        $rt  = $st.ReadByte()
        $rlb = Read-StreamBytes $st 4; [Array]::Reverse($rlb)
        $rLen = [BitConverter]::ToInt32($rlb, 0) - 4
        $rData = if ($rLen -gt 0) { Read-StreamBytes $st $rLen } else { @() }

        if ([char]$rt -eq 'R' -and $rData.Length -ge 4) {
            $ra = $rData[0..3]; [Array]::Reverse($ra)
            if ([BitConverter]::ToInt32($ra, 0) -eq 0) {
                return @{ OK=$true; Msg="authenticated (md5)" }
            }
        }
        if ([char]$rt -eq 'E') {
            $eStr  = $enc.GetString($rData)
            $eParts = $eStr -split "`0"
            $eMsg   = ($eParts | Where-Object { $_.Length -gt 0 -and $_[0] -eq 'M' } | Select-Object -First 1)
            $msg    = if ($eMsg) { $eMsg.Substring(1) } else { "auth failed" }
            if ($eStr -match 'password authentication failed') { $msg = "wrong password" }
            return @{ OK=$false; Msg=$msg }
        }
        return @{ OK=$false; Msg="unexpected auth response" }
    }
    catch { return @{ OK=$false; Msg=$_.Exception.Message } }
    finally { if ($tcp) { $tcp.Close() } }
}

# ═══════════════════════════════════════════════════════════════════════════
# MySQL wire-protocol auth test (mysql_native_password + caching_sha2)
# ═══════════════════════════════════════════════════════════════════════════

function Read-MySqlPacket([System.IO.Stream]$S) {
    $hdr = Read-StreamBytes $S 4
    $payLen = [int]$hdr[0] + ([int]$hdr[1] -shl 8) + ([int]$hdr[2] -shl 16)
    $seq = [int]$hdr[3]
    $data = if ($payLen -gt 0) { Read-StreamBytes $S $payLen } else { [byte[]]@() }
    return @{ Seq=$seq; Data=$data }
}

function Write-MySqlPacket([System.IO.Stream]$S, [int]$SeqId, [byte[]]$Payload) {
    $len = $Payload.Length
    [byte[]]$hdr = @( ($len -band 0xFF), (($len -shr 8) -band 0xFF), (($len -shr 16) -band 0xFF), $SeqId )
    $S.Write($hdr, 0, 4)
    $S.Write($Payload, 0, $Payload.Length)
    $S.Flush()
}

function Test-MySqlAuth {
    param([string]$IP, [int]$Port, [string]$User, [string]$Password)
    $tcp = $null
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect($IP, $Port)
        $st = $tcp.GetStream()
        $st.ReadTimeout  = 5000
        $st.WriteTimeout = 5000
        $enc = [System.Text.Encoding]::UTF8

        # ── 1. Read server Initial Handshake ──
        $pkt = Read-MySqlPacket $st
        $d = $pkt.Data; $p = 0

        $protoVer = $d[$p]; $p++
        $nulIdx   = [Array]::IndexOf($d, [byte]0, $p)
        $serverVer = $enc.GetString($d, $p, $nulIdx - $p); $p = $nulIdx + 1
        $p += 4  # connection id

        # auth-plugin-data part 1 (8 bytes)
        $auth1 = New-Object byte[] 8
        [Array]::Copy($d, $p, $auth1, 0, 8); $p += 8
        $p++  # filler 0x00

        $capLow = [BitConverter]::ToUInt16($d, $p); $p += 2
        $p++  # charset
        $p += 2  # status flags
        $capHigh = [BitConverter]::ToUInt16($d, $p); $p += 2
        $caps = [uint32]$capLow -bor ([uint32]$capHigh -shl 16)

        $authDataLen = [int]$d[$p]; $p++
        $p += 10  # reserved

        # auth-plugin-data part 2
        $part2Len = [Math]::Max(13, $authDataLen - 8)
        $auth2 = New-Object byte[] $part2Len
        $copyLen2 = [Math]::Min($part2Len, $d.Length - $p)
        if ($copyLen2 -gt 0) { [Array]::Copy($d, $p, $auth2, 0, $copyLen2) }
        $p += $part2Len

        # auth plugin name
        $pluginName = ""
        if ($p -lt $d.Length) {
            $pe = [Array]::IndexOf($d, [byte]0, $p)
            if ($pe -lt 0) { $pe = $d.Length }
            $pluginName = $enc.GetString($d, $p, $pe - $p)
        }

        # Combine nonce: 8 from part1 + 12 from part2 = 20 bytes
        $nonce = New-Object byte[] 20
        [Array]::Copy($auth1, 0, $nonce, 0, 8)
        [Array]::Copy($auth2, 0, $nonce, 8, [Math]::Min(12, $auth2.Length))

        # ── 2. Compute auth scramble ──
        $usePlugin = if ($pluginName) { $pluginName } else { "mysql_native_password" }
        $authResp = $null

        if ($usePlugin -eq "mysql_native_password") {
            $sha1 = [System.Security.Cryptography.SHA1]::Create()
            $h1 = $sha1.ComputeHash($enc.GetBytes($Password))
            $h2 = $sha1.ComputeHash($h1)
            $h3 = $sha1.ComputeHash([byte[]]($nonce + $h2))
            $authResp = New-Object byte[] 20
            for ($i = 0; $i -lt 20; $i++) { $authResp[$i] = $h1[$i] -bxor $h3[$i] }
        }
        elseif ($usePlugin -eq "caching_sha2_password") {
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            $h1 = $sha256.ComputeHash($enc.GetBytes($Password))
            $h2 = $sha256.ComputeHash($h1)
            $h3 = $sha256.ComputeHash([byte[]]($h2 + $nonce))
            $authResp = New-Object byte[] 32
            for ($i = 0; $i -lt 32; $i++) { $authResp[$i] = $h1[$i] -bxor $h3[$i] }
        }
        else {
            return @{ OK=$false; Msg="unsupported plugin: $usePlugin"; Plugin=$usePlugin; Version=$serverVer }
        }

        # ── 3. Build & send HandshakeResponse41 ──
        $ms = New-Object System.IO.MemoryStream
        # Client capabilities: LONG_PW | PROTOCOL_41 | SECURE_CONN | PLUGIN_AUTH
        $clientCap = [uint32](0x01 -bor 0x200 -bor 0x8000 -bor 0x80000)
        $ms.Write([BitConverter]::GetBytes($clientCap), 0, 4)
        $ms.Write([BitConverter]::GetBytes([uint32]16777216), 0, 4) # max packet
        $ms.WriteByte(33) # charset utf8
        $ms.Write((New-Object byte[] 23), 0, 23) # reserved
        $userB = $enc.GetBytes($User); $ms.Write($userB, 0, $userB.Length); $ms.WriteByte(0)
        $ms.WriteByte([byte]$authResp.Length)
        $ms.Write($authResp, 0, $authResp.Length)
        $plugB = $enc.GetBytes($usePlugin); $ms.Write($plugB, 0, $plugB.Length); $ms.WriteByte(0)
        Write-MySqlPacket $st 1 $ms.ToArray()

        # ── 4. Read auth response ──
        $resp = Read-MySqlPacket $st
        $rd = $resp.Data
        $firstByte = $rd[0]

        # caching_sha2_password fast-auth flow
        if ($firstByte -eq 0x01 -and $usePlugin -eq "caching_sha2_password") {
            if ($rd.Length -ge 2 -and $rd[1] -eq 0x03) {
                $null = Read-MySqlPacket $st  # consume final OK
                return @{ OK=$true; Msg="authenticated (caching_sha2 fast-auth)"; Plugin=$usePlugin; Version=$serverVer }
            }
            if ($rd.Length -ge 2 -and $rd[1] -eq 0x04) {
                return @{ OK=$false; Msg="caching_sha2 full-auth required (needs TLS — Azure Migrate may not support this)"; Plugin=$usePlugin; Version=$serverVer }
            }
        }

        if ($firstByte -eq 0x00) {
            return @{ OK=$true; Msg="authenticated ($usePlugin)"; Plugin=$usePlugin; Version=$serverVer }
        }
        if ($firstByte -eq 0xFF) {
            $errCode = [BitConverter]::ToUInt16($rd, 1)
            $msgStart = 3
            if ($rd.Length -gt 3 -and [char]$rd[3] -eq '#') { $msgStart = 9 }
            $errMsg = $enc.GetString($rd, $msgStart, $rd.Length - $msgStart)
            if ($errMsg -match 'Access denied') {
                return @{ OK=$false; Msg="Access denied (wrong password or user doesn't exist)"; Plugin=$usePlugin; Version=$serverVer }
            }
            if ($errMsg -match 'is not allowed') {
                return @{ OK=$false; Msg="host not allowed (need user@'%')"; Plugin=$usePlugin; Version=$serverVer }
            }
            return @{ OK=$false; Msg="error ${errCode}: $errMsg"; Plugin=$usePlugin; Version=$serverVer }
        }
        if ($firstByte -eq 0xFE) {
            # Auth switch — server wants a different plugin
            $nulI = [Array]::IndexOf($rd, [byte]0, 1)
            if ($nulI -le 1) {
                return @{ OK=$false; Msg="malformed auth switch"; Plugin=""; Version=$serverVer }
            }
            $switchPlugin = $enc.GetString($rd, 1, $nulI - 1)

            # Extract new scramble (after plugin name NUL)
            $newAuth = New-Object byte[] ($rd.Length - $nulI - 1)
            if ($newAuth.Length -gt 0) { [Array]::Copy($rd, $nulI + 1, $newAuth, 0, $newAuth.Length) }
            # Strip trailing NUL
            if ($newAuth.Length -gt 0 -and $newAuth[$newAuth.Length - 1] -eq 0) {
                $newAuth = $newAuth[0..($newAuth.Length - 2)]
            }

            $switchResp = $null
            if ($switchPlugin -eq "mysql_native_password") {
                $sha1s = [System.Security.Cryptography.SHA1]::Create()
                $sw1 = $sha1s.ComputeHash($enc.GetBytes($Password))
                $sw2 = $sha1s.ComputeHash($sw1)
                $sw3 = $sha1s.ComputeHash([byte[]]($newAuth + $sw2))
                $switchResp = New-Object byte[] 20
                for ($i = 0; $i -lt 20; $i++) { $switchResp[$i] = $sw1[$i] -bxor $sw3[$i] }
            }
            elseif ($switchPlugin -eq "caching_sha2_password") {
                $sha2s = [System.Security.Cryptography.SHA256]::Create()
                $sw1 = $sha2s.ComputeHash($enc.GetBytes($Password))
                $sw2 = $sha2s.ComputeHash($sw1)
                $sw3 = $sha2s.ComputeHash([byte[]]($sw2 + $newAuth))
                $switchResp = New-Object byte[] 32
                for ($i = 0; $i -lt 32; $i++) { $switchResp[$i] = $sw1[$i] -bxor $sw3[$i] }
            }
            else {
                return @{ OK=$false; Msg="unsupported switch plugin: $switchPlugin"; Plugin=$switchPlugin; Version=$serverVer }
            }

            Write-MySqlPacket $st ($resp.Seq + 1) $switchResp
            $resp2 = Read-MySqlPacket $st
            $rd2 = $resp2.Data

            if ($rd2[0] -eq 0x00) {
                return @{ OK=$true; Msg="authenticated ($switchPlugin)"; Plugin=$switchPlugin; Version=$serverVer }
            }
            if ($rd2[0] -eq 0xFF) {
                $ec2 = [BitConverter]::ToUInt16($rd2, 1)
                $ms2 = 3; if ($rd2.Length -gt 3 -and [char]$rd2[3] -eq '#') { $ms2 = 9 }
                $em2 = $enc.GetString($rd2, $ms2, $rd2.Length - $ms2)
                if ($em2 -match 'Access denied') {
                    return @{ OK=$false; Msg="Access denied (wrong password)"; Plugin=$switchPlugin; Version=$serverVer }
                }
                return @{ OK=$false; Msg="error ${ec2}: $em2"; Plugin=$switchPlugin; Version=$serverVer }
            }
            if ($rd2[0] -eq 0x01 -and $switchPlugin -eq "caching_sha2_password") {
                if ($rd2.Length -ge 2 -and $rd2[1] -eq 0x03) {
                    $null = Read-MySqlPacket $st
                    return @{ OK=$true; Msg="authenticated (caching_sha2 fast-auth)"; Plugin=$switchPlugin; Version=$serverVer }
                }
                if ($rd2.Length -ge 2 -and $rd2[1] -eq 0x04) {
                    return @{ OK=$false; Msg="caching_sha2 full-auth needs TLS"; Plugin=$switchPlugin; Version=$serverVer }
                }
            }
            return @{ OK=$false; Msg="unexpected switch response: 0x$($rd2[0].ToString('X2'))"; Plugin=$switchPlugin; Version=$serverVer }
        }
        return @{ OK=$false; Msg="unexpected response: 0x$($firstByte.ToString('X2'))"; Plugin=$usePlugin; Version=$serverVer }
    }
    catch { return @{ OK=$false; Msg=$_.Exception.Message; Plugin=""; Version="" } }
    finally { if ($tcp) { $tcp.Close() } }
}

# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

$passCount = 0; $failCount = 0

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Azure Migrate DB Credential Validator" -ForegroundColor Cyan
Write-Host " (protocol-level — no CLI tools needed)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "User: $User"
Write-Host "Appliance: $env:COMPUTERNAME ($((Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' } | Select-Object -First 1).IPAddress))`n"

# ── Test PostgreSQL ──
Write-Host "--- PostgreSQL (port 5432) ---" -ForegroundColor Yellow
foreach ($h in $pgHosts) {
    if ($TargetHost -and $h.IP -ne $TargetHost) { continue }
    Write-Host -NoNewline "  $($h.Name) ($($h.IP)):  "

    if (-not (Test-TcpPort -IP $h.IP -Port $h.Port)) {
        Write-Host "FAIL - port $($h.Port) unreachable (firewall/VM down)" -ForegroundColor Red
        $failCount++; continue
    }

    $r = Test-PgAuth -IP $h.IP -Port $h.Port -User $User -Password $Password
    if ($r.OK) {
        Write-Host "PASS - $($r.Msg)" -ForegroundColor Green
        $passCount++
    } else {
        Write-Host "FAIL - $($r.Msg)" -ForegroundColor Red
        $failCount++
    }
}

# ── Test MySQL ──
Write-Host "`n--- MySQL (port 3306) ---" -ForegroundColor Yellow
foreach ($h in $mysqlHosts) {
    if ($TargetHost -and $h.IP -ne $TargetHost) { continue }
    Write-Host -NoNewline "  $($h.Name) ($($h.IP)):  "

    if (-not (Test-TcpPort -IP $h.IP -Port $h.Port)) {
        Write-Host "FAIL - port $($h.Port) unreachable (firewall/VM down)" -ForegroundColor Red
        $failCount++; continue
    }

    $r = Test-MySqlAuth -IP $h.IP -Port $h.Port -User $User -Password $Password
    $detail = ""
    if ($r.Version) { $detail = " [MySQL $($r.Version), $($r.Plugin)]" }
    if ($r.OK) {
        Write-Host "PASS - $($r.Msg)$detail" -ForegroundColor Green
        $passCount++
    } else {
        Write-Host "FAIL - $($r.Msg)$detail" -ForegroundColor Red
        $failCount++
    }
}

# ── Summary ──
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Results: $passCount PASS, $failCount FAIL (of $($passCount + $failCount) tested)" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })
if ($failCount -gt 0) {
    Write-Host " Fix FAIL items, then refresh Azure Migrate." -ForegroundColor Cyan
} else {
    Write-Host " All clear — refresh discovery in Azure Migrate." -ForegroundColor Green
}
Write-Host "========================================`n" -ForegroundColor Cyan
