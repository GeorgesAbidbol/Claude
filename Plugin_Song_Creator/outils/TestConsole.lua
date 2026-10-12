-- Plugin de test minimal : vérifie que la console exécute un plugin Lua
-- et affiche une MessageBox. Aucun accent, aucune option d'écran.
local function Main(displayHandle, argument)
  Printf("[TestConsole] le plugin demarre")
  local r = MessageBox({
    title = "Test console",
    message = "Si tu vois cette fenetre, la console lance bien les plugins.",
    commands = { { value = 1, name = "OK" } },
  })
  Printf("[TestConsole] fin, resultat = " .. tostring(r and r.result))
end

return Main
