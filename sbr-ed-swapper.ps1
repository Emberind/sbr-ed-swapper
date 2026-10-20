param(
    [String]$EpisodePath,
    [String]$SongPath,
    [String]$OutPath,
    [String]$SongName
)

class SongData {
    [ValidateNotNull()][double]$StartTime
    [ValidateNotNull()][double]$FadeInDuration
    [ValidateNotNull()][double]$FadeOutDuration
    [ValidateNotNull()][double]$Volume
}

$global:SongDataDict = @{
    "wanted dead or alive" = [SongData]@{
        StartTime = 8.33
        FadeInDuration = 15.76 - 8.33
        FadeOutDuration = 6.39
        Volume = 0.85
    }
}

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

    return $(ffprobe `
        -loglevel error `
        -print_format json `
        -select_streams a `
        -show_streams `
        "$path" | ConvertFrom-Json).streams
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

    $edTimestampShift = -10 / 23.976
    $edTime = $(Get-EdTimestamp $episodePath) + $edTimestampShift

    $edLength = 90

    $episodeFadeOutDuration = 0.2
    $episodeFadeInDuration = 0.2

    $episodeStreamId = 0
    $songStreamId = 1


    $arguments = @(
        "-i", $episodePath,
        "-ss", $songData.StartTime,
        "-t", $edLength,
        "-i", $songPath
    )

    $complexFilterArguments = @(
        "[$($songStreamId):a]",
        (
            "afade=type=in:duration=$($songData.FadeInDuration):curve=qsin:unity=$($songData.Volume)," +
            "afade=type=out:start_time=$($edLength - $songData.FadeOutDuration):duration=$($songData.FadeOutDuration):unity=$($songData.Volume)," +
            "adelay=delays=$($edTime * 1000):all=1,",
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
            "afade=type=in:start_time=$($edTime + $edLength - $episodeFadeInDuration):duration=$episodeFadeInDuration",
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
            "-map", "[spliced_audio_$($audioStream.index)]",
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

    $arguments += "$outPath"

    Write-Host $arguments
    &"ffmpeg" $arguments
}

if ($EpisodePath -ne "") {
    Add-SwappedEd -EpisodePath $EpisodePath -SongPath $SongPath -OutPath $OutPath -SongName $SongName
}
