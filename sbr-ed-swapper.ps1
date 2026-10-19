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

    Write-Host $chapters

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

    $leadTime = 1
    $edTime = $(Get-EdTimestamp $path) - $leadTime

    $edLength = 90 + $leadTime
    $songStartTime = 7.60 - $leadTime
    $fadeOutDuration = 6.39

    $fadeInDuration = 15.76 - $songStartTime

    ffmpeg `
        -ss $edTime `
        -t $edLength `
        -i "$path" `
        -ss $songStartTime `
        -t $edLength `
        -i "./Bon Jovi - Wanted Dead Or Alive.mp3" `
        -af "afade=t=in:st=$($lead):d=$($fadeInDuration):curve=qsin,afade=t=out:st=$($edLength - $fadeOutDuration):d=$fadeOutDuration" `
        -map 0:v `
        -map 1:a `
        -c:v copy `
        "$outPath"
}

function Add-Ed {
    param(
        [Parameter(Mandatory=$true)][String]$path,
        [Parameter(Mandatory=$true)][String]$outPath
    )

    if (-not (TestPath -Path $path -PathType Leaf)) {
        Write-Error -Message "File not found '$path'" -ErrorAction Stop
    }

    $edTime = Get-EdTimestamp $path
}

function Main {
    Export-Ed ./episodes/03.mkv ./test.mkv
}

Main
