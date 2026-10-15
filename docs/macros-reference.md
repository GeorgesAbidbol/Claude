# Macros grandMA3 2.3.2.0

## Principes

- MacroLines = mots-clés de commande uniquement. Boucles et conditions → plugin.
- XML : `DataVersion="2.3.2.0"`, éléments `MacroLine` avec GUIDs, guillemets en `&quot;`.

## Variables

- Fermer les guillemets avant la variable : `"Page "$SongName`
- Pas d'échappement `\$`.
- Pas de guillemets internes dans `SetGlobalVariable`.
- `DeleteUserVariable` : une variable à la fois, aucun wildcard.

## Écrire une macro depuis une macro

```
Store Macro X.Y Property "Command" "texte "$variable
```

## Appeler un plugin

`"Plugin X.Y"` (pas `"Go+ Plugin X.Y"`). Exemple : composant « OffManuel »
de TC Auto Off Manager appelé depuis une macro.

## Mots-clés essentiels

Store (18 options), At (valeurs / presets), Thru (plages), Goto / Go+ / Go-
(playback), SetUserVariable / SetGlobalVariable, Assign (executors), Label (nommage).

## Full Song Creator (macro MA3)

Création de page, séquences, macros et cues en un seul workflow.
Timecodes et pages appelés par nom.
