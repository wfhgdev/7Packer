<#
.SYNOPSIS
    Script avanzado para comprimir archivos individuales usando 7-Zip.
    Version: 3.2 (Edicion Inmune a errores de codificacion)
#>

# Forzar codificacion estandar
chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Cargar ensamblado para usar la interfaz grafica de seleccion de carpetas
Add-Type -AssemblyName System.Windows.Forms

function Seleccionar-Carpeta($titulo) {
    $dialogo = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialogo.Description = $titulo
    $dialogo.ShowNewFolderButton = $true
    if ($dialogo.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialogo.SelectedPath
    }
    return $null
}

Clear-Host

# Banner de texto personalizado
$banner = @'
 _____ ___           _             
|___  / _ \__ _  ___| | _____ _ __ 
   / / /_)/ _` |/ __| |/ / _ \ '__|
  / / ___/ (_| | (__|   <  __/ |   
 /_/\/    \__,_|\___|_|\_\___|_|   
                                   
by William Hernandez
'@

Write-Host $banner -ForegroundColor Cyan
Write-Host ""

# 1. Validacion de la ruta estandar de 7-Zip (x64) y autoinstalacion
$exe7z = "C:\Program Files\7-Zip\7z.exe"
if (-not (Test-Path $exe7z)) {
    Write-Host "No se encontro 7-Zip en la ruta estandar ($exe7z)." -ForegroundColor Yellow
    $instalar = ""
    while ($instalar -notin @("S", "N")) {
        $instalar = (Read-Host "Deseas que el script instale 7-Zip automaticamente por ti usando Winget? (S/N)").ToUpper().Trim()
    }
    
    if ($instalar -eq "S") {
        Write-Host "`nInstalando 7-Zip mediante Winget... Por favor, espera." -ForegroundColor Cyan
        $procesoWinget = Start-Process winget -ArgumentList "install -e --id IgorPavlov.7-Zip --accept-source-agreements --accept-package-agreements" -Wait -NoNewWindow -PassThru
        
        Start-Sleep -Seconds 3
        
        if (-not (Test-Path $exe7z)) {
            Write-Host "[ERROR] La instalacion termino pero no se encontro el ejecutable en la ruta estandar." -ForegroundColor Red
            Write-Host "Por favor, instala 7-Zip x64 manualmente antes de continuar." -ForegroundColor Red
            Pause
            exit
        } else {
            Write-Host "7-Zip se ha instalado y verificado correctamente!`n" -ForegroundColor Green
        }
    } else {
        Write-Host "Operacion cancelada. El script requiere 7-Zip para continuar." -ForegroundColor Red
        Pause
        exit
    }
}

