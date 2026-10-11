# Journal du projet Plugin Song Creator

Trace des décisions, des versions et des leçons apprises, pour reprendre le projet plus tard.
Cible : grandMA3 **2.3.2.0**, console + onPC en session réseau.

## Décisions de Jo (10/10/2026)

| Sujet | Décision |
|---|---|
| Version MA3 | le plugin doit tourner en 2.3.2.0 |
| Timecode | le plugin le crée ; les cues 0.6 / 0.7 / Off TC reçoivent leur commande |
| Commandes TC | par le **nom** du timecode entre guillemets : `Go+ Timecode "Nom"` |
| Espaces | **tous les espaces deviennent `_`** (page, séquences, timecode, macro) |
| Extras | placées juste après la séquence main, on ne saisit que leur nombre (max 10, Exec 121-130) |
| Cues de song | nombre réglable (20 par défaut), à affiner avec le futur plugin de link Reaper |
| Notes | toutes les séquences de la song (main + extras) reçoivent une note au nom de la song |
| Écran | le plugin s'ouvre **sur l'écran 1** uniquement |
| Fenêtre | une seule fenêtre : déplaçable par la barre de titre, redimensionnable, croix pour fermer |
| Choix dans les pools | Page, Macro, Séquence, Timecode : taper le numéro **ou** ouvrir la fenêtre de sélection **native** de MA (style « Select Selection »), pas une fenêtre dessinée à part |
| Inspiration visuelle | SongMAnager de MATools (ma.tools) |

## Versions

| Version | Contenu |
|---|---|
| 0.1.0 | MessageBox de setup, récapitulatif, création complète (reprise de la macro + timecode) |
| 0.1.1 | listes déroulantes (PopupInput) pour Page, Macro, Timecode |
| 0.1.2 | liste pour la séquence main, avec contrôle de la place pour les extras |
| 0.2.0 | grille de tuiles dessinée façon Import/Export, liste en secours |
| 0.2.1 | taille relative à l'écran, écran 1 ou 2 |
| 0.2.2 | journal `[SongCreator]` dans le System Monitor, erreurs Lua affichées |
| 0.3.0 | fenêtre unique sur mesure (écran 1, déplaçable, redimensionnable, croix), récap en direct, boutons « ... » vers la sélection native MA, boîtes MA en secours |
| 0.3.1 | relecture avec les docs : retour des commandes vérifié (refus listés), création dans une seule action Oops, lignes de macro créées par `Store Macro N.i` puis remplies en Lua, `ClassExists` avant le coin de redimensionnement, version MA écrite au démarrage |
| 0.3.2 | test console du 11/10 : la commande des cues TC est écrite sur la part 0 de la cue (la cue refusait « Command »), chaque valeur posée en Lua est relue, propriétés listées dans le System Monitor si ça échoue |
| 0.3.3 | une couleur par cue et LAVENDER sur 0.5 : fausse piste, retirée en 0.3.4 (il manquait juste l'apparence LAVENDER dans le show de test) |
| 0.3.4 | retour à la ligne de couleur d'origine ; si une apparence manque dans le show, la liste native des apparences s'ouvre à la création pour en choisir une, et le choix est gardé dans une variable globale du show (`SongCreator_App_main`, `_extras`, `_tc`, `_bo`) |
| 0.4.0 | nouvelle fenêtre d'après la maquette v0.4 (modèle « Search and Modify ») : modes à gauche (Créer ; Renommer, Dupliquer, Supprimer grisés), emplacements avec flèche ▾ vers la sélection native, réglages, bouton Oui / Non pour le timecode, récap « Ce qui sera créé » et alertes en couleur à droite, cases occupées en orange (avec le nom de l'objet), boutons Créer / Valeurs par défaut / Annuler ; lignes de hauteur fixe et polices plus grandes |

## Leçons apprises

- **Plugin vide à l'import** : si le `.lua` n'est pas à côté du `.xml` lors de l'import, MA importe
  un plugin vide (« Could not load ... as content is empty ») qui ne fait rien. Un export MA d'un
  plugin vide n'écrit que le `.xml`. Toujours copier les deux fichiers du dépôt.
- **Session réseau** : un plugin s'exécute et affiche ses fenêtres sur le poste qui le lance ;
  les commandes `Cmd()` partent dans la session.
- **MessageBox** : sur console, elle s'affichait sur tous les écrans. D'où la fenêtre sur mesure
  sur l'écran 1.
- **Éléments d'interface qui marchent en 2.3.2 sur console** (vérifié avec la grille de la v0.2.2) :
  `ScreenOverlay:Append("BaseInput")`, `TitleBar`, `TitleButton`, `CloseButton`, `UILayoutGrid`,
  `Button` avec `PluginComponent` + `Clicked` + `SignalValue`.
