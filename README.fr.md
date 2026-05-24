[🇬🇧 Read in English](README.md)

# quarto-cnam-thesis

Extension [Quarto](https://quarto.org) pour la rédaction d'une thèse de doctorat au
[Conservatoire national des arts et métiers (Cnam)](https://www.cnam.fr).
Produit un **PDF** conforme à la maquette officielle Cnam 2024–2025 et une
**version HTML** navigable pour le partage en ligne et l'accessibilité.

## Fonctionnalités

- Sortie PDF/A-1b (standard d'archivage requis par le Cnam)
- Page de garde officielle Cnam : jury, logos, date de soutenance, encadrants
- Mini-tables des matières par chapitre (`minitoc`)
- Numérotation différenciée : romain (liminaire) / arabe (corps) / Romain (annexes)
- Bibliographie au format IEEE (`IEEEtran-francais`, BibTeX)
- Glossaire et acronymes optionnels (package `glossaries`)
- Bilingue : la langue de rédaction peut être le français ou l'anglais, la structure administrative restant en français
- Sortie HTML aux couleurs Cnam (barre rouge, barre latérale verre dépoli, responsive)
- Page d'accueil HTML avec image de couverture auto-générée (extraite de la page 1 du PDF), tableau du jury et métadonnées de la thèse
- Bouton de téléchargement du PDF dans la barre latérale HTML, pointant vers le PDF compilé
- Pages glossaire et acronymes rendues en PDF et en HTML
- Commentaires collaboratifs en marge via l'extension [`quarto-comments`](https://github.com/zinc75/quarto-comments)

## Prérequis

| Outil | Version minimale |
|-------|-----------------|
| [Quarto](https://quarto.org/docs/get-started/) | 1.4 |
| Distribution LaTeX avec **pdflatex** | TeX Live 2023+ ou MiKTeX |
| Python 3 _(génération du slug auteur en post-render)_ | 3.8 |

> **Utilisateurs Windows sans WSL :** remplacer `.sh` par `.bat` dans les entrées
> `post-render` de `_quarto-fr.yml` / `_quarto-en.yml`.

## Installation

```bash
quarto use template <org>/quarto-cnam-thesis
```

Quarto copie le template dans le répertoire courant (sans les fichiers de développement
listés dans `.quartoignore`). Il suffit ensuite de renseigner `_quarto.yml` et de
commencer à rédiger.

## Rendu

```bash
# Thèse en français — PDF + HTML → _these_fr/
quarto render --profile fr

# Thèse en anglais — PDF + HTML → _thesis-en/
quarto render --profile en

# PDF uniquement (français)
quarto render --profile fr --to cnam-thesis-pdf

# HTML uniquement — nécessite un rendu complet préalable et --no-clean
quarto render --profile fr --to cnam-thesis-html --no-clean
```

Le script post-render renomme la sortie en `these_<lang>_<auteur>.pdf` et
`these_<lang>_<auteur>.tex`, et génère `images/cover.png` à partir de la page 1 du PDF
(nécessite `poppler` ou `ImageMagick`).

> **Toujours utiliser `--profile fr` ou `--profile en`.** Lancer `quarto render`
> sans profil échoue car la liste des chapitres est définie dans les profils,
> et non dans `_quarto.yml`.

## Configuration

Renseigner les métadonnées de la thèse dans `_quarto.yml` :

```yaml
book:
  title: "Titre de la thèse"
  author: "Prénom NOM"

date-soutenance: "1er janvier 2025"   # utiliser date-soutenance, pas date
discipline: "60e section CNU — Mécanique, génie mécanique, génie civil"
specialite: "Acoustique"
ecole-doctorale: "Abbé Grégoire"      # ou "SMI"
laboratoire: "LMSSC"
directeur: "Pr. Prénom NOM, Université …"
# codirecteur: "…"    # optionnel, HDR requise
# coencadrant: "…"    # optionnel, sans HDR

jury:
  - nom: "Mme Prénom NOM"
    titre: "Titre, Unité, Université"
    role: "Présidente"
  - nom: "M. Prénom NOM"
    titre: "Titre, Unité, Université"
    role: "Rapporteur"
  # …
```

Puis ajouter les chapitres dans `_quarto-fr.yml` (ou `_quarto-en.yml`) :

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

## Structure du dépôt

```
quarto-cnam-thesis/
├── _extensions/cnam-thesis/    ← template LaTeX, SCSS, filtres Lua, shortcodes
│   ├── _extension.yml
│   ├── template.tex
│   ├── partials/before-body.tex
│   ├── thesis.scss
│   ├── cnam-thesis.lua
│   └── shortcodes.lua
├── _scripts/                   ← post-render (nettoyage, renommage, image couverture)
│   ├── postrender.sh           ← macOS / Linux
│   ├── postrender.bat          ← Windows (wrapper)
│   └── postrender.ps1          ← Windows (PowerShell)
├── content_fr/                 ← contenu de la thèse en français (à éditer)
│   ├── liminaire/              ← pages liminaires (remerciements, résumé, …)
│   ├── chapitres/              ← chapitres de la thèse
│   └── postliminaire/          ← pages postliminaires (conclusion, bibliographie, annexes)
├── content_en/                 ← contenu de la thèse en anglais (même structure)
├── images/                     ← logos Cnam — ne pas supprimer
├── references.bib              ← bibliographie BibTeX (à la racine, obligatoire)
├── IEEEtran-francais.bst       ← style bibliographique (à la racine, obligatoire)
├── index.qmd                   ← page de couverture HTML
├── _quarto.yml                 ← configuration principale
├── _quarto-fr.yml              ← profil français
└── _quarto-en.yml              ← profil anglais
```

## Contraintes techniques importantes

- **pdflatex uniquement** — le template utilise `pdfx` (PDF/A) et des packages spécifiques à `pdftex`.
  XeLaTeX et LuaLaTeX ne sont pas supportés.
- `references.bib` et `IEEEtran-francais.bst` **doivent** être à la racine du projet —
  BibTeX (mode natbib) ignore le chemin dans `\bibliography{}`.
- Utiliser `date-soutenance:` pour la date de soutenance, pas `date:` — Quarto parse
  `date:` comme une date JavaScript et produit « Invalid Date » pour les dates en français.

## Limitations connues (sortie HTML)

La sortie HTML est fonctionnelle. La seule fonctionnalité PDF sans équivalent HTML direct est :

- **Liste des figures / liste des tableaux** — PDF uniquement ; la barre latérale Quarto assure la navigation à la place

Les contributions sont les bienvenues.

## Licence

[MIT](LICENSE)
