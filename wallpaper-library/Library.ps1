$ErrorActionPreference = 'Stop'

function Assert-LocalPath([string]$Path) {
    if (!$Path -or $Path.StartsWith('\\') -or $Path -match '^[a-z]+://' ) { throw 'Only local disk paths are accepted.' }
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.Substring(2).Contains(':')) { throw 'Alternate data streams are not accepted.' }
    $part = $full
    while ($part) {
        if (Test-Path -LiteralPath $part) {
            if ((Get-Item -LiteralPath $part -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Links and junctions are not accepted.' }
        }
        $parent = Split-Path -Parent $part
        if ($parent -eq $part) { break }
        $part = $parent
    }
    return $full
}

function Resolve-WallpaperAsset([string]$Directory,[string]$Relative) {
    if (!$Relative -or [IO.Path]::IsPathRooted($Relative) -or $Relative.Contains(':')) { throw 'Invalid asset path.' }
    $root = (Assert-LocalPath $Directory).TrimEnd('\') + '\'
    $asset = Assert-LocalPath (Join-Path $root $Relative)
    if (!$asset.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'Asset escapes wallpaper directory.' }
    return $asset
}

function Get-WallpaperRoots([string[]]$ExtraRoots=@()) {
    $steamPaths = @()
    foreach ($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        $reg = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($reg) { $steamPaths += @($reg.SteamPath,$reg.InstallPath) | Where-Object { $_ } }
    }
    if (${env:ProgramFiles(x86)}) { $steamPaths += Join-Path ${env:ProgramFiles(x86)} 'Steam' }
    $libraries = @($steamPaths)
    foreach ($steam in $steamPaths) {
        foreach ($relative in @('steamapps\libraryfolders.vdf','config\libraryfolders.vdf')) {
            try {
                $vdf = Assert-LocalPath (Join-Path $steam $relative)
                if ((Test-Path -LiteralPath $vdf) -and (Get-Item -LiteralPath $vdf).Length -lt 2MB) {
                    $content = [IO.File]::ReadAllText($vdf)
                    foreach ($match in [regex]::Matches($content,'"path"\s+"((?:\\.|[^"\\])*)"')) {
                        $libraries += $match.Groups[1].Value.Replace('\\','\')
                    }
                }
            } catch { }
        }
    }
    $roots = @($ExtraRoots)
    foreach ($library in ($libraries | Select-Object -Unique)) {
        foreach ($relative in @('steamapps\workshop\content\431960','steamapps\common\wallpaper_engine\projects\myprojects','steamapps\common\wallpaper_engine\projects\defaultprojects')) {
            $roots += Join-Path $library $relative
        }
    }
    foreach ($root in ($roots | Where-Object { $_ } | Select-Object -Unique)) {
        try { $valid = Assert-LocalPath $root; if (Test-Path -LiteralPath $valid -PathType Container) { $valid } } catch { }
    }
}

function Read-WallpaperCatalog([string[]]$Roots) {
    $seen = @{}
    foreach ($root in $Roots) {
        try {
            $root = Assert-LocalPath $root
            $directories = @(Get-Item -LiteralPath $root) + @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction Stop)
        } catch { continue }
        foreach ($directory in $directories) {
            try {
                $project = Resolve-WallpaperAsset $directory.FullName 'project.json'
                if ($seen.ContainsKey($project) -or !(Test-Path -LiteralPath $project)) { continue }
                $seen[$project] = $true
                if ((Get-Item -LiteralPath $project).Length -gt 1MB) { throw 'project.json exceeds 1 MiB.' }
                $data = [IO.File]::ReadAllText($project) | ConvertFrom-Json
                $title = [string]$data.title
                if (!$title) { $title = $directory.Name }
                $type = [string]$data.type
                if (!$type) { $type = 'unknown' }
                $media = ''; $preview = ''; $size = 0; $compatible = $false
                $reason = '此类型可浏览；第一版只导出 MP4，不执行场景或网页。'
                if ($data.preview) {
                    try {
                        $p = Resolve-WallpaperAsset $directory.FullName ([string]$data.preview)
                        if ([IO.Path]::GetExtension($p) -match '^\.(png|jpg|jpeg)$' -and (Test-Path -LiteralPath $p) -and (Get-Item -LiteralPath $p).Length -le 8MB) { $preview = $p }
                    } catch { }
                }
                if ($data.file) {
                    $media = Resolve-WallpaperAsset $directory.FullName ([string]$data.file)
                    if (!(Test-Path -LiteralPath $media -PathType Leaf)) { $reason = '媒体文件缺失（场景的内容也可能已打包进 PKG）。' }
                    else {
                        $size = (Get-Item -LiteralPath $media).Length
                        if ($type -ieq 'video' -and [IO.Path]::GetExtension($media) -ieq '.mp4') {
                            if ($size -gt 16MB) { $reason = '超过当前 16 MiB 上限；第一版不含压缩转换。' }
                            elseif ($size -lt 16) { $reason = 'MP4 无效或为空。' }
                            else {
                                $stream = [IO.File]::OpenRead($media)
                                try { $header = New-Object byte[] 12; $null = $stream.Read($header,0,12) } finally { $stream.Dispose() }
                                if ([Text.Encoding]::ASCII.GetString($header,4,4) -eq 'ftyp') { $compatible=$true; $reason='可导出 MP4；能否预览仍取决于系统编码支持。' }
                                else { $reason='文件头不是有效的 MP4 容器。' }
                            }
                        }
                    }
                }
                $convertible=$false
                # A scene may ship an independent video next to its package. Do
                # not extract arbitrary packages or execute scene/web scripts.
                if ($type -ieq 'scene' -and (!$media -or [IO.Path]::GetExtension($media) -notmatch '^\.(mp4|webm|mov|m4v)$')) {
                    $candidates=@(Get-ChildItem -LiteralPath $directory.FullName -File | Where-Object {$_.Extension -match '^\.(mp4|webm|mov|m4v)$'} | Select-Object -First 2)
                    if ($candidates.Count -eq 1) {
                        $media=Resolve-WallpaperAsset $directory.FullName $candidates[0].Name
                        $size=$candidates[0].Length
                        $reason='找到场景随附视频；转换后不包含场景的实时交互效果。'
                    }
                }
                if ($media -and (Test-Path -LiteralPath $media -PathType Leaf) -and $type -notin @('web','application')) {
                    $convertible=([IO.Path]::GetExtension($media) -match '^\.(mp4|webm|mov|m4v|gif|png|jpg|jpeg|webp)$') -and $size -gt 0 -and $size -le 1GB
                    if ($convertible -and !$compatible) { $reason+=' 可尝试本地转换为静音 MP4（最长 30 秒）。' }
                }
                [pscustomobject]@{ Title=$title; Id=$directory.Name; Type=$type; MiB=[Math]::Round($size/1MB,2); Compatible=$compatible; Convertible=$convertible; Reason=$reason; Media=$media; Preview=$preview; Project=$project; Tags=($data.tags -join ' '); Folder=$directory.FullName }
            } catch {
                [pscustomobject]@{Title=$directory.Name;Id=$directory.Name;Type='invalid';MiB=0;Compatible=$false;Convertible=$false;Reason=$_.Exception.Message;Media='';Preview='';Project=$project;Tags='';Folder=$directory.FullName}
            }
        }
    }
}

function Export-WallpaperVideo($Item,[string]$Destination) {
    # Re-read metadata and validate at export time; never trust stale UI state.
    $fresh = @(Read-WallpaperCatalog @($Item.Folder) | Where-Object {$_.Project -eq $Item.Project})
    if ($fresh.Count -ne 1 -or !$fresh[0].Compatible) { throw 'Selected wallpaper is no longer a compatible MP4.' }
    $source = Assert-LocalPath $fresh[0].Media
    $destination = Assert-LocalPath $Destination
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $temp = Join-Path $destination ([guid]::NewGuid().ToString('N')+'.tmp')
    try {
        # Lock the source against concurrent writing while copying and hashing.
        $inputStream = [IO.File]::Open($source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        try {
            if ($inputStream.Length -gt 16MB) { throw 'Video grew beyond limit.' }
            $outputStream = [IO.File]::Create($temp)
            try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
        } finally { $inputStream.Dispose() }
        $hash = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant()
        $target = Assert-LocalPath (Join-Path $destination ($hash+'.mp4'))
        if (Test-Path -LiteralPath $target) {
            if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ine $hash) { throw 'Existing export has been modified.' }
        } else { Move-Item -LiteralPath $temp -Destination $target }
        $meta = @{schema=1;title=$fresh[0].Title;workshopId=$fresh[0].Id;source=$source;sha256=$hash;exportedAt=[DateTime]::UtcNow.ToString('o');automaticApply=$false}
        $metaPath=Assert-LocalPath (Join-Path $destination ($hash+'.json'))
        [IO.File]::WriteAllText($metaPath,($meta|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        return $target
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}
