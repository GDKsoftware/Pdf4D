param(
    [Parameter(Mandatory)][string]$OutputFolder
)
# Draws the placeholder palette icons (PNG, 24 and 32 pixels) and links them as BITMAP resources into one .res file.
# Resource names: the class name in capitals (24 x 24) and the same with _32 (32 x 32). The bottom-left pixel is the transparent colour.
Add-Type -AssemblyName System.Drawing

$icons = [ordered]@{
    TPdf4DDocument    = @{ Letters = 'D';  Color = '#1E6FD9' }
    TPdf4DSkiaBackend = @{ Letters = 'Sk'; Color = '#7A3FC4' }
    TPdf4DPageView    = @{ Letters = 'P';  Color = '#2E8B57' }
    TPdf4DThumbnails  = @{ Letters = 'Th'; Color = '#D98A1E' }
    TPdf4DOutlineView = @{ Letters = 'Ol'; Color = '#B5483A' }
    TPdf4DSearchBar   = @{ Letters = 'Sb'; Color = '#1E9CA8' }
    TPdf4DToolbar     = @{ Letters = 'Tb'; Color = '#5A6B7B' }
    TPdf4DViewer      = @{ Letters = 'V';  Color = '#C42E5C' }
    TPdf4DPrintDialog = @{ Letters = 'Pr'; Color = '#6B7F1E' }
}

function New-IconBitmap([int]$Size, [string]$Letters, [string]$Color) {
    $bitmap = New-Object System.Drawing.Bitmap $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = 'AntiAlias'
    $graphics.TextRenderingHint = 'AntiAliasGridFit'
    $graphics.Clear([System.Drawing.Color]::Fuchsia)
    $fill = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($Color))
    $margin = [Math]::Max(1, [int]($Size / 12))
    $graphics.FillRectangle($fill, $margin, $margin, $Size - 2 * $margin, $Size - 2 * $margin)
    $fontSize = if ($Letters.Length -gt 1) { $Size * 0.38 } else { $Size * 0.5 }
    $font = New-Object System.Drawing.Font 'Segoe UI', $fontSize, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = 'Center'
    $format.LineAlignment = 'Center'
    $rect = New-Object System.Drawing.RectangleF 0, 0, $Size, $Size
    $graphics.DrawString($Letters, $font, [System.Drawing.Brushes]::White, $rect, $format)
    $graphics.Dispose()
    return $bitmap
}

function Get-ResourceEntry([string]$Name, [byte[]]$Data) {
    $stream = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter $stream
    $nameBytes = [System.Text.Encoding]::Unicode.GetBytes($Name.ToUpperInvariant() + [char]0)
    # header: DataSize, HeaderSize, TYPE (ordinal RT_BITMAP = 2), NAME, padding to DWORD, then DataVersion, flags, language, version, characteristics
    $headerSize = 8 + 4 + $nameBytes.Length + 16
    $padding = (4 - (($headerSize - 16) % 4)) % 4
    $headerSize += $padding
    $writer.Write([uint32]$Data.Length)
    $writer.Write([uint32]$headerSize)
    $writer.Write([uint16]0xFFFF)
    $writer.Write([uint16]2)
    $writer.Write($nameBytes)
    $writer.Write([byte[]]::new($padding))
    $writer.Write([uint32]0)
    $writer.Write([uint16]0x1030)
    $writer.Write([uint16]0)
    $writer.Write([uint32]0)
    $writer.Write([uint32]0)
    $writer.Write($Data)
    $dataPadding = (4 - ($Data.Length % 4)) % 4
    $writer.Write([byte[]]::new($dataPadding))
    $writer.Flush()
    return $stream.ToArray()
}

New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null
$resource = New-Object System.IO.MemoryStream
# The empty 32-bit resource that starts a .res file
$resource.Write([byte[]](0,0,0,0, 0x20,0,0,0, 0xFF,0xFF,0,0, 0xFF,0xFF,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0), 0, 32)

foreach ($className in $icons.Keys) {
    foreach ($size in 24, 32) {
        $bitmap = New-IconBitmap $size $icons[$className].Letters $icons[$className].Color
        $bitmap.Save((Join-Path $OutputFolder "$className$size.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        $bmpStream = New-Object System.IO.MemoryStream
        $bitmap.Save($bmpStream, [System.Drawing.Imaging.ImageFormat]::Bmp)
        $bitmap.Dispose()
        # A BITMAP resource is the DIB: the file without its 14-byte file header
        $bmpBytes = $bmpStream.ToArray()
        $dib = New-Object byte[] ($bmpBytes.Length - 14)
        [Array]::Copy($bmpBytes, 14, $dib, 0, $dib.Length)
        $resourceName = if ($size -eq 24) { $className } else { "${className}_32" }
        $entry = Get-ResourceEntry $resourceName $dib
        $resource.Write($entry, 0, $entry.Length)
    }
}

[System.IO.File]::WriteAllBytes((Join-Path $OutputFolder 'Pdf4D.Vcl.Palette.res'), $resource.ToArray())
