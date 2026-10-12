# Plugin Song Creator v0.7.1 (grandMA3 2.3.2.0)

Plugin grandMA3 qui remplace la macro « FULL SONG CREATOR » : une fenêtre de setup,
puis la création complète d'une song (page, séquences, cues, timecode, executors,
macro de rappel). Depuis la 0.7 : renommer, dupliquer et supprimer une song existante.

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
  pour fermer (ou Échap). **Coin de redimensionnement** en bas à droite.
- **À gauche, « Mode »** : Créer, Renommer, Dupliquer, Supprimer (le mode en cours en jaune).
  Le centre, le récap de droite et le bouton principal changent avec le mode (voir plus bas).
- **Au centre** :
  - **Song** : le nom, avec en dessous le nom tel qu'il sera écrit dans MA (`Nuit_Blanche`) ;
  - **Emplacements** : une ligne par objet (Page, Séquence main, Macro de rappel, Timecode) avec
    le numéro, puis son état (« libre », ou « occupé : « Intro » » en orange), puis la flèche ▾.
    L'état ou la flèche affichent, **dans la fenêtre**, la liste « Select Page »,
    « Select Sequence »... : tous les numéros du pool comme dans la fenêtre du pool, jusqu'à
    30 numéros après le dernier objet, avec une **barre de défilement** à droite.
    **Noir : libre. Gris : occupé** (ou la couleur de son apparence, pas l'image). Les quatre
    pools marchent pareil : un clic sur une case libre ou occupée la met dans le champ et le
    setup revient ; « Annuler » en bas à droite revient sans rien changer. Pour la séquence, une
    case « pas la place » (la main et ses extras ne tiennent pas avant l'objet suivant) affiche
    un avertissement orange en haut de la liste, qui reste ouverte. L'état couvre tout le bloc ;
  - **Réglages** : BPM, Extras (0 à 10), Cues de song, Créer le timecode (Oui / Non) ;
  - rappel des réglages fixes : Exec main 216, extras 121 à 130, pages communes, Speed Master 3.1.
- **À droite, « Ce qui sera créé »** : le récap en direct, une case par ligne, puis l'alerte en couleur (rouge :
  erreur, orange : déjà occupé ou apparence absente, vert : prêt).
- **En bas** :
  - **Créer la song** (dans la couleur de mise en avant de MA) : si quelque chose est déjà occupé,
    un deuxième appui (« Écraser et créer ») est demandé. Le résultat s'affiche dans la fenêtre et
    le bouton devient « Fermer ». Changer un champ, le mode ou la song remet la fenêtre en saisie :
    on peut enchaîner plusieurs songs sans rouvrir le plugin ;
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
- Depuis la 0.7.1 : **note au nom de la song** sur la page, les séquences, le timecode et la macro, et
  **un tag au nom de la song** (pool Tags) posé sur ces mêmes objets, pour filtrer et pour d'autres
  plugins. Commandes : `Store Tag "Nom"`, `Assign Tag "Nom" At Page 3`, `... At Sequence 101 Thru 105`...

## Renommer, Dupliquer, Supprimer (0.7)
Une song, c'est **une page et une séquence qui portent le même nom** (ce que font le plugin et
l'ancienne macro). Ses extras sont les séquences qui suivent directement la main (numéros qui se
suivent, 10 au maximum) avec ce nom en **note** ; leur propre nom ne compte pas. Son timecode et sa
macro de rappel sont ceux qui portent ce nom. Un extra séparé de la main par un trou, ou dont la
note a été effacée, n'est pas vu comme faisant partie de la song.

Dans ces trois modes, la ligne **Song ▾** ouvre la liste des songs du show (même liste que les
pools, dans la fenêtre). En dessous : la séquence main, les extras, le timecode et la macro trouvés.
- **Renommer** : tape le nouveau nom. Page, séquence main, notes de toutes les séquences, timecode
  et macro prennent le nouveau nom ; dans les commandes des cues et les lignes de la macro,
  `"Ancien_Nom"` devient `"Nouveau_Nom"` (donc `Go+ Timecode "..."`, `Page "..."`...). Si la song
  était la `currentSong`, la variable suit. Un nom déjà porté par une page, une séquence, un
  timecode ou une macro est refusé.
- **Dupliquer** : nouveau nom (`Nom_copie` proposé) et emplacements de la copie (les premiers
  libres après la song, modifiables avec ▾ comme dans Créer ; timecode et macro grisés si la song
  n'en a pas). Le plugin copie les séquences avec leurs cues, la page (puis remet 216 et 121... sur
  les nouvelles séquences, ainsi que les autres executors de la page qui visaient une séquence de
  la song), la macro (nom remplacé dans ses lignes) et **le timecode entier** : chaque lien vers la
  song d'origine (piste, event vers une cue, executor) est ensuite rebranché sur la copie. Les
  pistes qui visent d'autres séquences restent telles quelles. Si un emplacement est occupé,
  deuxième appui « Écraser et dupliquer ».
- **Tag (0.7.1)** : Renommer renomme le tag de la song (ou le crée pour une song plus ancienne) ;
  Dupliquer retire le tag d'origine de la copie et lui pose le sien ; Supprimer supprime aussi le tag.
- **Supprimer** : le récap liste tout ce qui part (page, séquences, timecode, macro, tag). Bouton gris
  à texte rouge, deuxième appui « Confirmer la suppression ».

## Annuler (Oops)
Chaque opération (créer, renommer, dupliquer, supprimer) est regroupée dans une seule action
**Oops** : un Oops l'annule en entier. Exception : pour **Renommer**, les commandes des cues et les
lignes de macro sont écrites en Lua et Oops ne les remet pas ; renommer à nouveau pour revenir.

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
- v0.7.0 / 0.7.1 : Renommer, Dupliquer (timecode compris : les pistes déclenchent bien les nouvelles
  séquences) et Supprimer validés sur console par Jo (12/10). La 0.7.1 ne demande plus l'adresse des
  objets internes du timecode (lignes rouges « Could not resolve object address » en 0.7.0) et ferme
  la fenêtre sans vider l'écran 1. Les tags sont nouveaux en 0.7.1 : si MA refuse une commande de
  tag, elle est listée en avertissement. Le System Monitor note pour le timecode copié :
  `TC n : x objets lus, y liens vers la song d'origine, z rebranches ... (Target par handle ...)`.
  Si des liens n'ont pas pu être rebranchés, ils sont listés avec la structure du timecode
  (`TC classe ...`) : une photo de ces lignes suffit pour corriger.
- Liste dans la fenêtre principale validée sur onPC en 0.6.5 (« tout marche »).
- La liste (ScrollBox + ScrollBarV, recette d'un plugin publié) a défilé sans plantage sur onPC en 0.6.2
  à 0.6.4. Les couleurs d'apparence restent à voir sur des objets qui ont une apparence ; elles sont
  posées après l'affichage de la liste. Le System Monitor note « liste Sequences affichee » puis
  « cases en couleur d'apparence ».
- Les couleurs d'apparence passent par des couleurs ajoutées au thème MA (Global.SongCreator_...),
  retirées à la fin du plugin.
- Si la liste ne peut pas se construire, le plugin ouvre la liste native de MA (sans défilement ni
  apparences) et l'écrit dans le System Monitor.
- Le programmer doit être vide : les `Store Cue` enregistrent son contenu.
