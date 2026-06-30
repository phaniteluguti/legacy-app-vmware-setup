<#
.SYNOPSIS
    Register DNS A (and optional PTR) records for every VM tracked in Terraform state.

.DESCRIPTION
    Reads the `dns_records` output (hostname => IPv4) and `dns_zone` output from the
    Terraform state, then registers each host in DNS. Idempotent: an existing A record
    for the same name is removed and re-created so the script can be re-run after redeploys.

    Three modes:
      * Windows DNS Server (default)  -> uses the DnsServer module against -DnsServer.
      * Hosts file                    -> -HostsFile <path> writes records instead of calling DNS.
      * Preview                       -> -WhatIf prints intended actions without changing anything.

    The DnsServer cmdlets require RSAT DNS tools on the machine running this script
    (Install-WindowsFeature RSAT-DNS-Server  /  Add-WindowsCapability -Online -Name Rsat.Dns.Tools~~~~0.0.1.0).

.PARAMETER DnsServer
    Hostname or IP of the Windows DNS server (typically the domain controller). Required unless -HostsFile is used.

.PARAMETER Zone
    DNS zone to register into. Defaults to the Terraform `dns_zone` output (vm_domain).

.PARAMETER TerraformDir
    Path to the Terraform working directory. Defaults to the parent of this script's folder.

.PARAMETER CreatePtr
    Also create reverse (PTR) records. The matching reverse lookup zone must already exist on the DNS server.

.PARAMETER HostsFile
    Instead of contacting a DNS server, append/refresh entries in the given hosts-style file.

.PARAMETER WhatIf
    Show what would be registered without making changes.

.EXAMPLE
    ./register-dns.ps1 -DnsServer 10.35.1.5 -Zone lab.local -CreatePtr

.EXAMPLE
    ./register-dns.ps1 -HostsFile C:\Windows\System32\drivers\etc\hosts
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$DnsServer,
    [string]$Zone,
    [string]$TerraformDir = (Split-Path -Parent $PSScriptRoot),
    [switch]$CreatePtr,
    [string]$HostsFile
)

$ErrorActionPreference = 'Stop'

function Get-TerraformOutput {
    param([Parameter(Mandatory)][string]$Name)
    Push-Location $TerraformDir
    try {
        $json = terraform output -json $Name 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) {
            throw "Could not read Terraform output '$Name'. Run 'terraform apply' first (cwd: $TerraformDir)."
        }
        return ($json | ConvertFrom-Json)
    }
    finally {
        Pop-Location
    }
}

# --- Load records + zone from Terraform state ---
$recordsObj = Get-TerraformOutput -Name 'dns_records'
$records = @{}
foreach ($p in $recordsObj.PSObject.Properties) {
    if (-not [string]::IsNullOrWhiteSpace($p.Value)) { $records[$p.Name] = $p.Value }
}

if ($records.Count -eq 0) {
    Write-Warning "No DNS records found in Terraform state. Nothing to do."
    return
}

if (-not $Zone) {
    try { $Zone = Get-TerraformOutput -Name 'dns_zone' } catch { }
    if (-not $Zone) { throw "No -Zone supplied and 'dns_zone' output is unavailable." }
}

Write-Host "Zone : $Zone" -ForegroundColor Cyan
Write-Host "Hosts: $($records.Count) record(s) from Terraform state" -ForegroundColor Cyan

# --- Normalize: strip any trailing zone from the hostname to get the short name ---
function Get-ShortName {
    param([string]$Name, [string]$Zone)
    $n = $Name.TrimEnd('.')
    if ($n.ToLower().EndsWith("." + $Zone.ToLower())) {
        $n = $n.Substring(0, $n.Length - $Zone.Length - 1)
    }
    return $n
}

# --- Hosts-file mode ----------------------------------------------------------
if ($HostsFile) {
    $marker = '# >>> terraform dns_records >>>'
    $endMk  = '# <<< terraform dns_records <<<'
    $lines = @($marker)
    foreach ($name in ($records.Keys | Sort-Object)) {
        $short = Get-ShortName -Name $name -Zone $Zone
        $fqdn  = "$short.$Zone"
        $lines += ("{0}`t{1} {2}" -f $records[$name], $fqdn, $short)
    }
    $lines += $endMk

    $existing = @()
    if (Test-Path $HostsFile) { $existing = Get-Content $HostsFile }
    # Drop any previous managed block
    $clean = @()
    $inBlock = $false
    foreach ($l in $existing) {
        if ($l -eq $marker) { $inBlock = $true; continue }
        if ($l -eq $endMk)  { $inBlock = $false; continue }
        if (-not $inBlock)  { $clean += $l }
    }
    $out = ($clean + $lines) -join "`r`n"
    if ($PSCmdlet.ShouldProcess($HostsFile, "Write $($records.Count) host entries")) {
        Set-Content -Path $HostsFile -Value $out -Encoding ASCII
        Write-Host "Wrote managed block to $HostsFile" -ForegroundColor Green
    }
    else {
        Write-Host "--- would write ---`n$($lines -join "`n")" -ForegroundColor Yellow
    }
    return
}

# --- Windows DNS Server mode --------------------------------------------------
if (-not $DnsServer) { throw "Provide -DnsServer (Windows DNS server) or use -HostsFile." }
if (-not (Get-Module -ListAvailable -Name DnsServer)) {
    throw "DnsServer module not found. Install RSAT DNS tools: Add-WindowsCapability -Online -Name Rsat.Dns.Tools~~~~0.0.1.0"
}
Import-Module DnsServer -ErrorAction Stop

foreach ($name in ($records.Keys | Sort-Object)) {
    $ip    = $records[$name]
    $short = Get-ShortName -Name $name -Zone $Zone
    $fqdn  = "$short.$Zone"

    # Remove any stale A record so re-runs stay idempotent.
    $existing = Get-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $Zone -Name $short -RRType A -ErrorAction SilentlyContinue
    foreach ($rec in $existing) {
        $curIp = $rec.RecordData.IPv4Address.IPAddressToString
        if ($curIp -eq $ip) { continue }  # already correct, leave it for the create-skip below
        if ($PSCmdlet.ShouldProcess($fqdn, "Remove stale A -> $curIp")) {
            Remove-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $Zone -InputObject $rec -Force
            Write-Host "  removed stale $fqdn -> $curIp" -ForegroundColor DarkYellow
        }
    }

    $stillCorrect = Get-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $Zone -Name $short -RRType A -ErrorAction SilentlyContinue |
        Where-Object { $_.RecordData.IPv4Address.IPAddressToString -eq $ip }
    if ($stillCorrect) {
        Write-Host ("  ok    {0,-22} -> {1}" -f $fqdn, $ip) -ForegroundColor DarkGray
        continue
    }

    $ptrNote = if ($CreatePtr) { ' (+PTR)' } else { '' }
    if ($PSCmdlet.ShouldProcess($fqdn, "Add A -> $ip$ptrNote")) {
        Add-DnsServerResourceRecordA -ComputerName $DnsServer -ZoneName $Zone -Name $short `
            -IPv4Address $ip -CreatePtr:$CreatePtr -ErrorAction Stop
        Write-Host ("  added {0,-22} -> {1}" -f $fqdn, $ip) -ForegroundColor Green
    }
    else {
        Write-Host ("  would add {0,-22} -> {1}" -f $fqdn, $ip) -ForegroundColor Yellow
    }
}

Write-Host "DNS registration complete." -ForegroundColor Cyan
