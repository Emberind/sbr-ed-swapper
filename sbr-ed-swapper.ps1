param(
    [String]$EpisodePath,
    [String]$SongPath,
    [String]$OutPath,
    [String]$SongName
)

class FontConfig {
    [ValidateNotNullOrEmpty()][string]$Path

    FontConfig($path) {
        $this.Path = $path
    }

    [void] Install() {
        if (Test-Path -Path "./fonts/$($this.Path)" -PathType Leaf) { return }
        Write-Host -ForegroundColor Blue "Downloading font ""$($this.Path)""..."

        $family = $this.Path.Substring(0, $this.Path.IndexOf('/')).Replace('_', ' ')

        $uri = "https://fonts.google.com/download/list?family=$($family.Replace(' ', '+'))"
        $response = Invoke-WebRequest -Uri $uri

        if ($response.StatusCode -ne 200) {
            Write-Error "Failed to retrieve from metadata: $($response.StatusCode) - $($response.StatusDescription)" -ErrorAction Stop
            return
        }

        $content = ConvertFrom-Json $response.Content.Substring($response.Content.IndexOf('{'))

        $fileName = $this.Path.Substring($this.Path.IndexOf('/') + 1)
        $fileRefs = $content.manifest.fileRefs
        $fileRef = $fileRefs | Where-Object { $_.filename -eq $fileName }
        if ($fileRef.Count -eq 0) {
            Write-Error "Specific font file not found: $($response.Content)" -ErrorAction Stop
        } elseif ($fileRef.Count -gt 1) {
            Write-Error "More identically named files found: $($response.Content)" -ErrorAction Stop
        }
        $fileRef = $fileRef[0]

        $files = $content.manifest.files
        foreach ($file in $files) {
            $directory = "./fonts/$($family.Replace(' ', '_'))"
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
            Out-File -FilePath "$directory/$($file.filename)" -InputObject $file.contents -Force
        }

        $fontPath = Join-Path -Path "./fonts" -ChildPath $this.Path
        $fontDirectory = Split-Path -Path $fontPath -Parent
        New-Item -Path $fontDirectory -ItemType Directory -Force | Out-Null
        $downloadResponse = Invoke-WebRequest -Uri $fileRef.url -OutFile $fontPath -PassThru
        if ($downloadResponse.StatusCode -ne 200) {
            Write-Error "Failed to download font file: $($downloadResponse.StatusCode) - $($downloadResponse.StatusDescription)" -ErrorAction Stop
        }
    }
}

class SongData {
    [ValidateNotNull()][double]$StartTime
    [ValidateNotNull()][double]$FadeInDuration
    [ValidateNotNull()][double]$FadeOutDuration
    [ValidateNotNull()][double]$Volume
    [ValidateNotNull()][FontConfig[]]$Fonts
}

$global:SongDataDict = @{
    "wanted dead or alive" = [SongData]@{
        StartTime = 8.33
        FadeInDuration = 15.76 - 8.33
        FadeOutDuration = 6.39
        Volume = 0.85
        Fonts = @([FontConfig]::New("Maiden_Orange/MaidenOrange-Regular.ttf"))
    }
}

$global:EdLength = 90

function Get-EdTimestamp {
    [OutputType([double])]
    param(
        [Parameter(Mandatory=$true)][String]$path
    )

    if (-not (Test-Path -Path $path -PathType Leaf)) {
        Write-Error -Message "File not found '$path'" -ErrorAction Stop
    }

    $chapters = $(ffprobe `
        -loglevel error `
        -print_format json `
        -show_chapters `
        "$path" | ConvertFrom-Json).chapters

    $edTimestampShift = -10 / 23.976

    $edChapterNames = @(
        "credits",
        "ed",
        "ending"
    )

    foreach ($chapter in $chapters) {
        $title = $chapter.tags.title
        if (-not ($edChapterNames -contains $title.ToLower())) { continue }

        return [double]($chapter.start_time) + $edTimeStampShift
    }

    if ($chapters.Count -ge 2) {
        Write-Error -Message "Failed to find credits tag. Default to final chapter?" -ErrorAction Inquire
        return [double]($chapters[$chapters.Count - 1].start_time) + $edTimeStampShift
    } else {
        Write-Error -Message "Failed to find credits tag and fewer than two chapters defined" -ErrorAction Stop
    }
}

