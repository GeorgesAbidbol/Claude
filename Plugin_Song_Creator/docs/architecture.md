# Architecture du plugin « Song Creator » (grandMA3, Lua)

Basé sur la macro FULL SONG CREATOR (voir analyse-macro.md) et les choix de Jo du 10/10/2026 :
- le plugin crée le timecode et met les commandes dans les cues 0.6, 0.7 et 22 ;
- les extras sont placés juste après la séquence principale, on ne saisit que leur nombre ;
- le nombre de cues de song est réglable (20 par défaut, à affiner avec le plugin de link Reaper).

## Fichiers

```
gma3-song-plugin/
  SongCreator.xml        -- déclaration du plugin (import dans le pool Plugins)
  SongCreator.lua        -- point d'entrée : ouvre la fenêtre, lance la création
  (modules internes dans le même .lua au début, découpés en fonctions)
```

## Fenêtre de setup (UI sur mesure, objets UI MA3)

| Bloc | Champ | Défaut |
|---|---|---|
| Song | Nom | vide (obligatoire) |
| Song | Page | 1re page libre après la dernière song |
| Song | BPM | 120 |
| Séquences | Séquence principale | 1re séquence libre |
| Séquences | Nombre d'extras (0 à 10) | 4 |
| Séquences | Nombre de cues de song | 20 |
| Timecode | Créer le timecode | oui |
| Timecode | N° de timecode | = n° de séquence principale, ou 1er libre |
| Macro | N° de macro de rappel | 1re macro libre |
| Réglages fixes (repliés) | Exec main / extras / pages communes | 216 / 121-130 / 101-120 |

À droite : un **récapitulatif en direct** de ce qui va être créé, chaque ligne marquée libre / occupé.
Boutons : **Annuler**, **Créer la song** (grisé tant qu'il manque le nom ou qu'un emplacement est occupé, sauf si « écraser » est coché).

## Étapes de création (une fonction chacune, toutes via `Cmd()`)

1. **Vérifier** : page, séquences main..main+extras, timecode et macro libres (lecture `DataPool()`), sinon message.
2. **Page** : Store / Page / Label au nom de la song.
3. **Séquences** : Store main thru main+extras ; label + note.
4. **Cues de la main** : 0.5 Mise ; 0.6 Select Timecode ; 0.7 Go Timecode ; 1..N ; N+1 Black Out ; N+2 Off Timecode.
   Les cues timecode reçoivent leur commande (`Property "Command"`) et le trigger Follow ; apparences LAVENDER / Black.
   Commandes par le **nom** du timecode, entre guillemets (choix de Jo) : `Select Timecode "Nom"`, `Go+ Timecode "Nom"`, `Off Timecode "Nom"`.
   Le timecode porte le nom de la song.
   **Pas d'espace dans les noms** (choix de Jo) : le plugin remplace les espaces du nom saisi par `_`,
   et ce nom nettoyé sert partout (page, séquences, timecode, macro), ex. `Nuit_Blanche`.
   Note : avec N réglable, Black Out et Off Timecode suivent la dernière cue de song (21 et 22 quand N = 20).
5. **Timecode** : Store Timecode T, label au nom de la song.
6. **Executors** : main sur 216 (config MAIN SEQUENCE, GREEN), extras sur 121.. (config EXTRAS, BLUE).
7. **Macro de rappel** : 7 lignes reprises de la macro actuelle, avec `$currentSong` conservé tel quel.
8. **Récapitulatif** : ce qui a été créé, et les avertissements éventuels.

Plus aucune variable utilisateur temporaire : tout passe par des variables Lua, rien à nettoyer.

## À trancher plus tard

- Version de MA3 sur la console (l'export dit 2.3.2) : conditionne l'API UI disponible.
- Séquence modèle à copier au lieu de créer les cues (idée reprise de SongMAnager).
- Renommer / supprimer une song.
