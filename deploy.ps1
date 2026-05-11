# deploy.ps1 - Script de despliegue automatico FYGRAD
# Uso: npm run despliega
# Uso con mensaje: npm run despliega -- "descripcion del cambio"

param([string]$Mensaje = "")

function Step  { param($n, $txt) Write-Host "`n  [$n] $txt" -ForegroundColor Cyan }
function OK    { param($txt)     Write-Host "    v  $txt" -ForegroundColor Green }
function WARN  { param($txt)     Write-Host "    !  $txt" -ForegroundColor Yellow }
function FAIL  { param($txt)     Write-Host "    x  $txt" -ForegroundColor Red; exit 1 }
function INFO  { param($txt)     Write-Host "       $txt" -ForegroundColor Gray }

$pkgJson     = Get-Content "package.json" | ConvertFrom-Json
$projectName = $pkgJson.name
$timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm"
$commitMsg   = if ($Mensaje) { $Mensaje } else { "fix: actualizacion $timestamp" }

# Detectar modo: NUEVO o CORRECCION
$esGitRepo   = Test-Path ".git"
$tieneRemoto = $false
$estaVinculado = Test-Path ".vercel/project.json"

if ($esGitRepo) {
    git remote get-url origin 2>$null | Out-Null
    $tieneRemoto = $LASTEXITCODE -eq 0
}

$esProyectoNuevo = (-not $esGitRepo) -or (-not $tieneRemoto) -or (-not $estaVinculado)
$modo = if ($esProyectoNuevo) { "PROYECTO NUEVO" } else { "CORRECCION" }

Write-Host ""
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host "   DESPLIEGA -- $projectName" -ForegroundColor Cyan
Write-Host "   Modo: $modo" -ForegroundColor Cyan
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host ""

# ================================================================
# MODO CORRECCION: solo commit + push (Vercel auto-despliega)
# ================================================================
if (-not $esProyectoNuevo) {

    Step "1/2" "GitHub -- Subiendo cambios"

    $changes = git status --porcelain 2>$null
    if ($changes) {
        git add -A | Out-Null
        git commit -m $commitMsg | Out-Null
        git push origin main 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { FAIL "Error haciendo push a GitHub" }
        OK "Cambios subidos: $commitMsg"
    } else {
        OK "Sin cambios pendientes -- todo ya esta en GitHub"
    }

    Step "2/2" "Vercel -- Despliegue automatico"
    $data = Get-Content ".vercel/project.json" | ConvertFrom-Json
    OK "Vercel detectara el push y desplegara automaticamente"
    INFO "Proyecto: $($data.projectName)"
    INFO "Revisa el estado en: https://vercel.com/henry-56s-projects/$($data.projectName)"

    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor Green
    Write-Host "   CORRECCION PUBLICADA EN PRODUCCION" -ForegroundColor Green
    Write-Host "  =============================================" -ForegroundColor Green
    Write-Host ""
    exit 0
}

# ================================================================
# MODO NUEVO: crear repo GitHub + vincular Vercel + desplegar
# ================================================================

Step "1/4" "GitHub -- Repositorio"

if (-not $esGitRepo) {
    WARN "Inicializando repositorio git..."
    git init | Out-Null
    git branch -M main 2>$null | Out-Null
    OK "Repositorio git inicializado"
}

$firstPush = $false
if (-not $tieneRemoto) {
    WARN "Creando repositorio en GitHub: $projectName"
    $result = gh repo create $projectName --public --source=. --remote=origin 2>&1
    if ($LASTEXITCODE -ne 0) { FAIL "Error creando repositorio GitHub: $result" }
    OK "Repositorio creado: github.com/Henry-56/$projectName"
    $firstPush = $true
} else {
    OK "Repositorio GitHub ya existe"
    INFO (git remote get-url origin)
}

$changes = git status --porcelain 2>$null
if ($changes -or $firstPush) {
    git add -A | Out-Null
    $msg = if ($firstPush) { "feat: inicio del proyecto $projectName" } else { $commitMsg }
    git commit -m $msg 2>$null | Out-Null
    if ($firstPush) {
        git push --set-upstream origin main 2>&1 | Out-Null
    } else {
        git push origin main 2>&1 | Out-Null
    }
    if ($LASTEXITCODE -ne 0) { FAIL "Error haciendo push a GitHub" }
    OK "Codigo subido a GitHub"
} else {
    OK "Sin cambios -- GitHub al dia"
}

Step "2/4" "Variables de Entorno"

$archivosEnv = @(".env.local", ".env.production.local", ".env.production", ".env")
$envFile     = $null

foreach ($f in $archivosEnv) {
    if (Test-Path $f) {
        $contenido = Get-Content $f | Where-Object { $_ -match "^[A-Za-z_][A-Za-z0-9_]*=" -and $_ -notmatch "^#" }
        if ($contenido) { $envFile = $f; break }
    }
}

if ($envFile) {
    WARN "Encontrado: $envFile -- sincronizando con Vercel..."
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
    OK "Sin archivo .env -- omitiendo este paso"
}

Step "3/4" "Vercel -- Vinculacion del Proyecto"

if (-not $estaVinculado) {
    WARN "Creando y vinculando proyecto en Vercel..."
    vercel link --yes 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { FAIL "Error vinculando con Vercel" }
    OK "Proyecto creado y vinculado a Vercel"
} else {
    $data = Get-Content ".vercel/project.json" | ConvertFrom-Json
    OK "Ya vinculado -- Project ID: $($data.projectId)"
}

Step "4/4" "Vercel -- Primer despliegue a Produccion"

Write-Host ""
$output    = vercel --prod --yes 2>&1
$deployUrl = ($output | Select-String -Pattern "https://\S+" | Select-Object -Last 1).Matches.Value

if ($LASTEXITCODE -eq 0 -and $deployUrl) {
    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor Green
    Write-Host "   PROYECTO NUEVO DESPLEGADO EN PRODUCCION" -ForegroundColor Green
    Write-Host "   $deployUrl" -ForegroundColor Green
    Write-Host "  =============================================" -ForegroundColor Green
    Write-Host ""
} elseif ($LASTEXITCODE -eq 0) {
    OK "Desplegado -- revisa el dashboard de Vercel para la URL"
} else {
    FAIL "Error en el despliegue. Ejecuta: vercel logs"
}
