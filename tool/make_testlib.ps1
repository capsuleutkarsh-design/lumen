# Builds a small synthetic test library in _scratch\testlib with ffmpeg.
# Never touches real music. Run:  powershell -ExecutionPolicy Bypass -File tool\make_testlib.ps1
$ErrorActionPreference = 'Stop'
$ff = 'C:\Users\AI10482\AppData\Local\Programs\ffmpeg_root\ffmpeg-9.0.1-essentials_build\bin\ffmpeg.exe'
$root = Join-Path (Split-Path $PSScriptRoot -Parent) '_scratch\testlib'
if (Test-Path $root) { Remove-Item -Recurse -Force $root }
New-Item -ItemType Directory $root | Out-Null

function Cover($path, $c0, $c1) {
  & $ff -v error -y -f lavfi -i "gradients=s=600x600:c0=${c0}:c1=${c1}:x0=0:y0=0:x1=600:y1=600:d=1" -frames:v 1 $path
}

# ffmpeg writes FLAC without a SEEKTABLE; files marked seek=$true get one from tool\add_seektable.dart.
$withSeek = @()

# $t: hashtable with dir,file,title,artist,albumArtist,album,track,tracks,disc,discs,year,genre,dur,rate,fmt,cover,comp,seek,lyrics
function Track($t) {
  $out = Join-Path $root "$($t.dir)\$($t.file)"
  New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
  $f = 110 * [math]::Pow(2, $t.track / 12.0) * $t.disc
  $src = "aevalsrc='0.12*sin(2*PI*$f*t)*(0.6+0.4*sin(2*PI*0.25*t))+0.05*sin(2*PI*$($f*1.5)*t)|0.12*sin(2*PI*$($f*1.01)*t)*(0.6+0.4*cos(2*PI*0.25*t))+0.05*sin(2*PI*$($f*2)*t)':s=$($t.rate):d=$($t.dur)"
  $meta = @('-metadata', "title=$($t.title)", '-metadata', "artist=$($t.artist)", '-metadata', "album=$($t.album)",
            '-metadata', "track=$($t.track)/$($t.tracks)", '-metadata', "date=$($t.year)", '-metadata', "genre=$($t.genre)")
  if ($t.albumArtist) { $meta += '-metadata', "album_artist=$($t.albumArtist)" }
  if ($t.discs) { $meta += '-metadata', "disc=$($t.disc)/$($t.discs)" }
  if ($t.comp) { $meta += '-metadata', 'compilation=1' }
  if ($t.lyrics) { $meta += '-metadata', "lyrics=$($t.lyrics)" }
  $codec = switch ($t.fmt) {
    'flac16' { '-c:a', 'flac', '-sample_fmt', 's16' }
    'flac24' { '-c:a', 'flac', '-sample_fmt', 's32', '-bits_per_raw_sample', '24' }
    'mp3'    { '-c:a', 'libmp3lame', '-b:a', '256k', '-id3v2_version', '3' }
    'alac'   { '-c:a', 'alac', '-sample_fmt', 's16p' }
    'wav'    { '-c:a', 'pcm_s24le' }
  }
  if ($t.cover -and $t.fmt -ne 'wav') {
    & $ff -v error -y -f lavfi -i $src -i $t.cover -map 0:a -map 1:v -c:v copy -disposition:v attached_pic @meta @codec $out
  } else {
    & $ff -v error -y -f lavfi -i $src @meta @codec $out
  }
  if ($t.fmt -like 'flac*' -and $t.seek) { $script:withSeek += $out }
}

# 1. Aurora Fields - Northern Lights: FLAC 16/44.1, folder.jpg + embedded, odd tracks without seektable
$d = 'Aurora Fields\Northern Lights (2017)'; New-Item -ItemType Directory -Force "$root\$d" | Out-Null
Cover "$root\$d\folder.jpg" '0x1d3557' '0x2ec4b6'
$titles = 'First Light','Polar Drift','Magnetic','Slow Arc','Corona','Solar Wind','Green Veil','Last Light'
for ($i = 1; $i -le 8; $i++) {
  Track @{ dir=$d; file=('{0:D2} {1}.flac' -f $i, $titles[$i-1]); title=$titles[$i-1]; artist='Aurora Fields'; albumArtist='Aurora Fields'
    album='Northern Lights'; track=$i; tracks=8; disc=1; year=2017; genre='Ambient'; dur=(20 + 9*$i); rate=44100; fmt='flac16'
    cover="$root\$d\folder.jpg"; seek=($i % 2 -eq 0); lyrics=$(if ($i -eq 3) { "Unsynced words for Magnetic`nSecond line`nThird line" }) }
}

