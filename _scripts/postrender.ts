#!/usr/bin/env -S quarto run
// _scripts/postrender.ts — cross-platform post-render for quarto-cnam-thesis
// Replaces postrender.sh (macOS/Linux) + postrender.ps1 (Windows).
// Requires only Deno, which is bundled with Quarto ≥ 1.4 — no Python, no bash.
//
// Usage (declared in _quarto-fr.yml / _quarto-en.yml):
//   post-render: _scripts/postrender.ts fr _these_fr
//   post-render: _scripts/postrender.ts fr _these_fr validate
//
// Optional external tools:
//   pdftoppm (poppler) or magick / convert (ImageMagick) — cover image generation
//   curl                                                  — CINES PDF/A-1b validation

const [LANG, OUTPUT_DIR, MODE_ARG] = Deno.args;

if (!LANG || !OUTPUT_DIR) {
  console.error("postrender.ts: usage: postrender.ts <lang> <output-dir> [validate]");
  Deno.exit(1);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function exists(path: string): boolean {
  try { Deno.statSync(path); return true; } catch { return false; }
}

function removeIfExists(path: string, options?: Deno.RemoveOptions): void {
  try { Deno.removeSync(path, options); } catch { /* ignore */ }
}

/**
 * Extract a scalar value from a YAML string without a full YAML parser.
 * Handles quoted ("…" or '…') and unquoted values; ignores inline comments.
 * Only reads top-level or indented scalar lines — sufficient for our use-case.
 */
function readYamlScalar(content: string, key: string): string | undefined {
  const re = new RegExp(
    `^[ \\t]*${key}:[ \\t]+["']?([^"'\\n#]+?)["']?[ \\t]*(#.*)?$`,
    "m",
  );
  return content.match(re)?.[1]?.trim();
}

/**
 * Convert an author name to a filesystem-safe ASCII slug.
 * é → e, spaces/hyphens → _, uppercase → lowercase, special chars stripped.
 * Pure Unicode — no Python or iconv required.
 */
function slugify(name: string): string {
  return name
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "") // strip combining diacritics (é→e, à→a…)
    .toLowerCase()
    .replace(/[\s\t-]+/g, "_")        // spaces, tabs, hyphens → _
    .replace(/'/g, "_")
    .replace(/[^a-z0-9_]/g, "")       // strip anything else
    .replace(/_+/g, "_")              // collapse consecutive underscores
    .replace(/^_|_$/g, "");           // trim leading/trailing _
}

/** Recursively collect all files with a given extension under dir. */
function findFiles(dir: string, ext: string): string[] {
  const out: string[] = [];
  try {
    for (const e of Deno.readDirSync(dir)) {
      const full = `${dir}/${e.name}`;
      if (e.isDirectory) out.push(...findFiles(full, ext));
      else if (e.isFile && e.name.endsWith(ext)) out.push(full);
    }
  } catch { /* skip unreadable */ }
  return out;
}

/** Remove LaTeX build artifacts from the current directory. */
function removeArtifacts(): void {
  const exactNames = new Set([
    "pdfa.xmpi",
    "_glossaire-entries.tex",
    "_gloss-acr.html",
    "_gloss-main.html",
  ]);
  const extensions = new Set([
    ".aux", ".log", ".maf", ".mtc",
    ".toc", ".lof", ".lot",
    ".blg", ".bbl",
    ".idx", ".ilg", ".ind",
    ".out", ".xmpdata",
  ]);

  for (const entry of Deno.readDirSync(".")) {
    if (!entry.isFile) continue;
    const n = entry.name;
    const lastDot = n.lastIndexOf(".");
    const ext = lastDot >= 0 ? n.slice(lastDot) : "";
    if (
      exactNames.has(n) ||
      extensions.has(ext) ||
      /\.mtc\d{1,2}$/.test(n) // *.mtc0 … *.mtc99
    ) {
      removeIfExists(n);
    }
  }
}

/** Run an external command and return its exit code and stdout. */
async function run(
  cmd: string,
  args: string[],
): Promise<{ code: number; stdout: string }> {
  try {
    const r = await new Deno.Command(cmd, {
      args,
      stdout: "piped",
      stderr: "piped",
    }).output();
    return { code: r.code, stdout: new TextDecoder().decode(r.stdout) };
  } catch {
    return { code: 1, stdout: "" };
  }
}

/** Check whether an external command is available on PATH. */
async function cmdExists(cmd: string): Promise<boolean> {
  const checker = Deno.build.os === "windows" ? "where" : "which";
  return (await run(checker, [cmd])).code === 0;
}

// ── Determine profile YAML ────────────────────────────────────────────────────
// Docs profiles (_docs-*) use _quarto-docs-<lang>.yml; thesis profiles use _quarto-<lang>.yml.

const PROFILE_YAML = OUTPUT_DIR.startsWith("_docs-")
  ? `_quarto-docs-${LANG}.yml`
  : `_quarto-${LANG}.yml`;

// ── Read optional validate flag from profile YAML ─────────────────────────────

let MODE = MODE_ARG ?? "";
if (!MODE && exists(PROFILE_YAML)) {
  if (readYamlScalar(Deno.readTextFileSync(PROFILE_YAML), "validate") === "true") {
    MODE = "validate";
  }
}

// ── Remove spurious directories copied by Quarto's resource scanner ───────────
// Quarto mirrors the project structure into the HTML output dir and copies all
// root-level directories — _reference/ and other profile output dirs are not needed.

for (const d of ["_reference", "_these_fr", "_thesis-en", "_docs-fr", "_docs-en"]) {
  removeIfExists(`${OUTPUT_DIR}/${d}`, { recursive: true });
}

// ── Clean LaTeX build artifacts ───────────────────────────────────────────────

removeArtifacts();

// ── Read author → build slug ──────────────────────────────────────────────────
// Profile YAML takes precedence over _quarto.yml (book.author override support).

let rawAuthor = "";
if (exists(PROFILE_YAML)) {
  rawAuthor = readYamlScalar(Deno.readTextFileSync(PROFILE_YAML), "author") ?? "";
}
if (!rawAuthor && exists("_quarto.yml")) {
  rawAuthor = readYamlScalar(Deno.readTextFileSync("_quarto.yml"), "author") ?? "";
}
if (!rawAuthor) {
  console.error("postrender.ts: author not found — aborting.");
  Deno.exit(0);
}

const AUTHOR_SLUG = slugify(rawAuthor);
if (!AUTHOR_SLUG) {
  console.error("postrender.ts: could not build author slug — aborting.");
  Deno.exit(0);
}

// ── Rename PDF and .tex ───────────────────────────────────────────────────────

const SRC_PDF = `${OUTPUT_DIR}/these_${LANG}.pdf`;
const DST_PDF = `${OUTPUT_DIR}/these_${LANG}_${AUTHOR_SLUG}.pdf`;
const SRC_TEX = `these_${LANG}.tex`;
const DST_TEX = `these_${LANG}_${AUTHOR_SLUG}.tex`;

let pdfGenerated = false;
if (exists(SRC_PDF)) {
  Deno.renameSync(SRC_PDF, DST_PDF);
  pdfGenerated = true;
  console.log(`PDF renamed: ${DST_PDF}`);
  // Keep a copy under the canonical name so quarto preview can stat it after
  // the rename. The copy is overwritten by pdflatex on every subsequent render.
  Deno.copyFileSync(DST_PDF, SRC_PDF);
}

// ── Fix HTML navigation links ─────────────────────────────────────────────────
// Quarto emits .pdf extensions for ALL book navigation hrefs in HTML pages when
// both PDF and HTML formats are registered (cross-format artefact).
//
// Pass 1 — all relative .pdf hrefs → .html  (navigation links)
// Pass 2 — these_<lang>.html → these_<lang>_<slug>.pdf  (restore download link)

const navPdfRe = /href="([^:"]*?)\.pdf"/g;
const dlLinkRe = new RegExp(`href="([^"]*these_${LANG})\\.html"`, "g");

