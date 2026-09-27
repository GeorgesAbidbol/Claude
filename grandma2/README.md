# FULL SONG CREATOR — grandMA2 (3.9.60)

Portage de la macro grandMA3 « FULL SONG CREATOR ».

Le plugin sert **uniquement à créer un titre**. La macro de titre qu'il génère
est une macro MA2 classique : aucun plugin n'est utilisé pendant le show.

## Fichiers

| Fichier | Rôle |
|---|---|
| `FullSongCreator.lua` + `FullSongCreator.xml` | le plugin de création |
| `Macro_Full_Song_Creator.xml` | macro de lancement (une ligne : `Plugin "FULL SONG CREATOR"`) |

## Installation

1. Copier `FullSongCreator.lua` et `FullSongCreator.xml` dans le dossier `plugins`,
   et `Macro_Full_Song_Creator.xml` dans le dossier `importexport`
   (sur clé USB : `gma2/plugins` et `gma2/importexport`).
2. `Import "FullSongCreator.xml" At Plugin <n°>`
3. `Import "Macro_Full_Song_Creator.xml" At Macro <n°>` (facultatif)

## Ce que fait le plugin

**Questions** : nom du titre, page, BPM, séquence principale, première et
dernière séquence extra, numéro de la macro du titre. Un récapitulatif est
affiché avant toute modification.

**Page** : créée si besoin, puis nommée avec le titre.

**Séquence principale** (executor 16 de la page, largeur 2 faders) :

| Cue | Nom | Trig | CMD |
|---|---|---|---|
| 0.5 | Mise | — | — |
| 0.6 | Select Timecode | Follow | `Select Timecode '<nom du titre>'` |
| 0.7 | Go Timecode | Follow | `Go Timecode '<nom du titre>'` |
| 1 à 20 | cues du titre | — | — |
| 21 | Black Out | — | — |
| 22 | Off Timecode | Follow | `Off Timecode '<nom du titre>'` |

**Extras** : executors 121 à 130. Une séquence extra qui n'existe pas est créée
vide ; une séquence existante n'est pas modifiée.

**Macro de titre** : créée directement dans le show, ligne par ligne
(`Store Macro 1.<n°>.<ligne>` puis `Assign ... /cmd="..."`), comme dans la
version grandMA3. Chaque ligne est ensuite relue ; le plugin signale toute
ligne absente ou différente. Elle appelle la page **par son nom**, jamais par
son numéro. Le nom est entre apostrophes : MA2 n'accepte pas de `"` à
l'intérieur de `/cmd="..."`. Le nom du titre ne peut donc contenir ni `"` ni `'`.

Validé sur grandMA2 onPC 3.9.60 (27/09/2026) : création complète, et la macro
de titre change bien de page avec `Page '<nom>'`.

| N° | CMD |
|---|---|
| 1 | `Page '<nom du titre>'` |
| 2 | `Select Executor 16` |
| 3 | `Executor 16 At 100` |
| 4 | `SpecialMaster 3.1 At <bpm>` |
| 5 | `Goto Cue 0.5` |
| 6 | `Off Page Thru - $faderpage - $ButtonPage - 101 Thru - 1` |

## Réglages

En tête de `FullSongCreator.lua` : executors du main (et sa largeur) et des extras, SpecialMaster
du BPM, pages communes exclues du `Off Page Thru` (`EXCLUSIONS`).

## Différences avec la version grandMA3

- Pas d'apparences ni de configurations d'executor.
- Les notes (`Note`) des séquences ne sont pas reprises.
