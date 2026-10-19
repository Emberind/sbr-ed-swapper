function Get-EdTimestamp {
    [OutputType([double])]
    param(
        [Parameter(Mandatory=$true)][String]$path
    )

    if (-not (Test-Path -Path $path -PathType Leaf)) {
        Write-Error -Message "File not found '$path'" -ErrorAction Stop
    }

    $chapters = $(ffprobe `
        -v error `
        -print_format json `
        -show_chapters `
        "$path" | ConvertFrom-Json).chapters

    foreach ($chapter in $chapters) {
        $title = $chapter.tags.title
        if ($title.ToLower() -ne "credits") { continue }

        return [double]($chapter.start_time)
    }

    if ($chapters.Count -ge 2) {
        Write-Error -Message "Failed to find credits tag. Default to final chapter?" -ErrorAction Inquire
        return [double]($chapters[$chapters.Count - 1].start_time)
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

    return $((
        ffprobe `
        -v error `
        -print_format json `
        -select_streams a `
        -show_streams `
        "$path"
    ) | ConvertFrom-Json).streams
}

function Export-Ed {
    param(
        [Parameter(Mandatory=$true)][String]$path,
        [Parameter(Mandatory=$true)][String]$outPath
    )

    if (-not (Test-Path -Path $path -PathType Leaf)) {
        Write-Error -Message "File not found '$path'" -ErrorAction Stop
    }

    $audioStreamsInfo = Get-AudioStreamsInfo $path

    $edTime = $(Get-EdTimestamp $path)

    $edLength = 90

    $songStartTime = 7.60
    $songFadeInDuration = 15.76 - $songStartTime
    $songFadeOutDuration = 6.39
    $songVolume = 0.5

    $episodeFadeOutDuration = 0.2
    $episodeFadeInDuration = 0.2

    $arguments = @()

    $arguments += @(
        "-i", $path,
        "-ss", $songStartTime,
        "-t", $edLength,
        "-i", "./Bon Jovi - Wanted Dead Or Alive.mp3"
    )

    $complexFilterArguments = @(
        "[1:a]",
        (
            "afade=t=in:d=$($songFadeInDuration):curve=qsin:unity=$songVolume," +
            "afade=t=out:st=$($edLength - $songFadeOutDuration):d=$($songFadeOutDuration):unity=$songVolume," +
            "adelay=delays=$($edTime)s:all=1,",
            "asplit=$($audioStreamsInfo.Count)"
        )
    )
    foreach ($audioStream in $audioStreamsInfo) {
        $complexFilterArguments += "[song_audio_$($audioStream.index)]"
    }
    $complexFilterArguments[$complexFilterArguments.Count - 1] += ";"

    foreach ($audioStream in $audioStreamsInfo) {
        $audioStreamLabel = "0:$($audioStream.index)"

        $complexFilterArguments += @(
            "[$audioStreamLabel]",
            "afade=t=out:st=$($edTime - $episodeFadeOutDuration):d=$episodeFadeOutDuration",
            "[episode_audio_$($audioStream.index)];",

            "[$audioStreamLabel]",
            "afade=t=in:st=$($edTime + $edLength - $episodeFadeInDuration):d=$episodeFadeInDuration",
            "[postcredits_audio_$($audioStream.index)];",

            "[episode_audio_$($audioStream.index)]", "[song_audio_$($audioStream.index)]", "[postcredits_audio_$($audioStream.index)]",
            "amix=inputs=3:normalize=0",
            "[spliced_audio_$($audioStream.index)];"
        )
    }

    $arguments += @(
        "-filter_complex", $complexFilterArguments,

        "-c:0", "copy",
        "-map", "0"
    )

    for ($audioStreamIdx = 0; $audioStreamIdx -lt $audioStreamsInfo.Count; $audioStreamIdx++) {
        $audioStream = $audioStreamsInfo[$audioStreamIdx]
        $audioStreamId = $audioStreamsInfo.Count + $audioStreamIdx

        $arguments += @(
            "-map", "[spliced_audio_$($audioStream.index)]",
            "-metadata:s:a:$audioStreamId", "language=$($audioStream.tags.language)",
            "-metadata:s:a:$audioStreamId", "title=""Altered ED"""
        )
    }

    $arguments += "$outPath"

    Write-Host $arguments
    &"ffmpeg" $arguments
}

function Main {
    Export-Ed ./episodes/03.mkv ./test.mkv
}

Main
