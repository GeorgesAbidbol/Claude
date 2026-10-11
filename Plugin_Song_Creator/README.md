# Plugin Song Creator v0.3.4 (grandMA3 2.3.2.0)

Plugin grandMA3 qui remplace la macro « FULL SONG CREATOR » : une fenêtre de setup,
puis la création complète d'une song (page, séquences, cues, timecode, executors,
macro de rappel).

## Installation
1. Copier **les deux fichiers** `SongCreator.xml` **et** `SongCreator.lua` sur la clé USB
   dans `grandMA3/gma3_library/datapools/plugins/`.
2. Sur la console : supprimer l'ancien Song Creator du pool Plugins, puis case vide,
   **Import**, clé USB, « Song Creator ».
3. Lancer le plugin **depuis le poste où l'on veut voir la fenêtre** (en session réseau,
   la fenêtre s'affiche sur le poste qui lance le plugin).

Piège : si le `.lua` n'est pas à côté du `.xml` au moment de l'import, le plugin est
importé **vide** (System Monitor : « Could not load ... as content is empty ») et ne fait
rien. Un « Export Plugin » depuis un poste où il est déjà vide n'écrit que le `.xml`.

## La fenêtre
- Une seule fenêtre, toujours sur **l'écran 1**.
- **Barre de titre** : on la fait glisser pour déplacer la fenêtre ; **croix** en haut à droite
  pour fermer (ou Échap).
- **Coin de redimensionnement** en bas à droite ; taille de départ relative à l'écran.
- Champs : nom, page, macro de rappel, séquence main, n° de timecode, BPM, nombre
  d'extras (0-10), nombre de cues de song, case « Créer le timecode ».
- Bouton **« ... »** à côté de Page, Macro, Séquence et Timecode : ouvre la fenêtre de
  sélection native de MA (« Select ... », avec filtre clavier) ancrée sur le bouton.
  Elle liste les objets existants (`12 'Nom'`) puis des numéros libres. Pour la séquence,
  les numéros libres proposés ont la place pour la main et toutes les extras.
- **Récapitulatif en direct** sous le formulaire, avec les emplacements déjà occupés.
- **Créer la song** ; si quelque chose est déjà occupé, un deuxième appui (« Écraser et
  créer ») est demandé. Le résultat s'affiche dans la fenêtre.
- Si la fenêtre sur mesure ne peut pas s'afficher sur une version, le plugin repasse sur
  les boîtes de dialogue MA standard.

## Ce que crée le plugin
- Espaces du nom remplacés par `_` partout.
- Page créée et nommée.
- Séquence main + extras collées à la suite, notes au nom de la song.
- Main sur l'Exec 216 (config MAIN SEQUENCE, GREEN), extras sur 121.. (config EXTRAS, BLUE).
- Cues : 0.5 Mise, 0.6 Select Timecode, 0.7 Go Timecode, 1..N, N+1 Black Out, N+2 Off Timecode.
  Couleurs : LAVENDER sur 0.6, 0.7 et Off Timecode, Black sur Black Out.

Si une apparence (GREEN, BLUE, LAVENDER, Black) n'existe pas dans le show, le récap le signale et,
à l'appui sur « Creer la song », la liste des apparences du show s'ouvre pour en choisir une autre.
Le choix est gardé dans le show (variables globales `SongCreator_App_...`) : supprime la variable
pour revenir à l'apparence par défaut.
- Timecode créé et nommé ; commandes `Select Timecode "Nom"`, `Go+ Timecode "Nom"`,
  `Off Timecode "Nom"` posées sur les cues TC.
- Macro de rappel (7 lignes), `$currentSong` conservé tel quel.

## Annuler une song
Toute la création est regroupée dans une seule action **Oops** : un Oops annule la song entière.

## Diagnostic
Chaque commande envoyée est vérifiée : si MA la refuse (« Syntax Error », « Illegal Command »),
elle est listée en avertissement à la fin de la création et écrite en rouge dans le System Monitor.
Le démarrage indique aussi la version de grandMA3 détectée.
Le plugin écrit `[SongCreator] ...` dans le System Monitor (démarrage, propriétés d'interface
ignorées, erreurs). En cas d'erreur Lua, elle est aussi affichée dans une fenêtre.
Si une commande de cue timecode ou une ligne de macro n'a pas pu être posée, elle est listée en
avertissement, et les propriétés proposées par MA sont écrites dans le System Monitor.

Sur onPC, si les raccourcis clavier sont actifs, les touches tapées dans la fenêtre partent en
raccourcis. Coupe-les avec F10 (ou ShCuts) le temps de remplir le setup.

## À vérifier sur console
- Les commandes des cues TC et les lignes de la macro de rappel (posées via Lua).
- Le programmer doit être vide : les `Store Cue` enregistrent son contenu.
