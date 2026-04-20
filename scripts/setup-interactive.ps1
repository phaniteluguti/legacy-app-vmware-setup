# =============================================================================
# setup-interactive.ps1 — Interactive wizard that collects all inputs,
# generates terraform.tfvars + ansible group_vars, then runs the full pipeline
# =============================================================================
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Get-Location) }
$TfDir      = Join-Path $ProjectRoot "terraform"
$AnsibleDir = Join-Path $ProjectRoot "ansible"
$ScriptsDir = Join-Path $ProjectRoot "scripts"
$TfVarsFile = Join-Path $TfDir "terraform.tfvars"
$AllVarsFile = Join-Path $AnsibleDir "group_vars" "all.yml"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Header($text) {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step($text) {
    Write-Host "  >> $text" -ForegroundColor Green
}

function Write-Warn($text) {
    Write-Host "  [WARN] $text" -ForegroundColor Yellow
}

function Prompt-Input($prompt, $default) {
    if ($default) {
        $val = Read-Host "  $prompt [$default]"
        if ([string]::IsNullOrWhiteSpace($val)) { return $default }
        return $val.Trim()
    }
    else {
        do {
            $val = Read-Host "  $prompt"
        } while ([string]::IsNullOrWhiteSpace($val))
        return $val.Trim()
    }
}

function Prompt-SecureInput($prompt) {
    do {
        $secure = Read-Host "  $prompt" -AsSecureString
        $plain  = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    } while ([string]::IsNullOrWhiteSpace($plain))
    return $plain
}

function Prompt-YesNo($prompt, $default = "y") {
    $val = Read-Host "  $prompt [$(if($default -eq 'y'){'Y/n'}else{'y/N'})]"
    if ([string]::IsNullOrWhiteSpace($val)) { $val = $default }
    return $val.Trim().ToLower() -eq "y"
}

function Prompt-Choice($prompt, $options, $default) {
    Write-Host "  $prompt"
    for ($i = 0; $i -lt $options.Count; $i++) {
        $marker = if ($options[$i] -eq $default) { " (default)" } else { "" }
        Write-Host "    [$($i+1)] $($options[$i])$marker" -ForegroundColor Gray
    }
    $val = Read-Host "  Enter choice [1-$($options.Count)]"
    if ([string]::IsNullOrWhiteSpace($val)) { return $default }
    $idx = [int]$val - 1
    if ($idx -ge 0 -and $idx -lt $options.Count) { return $options[$idx] }
    return $default
}

function Test-IpAddress($ip) {
    return $ip -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$'
}

function Prompt-Ip($prompt, $default) {
    do {
        $ip = Prompt-Input $prompt $default
        if (-not (Test-IpAddress $ip)) {
            Write-Host "    Invalid IP format. Try again." -ForegroundColor Red
            $ip = $null
        }
    } while (-not $ip)
    return $ip
}

# ---------------------------------------------------------------------------
# Prerequisite check
# ---------------------------------------------------------------------------
function Test-Prerequisites {
    Write-Header "Checking Prerequisites"
    $missing = @()

    foreach ($cmd in @("terraform", "ansible-playbook", "ssh")) {
        if (Get-Command $cmd -ErrorAction SilentlyContinue) {
            Write-Step "$cmd ... found"
        }
        else {
            Write-Host "  [MISS] $cmd ... NOT found" -ForegroundColor Red
            $missing += $cmd
        }
    }

    if ($missing.Count -gt 0) {
        Write-Host ""
        Write-Host "  Missing tools: $($missing -join ', ')" -ForegroundColor Red
        Write-Host "  Please install them and re-run." -ForegroundColor Red
        Write-Host ""
        Write-Host "  Install hints:" -ForegroundColor Yellow
        Write-Host "    terraform      -> https://developer.hashicorp.com/terraform/install" -ForegroundColor Gray
        Write-Host "    ansible        -> pip install ansible  (or via WSL)" -ForegroundColor Gray
        Write-Host "    ssh            -> built into Windows 10+, or install OpenSSH" -ForegroundColor Gray
        exit 1
    }
    Write-Step "All prerequisites met."
}

# ---------------------------------------------------------------------------
# Load previous values from saved config files
# ---------------------------------------------------------------------------
function Get-TfValue($key, $fallback) {
    if (Test-Path $TfVarsFile) {
        $line = Get-Content $TfVarsFile | Where-Object { $_ -match "^${key}\s*=" } | Select-Object -First 1
        if ($line) {
            $val = ($line -split '=', 2)[1].Trim().Trim('"')
            if ($val -ne "") { return $val }
        }
    }
    return $fallback
}

function Get-YmlValue($key, $fallback) {
    if (Test-Path $AllVarsFile) {
        $line = Get-Content $AllVarsFile | Where-Object { $_ -match "^${key}:" } | Select-Object -First 1
        if ($line) {
            $val = ($line -split ':', 2)[1].Trim().Trim('"')
            if ($val -ne "") { return $val }
        }
    }
    return $fallback
}

function Load-PreviousValues {
    # Initialize all defaults
    $script:prev = @{}
    $script:prev.vsphere_server = ""; $script:prev.vsphere_user = "administrator@vsphere.local"
    $script:prev.vsphere_ssl = "true"
    $script:prev.vsphere_datacenter = "Datacenter1"; $script:prev.vsphere_cluster = "Cluster1"
    $script:prev.vsphere_datastore = "datastore1"; $script:prev.vsphere_network = "VM Network"
    $script:prev.vsphere_folder = ""; $script:prev.vm_template_name = "ubuntu-2204-template"
    $script:prev.vm_gateway = "192.168.1.1"; $script:prev.vm_netmask = "24"
    $script:prev.vm_domain = "lab.local"; $script:prev.vm_dns = "8.8.8.8,8.8.4.4"
    $script:prev.vm_ssh_user = "ubuntu"; $script:prev.vm_ssh_auth_method = "password"
    $script:prev.vm_ssh_private_key_path = ""
    $script:prev.java_vm_ip = "192.168.1.101"; $script:prev.java_vm_cpus = "2"
    $script:prev.java_vm_memory = "4096"; $script:prev.java_vm_disk = "40"
    $script:prev.dotnet_vm_ip = "192.168.1.102"; $script:prev.dotnet_vm_cpus = "2"
    $script:prev.dotnet_vm_memory = "4096"; $script:prev.dotnet_vm_disk = "40"
    $script:prev.php_vm_ip = "192.168.1.103"; $script:prev.php_vm_cpus = "2"
    $script:prev.php_vm_memory = "2048"; $script:prev.php_vm_disk = "30"
    $script:prev.petclinic_repo = "https://github.com/oreakinodidi98/AKS_APP_Mod_Demo"
    $script:prev.petclinic_branch = "main"; $script:prev.java_version = "21"
    $script:prev.dotnet_sdk_version = "6.0"
    $script:prev.dotnet_app_repo = "https://github.com/dotnet/eShop.git"
    $script:prev.dotnet_app_branch = "main"
    $script:prev.php_version = "8.1"
    $script:prev.php_app_repo = "https://github.com/laravel/laravel.git"
    $script:prev.php_app_branch = "10.x"
    $script:prev.install_azure_migrate_agent = "false"

    if (Test-Path $TfVarsFile) {
        Write-Step "Found previous config: terraform.tfvars - loading as defaults"
        $script:prev.vsphere_server = Get-TfValue "vsphere_server" ""
        $script:prev.vsphere_user = Get-TfValue "vsphere_user" "administrator@vsphere.local"
        $script:prev.vsphere_ssl = Get-TfValue "vsphere_allow_unverified_ssl" "true"
        $script:prev.vsphere_datacenter = Get-TfValue "vsphere_datacenter" "Datacenter1"
        $script:prev.vsphere_cluster = Get-TfValue "vsphere_cluster" "Cluster1"
        $script:prev.vsphere_datastore = Get-TfValue "vsphere_datastore" "datastore1"
        $script:prev.vsphere_network = Get-TfValue "vsphere_network" "VM Network"
        $script:prev.vsphere_folder = Get-TfValue "vsphere_folder" ""
        $script:prev.vm_template_name = Get-TfValue "vm_template_name" "ubuntu-2204-template"
        $script:prev.vm_gateway = Get-TfValue "vm_gateway" "192.168.1.1"
        $script:prev.vm_netmask = Get-TfValue "vm_netmask" "24"
        $script:prev.vm_domain = Get-TfValue "vm_domain" "lab.local"
        $dnsLine = Get-Content $TfVarsFile | Where-Object { $_ -match "^vm_dns_servers" } | Select-Object -First 1
        if ($dnsLine) {
            $raw = ($dnsLine -replace '.*\[','') -replace '\].*','' -replace '"','' -replace ' ',''
            if ($raw) { $script:prev.vm_dns = $raw }
        }
        $script:prev.vm_ssh_user = Get-TfValue "vm_ssh_user" "ubuntu"
        $script:prev.vm_ssh_auth_method = Get-TfValue "vm_ssh_auth_method" "password"
        $script:prev.vm_ssh_private_key_path = Get-TfValue "vm_ssh_private_key_path" ""
        $script:prev.java_vm_ip = Get-TfValue "java_vm_ip" "192.168.1.101"
        $script:prev.java_vm_cpus = Get-TfValue "java_vm_cpus" "2"
        $script:prev.java_vm_memory = Get-TfValue "java_vm_memory" "4096"
        $script:prev.java_vm_disk = Get-TfValue "java_vm_disk" "40"
        $script:prev.dotnet_vm_ip = Get-TfValue "dotnet_vm_ip" "192.168.1.102"
        $script:prev.dotnet_vm_cpus = Get-TfValue "dotnet_vm_cpus" "2"
        $script:prev.dotnet_vm_memory = Get-TfValue "dotnet_vm_memory" "4096"
        $script:prev.dotnet_vm_disk = Get-TfValue "dotnet_vm_disk" "40"
        $script:prev.php_vm_ip = Get-TfValue "php_vm_ip" "192.168.1.103"
        $script:prev.php_vm_cpus = Get-TfValue "php_vm_cpus" "2"
        $script:prev.php_vm_memory = Get-TfValue "php_vm_memory" "2048"
        $script:prev.php_vm_disk = Get-TfValue "php_vm_disk" "30"
    }

    if (Test-Path $AllVarsFile) {
        Write-Step "Found previous config: group_vars/all.yml - loading as defaults"
        $script:prev.petclinic_repo = Get-YmlValue "petclinic_repo" "https://github.com/oreakinodidi98/AKS_APP_Mod_Demo"
        $script:prev.petclinic_branch = Get-YmlValue "petclinic_branch" "main"
        $script:prev.java_version = Get-YmlValue "java_version" "21"
        $script:prev.dotnet_sdk_version = Get-YmlValue "dotnet_sdk_version" "6.0"
        $script:prev.dotnet_app_repo = Get-YmlValue "dotnet_app_repo" "https://github.com/dotnet/eShop.git"
        $script:prev.dotnet_app_branch = Get-YmlValue "dotnet_app_branch" "main"
        $script:prev.php_version = Get-YmlValue "php_version" "8.1"
        $script:prev.php_app_repo = Get-YmlValue "php_app_repo" "https://github.com/laravel/laravel.git"
        $script:prev.php_app_branch = Get-YmlValue "php_app_branch" "10.x"
        $script:prev.install_azure_migrate_agent = Get-YmlValue "install_azure_migrate_agent" "false"
    }
}

# ---------------------------------------------------------------------------
# Section 1: vCenter Connection
# ---------------------------------------------------------------------------
function Get-VCenterDetails {
    Write-Header "Step 1/6 — vCenter Connection"

    $defaultServer = $script:prev.vsphere_server
    if ($defaultServer) {
        $script:vsphere_server = Prompt-Input "vCenter Server FQDN or IP" $defaultServer
    } else {
        $script:vsphere_server = Prompt-Input "vCenter Server FQDN or IP"
    }
    $script:vsphere_user     = Prompt-Input "vCenter Username" $script:prev.vsphere_user
    $script:vsphere_password = Prompt-SecureInput "vCenter Password"
    $defaultSsl = if ($script:prev.vsphere_ssl -eq "true") { "y" } else { "n" }
    $script:vsphere_allow_unverified_ssl = Prompt-YesNo "Allow unverified SSL certificates?" $defaultSsl
}

# ---------------------------------------------------------------------------
# Section 2: vSphere Infrastructure
# ---------------------------------------------------------------------------
function Get-VSphereInfra {
    Write-Header "Step 2/6 — vSphere Infrastructure"
    Write-Host "  These names must match your vCenter inventory exactly." -ForegroundColor Gray
    Write-Host ""

    $script:vsphere_datacenter = Prompt-Input "Datacenter name" $script:prev.vsphere_datacenter
    $script:vsphere_cluster    = Prompt-Input "Compute Cluster name" $script:prev.vsphere_cluster
    $script:vsphere_datastore  = Prompt-Input "Datastore name" $script:prev.vsphere_datastore
    $script:vsphere_network    = Prompt-Input "Network / Port Group name" $script:prev.vsphere_network
    $script:vsphere_folder     = Prompt-Input "VM Folder (leave blank for root)" $script:prev.vsphere_folder
    $script:vm_template_name   = Prompt-Input "Ubuntu 22.04 VM Template name" $script:prev.vm_template_name
}

# ---------------------------------------------------------------------------
# Section 3: Network Settings
# ---------------------------------------------------------------------------
function Get-NetworkSettings {
    Write-Header "Step 3/6 — VM Network Settings"

    $script:vm_gateway   = Prompt-Ip "Default Gateway IP" $script:prev.vm_gateway
    $script:vm_netmask   = Prompt-Input "Subnet mask (CIDR bits)" $script:prev.vm_netmask
    $script:vm_domain    = Prompt-Input "Domain suffix" $script:prev.vm_domain

    $dnsInput = Prompt-Input "DNS Servers (comma-separated)" $script:prev.vm_dns
    $script:vm_dns_servers = ($dnsInput -split ',').Trim()

    $script:vm_ssh_user = Prompt-Input "SSH username in template" $script:prev.vm_ssh_user

    # SSH auth method
    Write-Host ""
    Write-Host "    How will Ansible connect to the VMs?" -ForegroundColor Yellow
    Write-Host "      1) SSH key (public key baked into template)" -ForegroundColor Gray
    Write-Host "      2) SSH password (simpler - no key needed in template)" -ForegroundColor Gray
    $defaultAuth = if ($script:prev.vm_ssh_auth_method -eq "key") { "1" } else { "2" }
    $authChoice = Prompt-Input "Choose [1/2]" $defaultAuth

    if ($authChoice -eq "1") {
        $script:vm_ssh_auth_method = "key"
        $script:vm_ssh_password = ""
        $defaultKey = if ($script:prev.vm_ssh_private_key_path) { $script:prev.vm_ssh_private_key_path } else { Join-Path $env:USERPROFILE ".ssh\id_rsa" }
        $script:vm_ssh_private_key_path = Prompt-Input "SSH private key path" $defaultKey
        if (-not (Test-Path $script:vm_ssh_private_key_path)) {
            Write-Warn "Key file not found at: $($script:vm_ssh_private_key_path)"
            if (-not (Prompt-YesNo "Continue anyway?")) { exit 1 }
        }
    }
    else {
        $script:vm_ssh_auth_method = "password"
        $script:vm_ssh_private_key_path = ""
        $script:vm_ssh_password = Prompt-SecureInput "SSH password for user '$($script:vm_ssh_user)'"
    }
}

# ---------------------------------------------------------------------------
# Section 4: VM Sizing & IPs
# ---------------------------------------------------------------------------
function Get-VMSettings {
    Write-Header "Step 4/6 — VM Sizing & IP Addresses"
    Write-Host "  Provide static IPs on the same subnet as your gateway ($($script:vm_gateway))." -ForegroundColor Gray
    Write-Host ""

    # Java VM
    Write-Host "  --- Java VM (Spring PetClinic + PostgreSQL) ---" -ForegroundColor Yellow
    $script:java_vm_ip     = Prompt-Ip   "  IP Address" $script:prev.java_vm_ip
    $script:java_vm_cpus   = Prompt-Input "  CPUs" $script:prev.java_vm_cpus
    $script:java_vm_memory = Prompt-Input "  Memory (MB)" $script:prev.java_vm_memory
    $script:java_vm_disk   = Prompt-Input "  Disk (GB)" $script:prev.java_vm_disk

    Write-Host ""
    Write-Host "  --- .NET VM (ASP.NET Core + SQL Server) ---" -ForegroundColor Yellow
    $script:dotnet_vm_ip     = Prompt-Ip   "  IP Address" $script:prev.dotnet_vm_ip
    $script:dotnet_vm_cpus   = Prompt-Input "  CPUs" $script:prev.dotnet_vm_cpus
    $script:dotnet_vm_memory = Prompt-Input "  Memory (MB)" $script:prev.dotnet_vm_memory
    $script:dotnet_vm_disk   = Prompt-Input "  Disk (GB)" $script:prev.dotnet_vm_disk

    Write-Host ""
    Write-Host "  --- PHP VM (Laravel + MySQL) ---" -ForegroundColor Yellow
    $script:php_vm_ip     = Prompt-Ip   "  IP Address" $script:prev.php_vm_ip
    $script:php_vm_cpus   = Prompt-Input "  CPUs" $script:prev.php_vm_cpus
    $script:php_vm_memory = Prompt-Input "  Memory (MB)" $script:prev.php_vm_memory
    $script:php_vm_disk   = Prompt-Input "  Disk (GB)" $script:prev.php_vm_disk
}

# ---------------------------------------------------------------------------
# Section 5: Application & Database Settings
# ---------------------------------------------------------------------------
function Get-AppSettings {
    Write-Header "Step 5/6 — Application & Database Configuration"

    # Java / PetClinic
    Write-Host "  --- Java / Spring PetClinic ---" -ForegroundColor Yellow
    $script:petclinic_repo   = Prompt-Input "  PetClinic Git repo URL" $script:prev.petclinic_repo
    $script:petclinic_branch = Prompt-Input "  Branch" $script:prev.petclinic_branch
    $script:java_version     = Prompt-Input "  JDK version" $script:prev.java_version
    $script:postgres_password= Prompt-SecureInput "  PostgreSQL password for 'petclinic' user"

    Write-Host ""
    Write-Host "  --- .NET / ASP.NET Core ---" -ForegroundColor Yellow
    $script:dotnet_sdk_version = Prompt-Input "  .NET SDK version" $script:prev.dotnet_sdk_version
    $script:dotnet_app_repo    = Prompt-Input "  .NET app Git repo URL" $script:prev.dotnet_app_repo
    $script:dotnet_app_branch  = Prompt-Input "  Branch" $script:prev.dotnet_app_branch
    $script:mssql_sa_password  = Prompt-SecureInput "  SQL Server SA password (min 8 chars, needs complexity)"

    Write-Host ""
    Write-Host "  --- PHP / Laravel ---" -ForegroundColor Yellow
    $script:php_version       = Prompt-Input "  PHP version" $script:prev.php_version
    $script:php_app_repo      = Prompt-Input "  Laravel Git repo URL" $script:prev.php_app_repo
    $script:php_app_branch    = Prompt-Input "  Branch" $script:prev.php_app_branch
    $script:mysql_root_password = Prompt-SecureInput "  MySQL root password"
    $script:mysql_db_password   = Prompt-SecureInput "  MySQL app user ('laravel') password"
}

# ---------------------------------------------------------------------------
# Section 6: Azure Migrate Options
# ---------------------------------------------------------------------------
function Get-MigrateOptions {
    Write-Header "Step 6/6 — Azure Migrate Options"

    $defaultMigrate = if ($script:prev.install_azure_migrate_agent -eq "true") { "y" } else { "n" }
    $script:install_azure_migrate_agent = Prompt-YesNo "Install Azure Migrate Dependency Agent on all VMs?" $defaultMigrate
}

# ---------------------------------------------------------------------------
# Generate terraform.tfvars
# ---------------------------------------------------------------------------
function Write-TerraformVars {
    Write-Step "Generating terraform/terraform.tfvars ..."

    $sslVal = if ($script:vsphere_allow_unverified_ssl) { "true" } else { "false" }
    $dnsArr = ($script:vm_dns_servers | ForEach-Object { "`"$_`"" }) -join ", "

    $content = @"
# =============================================================================
# Auto-generated by setup-interactive.ps1 on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# =============================================================================

# vCenter Connection
vsphere_server               = "$($script:vsphere_server)"
vsphere_user                 = "$($script:vsphere_user)"
vsphere_password             = "$($script:vsphere_password)"
vsphere_allow_unverified_ssl = $sslVal

# vSphere Infrastructure
vsphere_datacenter = "$($script:vsphere_datacenter)"
vsphere_cluster    = "$($script:vsphere_cluster)"
vsphere_datastore  = "$($script:vsphere_datastore)"
vsphere_network    = "$($script:vsphere_network)"
vsphere_folder     = "$($script:vsphere_folder)"
vm_template_name   = "$($script:vm_template_name)"

# VM Networking
vm_domain              = "$($script:vm_domain)"
vm_gateway             = "$($script:vm_gateway)"
vm_netmask             = $($script:vm_netmask)
vm_dns_servers         = [$dnsArr]
vm_ssh_user            = "$($script:vm_ssh_user)"
vm_ssh_auth_method     = "$($script:vm_ssh_auth_method)"
vm_ssh_private_key_path = "$($script:vm_ssh_private_key_path -replace '\\','/')"
vm_ssh_password        = "$($script:vm_ssh_password)"

# Java VM
java_vm_ip     = "$($script:java_vm_ip)"
java_vm_cpus   = $($script:java_vm_cpus)
java_vm_memory = $($script:java_vm_memory)
java_vm_disk   = $($script:java_vm_disk)

# .NET VM
dotnet_vm_ip     = "$($script:dotnet_vm_ip)"
dotnet_vm_cpus   = $($script:dotnet_vm_cpus)
dotnet_vm_memory = $($script:dotnet_vm_memory)
dotnet_vm_disk   = $($script:dotnet_vm_disk)

# PHP VM
php_vm_ip     = "$($script:php_vm_ip)"
php_vm_cpus   = $($script:php_vm_cpus)
php_vm_memory = $($script:php_vm_memory)
php_vm_disk   = $($script:php_vm_disk)
"@

    $content | Out-File -FilePath (Join-Path $TfDir "terraform.tfvars") -Encoding utf8
    Write-Step "Created: terraform/terraform.tfvars"
}

# ---------------------------------------------------------------------------
# Generate ansible group_vars/all.yml
# ---------------------------------------------------------------------------
function Write-AnsibleVars {
    Write-Step "Generating ansible/group_vars/all.yml ..."

    $migrateVal = if ($script:install_azure_migrate_agent) { "true" } else { "false" }

    $content = @"
# =============================================================================
# Auto-generated by setup-interactive.ps1 on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# =============================================================================

# --- Common ---
ansible_become: true
ansible_python_interpreter: /usr/bin/python3

# --- Java / PetClinic ---
petclinic_repo: "$($script:petclinic_repo)"
petclinic_branch: "$($script:petclinic_branch)"
java_version: "$($script:java_version)"
petclinic_app_port: 8080

# PostgreSQL
postgres_version: "15"
postgres_db: "petclinic"
postgres_user: "petclinic"
postgres_password: "$($script:postgres_password)"

# --- .NET / ASP.NET Core ---
dotnet_sdk_version: "$($script:dotnet_sdk_version)"
dotnet_app_repo: "$($script:dotnet_app_repo)"
dotnet_app_branch: "$($script:dotnet_app_branch)"
dotnet_app_port: 5000

# SQL Server
mssql_edition: "express"
mssql_sa_password: "$($script:mssql_sa_password)"
mssql_db_name: "eShopDb"

# --- PHP / Laravel ---
php_version: "$($script:php_version)"
php_app_repo: "$($script:php_app_repo)"
php_app_branch: "$($script:php_app_branch)"
php_app_port: 80

# MySQL
mysql_root_password: "$($script:mysql_root_password)"
mysql_db_name: "laravel_app"
mysql_db_user: "laravel"
mysql_db_password: "$($script:mysql_db_password)"

# --- Azure Migrate Discovery ---
install_azure_migrate_agent: $migrateVal
"@

    $varsDir = Join-Path $AnsibleDir "group_vars"
    if (-not (Test-Path $varsDir)) { New-Item -ItemType Directory -Path $varsDir -Force | Out-Null }
    $content | Out-File -FilePath (Join-Path $varsDir "all.yml") -Encoding utf8
    Write-Step "Created: ansible/group_vars/all.yml"
}

# ---------------------------------------------------------------------------
# Generate Ansible inventory from collected IPs
# ---------------------------------------------------------------------------
function Write-AnsibleInventory {
    Write-Step "Generating ansible/inventory/hosts.ini ..."

    if ($script:vm_ssh_auth_method -eq "password") {
        $authLine = "ansible_ssh_pass=$($script:vm_ssh_password) ansible_become_pass=$($script:vm_ssh_password) ansible_ssh_common_args='-o StrictHostKeyChecking=no'"
    }
    else {
        $keyPath = $script:vm_ssh_private_key_path -replace '\\','/'
        $authLine = "ansible_ssh_private_key_file=$keyPath"
    }
    $content = @"
# Auto-generated by setup-interactive.ps1
[java_servers]
$($script:java_vm_ip) ansible_user=$($script:vm_ssh_user) $authLine

[dotnet_servers]
$($script:dotnet_vm_ip) ansible_user=$($script:vm_ssh_user) $authLine

[php_servers]
$($script:php_vm_ip) ansible_user=$($script:vm_ssh_user) $authLine

[legacy_apps:children]
java_servers
dotnet_servers
php_servers
"@

    $invDir = Join-Path $AnsibleDir "inventory"
    if (-not (Test-Path $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    $content | Out-File -FilePath (Join-Path $invDir "hosts.ini") -Encoding utf8
    Write-Step "Created: ansible/inventory/hosts.ini"
}

# ---------------------------------------------------------------------------
# Show summary & confirm
# ---------------------------------------------------------------------------
function Show-Summary {
    Write-Header "Configuration Summary"

    Write-Host "  vCenter:       $($script:vsphere_server)" -ForegroundColor White
    Write-Host "  Datacenter:    $($script:vsphere_datacenter)" -ForegroundColor White
    Write-Host "  Cluster:       $($script:vsphere_cluster)" -ForegroundColor White
    Write-Host "  Template:      $($script:vm_template_name)" -ForegroundColor White
    Write-Host "  Network:       $($script:vsphere_network)  Gateway: $($script:vm_gateway)/$($script:vm_netmask)" -ForegroundColor White
    Write-Host ""
    Write-Host "  VMs to create:" -ForegroundColor White
    Write-Host "    Java VM    $($script:java_vm_ip)    ${script:java_vm_cpus} CPU / ${script:java_vm_memory}MB / ${script:java_vm_disk}GB" -ForegroundColor Gray
    Write-Host "    .NET VM    $($script:dotnet_vm_ip)  ${script:dotnet_vm_cpus} CPU / ${script:dotnet_vm_memory}MB / ${script:dotnet_vm_disk}GB" -ForegroundColor Gray
    Write-Host "    PHP  VM    $($script:php_vm_ip)     ${script:php_vm_cpus} CPU / ${script:php_vm_memory}MB / ${script:php_vm_disk}GB" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Apps:" -ForegroundColor White
    Write-Host "    Java:  PetClinic ($($script:petclinic_repo))" -ForegroundColor Gray
    Write-Host "    .NET:  ASP.NET Core ($($script:dotnet_app_repo))" -ForegroundColor Gray
    Write-Host "    PHP:   Laravel ($($script:php_app_repo))" -ForegroundColor Gray
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Run Terraform
# ---------------------------------------------------------------------------
function Invoke-Terraform {
    Write-Header "Phase 1 — Provisioning VMs on vSphere (Terraform)"

    Push-Location $TfDir
    try {
        Write-Step "terraform init ..."
        terraform init -input=false
        if ($LASTEXITCODE -ne 0) { throw "terraform init failed" }

        Write-Step "terraform plan ..."
        terraform plan -out=tfplan
        if ($LASTEXITCODE -ne 0) { throw "terraform plan failed" }

        Write-Step "terraform apply ..."
        terraform apply -auto-approve tfplan
        if ($LASTEXITCODE -ne 0) { throw "terraform apply failed" }

        Write-Step "VMs created. Waiting 60s for guest OS boot + SSH readiness..."
        Start-Sleep -Seconds 60
    }
    finally {
        Pop-Location
    }
}

# ---------------------------------------------------------------------------
# Run Ansible
# ---------------------------------------------------------------------------
function Invoke-Ansible {
    Write-Header "Phase 2 — Deploying Applications (Ansible)"

    Push-Location $AnsibleDir
    try {
        # Only install collections not already present
        $collections = @("community.postgresql", "community.mysql", "community.general")
        $installed = ansible-galaxy collection list 2>$null | Out-String
        $missing = $collections | Where-Object { $installed -notmatch [regex]::Escape($_) }
        if ($missing.Count -gt 0) {
            Write-Step "Installing Ansible Galaxy collections: $($missing -join ', ')"
            ansible-galaxy collection install @missing
        } else {
            Write-Step "Ansible Galaxy collections already installed — skipping"
        }

        Write-Step "Running master playbook (this may take 15-30 minutes)..."
        ansible-playbook -i inventory/hosts.ini site.yml -v
        if ($LASTEXITCODE -ne 0) { throw "Ansible playbook failed" }
    }
    finally {
        Pop-Location
    }
}

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
function Invoke-Verify {
    Write-Header "Phase 3 — Verification"

    Write-Host ""
    Write-Host "  Testing service health on each VM..." -ForegroundColor Gray

    $checks = @(
        @{ Name = "Java PetClinic";  IP = $script:java_vm_ip;   Port = "8080"; Url = "http://$($script:java_vm_ip):8080" }
        @{ Name = ".NET MVC App";    IP = $script:dotnet_vm_ip;  Port = "80";   Url = "http://$($script:dotnet_vm_ip)" }
        @{ Name = "PHP Laravel App"; IP = $script:php_vm_ip;     Port = "80";   Url = "http://$($script:php_vm_ip)" }
    )

    foreach ($app in $checks) {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $tcp.Connect($app.IP, [int]$app.Port)
            $tcp.Close()
            Write-Host "    [OK]   $($app.Name) at $($app.Url)" -ForegroundColor Green
        }
        catch {
            Write-Host "    [WAIT] $($app.Name) at $($app.Url) — may still be starting" -ForegroundColor Yellow
        }
    }

    Write-Header "Deployment Complete!"
    Write-Host "  Access your apps:" -ForegroundColor White
    foreach ($app in $checks) {
        Write-Host "    $($app.Name):  $($app.Url)" -ForegroundColor Cyan
    }
    Write-Host ""
    Write-Host "  All VMs are ready for Azure Migrate agentless discovery." -ForegroundColor Green
    Write-Host "  Point your Azure Migrate appliance at vCenter: $($script:vsphere_server)" -ForegroundColor Green
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
function Main {
    Clear-Host
    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host "       Legacy App Lab — Interactive Setup Wizard" -ForegroundColor Cyan
    Write-Host "       VMware VM Provisioning + App Deployment" -ForegroundColor Cyan
    Write-Host "       For Azure Migrate Assessment" -ForegroundColor Cyan
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host ""

    # Check tools first
    Test-Prerequisites

    # Load previous values as defaults
    Load-PreviousValues

    # Collect all inputs
    Get-VCenterDetails
    Get-VSphereInfra
    Get-NetworkSettings
    Get-VMSettings
    Get-AppSettings
    Get-MigrateOptions

    # Show summary
    Show-Summary

    # Ask whether to save config files
    Write-Host ""
    Write-Host "  Would you like to save these values to config files?" -ForegroundColor Yellow
    Write-Host "    1) Save to terraform.tfvars + ansible vars + inventory" -ForegroundColor Gray
    Write-Host "    2) Discard and exit (nothing is written)" -ForegroundColor Gray
    $saveChoice = Prompt-Input "Choice" "1"

    if ($saveChoice -ne "1") {
        Write-Host ""
        Write-Warn "Aborted. No files were written."
        exit 0
    }

    # Save config files
    Write-Header "Saving Configuration Files"
    Write-TerraformVars
    Write-AnsibleVars
    Write-AnsibleInventory

    Write-Host ""
    Write-Host "  Files saved successfully:" -ForegroundColor Green
    Write-Host "    terraform/terraform.tfvars" -ForegroundColor Cyan
    Write-Host "    ansible/group_vars/all.yml" -ForegroundColor Cyan
    Write-Host "    ansible/inventory/hosts.ini" -ForegroundColor Cyan

    # Ask what to do next
    Write-Host ""
    $runChoice = Prompt-Choice "What would you like to do next?" @(
        "Run full pipeline (Terraform + Ansible + Verify)",
        "Stop here - I'll run Terraform & Ansible myself later",
        "Terraform only (provision VMs)",
        "Ansible only (deploy to existing VMs)"
    ) "Stop here - I'll run Terraform & Ansible myself later"

    switch -Wildcard ($runChoice) {
        "Run full*" {
            Invoke-Terraform
            Invoke-Ansible
            Invoke-Verify
        }
        "Stop here*" {
            Write-Host ""
            Write-Step "Config files saved. Run manually when ready:"
            Write-Host "    cd terraform; terraform init; terraform apply" -ForegroundColor Gray
            Write-Host "    cd ansible;   ansible-playbook -i inventory/hosts.ini site.yml" -ForegroundColor Gray
        }
        "Terraform*" {
            Invoke-Terraform
            Write-Step "VMs provisioned. Run Ansible next:"
            Write-Host "    cd ansible; ansible-playbook -i inventory/hosts.ini site.yml" -ForegroundColor Gray
        }
        "Ansible*" {
            Invoke-Ansible
            Invoke-Verify
        }
    }
}

Main
