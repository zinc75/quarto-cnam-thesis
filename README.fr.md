[🇬🇧 Read in English](README.md)

<img width="426" height="213" alt="Quarto-cnam-thesis-template_social_preview 001" src="https://github.com/user-attachments/assets/ecf08076-8343-4fc9-b5bb-c41d2542f36f" />


# quarto-cnam-thesis

Extension [Quarto](https://quarto.org) pour la rédaction d'une thèse de doctorat au
[Conservatoire national des arts et métiers (Cnam)](https://www.cnam.fr).
Produit un **PDF** conforme à la maquette officielle Cnam 2024–2025 et une
**version HTML** navigable pour le partage en ligne et l'accessibilité.

## Fonctionnalités

- Sortie validée selon les critères PDF/A-1b de [facile.cines.fr](https://facile.cines.fr) (CINES), le validateur officiel pour les dépôts sur theses.fr
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

Installer les trois outils ci-dessous **dans l'ordre** :

**Étape 1 — Quarto 1.4+** — <https://quarto.org/docs/get-started/>

**Étape 2 — LaTeX (pdflatex).** Si vous n'avez pas encore LaTeX, installez TinyTeX *après* Quarto :

```bash
quarto install tinytex
```

TinyTeX est la distribution minimale intégrée à Quarto. Elle télécharge automatiquement
les packages manquants au premier rendu (connexion internet requise ; entièrement hors
ligne ensuite). **Vous avez déjà TeX Live 2023+ ou MiKTeX ?** Ça fonctionne sans
configuration supplémentaire.

**Étape 3 — [Python 3.10+](#configuration-de-python)** — requis par les scripts post-render. Également nécessaire
pour l'exécution des cellules de code si la thèse contient des figures ou tableaux calculés.

> **Utilisateurs Windows sans WSL :** remplacer `.sh` par `.bat` dans les entrées
> `post-render` de `_quarto-fr.yml` / `_quarto-en.yml`.


## Installation

```bash
quarto use template zinc75/quarto-cnam-thesis
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

Les métadonnées de la thèse sont réparties dans deux fichiers.

**`_quarto-fr.yml`** (ou `_quarto-en.yml`) — titre, auteur, date de soutenance :

```yaml
book:
  title: "Titre de la thèse"
  subtitle: "Sous-titre optionnel"
  author: "Prénom NOM"

date-soutenance: "1er janvier 2025"   # utiliser date-soutenance, pas date (problème d'encodage)
```

**`_quarto.yml`** — champs de la page de garde (jury, encadrants, informations institutionnelles) :

```yaml
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


## Configuration de Python

### Python est-il indispensable ?

Python intervient à deux niveaux dans ce template :

1. **Scripts post-render** — toujours nécessaires (génération du slug auteur, renommage
   des fichiers, image de couverture). Python 3.8+ suffit ; aucun package supplémentaire
   n'est requis.
2. **Cellules de code exécutables** — uniquement si la thèse contient des figures
   calculées (matplotlib…) ou des tableaux (pandas…). Une thèse rédigée en texte pur
   avec des images statiques n'a besoin que du point 1.

Si la thèse ne contient pas de code Python exécutable, une installation Python de base
est suffisante et la suite de cette section ne vous concerne pas.

### Packages pour le code exécutable

Les packages requis par les chapitres d'exemple du template sont listés dans
`requirements.txt` :

```
numpy>=1.24      # tableaux numériques
matplotlib>=3.7  # figures
pandas>=2.0      # tableaux de données
tabulate>=0.9    # sortie Markdown (utilisé par pandas .to_markdown())
```

Quarto a également besoin de **Jupyter** pour exécuter les cellules Python. Il est
installé automatiquement par les méthodes ci-dessous.

### Recommandation : `uv`

[`uv`](https://docs.astral.sh/uv/) est un gestionnaire de packages moderne (écrit en
Rust) qui installe Python, crée des environnements virtuels et gère les packages — le
tout avec un seul outil. Aucune installation Python préalable n'est nécessaire.

**Pourquoi `uv` pour une thèse ?** Une thèse n'a besoin que d'une poignée de packages
pour un seul projet. Les installer globalement pollue le système et risque de créer des
conflits de versions. `uv` crée un dossier `.venv/` isolé dans le répertoire du projet ;
Quarto le détecte automatiquement — pas d'activation manuelle avant `quarto render`.

**Étape 1 — Installer `uv`** (une seule fois, sur le système) :

```bash
# macOS / Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# Windows (PowerShell — à exécuter une seule fois, sans droits admin)
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

**Étape 2 — Configurer le projet** (dans le répertoire de la thèse) :

```bash
uv python install 3.12          # télécharge et installe Python 3.12
uv venv                         # crée .venv/ dans le répertoire courant
uv pip install -r requirements.txt   # installe tous les packages + Jupyter
```

C'est tout. Quarto détecte `.venv/` et l'utilise automatiquement.

> Ajouter vos propres packages avec `uv pip install <package>` (et non `pip install`
> — cela garantit l'installation dans `.venv/`, pas dans Python système).

### Alternative : `venv` + `pip` classique

Si Python 3.10+ est déjà installé :

```bash
python -m venv .venv

# Activer l'environnement (une fois par session de terminal) :
source .venv/bin/activate          # macOS / Linux
.venv\Scripts\activate             # Windows (cmd)
.venv\Scripts\Activate.ps1         # Windows (PowerShell)

pip install jupyter -r requirements.txt
```

Contrairement à `uv`, l'environnement doit être activé avant chaque session de
`quarto render`, ou indiquer explicitement le Python à utiliser :

```bash
quarto render --profile fr --execute-env QUARTO_PYTHON=.venv/bin/python
```

> **Utilisateurs conda :** `conda create -n mathese python=3.12 && conda activate
> mathese && pip install jupyter -r requirements.txt` fonctionne aussi. Veillez à
> activer l'environnement conda avant de lancer Quarto, afin que `jupyter` soit
> disponible sur le `PATH`.

> **Utilisateurs pyenv :** installer la version Python cible avec pyenv, puis
> utiliser le workflow `venv` standard ci-dessus.


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

## Dépôt sur theses.fr

Avant le dépôt final, valider le PDF selon les critères CINES — les mêmes que ceux
appliqués par theses.fr. Passer `validate: true` dans `_quarto-fr.yml` (ou
`_quarto-en.yml`) et lancer le rendu normalement :

```yaml
# Dans _quarto-fr.yml :
validate: true
```

```bash
quarto render --profile fr --to cnam-thesis-pdf
```

Le script post-render enverra le PDF sur [facile.cines.fr](https://facile.cines.fr)
et affichera `✅ PDF/A-1b valide` ou vous orientera vers le service de correction
CINES ([facile.cines.fr/#correction](https://facile.cines.fr/#correction)) si une
correction est nécessaire.
Remettre `validate: false` pour les rendus quotidiens.

> **curl** (préinstallé sur macOS 10.15+ et la plupart des distributions Linux ;
> inclus dans Windows 10 v1803+ sous le nom `curl.exe`) est la seule dépendance.

## Limitations connues (sortie HTML)

La sortie HTML est fonctionnelle. La seule fonctionnalité PDF sans équivalent HTML direct est :

- **Liste des figures / liste des tableaux** — PDF uniquement ; la barre latérale Quarto assure la navigation à la place

Les contributions sont les bienvenues.

## Licence

[MIT](LICENSE)
