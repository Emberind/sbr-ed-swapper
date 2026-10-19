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

function Export-Ed {
    param(
        [Parameter(Mandatory=$true)][String]$path,
        [Parameter(Mandatory=$true)][String]$outPath
    )

    if (-not (Test-Path -Path $path -PathType Leaf)) {
        Write-Error -Message "File not found '$path'" -ErrorAction Stop
    }

    $edTime = $(Get-EdTimestamp $path)

    $edLength = 90
    $songStartTime = 7.60

    $songFadeInDuration = 15.76 - $songStartTime
    $songFadeOutDuration = 6.39

    $episodeFadeOutDuration = 0.2
    $episodeFadeInDuration = 0.2

    ffmpeg `
        -i "$path" `
        `
        -ss $songStartTime `
        -t $edLength `
        -i "./Bon Jovi - Wanted Dead Or Alive.mp3" `
        `
        -filter_complex (
            "[0:a:0] " +
            "afade=t=out:st=$($edTime - $episodeFadeOutDuration):d=$($episodeFadeOutDuration)" +
            "[episode_audio];" +
            "" +
            "[0:a:0] " +
            "afade=t=in:st=$($edTime + $edLength - $episodeFadeInDuration):d=$($episodeFadeInDuration) " +
            "[postcredits_audio];" +
            "" +
            "[1:a] " +
            "afade=t=in:d=$($songFadeInDuration):curve=qsin," +
            "afade=t=out:st=$($edLength - $songFadeOutDuration):d=$songFadeOutDuration," +
            "adelay=delays=$($edTime)s:all=1 " +
            "[song_audio];" +
            "" +
            "[episode_audio] [song_audio] [postcredits_audio] " +
            "amix=inputs=3:normalize=0 " +
            "[spliced_audio]"
        ) `
        `
        -map "0:v" `
        -c:v copy `
        -map "[spliced_audio]" `
        "$outPath"
}

function Main {
    Export-Ed ./episodes/03.mkv ./test.mkv
}

Main
