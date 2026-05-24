[🇫🇷 Lire en français](README.fr.md)

# quarto-cnam-thesis

A [Quarto](https://quarto.org) extension for writing a doctoral thesis at the
[Conservatoire national des arts et métiers (Cnam)](https://www.cnam.fr).
Produces a **PDF** that conforms to the official Cnam 2024–2025 template and a
**navigable HTML** version for online sharing and accessibility.

## Features

- PDF/A-1b compliant output (archival standard required by Cnam)
- Official Cnam cover page: jury, logos, defence date, supervisors
- Chapter mini-tables of contents (`minitoc`)
- Differentiated page numbering: roman (front matter) / arabic (body) / Roman (appendices)
- IEEE-style bibliography (`IEEEtran-francais`, BibTeX)
- Optional glossary and acronym support (`glossaries` package)
- Bilingual: thesis language can be French or English while the administrative structure remains French
- HTML output with Cnam branding (red topbar, frosted-glass sidebar, responsive)
- HTML home page with auto-generated cover image (extracted from PDF page 1), jury table and thesis metadata
- PDF download button in the HTML sidebar, linking to the compiled PDF
- Glossary and acronym pages rendered in both PDF and HTML
- Collaborative margin comments via the [`quarto-comments`](https://github.com/zinc75/quarto-comments) extension

## Prerequisites

| Tool | Minimum version |
|------|----------------|
| [Quarto](https://quarto.org/docs/get-started/) | 1.4 |
| A LaTeX distribution with **pdflatex** | TeX Live 2023+ or MiKTeX |
| Python 3 _(post-render slug generation)_ | 3.8 |

> **Windows users without WSL:** replace `.sh` with `.bat` in the `post-render`
> entries of `_quarto-fr.yml` / `_quarto-en.yml`.

## Installation

```bash
quarto use template <org>/quarto-cnam-thesis
```

Quarto copies the template into the current directory (excluding development
files listed in `.quartoignore`). You can then edit `_quarto.yml` and start
writing.

## Rendering

```bash
# French thesis — PDF + HTML → _these_fr/
quarto render --profile fr

# English thesis — PDF + HTML → _thesis-en/
quarto render --profile en

# PDF only (French)
quarto render --profile fr --to cnam-thesis-pdf

# HTML only — requires a prior full render and --no-clean
quarto render --profile fr --to cnam-thesis-html --no-clean
```

The post-render script renames the output to `these_<lang>_<author>.pdf` and
`these_<lang>_<author>.tex`, and generates `images/cover.png` from PDF page 1
(requires `poppler` or `ImageMagick`).

> **Always use `--profile fr` or `--profile en`.** Running `quarto render`
> without a profile fails because the chapter list is defined in the profiles,
> not in `_quarto.yml`.

## Configuration

Fill in the thesis metadata in `_quarto.yml`:

```yaml
book:
  title: "Thesis title"
  author: "Firstname LASTNAME"

date-soutenance: "1 January 2025"   # use date-soutenance, not date
discipline: "60th CNU section — Mechanics, Mechanical Engineering, Civil Engineering"
specialite: "Acoustics"
ecole-doctorale: "Abbé Grégoire"    # or "SMI"
laboratoire: "LMSSC"
directeur: "Prof. Firstname LASTNAME, Université …"
# codirecteur: "…"    # optional, HDR required
# coencadrant: "…"    # optional, without HDR

jury:
  - nom: "Ms Firstname LASTNAME"
    titre: "Title, Unit, University"
    role: "Présidente"
  - nom: "Mr Firstname LASTNAME"
    titre: "Title, Unit, University"
    role: "Rapporteur"
  # …
```

Then add your chapters to `_quarto-fr.yml` (or `_quarto-en.yml`):

```yaml
book:
  chapters:
    - index.qmd
    - content_fr/liminaire/remerciements.qmd
    - content_fr/chapitres/01-introduction.qmd
    - content_fr/chapitres/02-chapitre.qmd
    # …
    - content_fr/postliminaire/conclusion.qmd
    - content_fr/postliminaire/bibliographie.qmd
  appendices:
    - content_fr/postliminaire/annexes.qmd
```

## Repository structure

```
quarto-cnam-thesis/
├── _extensions/cnam-thesis/    ← LaTeX template, SCSS, Lua filters, shortcodes
│   ├── _extension.yml
│   ├── template.tex
│   ├── partials/before-body.tex
│   ├── thesis.scss
│   ├── cnam-thesis.lua
│   └── shortcodes.lua
├── _scripts/                   ← post-render (cleanup, rename, cover image)
│   ├── postrender.sh           ← macOS / Linux
│   ├── postrender.bat          ← Windows wrapper
│   └── postrender.ps1          ← Windows (PowerShell)
├── content_fr/                 ← French thesis content (edit this)
│   ├── liminaire/              ← front matter (acknowledgements, abstract, …)
│   ├── chapitres/              ← thesis chapters
│   └── postliminaire/          ← back matter (conclusion, bibliography, appendices)
├── content_en/                 ← English thesis content (same structure)
├── images/                     ← Cnam logos — do not remove
├── references.bib              ← BibTeX bibliography (project root, required)
├── IEEEtran-francais.bst       ← bibliography style (project root, required)
├── index.qmd                   ← HTML cover page
├── _quarto.yml                 ← main configuration
├── _quarto-fr.yml              ← French profile
└── _quarto-en.yml              ← English profile
```

## Key design constraints

- **pdflatex only** — the template uses `pdfx` (PDF/A) and `pdftex`-specific packages.
  XeLaTeX and LuaLaTeX are not supported.
- `references.bib` and `IEEEtran-francais.bst` **must** be at the project root —
  BibTeX (natbib mode) strips directory paths from `\bibliography{}`.
- Use `date-soutenance:` for the defence date, not `date:` — Quarto parses `date:` as
  a JavaScript Date and produces "Invalid Date" for French date strings.

## Known limitations (HTML output)

The HTML output is functional. The only PDF feature without a direct HTML equivalent is:

- **List of figures / list of tables** — PDF only; Quarto's sidebar provides navigation instead

Contributions are welcome.

## License

[MIT](LICENSE)