function Get-AudioStreamsInfo {
    param(
        [Parameter(Mandatory=$true)][String]$path
    )

    if (-not (Test-Path -Path $path -PathType Leaf)) {
        Write-Error -Message "File not found '$path'" -ErrorAction Stop
    }

    return $(ffprobe `
        -loglevel error `
        -print_format json `
        -select_streams a `
        -show_streams `
        "$path" | ConvertFrom-Json).streams
}

function Export-Ed {
    param(
        [Parameter(Mandatory=$true)][String]$inPath,
        [Parameter(Mandatory=$true)][String]$outPath
    )

    if (-not (Test-Path -Path $inPath -PathType Leaf)) {
        Write-Error -Message "File not found '$inPath'" -ErrorAction Stop
    }

    $edTime = Get-EdTimestamp $inPath

    $arguments = @(
        "-ss", $edTime,
        "-t", $global:EdLength,
        "-i", $inPath,
        "-codec", "copy",
        "-map", 0,
        $outPath
    )

    &"ffmpeg" $arguments
}

function Add-SwappedEd {
    param(
        [Parameter(Mandatory=$true)][String]$episodePath,
        [Parameter(Mandatory=$true)][String]$songPath,
        [Parameter(Mandatory=$true)][String]$outPath,
        [String]$songName = "Wanted Dead or Alive"
    )

    if (-not (Test-Path -Path $episodePath -PathType Leaf)) {
        Write-Error -Message "Episode file not found '$episodePath'" -ErrorAction Stop
    }

    if (-not (Test-Path -Path $songPath -PathType Leaf)) {
        Write-Error -Message "Song file not found '$songPath'" -ErrorAction Stop
    }

    $audioStreamsInfo = Get-AudioStreamsInfo $episodePath

    $songData = $null
    foreach ($name in $global:SongDataDict.Keys) {
        if ($name -ne $songName.ToLower()) { continue }

        $songData = $global:SongDataDict[$name.ToLower()]
        break
    }
    if ($null -eq $songData) {
        Write-Error -Message "Song not defined '$songName'" -ErrorAction Stop
    }

    foreach ($font in $songData.Fonts) {
        $font.Install()
    }

    $edTime = Get-EdTimestamp $episodePath

    $episodeFadeOutDuration = 0.2
    $episodeFadeInDuration = 0.2

    $episodeStreamId = 0
    $songStreamId = 1

    $arguments = @(
        "-i", $episodePath,
        "-ss", $songData.StartTime,
        "-t", $global:EdLength,
        "-i", $songPath
    )

    $complexFilterArguments = @(
        "[$($songStreamId):a]",
        (
            "afade=type=in:duration=$($songData.FadeInDuration):curve=qsin:unity=$($songData.Volume)," +
            "afade=type=out:start_time=$($global:EdLength - $songData.FadeOutDuration):duration=$($songData.FadeOutDuration):unity=$($songData.Volume)," +
            "adelay=delays=$($edTime * 1000):all=1," +
            "asplit=$($audioStreamsInfo.Count)"
        )
    )
    foreach ($audioStream in $audioStreamsInfo) {
        $complexFilterArguments += "[song_audio_$($audioStream.index)]"
    }
    $complexFilterArguments[$complexFilterArguments.Count - 1] += ";"

    foreach ($audioStream in $audioStreamsInfo) {
        $audioStreamLabel = "$($episodeStreamId):$($audioStream.index)"

        $complexFilterArguments += @(
            "[$audioStreamLabel]",
            "afade=type=out:start_time=$($edTime - $episodeFadeOutDuration):duration=$episodeFadeOutDuration",
            "[episode_audio_$($audioStream.index)];",

            "[$audioStreamLabel]",
            "afade=type=in:start_time=$($edTime + $global:EdLength - $episodeFadeInDuration):duration=$episodeFadeInDuration",
            "[postcredits_audio_$($audioStream.index)];",

            "[episode_audio_$($audioStream.index)]", "[song_audio_$($audioStream.index)]", "[postcredits_audio_$($audioStream.index)]",
            "amix=inputs=3:normalize=0",
            "[spliced_audio_$($audioStream.index)];"
        )
    }

    $arguments += @(
        "-filter_complex", $complexFilterArguments,

        "-codec:$episodeStreamId", "copy",
        "-map", "$episodeStreamId"
    )

    for ($audioStreamIdx = 0; $audioStreamIdx -lt $audioStreamsInfo.Count; $audioStreamIdx++) {
        $audioStream = $audioStreamsInfo[$audioStreamIdx]
        $audioStreamId = $audioStreamsInfo.Count + $audioStreamIdx

        $arguments += @(
            "-max_interleave_delta", 0,
            "-map", "[spliced_audio_$($audioStream.index)]",
            "-codec:a:$audioStreamIdx", "copy",
            "-codec:a:$audioStreamId", "libvorbis",
            "-qscale:a:$audioStreamId", 3,

            "-metadata:s:a:$audioStreamId", "language=$($audioStream.tags.language)",
            "-metadata:s:a:$audioStreamId", "title=""Altered ED"""
        )

        if ($audioStream.tags.language -eq "jpn") {
            $arguments += @("-disposition:a:$audioStreamIdx", "original")
            $arguments += @("-disposition:a:$audioStreamId", "default")
        } else {
            $arguments += @("-disposition:a:$audioStreamIdx", "dub")
            $arguments += @("-disposition:a:$audioStreamId", "dub")
        }
    }

    $arguments += @("-metadata:s:t", "mimetype=application/x-truetype-font")
    foreach ($font in $songData.Fonts) {
        $arguments += @("-attach", "./fonts/$($font.Path)")
    }

    $arguments += "$outPath"

    Write-Host $arguments
    &"ffmpeg" $arguments
}

if ($EpisodePath -ne "") {
    Add-SwappedEd -EpisodePath $EpisodePath -SongPath $SongPath -OutPath $OutPath -SongName $SongName
}