for (const f of findFiles(OUTPUT_DIR, ".html")) {
  let content = Deno.readTextFileSync(f);
  if (!content.includes('.pdf"')) continue;
  content = content.replace(navPdfRe, 'href="$1.html"');
  content = content.replace(dlLinkRe, `href="$1_${AUTHOR_SLUG}.pdf"`);
  Deno.writeTextFileSync(f, content);
}
console.log(`HTML links updated → these_${LANG}_${AUTHOR_SLUG}.pdf`);

if (exists(SRC_TEX)) {
  Deno.renameSync(SRC_TEX, DST_TEX);
  console.log(`TeX renamed: ${DST_TEX}`);
}

// ── Submission hint ───────────────────────────────────────────────────────────

if (!MODE && pdfGenerated) {
  console.log(
    `→ Before depositing to theses.fr: set 'validate: true' in ${PROFILE_YAML} and re-render.`,
  );
}

// ── Generate cover image from PDF page 1 ─────────────────────────────────────
// Saves page 1 of the compiled PDF as images/cover.png for the HTML cover page.
// Only regenerated when a new PDF was produced; HTML-only renders reuse the
// existing cover.png (Quarto copies images/ to the output dir during render).
//
// Requires poppler-utils (pdftoppm) or ImageMagick (magick / convert).
//   macOS:  brew install poppler
//   Linux:  apt install poppler-utils
//   Windows: winget install oschwartz10612.poppler  (or use the ImageMagick fallback)