# 2. Seleccion de carpeta de origen
Write-Host "[1/6] Selecciona la carpeta que contiene los archivos a comprimir..." -ForegroundColor Yellow
$rutaOrigen = Seleccionar-Carpeta "Selecciona la carpeta de ORIGEN (Se incluiran subcarpetas)"
if (-not $rutaOrigen) {
    Write-Host "Operacion cancelada por el usuario." -ForegroundColor Red; exit
}
$rutaOrigen = $rutaOrigen.TrimEnd('\')
Write-Host "Carpeta de origen seleccionada: $rutaOrigen" -ForegroundColor Green
Write-Host ""

# 3. Filtrado por extensiones especificas de entrada
$filtrarExt = ""
while ($filtrarExt -notin @("S", "N")) {
    $filtrarExt = (Read-Host "[2/6] Deseas comprimir solo extensiones de archivo especificas? (S/N)").ToUpper().Trim()
}

$extFiltro = @()
if ($filtrarExt -eq "S") {
    $extInput = Read-Host "   Digite las extensiones separadas por un espacio (ej: txt docx pdf)"
    if (-not [string]::IsNullOrWhiteSpace($extInput)) {
        $extFiltro = $extInput.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object {
            $e = $_.Trim().ToLower()
            if (-not $e.StartsWith(".")) { $e = ".$e" }
            $e
        }
        Write-Host "   Filtro activo para extensiones: $($extFiltro -join ', ')" -ForegroundColor Green
    } else {
        Write-Host "   No se introdujeron extensiones. Se procesaran todos los archivos." -ForegroundColor Yellow
    }
}
Write-Host ""

# 4. Configuracion del formato de salida y nivel de compresion
$extension = ""
while ($extension -notin @("7z", "zip")) {
    $extension = (Read-Host "[3/6] Elige la extension del archivo comprimido de salida (7z / zip)").ToLower().Trim()
}

$nivel = ""
while ($nivel -notin @("0", "1", "3", "5", "7", "9")) {
    $nivel = Read-Host "[4/6] Nivel de compresion (0=Copiar, 1=Rapido, 5=Normal, 7=Maxima, 9=Ultra)"
}

# 5. Configuracion de contrasena
$password = Read-Host "[5/6] Introduce una contrasena (deja en blanco si no deseas usar contrasena)"
Write-Host ""

# 6. Menu de opciones de destino
Write-Host "[6/6] Que deseas hacer con los archivos?" -ForegroundColor Yellow
Write-Host "A) Guardar comprimido al lado del original y CONSERVAR el original."
Write-Host "B) Guardar comprimido al lado del original y ELIMINAR el original."
Write-Host "C) Guardar en una CARPETA DESTINO independiente (replicando subcarpetas)."
$opcion = ""
while ($opcion -notin @("A", "B", "C")) {
    $opcion = (Read-Host "Elige una opcion (A, B o C)").ToUpper().Trim()
}

$rutaDestino = ""
if ($opcion -eq "C") {
    Write-Host "`nSelecciona la carpeta donde se guardaran los archivos comprimidos..." -ForegroundColor Yellow
    $rutaDestino = Seleccionar-Carpeta "Selecciona la carpeta de DESTINO"
    if (-not $rutaDestino) {
        Write-Host "Operacion cancelada por el usuario." -ForegroundColor Red; exit
    }
    $rutaDestino = $rutaDestino.TrimEnd('\')
    Write-Host "Carpeta de destino seleccionada: $rutaDestino" -ForegroundColor Green
}

# 7. Obtener y filtrar archivos individuales (incluyendo subcarpetas)
Write-Host "`nBuscando archivos... Por favor, espera." -ForegroundColor Cyan
$archivos = Get-ChildItem -Path $rutaOrigen -File -Recurse

if ($extFiltro.Count -gt 0) {
    $archivos = $archivos | Where-Object { $_.Extension.ToLower() -in $extFiltro }
}

if ($archivos.Count -eq 0) {
    Write-Host "No se encontraron archivos validos para comprimir con los criterios especificados." -ForegroundColor Yellow
    Pause
    exit
}

Write-Host "Se encontraron $($archivos.Count) archivos. Iniciando proceso...`n" -ForegroundColor Cyan

# 8. Bucle principal de compresion
foreach ($file in $archivos) {
    if ($opcion -eq "C") {
        $subRuta = $file.DirectoryName.Substring($rutaOrigen.Length)
        $carpetaObjetivo = Join-Path $rutaDestino $subRuta
        if (-not (Test-Path $carpetaObjetivo)) {
            New-Item -ItemType Directory -Path $carpetaObjetivo -Force | Out-Null
        }
        $archivoComprimido = Join-Path $carpetaObjetivo "$($file.BaseName).$extension"
    } else {
        $archivoComprimido = Join-Path $file.DirectoryName "$($file.BaseName).$extension"
    }

    Write-Host "Comprimiendo: $($file.Name) -> $(Split-Path $archivoComprimido -Leaf)" -ForegroundColor Gray

    $argumentos = @("a", "`"$archivoComprimido`"", "`"$($file.FullName)`"", "-t$extension", "-mx=$nivel")
    if (-not [string]::IsNullOrEmpty($password)) {
        $argumentos += "-p`"$password`""
        if ($extension -eq "7z") { $argumentos += "-mhe=on" }
    }

    $proceso = Start-Process -FilePath $exe7z -ArgumentList $argumentos -Wait -NoNewWindow -PassThru

    if ($proceso.ExitCode -eq 0) {
        if ($opcion -eq "B") {
            Remove-Item -Path $file.FullName -Force
            Write-Host " [OK] Comprimido y original eliminado." -ForegroundColor Green
        } else {
            Write-Host " [OK] Comprimido con exito." -ForegroundColor Green
        }
    } else {
        Write-Host " [ERROR] Fallo la compresion de $($file.Name)" -ForegroundColor Red
    }
}

Write-Host "`nProceso finalizado por completo!" -ForegroundColor Cyan
Pause