Add-Type -AssemblyName System.Drawing

$srcDir = Join-Path $PSScriptRoot '..' | Resolve-Path
$dstDir = Join-Path $PSScriptRoot 'img'
New-Item -ItemType Directory -Force -Path $dstDir | Out-Null

$maxSide = 1600
$quality = 80

$jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
$encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
$encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$quality)

function Get-Orientation([System.Drawing.Image]$img) {
    try {
        $v = $img.GetPropertyItem(274).Value
        return [BitConverter]::ToUInt16($v, 0)
    } catch {
        return 1
    }
}

function Rotate-Image([System.Drawing.Bitmap]$src, [int]$degrees) {
    $flip = switch ($degrees) {
        90  { [System.Drawing.RotateFlipType]::Rotate90FlipNone }
        180 { [System.Drawing.RotateFlipType]::Rotate180FlipNone }
        270 { [System.Drawing.RotateFlipType]::Rotate270FlipNone }
        default { [System.Drawing.RotateFlipType]::RotateNoneFlipNone }
    }
    $copy = New-Object System.Drawing.Bitmap($src)
    $copy.RotateFlip($flip)
    return $copy
}

$files = Get-ChildItem -Path $srcDir -File | Where-Object { $_.Extension.ToLower() -in '.jpg', '.jpeg' }
$rows = foreach ($f in $files) {
    $src = [System.Drawing.Image]::FromFile($f.FullName)
    $canvas = $null
    try {
        $orient = Get-Orientation $src
        if ($orient -in 3, 6, 8) {
            $deg = @{ 3 = 180; 6 = 90; 8 = 270 }[[int]$orient]
            $canvas = Rotate-Image ([System.Drawing.Bitmap]$src) $deg
        } else {
            $canvas = $src
        }

        $ratio = [Math]::Min(1.0, $maxSide / [Math]::Max($canvas.Width, $canvas.Height))
        $w = [Math]::Max(1, [int][Math]::Round($canvas.Width * $ratio))
        $h = [Math]::Max(1, [int][Math]::Round($canvas.Height * $ratio))

        $bmp = New-Object System.Drawing.Bitmap($w, $h)
        $g2 = [System.Drawing.Graphics]::FromImage($bmp)
        $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g2.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g2.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g2.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g2.DrawImage($canvas, 0, 0, $w, $h)
        $g2.Dispose()

        $outPath = Join-Path $dstDir ($f.BaseName + '.jpg')
        $bmp.Save($outPath, $jpegCodec, $encParams)
        $bmp.Dispose()

        if ($canvas -ne $src) { $canvas.Dispose() }

        [PSCustomObject]@{
            Name   = $f.Name
            Output = $f.BaseName + '.jpg'
            Width  = $w
            Height = $h
            SizeKB = [Math]::Round((Get-Item $outPath).Length / 1KB)
        }
    } finally {
        $src.Dispose()
    }
}

$rows | Format-Table -AutoSize
$totalMB = [Math]::Round((Get-ChildItem -Path $dstDir -File | Measure-Object Length -Sum).Sum / 1MB, 1)
Write-Host "共 $($rows.Count) 张，总大小约 $totalMB MB"
