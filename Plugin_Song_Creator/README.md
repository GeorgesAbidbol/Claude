# Plugin Song Creator v0.6.0 (grandMA3 2.3.2.0)

Plugin grandMA3 qui remplace la macro « FULL SONG CREATOR » : une fenêtre de setup,
puis la création complète d'une song (page, séquences, cues, timecode, executors,
macro de rappel).

## Installation
Pour mettre à jour : vérifier la version dans la barre de titre après l'import. Si elle n'a pas
changé, l'ancien plugin est encore chargé : le supprimer du pool et réimporter.

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
Disposition de la maquette v0.4 (modèle « Search and Modify »), avec les recettes graphiques du
plugin GUI REPLACE V15 de Jo : cadre de dialogue MA, marges entre les cases, libellés sans fond.
- Une seule fenêtre, toujours sur **l'écran 1**, taille de départ 1300 x 760 (au plus 95 % de l'écran).
- **Barre de titre** : on la fait glisser pour déplacer la fenêtre ; version à droite ; **croix**
  pour fermer (ou Échap). **Logo** : si le show a une apparence (ou une image) dont le nom contient
  « banane », elle s'affiche à gauche du titre. Sinon, l'icône plugin de MA. **Coin de redimensionnement** en bas à droite.
- **À gauche, « Mode »** : Créer (en jaune). Renommer, Dupliquer et Supprimer sont grisés,
  ils viendront plus tard.
- **Au centre** :
  - **Song** : le nom, avec en dessous le nom tel qu'il sera écrit dans MA (`Nuit_Blanche`) ;
  - **Emplacements** : une ligne par objet (Page, Séquence main, Macro de rappel, Timecode) avec
    le numéro, puis son état (« libre », ou « occupé : « Intro » » en orange), puis la flèche ▾.
    L'état ou la flèche ouvrent la liste « Select ... » du pool : tous les objets existants avec
    leur apparence (couleur, image), plus des numéros libres (30 dans les trous du pool, 5 après le
    dernier objet), triés par numéro. Barre de défilement à droite, filtre en haut (on tape un bout
    du nom ou du numéro, Entrée prend le premier). Pour la séquence, seuls les numéros qui ont la
    place pour la main et toutes les extras sont proposés libres, et l'état couvre tout le bloc.
    Si cette liste ne peut pas s'ouvrir sur une version de MA, le plugin ouvre la liste simple
    (sans apparences) et l'écrit dans le System Monitor ;
  - **Réglages** : BPM, Extras (0 à 10), Cues de song, Créer le timecode (Oui / Non) ;
  - rappel des réglages fixes : Exec main 216, extras 121 à 130, pages communes, Speed Master 3.1.
- **À droite, « Ce qui sera créé »** : le récap en direct, puis l'alerte en couleur (rouge :
  erreur, orange : déjà occupé ou apparence absente, vert : prêt).
- **En bas** :
  - **Créer la song** (dans la couleur de mise en avant de MA) : si quelque chose est déjà occupé,
    un deuxième appui (« Écraser et créer ») est demandé. Le résultat s'affiche dans la fenêtre et
    le bouton devient « Fermer » ;
  - **Valeurs par défaut** : remet tout sauf le nom (premiers numéros libres, 120 BPM, 4 extras,
    20 cues, timecode Oui) ;
  - **Annuler**.
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
à l'appui sur « Créer la song », la liste des apparences du show s'ouvre pour en choisir une autre.
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
- La liste « Select ... » v0.6 : apparences, barre de défilement, filtre, choix d'un élément ; le logo. Une propriété
  refusée par MA est ignorée et notée « propriete ignoree » dans le System Monitor.
- Le programmer doit être vide : les `Store Cue` enregistrent son contenu.
