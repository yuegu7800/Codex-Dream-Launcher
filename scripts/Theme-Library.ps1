$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Package-Common.ps1')

function Write-DragonThemeJson([string]$Path,$Value) {
    $parent=Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temp,($Value | ConvertTo-Json -Depth 30),(New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temp -Destination $Path -Force
    } finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp}}
}

function Get-DragonPresets {
    @(
        [pscustomobject]@{Id='dragon';Name='龙娘 · 原色';Accent='#7468bd';Panel='#f8f9fd';Background='#eef1f8';Opacity=0.90},
        [pscustomobject]@{Id='mist';Name='雾蓝 · 专注';Accent='#537b98';Panel='#f3f7fa';Background='#e9eff4';Opacity=0.72},
        [pscustomobject]@{Id='sage';Name='鼠尾草 · 柔和';Accent='#60836c';Panel='#f5f8f3';Background='#edf2e9';Opacity=0.68},
        [pscustomobject]@{Id='rose';Name='蔷薇 · 暖光';Accent='#ad7183';Panel='#fff7f8';Background='#f6edf0';Opacity=0.78},
        [pscustomobject]@{Id='paper';Name='纸白 · 阅读';Accent='#73716a';Panel='#faf9f4';Background='#efeee8';Opacity=0.45}
    )
}

function Initialize-DragonLibrary([string]$Root) {
    $Root = Assert-DragonOrdinaryPath $Root
    $store = Assert-DragonOrdinaryPath (Join-Path $Root 'skin\library')
    New-Item -ItemType Directory -Path $store -Force | Out-Null
    $baseline = Join-Path $store 'baseline.json'
    if (!(Test-Path -LiteralPath $baseline)) {
        Copy-Item -LiteralPath (Join-Path $Root 'themes\dragon\theme.json') -Destination $baseline
    }
    return $store
}

function Get-DragonVideos([string]$Root) {
    $store = Initialize-DragonLibrary $Root
    [pscustomobject]@{Name='龙娘 · 随附视频';Path=(Join-Path $Root 'themes\dragon\wallpaper.mp4');Id='bundled'}
    foreach ($file in Get-ChildItem -LiteralPath $store -Filter '*.mp4' -File) {
        if ($file.BaseName -match '^[a-f0-9]{64}$') {
            $name = $file.BaseName.Substring(0,12)
            $meta = Join-Path $store ($file.BaseName+'.json')
            if (Test-Path -LiteralPath $meta) {
                try { $name = [string](Get-Content -LiteralPath $meta -Encoding UTF8 -Raw | ConvertFrom-Json).name } catch {}
            }
            [pscustomobject]@{Name=$name;Path=$file.FullName;Id=$file.BaseName}
        }
    }
}

function Test-DragonVideo([string]$Root,[string]$Path) {
    $Path = Assert-DragonOrdinaryPath $Path
    $file = Get-Item -LiteralPath $Path
    if ($file.PSIsContainer -or $file.Extension -ine '.mp4' -or $file.Length -lt 16 -or $file.Length -gt 16MB) {
        throw '请选择 16 MiB 以内的本地 MP4 视频。'
    }
    $stream = [IO.File]::OpenRead($Path)
    try {
        $header = New-Object byte[] 12
        $null = $stream.Read($header,0,12)
        if ([Text.Encoding]::ASCII.GetString($header,4,4) -ne 'ftyp') { throw '文件不是可识别的 MP4 容器。' }
    } finally { $stream.Dispose() }
    $node = Join-Path $Root 'engine\runtime\node\node.exe'
    if ((Get-FileHash -LiteralPath $node -Algorithm SHA256).Hash -ine 'f8d162c0641dcee512132f3bcf8a68169c7ecb852efd8e1a46c9fec5a0f469ed') { throw 'Node 校验失败。' }
    return $node
}

