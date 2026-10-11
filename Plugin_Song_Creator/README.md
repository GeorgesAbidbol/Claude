# Plugin Song Creator v0.4.1 (grandMA3 2.3.2.0)

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
Disposition reprise de la fenêtre MA « Search and Modify » (maquette v0.4).
- Une seule fenêtre, toujours sur **l'écran 1**, taille de départ 1400 x 600 (réduite si l'écran
  est plus petit). Lignes de hauteur fixe, texte plus grand.
- **Barre de titre** : on la fait glisser pour déplacer la fenêtre ; **croix** en haut à droite
  pour fermer (ou Échap). **Coin de redimensionnement** en bas à droite.
- **À gauche, « Mode : »** : Créer (en jaune). Renommer, Dupliquer et Supprimer sont grisés,
  ils viendront plus tard.
- **Au centre** :
  - nom de la song, avec en dessous le nom tel qu'il sera écrit dans MA (`Nuit_Blanche`) ;
  - **Emplacements** : Page, Séquence main, Macro de rappel, Timecode. On tape le numéro ou on
    appuie sur la **flèche ▾** à côté : la fenêtre de sélection native de MA (« Select ... »,
    avec filtre clavier) s'ouvre sur le bouton. Elle liste les objets existants (`12 'Nom'`) puis
    des numéros libres. Pour la séquence, les numéros libres ont la place pour la main et toutes
    les extras. Une case dont le numéro est déjà occupé s'écrit en orange ;
  - **Réglages** : BPM, Extras (0 à 10), Cues de song, Créer le timecode (bouton Oui / Non) ;
  - rappel des réglages fixes : Exec main 216, extras 121 à 130, pages communes, Speed Master 3.1.
- **À droite, « Ce qui sera créé : »** : le récap en direct, puis les alertes (rouge : erreur,
  orange : déjà occupé ou apparence absente, vert : prêt).
- **En bas** :
  - **Créer la song** : si quelque chose est déjà occupé, un deuxième appui (« Écraser et créer »)
    est demandé. Le résultat s'affiche dans la fenêtre et le bouton devient « Fermer » ;
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
- L'aspect de la fenêtre v0.4 : polices, couleurs, icônes des boutons, modes grisés. Une propriété
  refusée par MA est ignorée et notée « propriete ignoree » dans le System Monitor.
- Le programmer doit être vide : les `Store Cue` enregistrent son contenu.