# 2. The Tidal Set - Deep Water: FLAC 24/96, two discs, cover.jpg only
$d = 'The Tidal Set\Deep Water'; New-Item -ItemType Directory -Force "$root\$d" | Out-Null
Cover "$root\$d\cover.jpg" '0x03045e' '0x48cae4'
$titles = 'Undertow','Kelp Forest','Pressure','Abyssal','Bioluminescence','Thermocline','Currents','Surface'
for ($i = 1; $i -le 8; $i++) {
  $disc = if ($i -le 4) { 1 } else { 2 }; $tn = (($i - 1) % 4) + 1
  Track @{ dir="$d\CD$disc"; file=('{0:D2} {1}.flac' -f $tn, $titles[$i-1]); title=$titles[$i-1]; artist='The Tidal Set'; albumArtist='The Tidal Set'
    album='Deep Water'; track=$tn; tracks=4; disc=$disc; discs=2; year=2021; genre='Jazz'; dur=(25 + 7*$i); rate=96000; fmt='flac24'; seek=$true }
}
Copy-Item "$root\$d\cover.jpg" "$root\$d\CD1\cover.jpg"; Copy-Item "$root\$d\cover.jpg" "$root\$d\CD2\cover.jpg"

# 3. Mira Kade - Hi-Res Sketches: FLAC 24/192, no seektable, embedded cover only, .lrc on track 1
$d = 'Mira Kade\Hi-Res Sketches'; New-Item -ItemType Directory -Force "$root\$d" | Out-Null
$cov = "$root\cover_mira.jpg"; Cover $cov '0x7b2cbf' '0xff006e'
$titles = 'Etude in Glass','Paper Birds','Interlude','Chalk Lines','Graphite','Coda'
for ($i = 1; $i -le 6; $i++) {
  Track @{ dir=$d; file=('{0:D2} {1}.flac' -f $i, $titles[$i-1]); title=$titles[$i-1]; artist='Mira Kade'; albumArtist='Mira Kade'
    album='Hi-Res Sketches'; track=$i; tracks=6; disc=1; year=2023; genre='Classical'; dur=(20 + 4*$i); rate=192000; fmt='flac24'; cover=$cov; seek=$false }
}
Remove-Item $cov
@'
[ar:Mira Kade]
[ti:Etude in Glass]
[00:00.50]Light falls through the glass
[00:03.00]Every line a little brighter
[00:06.00]Hold the note
[00:09.00]Let it ring
[00:12.00]Paper, chalk and graphite
[00:15.00]Sketching in the quiet
[00:18.00]Fade to white
'@ | Set-Content -Encoding utf8 "$root\$d\01 Etude in Glass.lrc"

# 4. Various Artists - Summer Mix: compilation, mixed formats, folder.jpg
$d = 'Compilations\Summer Mix'; New-Item -ItemType Directory -Force "$root\$d" | Out-Null
Cover "$root\$d\folder.jpg" '0xffbe0b' '0xfb5607'
$mix = @(
  @('Heatwave','Sunny Days','mp3'), @('Boardwalk','The Pier Kids','mp3'), @('Lemonade','Citrus','mp3'),
  @('Golden Hour','Aurora Fields','alac'), @('Tide Pools','The Tidal Set','wav'), @('Sundial','Mira Kade','flac16'), @('Late August','Citrus','flac24'))
for ($i = 1; $i -le $mix.Count; $i++) {
  $m = $mix[$i-1]; $ext = @{ mp3='mp3'; alac='m4a'; wav='wav'; flac16='flac'; flac24='flac' }[$m[2]]
  Track @{ dir=$d; file=('{0:D2} {1}.{2}' -f $i, $m[0], $ext); title=$m[0]; artist=$m[1]; albumArtist='Various Artists'
    album='Summer Mix'; track=$i; tracks=$mix.Count; disc=1; year=2019; genre='Pop'; dur=(30 + 8*$i); rate=$(if ($m[2] -eq 'flac24') { 96000 } else { 44100 })
    fmt=$m[2]; cover="$root\$d\folder.jpg"; comp=$true; seek=$true }
}
& C:\dev\flutter\bin\dart.bat run (Join-Path $PSScriptRoot 'add_seektable.dart') @withSeek
Get-ChildItem -Recurse $root -File | Measure-Object Length -Sum | ForEach-Object { "$($_.Count) files, $([math]::Round($_.Sum/1MB)) MB" }