function Import-DragonVideo([string]$Root,[string]$Path) {
    $null = Test-DragonVideo $Root $Path
    $store = Initialize-DragonLibrary $Root
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $target = Join-Path $store ($hash+'.mp4')
    if (!(Test-Path -LiteralPath $target)) { Copy-Item -LiteralPath $Path -Destination $target }
    if ((Get-FileHash -LiteralPath $target).Hash -ine $hash) { throw '视频副本校验失败。' }
    Write-DragonJson (Join-Path $store ($hash+'.json')) @{name=[IO.Path]::GetFileNameWithoutExtension($Path)}
    return $hash
}

function Set-DragonTheme([string]$Root,[string]$VideoId,[string]$PresetId,[int]$Reveal=90) {
    if ($Reveal -lt 0 -or $Reveal -gt 100) { throw '透明度超出范围。' }
    $preset = @(Get-DragonPresets | Where-Object {$_.Id -ceq $PresetId})
    $video = @(Get-DragonVideos $Root | Where-Object {$_.Id -ceq $VideoId})
    if ($preset.Count -ne 1 -or $video.Count -ne 1) { throw '请选择有效的视频和预设。' }
    $node = Test-DragonVideo $Root $video[0].Path
    $store = Initialize-DragonLibrary $Root
    $themeDir = Assert-DragonOrdinaryPath (Join-Path $Root 'themes\dragon')
    $configPath = Join-Path $themeDir 'theme.json'
    $baseline = Get-Content -LiteralPath (Join-Path $store 'baseline.json') -Encoding UTF8 -Raw | ConvertFrom-Json
    $config = $baseline
    $config.name = $preset[0].Name
    $config.colors.accent = $preset[0].Accent
    $config.colors.panel = $preset[0].Panel
    $config.colors.background = $preset[0].Background
    $config.media.opacity = $Reveal/100.0
    $config.image = if ($VideoId -eq 'bundled') {'wallpaper.mp4'} else {'library-'+$VideoId+'.mp4'}
    $destination = Assert-DragonOrdinaryPath (Join-Path $themeDir $config.image)
    if ($VideoId -ne 'bundled') {
        if (!(Test-Path -LiteralPath $destination)) { Copy-Item -LiteralPath $video[0].Path -Destination $destination }
        if ((Get-FileHash -LiteralPath $destination).Hash -ine $VideoId) { throw '已保存视频的哈希不匹配。' }
    }
    $stage = Join-Path $store ('validate-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    try {
        Copy-Item -LiteralPath $destination -Destination (Join-Path $stage $config.image)
        Write-DragonThemeJson (Join-Path $stage 'theme.json') $config
        $output = & $node (Join-Path $Root 'engine\scripts\injector.mjs') --check-payload --theme-dir $stage 2>&1
        if ($LASTEXITCODE -ne 0) { throw ('主题验证失败：'+($output -join ' ')) }
        $backup = Assert-DragonOrdinaryPath (Join-Path $Root 'backups')
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        Copy-Item -LiteralPath $configPath -Destination (Join-Path $backup ('theme-'+[guid]::NewGuid().ToString('N')+'.json'))
        # Existing per-theme preferences take precedence over media.opacity.
        $prefPath = Assert-DragonOrdinaryPath (Join-Path $Root 'skin\theme-preferences.json')
        $prefs = if (Test-Path -LiteralPath $prefPath) {Get-Content -LiteralPath $prefPath -Encoding UTF8 -Raw | ConvertFrom-Json} else {[pscustomobject]@{schemaVersion=1;themes=[pscustomobject]@{}}}
        $prefs.themes | Add-Member -NotePropertyName $config.id -NotePropertyValue @{transparency=$Reveal} -Force
        Write-DragonThemeJson $prefPath $prefs
        Write-DragonThemeJson $configPath $config
        Write-DragonJson (Join-Path $store 'selection.json') @{videoId=$VideoId;presetId=$PresetId;reveal=$Reveal}
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    }
}

function Set-DragonPaused([string]$Root,[bool]$Paused) {
    $path = Assert-DragonOrdinaryPath (Join-Path $Root 'skin\paused')
    if ($Paused) { [IO.File]::WriteAllText($path,'paused') }
    elseif (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
}
