# Pièges connus — grandMA3 2.3.2.0 / grandMA2 3.9.60

Erreurs déjà rencontrées en test réel. Format : symptôme → solution.
Ajouter chaque nouvelle découverte ici (avec version et date).

## Structure d'un plugin MA3

- **Le plugin ne se lance pas / callbacks muets** → récupérer les 4 paramètres
  avec `select()` (`pluginName, componentName, signalTable, myHandle`),
  définir les callbacks **dans `signalTable`**, utiliser `myHandle` pour le
  PluginComponent des boutons. (MIDI Mapper)
- **`return Main, Cleanup` pose problème** → retourner **uniquement `Main`**.
- `return Main` avec **M majuscule**.
- Retours à la ligne dans les chaînes : `\n`.

## Objets du show

- **Remplacer le preset d'une ligne de recipe** : `recipeLine:Set(...)` échoue →
  affectation directe `recipeLine.Preset = targetPreset`. (Preset Search & Replace)
- **`GetReferences()`** est obsolète → scanner manuellement les objets.
- **Pas de propriété `.Enable`**.
- **MAtricks** : l'affectation directe ne marche pas →
  `matricks:Set(property, value)`. (Grid Width Phaser)
- **`SelectionFirst()` / `SelectionNext()`** retournent
  `handle, GridPosX, GridPosY, GridPosZ`.
- **`DeleteUserVariable`** n'accepte **aucun wildcard** (`"Temp*"` ne marche pas)
  → supprimer les variables une par une.

## Hooks

- **`HookObjectChange`** exige **3 paramètres** :
  `HookObjectChange(callback, hookTarget, pluginHandle)` avec
  `pluginHandle = myHandle:Parent()`. (TC Auto Off Manager)

## Chaînes Lua

- **Bug 2.3.x** : `#[...]` dans le code Lua est corrompu en `#FFFFFFFFFFFFFFFF`
  → extraire avec un pattern : `select(3, str:find('pattern(.+)'))`.

## UI et écrans

- **`MessageBox`** : `titleTextColor` et `backColor` provoquent des erreurs → ne pas les utiliser.
  Selectors `type=0` pour un affichage sans clavier. Mise en page verticale simple : `\n` dans le message.
- **`ui` vaut NIL** dans l'API standard. **`CreateOverlay` / `ScreenOverlay` sont NIL** :
  les menus déroulants de barre de titre (type Setup Manager) passent par une API privée,
  inaccessible aux plugins standards.
- **`GetDisplayByIndex()`** est indexé **à partir de 0**.
- **`disp.W` / `disp.H`** : passer par `tonumber()` avant toute comparaison.
- **Cibler un écran précis** : `PopupInput` est la seule méthode standard,
  mais elle crée des chaînes de fenêtres modales.
- **Images** : pas de Base64 dans le Lua (mémoire limitée) → XML avec
  `DependencyExport Address="ShowData.MediaPools.Images.xxx"`.

## Macros MA3

- **Pas de Lua complexe dans les macros** (boucles, conditions) → faire un plugin.
- **Substitution de variable** : fermer les guillemets avant la variable :
  `"Page "$SongName`. Pas d'échappement `\$`.
- **Pas de guillemets internes** dans `SetGlobalVariable`.
- **Appeler un composant de plugin** : `"Plugin X.Y"`, pas `"Go+ Plugin X.Y"`.
- XML : guillemets encodés `&quot;`.

## Phasers (Grid Phaser Tools, en cours)

- **Non résolu** : appliquer des largeurs de phaser alors que des séquences sont actives
  contamine le programmer (tous les attributs s'activent au lieu de celui ciblé).
- `GetProgPhaser()` renvoie une structure **plate indexée par métadonnées**,
  pas par numéro de step.
- Les données de phaser viennent du **preset** (`abs_preset`), pas de valeurs
  directes du programmer.

## grandMA2 3.9.60

- **`/cmd="..."`** n'accepte pas de `"` à l'intérieur, et `/cmd='...'` non plus
  (Error #14, testé console) → apostrophes dans la commande.
- Les apostrophes **ne suffisent pas pour appeler un timecode** par nom :
  correction manuelle en `"<nom>"` nécessaire.
- **`gma.echo`** n'écrit que dans le System Monitor ; **`gma.feedback`** écrit dans
  la ligne de commande → logger dans les deux.
