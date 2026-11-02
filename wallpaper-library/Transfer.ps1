$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Library.ps1')

function Get-LibraryConverter {
    $command=Get-Command ffmpeg.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (!$command) { throw '未找到 FFmpeg。此功能使用已安装的 FFmpeg，不会自动下载安装。' }
    return $command.Source
}

function Invoke-LibraryConversion($Item,[string]$Destination,[int]$Seconds=30) {
    if ($Seconds -lt 1 -or $Seconds -gt 30) { throw '转换时长须为 1–30 秒。' }
    $fresh=@(Read-WallpaperCatalog @($Item.Folder) | Where-Object {$_.Project -eq $Item.Project})
    if ($fresh.Count -ne 1 -or !$fresh[0].Convertible) { throw '该素材无法转换；场景包和网页不会被执行。' }
    $source=Assert-LocalPath $fresh[0].Media
    $destination=Assert-LocalPath $Destination
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $stage=Join-Path $destination ('convert-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    $inputCopy=Join-Path $stage ('source'+[IO.Path]::GetExtension($source).ToLowerInvariant())
    $output=Join-Path $stage 'output.mp4'
    $guard=$null
    try {
        # Snapshot the input; no links, playlists, network inputs or source edits.
        $inputStream=[IO.File]::Open($source,'Open','Read','Read')
        try {
            if ($inputStream.Length -gt 1GB) { throw '源文件超过 1 GiB 转换上限。' }
            $out=[IO.File]::Create($inputCopy)
            try {$inputStream.CopyTo($out)} finally {$out.Dispose()}
        } finally {$inputStream.Dispose()}
        $guard=[IO.File]::Open($inputCopy,'Open','Read','Read')
        $converter=Get-LibraryConverter
        $arguments=@('-nostdin','-hide_banner','-loglevel','error','-y','-max_alloc','268435456','-threads','2','-protocol_whitelist','file')
        if ([IO.Path]::GetExtension($source) -match '^\.(png|jpg|jpeg|webp)$') { $arguments+=@('-loop','1') }
        $arguments+=@('-i',$inputCopy,'-t',"$Seconds",'-map','0:v:0','-an','-sn','-dn','-map_metadata','-1','-vf',"scale=1280:720:force_original_aspect_ratio=decrease:force_divisible_by=2,pad=1280:720:(ow-iw)/2:(oh-ih)/2,setsar=1",'-r','24','-c:v','libx264','-threads','2','-preset','veryfast','-crf','25','-maxrate','2500k','-bufsize','5000k','-pix_fmt','yuv420p','-movflags','+faststart',$output)
        foreach ($argument in $arguments) { if ($argument -match '["\r\n]') { throw '转换参数含无效字符。' } }
        $line=($arguments | ForEach-Object {'"'+$_+'"'}) -join ' '
        $info=New-Object Diagnostics.ProcessStartInfo
        $info.FileName=$converter; $info.Arguments=$line; $info.UseShellExecute=$false; $info.CreateNoWindow=$true
        $info.RedirectStandardError=$true
        $process=New-Object Diagnostics.Process
        $process.StartInfo=$info
        try {
            $null=$process.Start(); $errors=$process.StandardError.ReadToEndAsync()
            if (!$process.WaitForExit(120000)) {$process.Kill(); $process.WaitForExit(); throw '转换超过 120 秒，已停止本次 FFmpeg 进程。'}
            if ($process.ExitCode -ne 0) { throw ('FFmpeg 转换失败：'+$errors.Result.Substring(0,[Math]::Min(1200,$errors.Result.Length))) }
        } finally {$process.Dispose()}
        $file=Get-Item -LiteralPath $output
        if ($file.Length -lt 16 -or $file.Length -gt 16MB) {throw '转换结果不在 16 MiB 限制内；没有添加到素材库。'}
        $hash=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
        $target=Assert-LocalPath (Join-Path $destination ($hash+'.mp4'))
        if (Test-Path -LiteralPath $target) {
            if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ine $hash) {throw '同名导出文件已被修改。'}
        } else {Copy-Item -LiteralPath $output -Destination $target}
        $meta=@{schema=1;title=$fresh[0].Title;workshopId=$fresh[0].Id;source=$source;sha256=$hash;converted=$true;maximumDurationSeconds=$Seconds;automaticApply=$false}
        [IO.File]::WriteAllText([IO.Path]::ChangeExtension($target,'.json'),($meta|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        return $target
    } finally {
        if ($guard) {$guard.Dispose()}
        # The generated GUID directory is local to the validated export root.
        if ((Split-Path -Parent $stage) -eq $destination -and (Split-Path -Leaf $stage) -match '^convert-[a-f0-9]{32}$') {
            Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Add-ExperimentalVideo([string]$Path,[string]$Title) {
    # Destination is always this experiment, never the active installed manager.
    $source=Assert-LocalPath $Path
    $root=Split-Path -Parent $PSScriptRoot
    $store=Assert-LocalPath (Join-Path $root 'skin\library')
    New-Item -ItemType Directory -Path $store -Force | Out-Null
    $stream=[IO.File]::Open($source,'Open','Read','Read')
    try {
        if ([IO.Path]::GetExtension($source) -ine '.mp4' -or $stream.Length -lt 16 -or $stream.Length -gt 16MB) {throw '不是符合限制的 MP4。'}
        $header=New-Object byte[] 12; $null=$stream.Read($header,0,12)
        if ([Text.Encoding]::ASCII.GetString($header,4,4) -ne 'ftyp') {throw 'MP4 文件头无效。'}
        $stream.Position=0; $sha=[Security.Cryptography.SHA256]::Create()
        try {$hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()} finally {$sha.Dispose()}
        $target=Assert-LocalPath (Join-Path $store ($hash+'.mp4'))
        if (!(Test-Path -LiteralPath $target)) {
            $temp=Join-Path $store ([guid]::NewGuid().ToString('N')+'.tmp')
            try {
                $stream.Position=0; $out=[IO.File]::Create($temp)
                try {$stream.CopyTo($out)} finally {$out.Dispose()}
                Move-Item -LiteralPath $temp -Destination $target
            } finally {if (Test-Path -LiteralPath $temp) {Remove-Item -LiteralPath $temp -Force}}
        }
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ine $hash) {throw '素材库副本哈希校验失败。'}
        $metaPath=Assert-LocalPath (Join-Path $store ($hash+'.json'))
        [IO.File]::WriteAllText($metaPath,(@{name=$Title}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        return [pscustomobject]@{Id=$hash;Path=$target;ManagerRoot=$root;AutomaticApply=$false}
    } finally {$stream.Dispose()}
}

function Send-WallpaperToExperiment($Item,[bool]$Convert=$false) {
    $destination=Join-Path $PSScriptRoot 'data\exports'
    $path=if ($Convert) {Invoke-LibraryConversion $Item $destination} else {Export-WallpaperVideo $Item $destination}
    Add-ExperimentalVideo $path $Item.Title
}
