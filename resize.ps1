Add-Type -AssemblyName System.Drawing

$inputPath = "C:\Users\user\.gemini\antigravity\brain\2ad400b7-b076-4359-9393-a6900258c3d9\karkyra_app_icon_1776723353911.png"

$img = [System.Drawing.Image]::FromFile($inputPath)

$bm192 = New-Object System.Drawing.Bitmap 192, 192
$g192 = [System.Drawing.Graphics]::FromImage($bm192)
$g192.DrawImage($img, 0, 0, 192, 192)
$bm192.Save("d:\Karkyra\menu_app\web\icons\Icon-192.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bm192.Save("d:\Karkyra\menu_app\web\icons\Icon-maskable-192.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bm192.Save("d:\Karkyra\menu_app\web\favicon.png", [System.Drawing.Imaging.ImageFormat]::Png)

$bm512 = New-Object System.Drawing.Bitmap 512, 512
$g512 = [System.Drawing.Graphics]::FromImage($bm512)
$g512.DrawImage($img, 0, 0, 512, 512)
$bm512.Save("d:\Karkyra\menu_app\web\icons\Icon-512.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bm512.Save("d:\Karkyra\menu_app\web\icons\Icon-maskable-512.png", [System.Drawing.Imaging.ImageFormat]::Png)

$g192.Dispose()
$bm192.Dispose()
$g512.Dispose()
$bm512.Dispose()
$img.Dispose()
