--[[
  <NOM DU PLUGIN> - grandMA3 2.3.2.0
  <Une phrase : ce que fait le plugin.>

  Squelette sans UI. Pour une GUI, partir du template 3 onglets.
]]

-- ============================== REGLAGES ==============================
local DEBUG  = true          -- logs détaillés dans la ligne de commande
local PREFIX = '[XXX]'       -- préfixe des logs (abréviation du plugin)
-- ======================================================================

local pluginName    = select(1, ...)
local componentName = select(2, ...)
local signalTable   = select(3, ...)
local myHandle      = select(4, ...)

local function log(msg)
  Printf(PREFIX .. ' ' .. tostring(msg))
end

local function dbg(msg)
  if DEBUG then log(msg) end
end

local function fail(msg)
  ErrPrintf(PREFIX .. ' ERREUR : ' .. tostring(msg))
end

local function run()
  dbg('début')
  -- 1. lire / valider les entrées
  -- 2. afficher un récapitulatif et demander confirmation
  -- 3. modifier le show
  -- 4. relire ce qui a été écrit et signaler les différences
  dbg('fin')
end

local function Main(display, argument)
  local ok, err = pcall(run)
  if not ok then fail(err) end
end

return Main
