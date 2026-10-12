# Analyse de la macro « FULL SONG CREATOR »

Source : export grandMA3 v2.3.2.0, 46 lignes de macro.

## 1. Ce que la macro demande (7 saisies)

| Variable | Question posée | Utilisation |
|---|---|---|
| TempSongName | Song Name ? | nom de la page, de la séquence principale, de la macro, notes |
| TempPageNum | Page Number ? | page créée pour la song |
| TempBPM | Song BPM ? | vitesse du Speed Master 3.1 |
| TempSeqStart | Main Sequence ? | n° de la séquence principale |
| TempExtraStart | First extra ? | 1re séquence « extra » |
| TempExtraEnd | Last extra ? | dernière séquence « extra » |
| TempNextMacro | Macro Number For Song ? | n° de la macro de rappel de la song |

## 2. Ce qu'elle crée, dans l'ordre

1. **Page** : `Store Page N`, `Page N`, `Label Page N "nom"`.
2. **Séquences** : `Store Sequence Main Thru LastExtra` (toute la plage, y compris les trous éventuels entre Main et FirstExtra).
3. **Executors** :
   - séquence principale sur **Exec 216**, label = nom de la song, note = nom de la song ;
   - extras sur **Exec 121 à 130** (10 max), label vide, note = nom de la song.
4. **Macro de rappel de la song** (7 lignes, labelée au nom de la song) :
   1. `Page "nom"` : va sur la page par son nom
   2. `SetGlobalVariable currentSong "nom"`
   3. `Off Page thru -Page $currentSong - Page 101 thru 120` : éteint toutes les autres pages, sauf la song et les pages 101 à 120 (pages communes)
   4. `FaderMaster Executor 216 at 100`
   5. `Select Executor 216`
   6. `Goto Cue 0.5` : se met en Mise
   7. `Master 3.1 at BPM <bpm>` : règle le Speed Master 1 sur le tempo de la song
5. **Cues de la séquence principale** (Exec 216 sélectionné) :
   - 0.5 « Mise »
   - 0.6 « Select Timecode » (Follow)
   - 0.7 « Go Timecode » (Follow)
   - 1 à 20 : cues vides de la song
   - 21 « Black Out »
   - 22 « Off Timecode » (Follow)
   - couleurs : LAVENDER sur 0.6, 0.7, 22 ; Black sur 21
6. **Look des executors** : configuration « EXTRAS » + apparence BLUE sur 121-130 ; configuration « MAIN SEQUENCE » + apparence GREEN sur 216.
7. **Nettoyage** des 7 variables utilisateur.

## 3. Points fragiles repérés

- **Ligne « Create Tag » vide** : elle ne fait rien (prévue mais pas écrite ?).
- **Label des extras** : `Label Sequence ... "   ` a un guillemet non fermé. L'intention semble être un label vide.
- **Guillemets imbriqués** dans les `Store Macro ... Property "command" "Page "$TempSongName"` : ça marche peut-être par chance, mais c'est fragile si le nom contient un espace.
- **`$currentSong` dans la ligne 3** : *déduit, à vérifier sur console* : la variable risque d'être remplacée au moment de la création par la valeur courante (la song précédente) au lieu de rester `$currentSong` dans la macro créée.
- **Timecode** : les cues 0.6 / 0.7 / 22 portent des noms (« Select / Go / Off Timecode ») mais aucune commande CMD, et aucun objet Timecode n'est créé.
- **Aucune vérification** : si la page, les séquences ou la macro existent déjà, la macro écrase ou échoue sans prévenir.
- **Extras** : plus de 10 extras ne tiennent pas sur 121-130.
- **Dépendances** : apparences (LAVENDER, Black, BLUE, GREEN) et configurations d'executor (« EXTRAS », « MAIN SEQUENCE ») doivent déjà exister dans le show.

## 4. Ce que le plugin apporterait

- **Une seule fenêtre** au lieu de 7 questions successives, avec valeurs par défaut.
- **Numéros proposés automatiquement** : prochaine page libre, prochaine séquence libre, prochaine macro libre.
- **Nombre d'extras** saisi directement (au lieu de premier/dernier), placés juste après la séquence principale.
- **Vérification avant création** (rien n'est écrasé sans confirmation) et récapitulatif à la fin.
- **Corrections** : labels propres, macro de rappel fiable, `$currentSong` conservé tel quel.
- **Options** : nombre de cues de song, création du timecode et des commandes de cues, etc.