if (pdfGenerated && exists(DST_PDF)) {
  const COVER_SRC = "images/cover.png";
  const COVER_DST = `${OUTPUT_DIR}/images/cover.png`;

  if (await cmdExists("pdftoppm")) {
    const r = await run("pdftoppm", [
      "-r", "150", "-png", "-singlefile", "-f", "1", "-l", "1",
      DST_PDF, "images/cover",
    ]);
    if (r.code === 0) console.log("Cover image generated: images/cover.png");
    else console.error("postrender.ts: pdftoppm failed.");
  } else if (await cmdExists("magick")) {
    // ImageMagick v7+
    const r = await run("magick", [
      "-density", "150", `${DST_PDF}[0]`, "-quality", "90", COVER_SRC,
    ]);
    if (r.code === 0) console.log("Cover image generated: images/cover.png");
    else console.error("postrender.ts: magick failed.");
  } else if (await cmdExists("convert")) {
    // ImageMagick v6 (requires Ghostscript for PDF)
    const r = await run("convert", [
      "-density", "150", `${DST_PDF}[0]`, "-quality", "90", COVER_SRC,
    ]);
    if (r.code === 0) console.log("Cover image generated: images/cover.png");
    else console.error("postrender.ts: convert failed.");
  } else {
    console.error(
      "postrender.ts: install 'poppler' (pdftoppm) or 'ImageMagick' (magick)" +
      " to auto-generate images/cover.png.",
    );
  }

  // Copy the freshly generated cover into the HTML output dir so index.html
  // shows the current version immediately (Quarto copies resources before postrender).
  if (exists(COVER_SRC)) {
    try { Deno.mkdirSync(`${OUTPUT_DIR}/images`, { recursive: true }); } catch { /* exists */ }
    Deno.copyFileSync(COVER_SRC, COVER_DST);
    console.log(`Cover image copied to: ${COVER_DST}`);
  }
}

// ── CINES PDF/A-1b validation (optional) ─────────────────────────────────────
// Activated by passing "validate" as third argument, or via validate: true in the
// profile YAML. Sends the compiled PDF to facile.cines.fr and reports whether it
// is archivable on theses.fr. Requires curl (pre-installed on most systems).

if (MODE === "validate" && exists(DST_PDF)) {
  if (!await cmdExists("curl")) {
    console.error("postrender.ts: 'curl' not found — PDF/A validation skipped.");
    console.error("  Alternatively, upload the PDF manually at https://facile.cines.fr");
  } else {
    console.log("Validating PDF/A on facile.cines.fr (CINES)...");
    const r = await run("curl", [
      "--silent", "--max-time", "120",
      "--form", `file=@${DST_PDF}`,
      "https://facile.cines.fr/xml",
    ]);
    if (!r.stdout.trim()) {
      console.error("postrender.ts: no response from facile.cines.fr — check network connection.");
      console.error("  Alternatively, upload the PDF manually at https://facile.cines.fr");
    } else {
      const valid      = r.stdout.match(/<valid>([^<]*)<\/valid>/)?.[1]?.trim();
      const wellformed = r.stdout.match(/<wellformed>([^<]*)<\/wellformed>/)?.[1]?.trim();
      if (valid === "true") {
        console.log("[OK]  PDF/A-1b valide -- archivable sur theses.fr.");
      } else {
        console.error(`[!!]  PDF/A-1b non valide (valid=${valid}, wellformed=${wellformed}).`);
        console.error("      -> Corriger via : https://facile.cines.fr/#correction");
      }
    }
  }
}
