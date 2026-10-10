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

## Ressources

Le dossier `Ressources/` du dépôt contient deux références Lua grandMA3 copiées avec leur licence :
la documentation de l'API (MacTirney, MIT) et des exemples avec la liste des éléments d'interface,
polices, icônes et couleurs (BakaCowpoke, CC0). À consulter avant de deviner un nom de fonction ou
de propriété. Elles confirment que `LineEdit`, `ResizeCorner`, la police `Medium20` et l'icône
`object_plugin1` existent, et que `MessageBox` n'a pas d'option pour choisir l'écran.

## Reste à faire

- Retour de Jo sur la v0.3.0 sur console (fenêtre, déplacement, redimensionnement, sélection native).
- Vérifier les commandes des cues TC et les lignes de la macro de rappel.
- Plus tard : séquence modèle à copier, renommer / supprimer une song, link Reaper.
