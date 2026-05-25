# Post-render: clean LaTeX build artifacts, remove Quarto resource-scan artefacts,
# rename PDF and .tex output files, fix HTML navigation links, generate cover image.
# Usage: postrender.ps1 -Lang <lang> -OutputDir <output-dir>
# Windows equivalent of postrender.sh — called via postrender.bat.

param(
    [Parameter(Mandatory)][string]$Lang,
    [Parameter(Mandatory)][string]$OutputDir
)

# ── Remove spurious directories copied by Quarto's resource scanner ──────────
# Quarto copies all root-level directories to the output dir when mirroring the
# project structure for HTML books. _reference/ (archival sources) and the other
# profile's output dir (_thesis/ or _thesis-en/) are never needed in the output.
Remove-Item -Path "$OutputDir\_reference" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$OutputDir\_these_fr"  -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$OutputDir\_thesis-en" -Recurse -Force -ErrorAction SilentlyContinue

# ── Clean LaTeX build artifacts ───────────────────────────────────────────────
$exts = @("aux","log","maf","toc","lof","lot","blg","bbl","idx","ilg","ind","out","xmpdata")
foreach ($ext in $exts) {
    Get-ChildItem -Path "." -Filter "*.$ext" | Remove-Item -Force -ErrorAction SilentlyContinue
}
Get-ChildItem -Path "." -Filter "*.mtc*"   | Remove-Item -Force -ErrorAction SilentlyContinue
Remove-Item -Path "pdfa.xmpi"               -Force -ErrorAction SilentlyContinue
Remove-Item -Path "_glossaire-entries.tex"  -Force -ErrorAction SilentlyContinue
Remove-Item -Path "_gloss-acr.html"         -Force -ErrorAction SilentlyContinue
Remove-Item -Path "_gloss-main.html"        -Force -ErrorAction SilentlyContinue

# ── Rename these_<lang>.pdf/.tex → these_<lang>_<author>.pdf/.tex ────────────
$line   = (Select-String -Path "_quarto.yml" -Pattern "author:" | Select-Object -First 1).Line
$author = $line -replace '.*author:\s*', '' -replace '"', '' -replace "'", ''

if ([string]::IsNullOrWhiteSpace($author)) { exit 0 }

# Normalise: accents → ASCII, uppercase → lowercase, hyphens/spaces → _, rest removed.
$nfd   = $author.Normalize([System.Text.NormalizationForm]::FormD)
$ascii = [regex]::Replace($nfd, '\p{M}', '')
$slug  = ($ascii.ToLower() `
          -replace '[ \t-]', '_' `
          -replace "[']",    '_' `
          -replace '[^a-z0-9_]', '' `
          -replace '_+',     '_').Trim('_')

if ([string]::IsNullOrEmpty($slug)) { exit 0 }

$srcPdf = "$OutputDir\these_$Lang.pdf"
$dstPdf = "$OutputDir\these_${Lang}_$slug.pdf"
$srcTex = "these_$Lang.tex"
$dstTex = "these_${Lang}_$slug.tex"

$pdfGenerated = $false
if (Test-Path $srcPdf) {
    Move-Item $srcPdf $dstPdf
    $pdfGenerated = $true
    Write-Host "PDF renamed: $dstPdf"
    # Keep a copy under the canonical output-file name so Quarto's preview server can
    # stat it after the rename. Without this, `quarto preview` crashes with:
    #   NotFound: No such file or directory: stat '_these_<lang>/these_<lang>.pdf'
    # The copy is overwritten by pdflatex on every subsequent render and is gitignored. /
    # Copie au nom canonique pour le serveur de preview. Écrasée à chaque re-rendu.
    Copy-Item $dstPdf $srcPdf
}

# ── Fix HTML navigation links and update the PDF download link ────────────────
# Quarto emits .pdf extensions for ALL book navigation hrefs in HTML pages when
# both PDF and HTML formats are registered (cross-format artefact). Two-pass fix:
# Pass 1 — all relative .pdf hrefs → .html  (navigation links)
# Pass 2 — these_<lang>.html → these_<lang>_<slug>.pdf  (restore download link)
# Pattern/replacement are built as plain strings so that PowerShell variable
# interpolation does not conflict with .NET regex backreference $1.
$pat2  = 'href="([^"]*these_' + $Lang + ')\.html"'
$repl2 = 'href="$1_' + $slug + '.pdf"'

Get-ChildItem -Path $OutputDir -Filter "*.html" -Recurse | ForEach-Object {
    $content = Get-Content $_.FullName -Raw -Encoding UTF8
    if ($content -match '\.pdf"') {
        $content = $content -replace 'href="([^:"]*?)\.pdf"', 'href="$1.html"'
        $content = $content -replace $pat2, $repl2
        Set-Content $_.FullName $content -NoNewline -Encoding UTF8
    }
}
Write-Host "HTML links updated → these_${Lang}_$slug.pdf"

if (Test-Path $srcTex) {
    Move-Item $srcTex $dstTex
    Write-Host "TeX renamed: $dstTex"
}

# ── Generate cover image from PDF page 1 ──────────────────────────────────────
# Saves page 1 of the compiled PDF as images/cover.png for the HTML cover page.
# Requires poppler (pdftoppm) or ImageMagick (magick / convert + Ghostscript).
#   winget install oschwartz10612.poppler   →  pdftoppm
#   winget install ImageMagick.ImageMagick  →  magick
# Only regenerated when a new PDF was produced; HTML-only renders reuse the
# existing cover.png (Quarto copies images/ to the output dir during render).
if ($pdfGenerated -and (Test-Path $dstPdf)) {
    $coverSrc = "images\cover.png"
    $coverDst = "$OutputDir\images\cover.png"

    if (Get-Command pdftoppm -ErrorAction SilentlyContinue) {
        pdftoppm -r 150 -png -singlefile -f 1 -l 1 $dstPdf "images\cover"
        Write-Host "Cover image generated: $coverSrc"
    } elseif (Get-Command magick -ErrorAction SilentlyContinue) {
        # ImageMagick v7+: use 'magick' instead of 'convert'
        magick -density 150 "${dstPdf}[0]" -quality 90 $coverSrc
        Write-Host "Cover image generated: $coverSrc"
    } elseif (Get-Command convert -ErrorAction SilentlyContinue) {
        # ImageMagick v6 / legacy: 'convert' + Ghostscript must be installed
        convert -density 150 "${dstPdf}[0]" -quality 90 $coverSrc
        Write-Host "Cover image generated: $coverSrc"
    } else {
        Write-Warning "Install 'poppler' (pdftoppm) or 'ImageMagick' (magick) to auto-generate $coverSrc."
    }

    if (Test-Path $coverSrc) {
        New-Item -ItemType Directory -Path "$OutputDir\images" -Force | Out-Null
        Copy-Item $coverSrc $coverDst -Force
        Write-Host "Cover image copied to: $coverDst"
    }
}
