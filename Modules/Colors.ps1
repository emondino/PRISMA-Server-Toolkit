function Write-SectionLine {
    param(
        [string]$Color = "DarkCyan"
    )

    Write-Host "===========================================" -ForegroundColor $Color
}

function Write-Title {
    param(
        [string]$Text
    )

    Write-Host ""
    Write-SectionLine -Color "DarkCyan"
    Write-Host (" {0}" -f $Text) -ForegroundColor Cyan
    Write-SectionLine -Color "DarkCyan"
}

function Write-SubTitle {
    param(
        [string]$Text
    )

    Write-Host ""
    Write-Host $Text -ForegroundColor White
    Write-Host "-------------------------------------------" -ForegroundColor DarkGray
}

function Write-Info {
    param(
        [string]$Text
    )

    Write-Host $Text -ForegroundColor Gray
}

function Write-Success {
    param(
        [string]$Text
    )

    Write-Host $Text -ForegroundColor Green
}

function Write-WarningText {
    param(
        [string]$Text
    )

    Write-Host $Text -ForegroundColor Yellow
}

function Write-ErrorText {
    param(
        [string]$Text
    )

    Write-Host $Text -ForegroundColor Red
}

function Write-Highlight {
    param(
        [string]$Text
    )

    Write-Host $Text -ForegroundColor Magenta
}