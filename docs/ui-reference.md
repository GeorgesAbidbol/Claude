# UI des plugins grandMA3 2.3.2.0

## Architecture validée (MIDI Mapper)

```lua
local pluginName    = select(1, ...)
local componentName = select(2, ...)
local signalTable   = select(3, ...)
local myHandle      = select(4, ...)

signalTable.OnMonBouton = function(caller)
  -- callbacks définis DANS signalTable
end

local function Main(display, argument)
  -- construction de l'UI ; les boutons utilisent myHandle comme PluginComponent
end

return Main   -- uniquement Main
```

## Patterns maîtrisés

- Plugins à onglets (template 3 onglets : à déposer dans `templates/`).
- Layouts responsives, styles natifs grandMA3, variantes petit / grand écran.
- Structure XML / bytecode des plugins.
- Interface live : lecture seule, épurée (TC Auto Off Manager).

## MessageBox

- Pas de `titleTextColor` ni `backColor`.
- Selectors `type=0` pour afficher sans clavier.
- Mise en page verticale simple : `\n` dans le message.

## Fenêtres redimensionnables

`CreateAddonWindow`, `OnResizeMove`, `OnResizeEnd`, `GetCachedWindowPos`,
`SetCachedWindowPos`, `MinSize`, `SizePolicy`.

## Overlays et popups

Disponibles : `DoOverlay`, `ModalOverlay`, `PopupInput`, `SelectionPopup`,
`EnumSelectionPopup`.
NIL en API standard : `ui`, `CreateOverlay`, `ScreenOverlay`.

## Cibler un écran

- `GetDisplayByIndex(i)` : index à partir de 0.
- `tonumber(disp.W)`, `tonumber(disp.H)` avant comparaison.
- `PopupInput` : seule méthode standard qui vise un écran précis (crée des modales en chaîne).

## Images

XML avec `DependencyExport Address="ShowData.MediaPools.Images.xxx"`, jamais de Base64 dans le Lua.
