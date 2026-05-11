# ╔══════════════════════════════════════════════════════════════╗
# ║  deploy.ps1 — Script de despliegue automático FYGRAD        ║
# ║  Uso:  npm run despliega                                     ║
# ║  Uso con mensaje: npm run despliega -- "mi descripción"      ║
# ╚══════════════════════════════════════════════════════════════╝

param([string]$Mensaje = "")

# ── Helpers ───────────────────────────────────────────────────────────────────
function Step  { param($n, $txt) Write-Host "`n  [$n/4] $txt" -ForegroundColor Cyan }
function OK    { param($txt)     Write-Host "    ✓  $txt" -ForegroundColor Green }
function WARN  { param($txt)     Write-Host "    ⚠  $txt" -ForegroundColor Yellow }
function FAIL  { param($txt)     Write-Host "    ✗  $txt" -ForegroundColor Red; exit 1 }
function INFO  { param($txt)     Write-Host "       $txt" -ForegroundColor Gray }

# ── Datos del proyecto ────────────────────────────────────────────────────────
$pkgJson     = Get-Content "package.json" | ConvertFrom-Json
$projectName = $pkgJson.name
$timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm"
$commitMsg   = if ($Mensaje) { $Mensaje } else { "deploy: $timestamp" }

Clear-Host
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   🚀  DESPLIEGA — $projectName" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# PASO 1 — GitHub
# ═══════════════════════════════════════════════════════════════════════════════
Step 1 "GitHub — Repositorio"

$esGitRepo   = Test-Path ".git"
$tieneRemoto = $false

if ($esGitRepo) {
    $remoteUrl   = git remote get-url origin 2>$null
    $tieneRemoto = ($LASTEXITCODE -eq 0) -and $remoteUrl
}

if (-not $esGitRepo) {
    WARN "Inicializando repositorio git..."
    git init | Out-Null
    git branch -M main 2>$null | Out-Null
    OK "Repositorio git inicializado"
}

if (-not $tieneRemoto) {
    WARN "Creando repositorio en GitHub: $projectName"
    $result = gh repo create $projectName --public --source=. --remote=origin 2>&1
    if ($LASTEXITCODE -ne 0) { FAIL "Error creando repositorio GitHub: $result" }
    OK "Repositorio creado en GitHub"
    $firstPush = $true
} else {
    $remoteUrl = git remote get-url origin
    OK "Repositorio GitHub existente"
    INFO $remoteUrl
    $firstPush = $false
}

$changes = git status --porcelain 2>$null
if ($changes) {
    git add -A | Out-Null
    git commit -m $commitMsg | Out-Null
    if ($firstPush) {
        git push --set-upstream origin main 2>&1 | Out-Null
    } else {
        git push origin main 2>&1 | Out-Null
    }
    if ($LASTEXITCODE -ne 0) { FAIL "Error haciendo push a GitHub" }
    OK "Código subido: `"$commitMsg`""
} else {
    OK "Sin cambios nuevos — GitHub ya está al día"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PASO 2 — Variables de entorno
# ═══════════════════════════════════════════════════════════════════════════════
Step 2 "Variables de Entorno"

$archivosEnv = @(".env.local", ".env.production.local", ".env.production", ".env")
$envFile     = $null

foreach ($f in $archivosEnv) {
    if (Test-Path $f) {
        $contenido = Get-Content $f | Where-Object { $_ -match "^[A-Za-z_][A-Za-z0-9_]*=" -and $_ -notmatch "^#" }
        if ($contenido) { $envFile = $f; break }
    }
}

if ($envFile) {
    WARN "Encontrado: $envFile — sincronizando con Vercel..."
    $lineas = Get-Content $envFile | Where-Object { $_ -match "^[A-Za-z_][A-Za-z0-9_]*=" -and $_ -notmatch "^#" }
    $count  = 0
    foreach ($linea in $lineas) {
        $idx = $linea.IndexOf("=")
        $key = $linea.Substring(0, $idx).Trim()
        $val = $linea.Substring($idx + 1).Trim().Trim('"').Trim("'")
        $val | vercel env add $key production --force 2>$null | Out-Null
        $count++
    }
    OK "$count variable(s) sincronizadas en Vercel (Production)"
} else {
    OK "Sin archivo .env detectado — omitiendo este paso"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PASO 3 — Vercel: vincular
# ═══════════════════════════════════════════════════════════════════════════════
Step 3 "Vercel — Vinculación del Proyecto"

$estaVinculado = Test-Path ".vercel/project.json"

if (-not $estaVinculado) {
    WARN "Proyecto no vinculado. Creando proyecto en Vercel..."
    vercel link --yes 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { FAIL "Error vinculando con Vercel" }
    OK "Proyecto vinculado a Vercel"

    $gitignore = if (Test-Path ".gitignore") { Get-Content ".gitignore" } else { @() }
    if ($gitignore -notcontains ".vercel") {
        Add-Content ".gitignore" "`n# Vercel`n.vercel"
        git add .gitignore | Out-Null
        git commit -m "chore: agregar .vercel a .gitignore" | Out-Null
        git push origin main 2>&1 | Out-Null
    }
} else {
    $data = Get-Content ".vercel/project.json" | ConvertFrom-Json
    OK "Ya vinculado a Vercel"
    INFO "Project ID: $($data.projectId)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PASO 4 — Deploy a producción
# ═══════════════════════════════════════════════════════════════════════════════
Step 4 "Vercel — Desplegando a Producción"

Write-Host ""
$output    = vercel --prod --yes 2>&1
$deployUrl = ($output | Select-String -Pattern "https://\S+" | Select-Object -Last 1).Matches.Value

if ($LASTEXITCODE -eq 0 -and $deployUrl) {
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║   ✅  DESPLEGADO EN PRODUCCIÓN                        ║" -ForegroundColor Green
    Write-Host "  ║                                                       ║" -ForegroundColor Green
    Write-Host "  ║   🌐  $deployUrl" -ForegroundColor Green
    Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
} elseif ($LASTEXITCODE -eq 0) {
    OK "Desplegado correctamente — revisa el dashboard de Vercel para la URL"
} else {
    FAIL "Error en el despliegue. Ejecuta: vercel logs"
}
