# Dev plugins grandMA3 / grandMA2 — Jo Martin

Plugins Lua et macros pour consoles grandMA, utilisés en tournée sur de gros
parcs (800+ fixtures). Robustesse en live et performance passent avant tout.

## Versions cibles

- **grandMA3 2.3.2.0** uniquement. Jo ne passe pas en 2.4+ (trop buguée).
  Ne jamais proposer une fonction propre à une version plus récente.
- XML (macros, plugins) : `DataVersion="2.3.2.0"`.
- **grandMA2 3.9.60** pour les portages (dossier `grandma2/`).
- Visualisation : Capture.

## Avant d'écrire du code

1. Les pièges connus sont chargés ci-dessous (`docs/api-pieges.md`) : les respecter.
2. Selon le besoin, lire :
   - `docs/api-reference.md` : fonctions Lua validées
   - `docs/ui-reference.md` : architecture plugin avec UI, MessageBox, écrans
   - `docs/macros-reference.md` : syntaxe des macros et du XML
3. Une fonction absente de ces fichiers n'est **pas validée** : le dire clairement,
   et commencer par un petit script de diagnostic plutôt que de deviner l'API.
4. Si la spec est floue sur un point qui change le code (objets touchés,
   déclenchement, comportement si séquence active…), poser la question avant.

## Règles de livraison (obligatoires)

Chaque plugin livré doit avoir :

- **Réglages en tête de fichier** (numéros d'executors, pools, options).
- **`DEBUG = true/false`** et des logs préfixés (ex. `[FSC]`) :
  `Printf` en MA3 ; `gma.echo` + `gma.feedback` en MA2.
- **`pcall`** autour des opérations risquées, avec un message d'erreur lisible.
- **Récapitulatif + confirmation** avant toute modification du show.
- **Relecture** de ce qui a été écrit dans le show quand c'est possible,
  et signalement de toute différence.
- **Procédure de test numérotée** dans la réponse : quoi faire sur l'onPC,
  quoi doit s'afficher, quoi me renvoyer si ça échoue (lignes de log exactes).

Objectif : un test raté doit donner assez d'infos pour corriger en un seul aller-retour.

## Conventions de show (MA3)

- Une page par titre.
- Séquence principale sur l'executor 201, extras sur 106 à 115.
- Timecodes appelés **par nom entre guillemets**, jamais par numéro.
- Pages appelées par nom.
- Tous les phasers sont assignés au **Speed master 1** dans les presets ;
  phasers stockés dans des séquences en tracking ; SM1 calé au BPM du titre.

## Boucle d'apprentissage

Quand un test révèle un comportement non documenté (fonction qui échoue,
syntaxe refusée, bug de version) :

1. ajouter une entrée dans `docs/api-pieges.md` (symptôme → cause → solution, version, date) ;
2. mettre à jour `docs/api-reference.md` si une fonction est validée ;
3. commit avec le plugin.

## Structure du repo

```
CLAUDE.md          ce fichier
docs/              base de connaissances MA3 / MA2
templates/         squelettes de plugins
specs/             fiches plugins générées par l'app de conception
plugins/           plugins grandMA3 (un dossier par plugin)
grandma2/          portages grandMA2
```

Un plugin = un dossier `plugins/<NomPlugin>/` avec le `.lua`, le `.xml`
d'import et un `README.md` (installation, usage, réglages, version validée).

## Plugins déjà développés (pas encore dans le repo)

MIDI Mapper, TC Auto Off Manager, Preset Search & Replace, Grid Placer,
Grid Width Phaser / Grid Phaser Tools (v15), Full Song Creator (macro MA3,
portage MA2 dans `grandma2/`). Leurs enseignements sont dans `docs/`.

@docs/api-pieges.md
