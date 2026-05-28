[🇫🇷 Lire en français](README.fr.md)


<img width="426" height="213" alt="Quarto-cnam-thesis-template_social_preview 001" src="https://github.com/user-attachments/assets/ecf08076-8343-4fc9-b5bb-c41d2542f36f" />


# quarto-cnam-thesis

A [Quarto](https://quarto.org) extension for writing a doctoral thesis at the
[Conservatoire national des arts et métiers (Cnam)](https://www.cnam.fr).
Produces a **PDF** that conforms to the official Cnam 2024–2025 template and a
**navigable HTML** version for online sharing and accessibility.

## Features

- Output validated against the PDF/A-1b criteria of [facile.cines.fr](https://facile.cines.fr) (CINES), the official validator for theses.fr deposits
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

| Tool | Minimum version | Notes |
|------|----------------|-------|
| [Quarto](https://quarto.org/docs/get-started/) | 1.4 | |
| LaTeX distribution with **pdflatex** | TeX Live 2023+ or MiKTeX | |
| Python 3 | 3.10 | required by post-render scripts and by Quarto to execute code cells |

> **Windows users without WSL:** replace `.sh` with `.bat` in the `post-render`
> entries of `_quarto-fr.yml` / `_quarto-en.yml`.

## Installation

```bash
quarto use template zinc75/quarto-cnam-thesis
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


## Python setup

### Do you need Python at all?

Python serves two purposes in this template:

1. **Post-render scripts** — always needed (slug generation, file renaming,
   cover image). Python 3.8+ is sufficient; no extra packages required.
2. **Executable code chunks** — only needed if your thesis contains computed
   figures (matplotlib…) or tables (pandas…). A text-only thesis with static
   images requires nothing beyond point 1.

If your thesis has no Python code cells, a bare Python 3 installation is enough
and you can skip the rest of this section.

### Packages for executable code

The packages required for the template's own example chapters are listed in
`requirements.txt`:

```
numpy>=1.24      # numerical arrays
matplotlib>=3.7  # figures
pandas>=2.0      # data tables
tabulate>=0.9    # Markdown table output (used by pandas .to_markdown())
```

Quarto also requires **Jupyter** to execute Python code cells. It is installed
automatically by the methods below.

### Recommended: `uv`

[`uv`](https://docs.astral.sh/uv/) is a modern package manager (written in Rust)
that installs Python, creates virtual environments, and manages packages — all
with one tool. No prior Python installation is needed.

**Why `uv` for a thesis?** You only need a handful of packages for one project.
Installing them globally pollutes your system and risks version conflicts. `uv`
creates a self-contained `.venv/` folder in the project directory; Quarto finds
it automatically — no manual activation needed before `quarto render`.

**Step 1 — Install `uv`** (once, system-wide):

```bash
# macOS / Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# Windows (PowerShell — run once as a regular user)
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

**Step 2 — Set up the project** (inside the thesis directory):

```bash
uv python install 3.12          # download and install Python 3.12
uv venv                         # create .venv/ in the current directory
uv pip install -r requirements.txt   # install all packages + Jupyter
```

That's it. Quarto detects `.venv/` and uses it automatically.

> Add your own packages with `uv pip install <package>` (not `pip install` —
> this ensures they go into `.venv/`, not system Python).

### Alternative: standard `venv` + `pip`

If Python 3.10+ is already installed:

```bash
python -m venv .venv

# Activate (once per terminal session):
source .venv/bin/activate          # macOS / Linux
.venv\Scripts\activate             # Windows (cmd)
.venv\Scripts\Activate.ps1         # Windows (PowerShell)

pip install jupyter -r requirements.txt
```

Unlike `uv`, the virtual environment must be activated before every `quarto render`
session, or Quarto must be told which Python to use:

```bash
quarto render --profile fr --execute-env QUARTO_PYTHON=.venv/bin/python
```

> **conda users:** `conda create -n mythesis python=3.12 && conda activate mythesis
> && pip install jupyter -r requirements.txt` works too. Note that Quarto looks for
> `jupyter` on `PATH` — make sure to activate the conda environment before rendering.

> **pyenv users:** install the target Python version with pyenv, then use the
> standard `venv` workflow above.

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

## Depositing to theses.fr

Before the final deposit, validate your PDF against the CINES criteria — the same
check run by theses.fr. Add `validate` as a third argument in `_quarto-fr.yml` (or
`_quarto-en.yml`) and re-render:

```yaml
# In _quarto-fr.yml:
project:
  post-render:
    - ./_scripts/postrender.sh fr _these_fr validate
    # Windows: ./_scripts/postrender.bat fr _these_fr validate
```

The post-render script will send the PDF to [facile.cines.fr](https://facile.cines.fr)
and print `✅ PDF/A-1b valide` or point you to the CINES correction service
([facile.cines.fr/#correction](https://facile.cines.fr/#correction)) if a fix is needed.
Restore the standard line (without `validate`) for day-to-day builds.

> **curl** (pre-installed on macOS 10.15+ and most Linux distros; included in
> Windows 10 v1803+ as `curl.exe`) is the only requirement.

## Known limitations (HTML output)

The HTML output is functional. The only PDF feature without a direct HTML equivalent is:

- **List of figures / list of tables** — PDF only; Quarto's sidebar provides navigation instead

Contributions are welcome.

## License

[MIT](LICENSE)