- **À vérifier** : `LineEdit`, `CheckBox`, `ResizeCorner`, `PopupInput` avec `caller` = bouton.
  Les propriétés « confort » passent par `opt()` : une propriété inconnue est ignorée et notée
  dans le System Monitor au lieu de faire planter la fenêtre.
- **Pas d'API pour la fenêtre native de pool** de l'Import/Export ; `PopupInput` est la fenêtre de
  sélection native la plus proche (colonnes, filtre clavier).
- **Plugins MATools** : compilés en bytecode Lua, payants et sous licence ; on s'en inspire pour
  le visuel, on n'en reprend pas le code.

- **`Cmd()` renvoie le retour de la ligne de commande** (« OK », « Syntax Error », « Illegal Command ») :
  il faut le lire, sinon une commande refusée passe inaperçue.
- **`CreateUndo()` / `CloseUndo()`** : passer la liste à `Cmd(cmd, undo)` regroupe toute la création dans un seul Oops.
- **`ClassExists("Classe")`** permet de vérifier un élément d'interface avant de l'ajouter.
- **Test console du 11/10 (v0.3.1)** : toutes les commandes de création passent (OK). `cue:Set("Command", ...)` donne
  « LUA API Syntax error, wrong parameter #2 » : la cue n'a pas de propriété Command en 2.3.2, elle est
  probablement sur la part 0. Un `Set` refusé ne lève pas toujours d'erreur Lua : il faut relire avec `Get`.
  Les lignes de macro (`MacroLine:Set("Command")`) passent sans erreur.
  Avec la v0.3.2 (commande écrite sur la part 0), les cues TC et la macro de rappel marchent.
- **Apparence absente** : `Assign Appearance "X"` répond OK même si l'apparence X n'existe pas dans le show,
  et rien n'est coloré. Le plugin vérifie donc les apparences dans `ShowData().Appearances` avant de créer.
  La liste `Cue 0.6 + 0.7 + 22` marche très bien.
- **Raccourcis clavier onPC** (F10 ou ShCuts) : ils captent les touches tapées dans les champs du plugin.
  MA ne les coupe tout seul que dans ses propres menus et fenêtres.
- **Fenêtre trop grande** : une zone « Stretch » partagée en lignes égales donne des cases énormes avec un
  texte petit. Les fenêtres MA ont des lignes de hauteur fixe. Modèle choisi par Jo : « Search and Modify ».
  Maquette v0.4 : `docs/Song_Creator_maquette_v0.4.html` (artifact https://claude.ai/artifact/YEKLN6ZJCbJx1G6jpW5vLQ),
  codée en v0.4.0.

## Ressources

Le dossier `Ressources/` du dépôt contient deux références Lua grandMA3 copiées avec leur licence :
la documentation de l'API (MacTirney, MIT) et des exemples avec la liste des éléments d'interface,
polices, icônes et couleurs (BakaCowpoke, CC0). À consulter avant de deviner un nom de fonction ou
de propriété. Elles confirment que `LineEdit`, `ResizeCorner`, la police `Medium20` et l'icône
`object_plugin1` existent, et que `MessageBox` n'a pas d'option pour choisir l'écran.

Ajouté le 11/10/2026 : `Ressources/GrandMA3-Reference-patopesto/`, copie de la référence de
[grandma3.bambinito.net](https://grandma3.bambinito.net/reference/) (dépôt patopesto, AGPL v3). C'est un dump de la
vraie API **2.3** : à consulter en premier (`API_2.3.md`, `ENUMS_2.3.md`). Documentation seulement, pas de copie de code.
Ce qu'elle a appris tout de suite : `PopupInput` accepte `render_options = {left_icon, number, right_icon}`,
`MessageBox` accepte un `display` en 2.3, `Cmd()` renvoie « Ok », `LineEdit` a un signal `TextChanged`, et les icônes
`ok`, `cancel`, `undo`, `triangle_down`, `object_sequence`, `object_macro`, `object_timecode`, `object_pages` existent.

## Reste à faire

- Tester sur console l'aspect de la v0.4.0 (polices, couleurs, icônes, modes grisés) et ajuster.
- Problèmes de code repérés par Jo (11/10), à reprendre ensemble.
- Saisie de texte avec les raccourcis clavier actifs sur onPC.
- Question de Jo (11/10) : le plugin apporte-t-il plus que la macro ? Piste : gérer les songs existantes
  (liste, renommer, supprimer, dupliquer, modèle, link Reaper).
- Plus tard : séquence modèle à copier, renommer / supprimer une song, link Reaper.
