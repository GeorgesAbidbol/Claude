# Référence API Lua grandMA3 2.3.2.0 — fonctions validées

Uniquement ce qui a fonctionné en test réel. Voir aussi `api-pieges.md`.

## Accès aux objets

| Fonction | Usage |
|---|---|
| `GetObject('path')` | accès textuel à un objet |
| `obj:FindParent('Type')` | remonter la hiérarchie |
| `ObjectList('path')` | table itérable avec `ipairs` |
| `ObjectList("Timecode 1 Thru 999")` | lister tous les timecodes |
| `ShowData().DataPools.Default.Timecodes` | pool des timecodes |
| `SelectedTimecode()` | timecode sélectionné (natif) |

## Macros (objets)

| Fonction | Usage |
|---|---|
| `macro[lineName]` | MacroLine par nom |
| `macro:Insert(1)` | insérer une ligne en position 1 |
| `macro:Aquire()` | nouvelle macro (orthographe API : `Aquire`) |
| `ml:Copy(source)`, `ml:Index()`, `ml:Parent()` | manipulation de lignes |

## Exécution

| Fonction | Usage |
|---|---|
| `CmdIndirectWait(cmd)` | exécuter une commande et attendre |
| `coroutine.yield(sec)` | pause |
| `pcall(func)` | gestion d'erreur |
| `StartProgress` / `SetProgress` / `StopProgress` | barre de progression |

## Hooks

`HookObjectChange(callback, hookTarget, myHandle:Parent())`

## Sélection et MAtricks

- `SelectionFirst()` / `SelectionNext()` → `handle, GridPosX, GridPosY, GridPosZ`
- `matricks:Set(property, value)`

## Écrans

`GetDisplayCollect`, `GetFocusDisplay`, `GetDisplayByIndex` (base 0) — voir `ui-reference.md`.

## Variables (pattern MULE)

Accès simplifié aux variables utilisateur puis globales :

```lua
setmetatable({}, {__index = function(t, k)
  return GetVar(UserVars(), k) or GetVar(GlobalVars(), k) or _G[k]
end})
```

## OSC

Trois méthodes de contrôle : executor direct, ligne de commande `/cmd`,
adressage d'objets énumérés.

## Formules de largeur de phaser

- **Phaser to Chase** : Step1 Width = (1/x)×100, Step2 Width = ((x-1)/x)×100
- **Line by Line** (formule de Sebastian) : Step1 Width = (1/X)×100,
  Step2 Width = ((X-1)/X)×100, PhaseToX = (360/Y) - (360/(X×Y)), PhaseToY = 360

## Grid Placer

`RemoveGaps` appliqué uniquement quand aucun spacer ni offset n'est donné.

## Plugins étudiés

- **MULE Creator** (Andreas Glad) : injection Lua en MacroLine 1, conditions `[expr]`
  dans les champs Name, gotos `::label::`, substitution `{expr}`.
- **BumpMakerXXL** : bytecode compilé, ~48 % de compression des presets,
  pattern `CopyRecipeMatricksToSequence`.
- **Setup Manager Free** : `GetDisplayCollect` / `GetFocusDisplay` / `GetDisplayByIndex`
  OK en API standard ; ses menus de barre de titre utilisent une API privée.

## Ressources externes

Extension VS Code de Jeremy012, wiki hossimo/GMA3Plugins, définitions de
fonctions de jefffarrow, grandma3.bambinito.net.
