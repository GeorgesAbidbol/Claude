-- ============================================================================
--  Song Creator  -  plugin grandMA3 (cible 2.3.2.0)
--  Remplace la macro "FULL SONG CREATOR" : une fenêtre de setup, puis
--  création de la page, des séquences, des cues, du timecode, des executors
--  et de la macro de rappel de la song.
-- ============================================================================

local pluginName    = select(1, ...)
local componentName = select(2, ...)
local signalTable   = select(3, ...)
local myHandle      = select(4, ...)

local VERSION = "0.6.4"

-- ---------------------------------------------------------------------------
--  Réglages fixes (ceux de la macro d'origine)
-- ---------------------------------------------------------------------------
local CFG = {
  execMain      = 216,            -- executor de la séquence principale
  execExtraFrom = 121,            -- 1er executor des extras
  maxExtras     = 10,             -- 121..130
  commonPages   = "101 thru 120", -- pages qui restent allumées au rappel
  speedMaster   = "3.1",          -- speed master réglé au BPM

  confMain      = "MAIN SEQUENCE",
  confExtras    = "EXTRAS",
  appMain       = "GREEN",
  appExtras     = "BLUE",
  appTcCues     = "LAVENDER",
  appBlackOut   = "Black",

  defaults = { bpm = 120, extras = 4, cues = 20 },
}

-- ---------------------------------------------------------------------------
--  Outils
-- ---------------------------------------------------------------------------
local log = {}
local undo        -- liste Oops de la création en cours (une seule annulation)
local cmdErrors = {}

-- Exécute une commande et vérifie le retour de MA (« OK », « Syntax Error »,
-- « Illegal Command »...) : une commande refusée est signalée, pas ignorée.
local function C(cmd)
  log[#log + 1] = cmd
  Printf("[SongCreator] " .. cmd)
  local ok, res
  if undo then ok, res = pcall(Cmd, cmd, undo) else ok, res = pcall(Cmd, cmd) end
  if not ok then
    cmdErrors[#cmdErrors + 1] = cmd .. "  ->  " .. tostring(res)
  elseif res ~= nil and not tostring(res):upper():find("^%s*OK") then
    cmdErrors[#cmdErrors + 1] = cmd .. "  ->  " .. tostring(res)
    ErrPrintf("[SongCreator] refusee : " .. cmd .. " -> " .. tostring(res))
  end
end

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- Pas d'espace dans les noms : tous les espaces deviennent "_",
-- et les guillemets sont retirés (ils casseraient les commandes).
local function cleanName(s)
  s = trim(s):gsub('"', ""):gsub("%s+", "_")
  return s -- (une seule valeur)
end

local function toInt(s)
  local n = tonumber(trim(s))
  if n and n == math.floor(n) then return n end
  return nil
end

local function pool(name)
  local dp = DataPool()
  return dp and dp[name]
end

local function exists(poolName, no)
  local p = pool(poolName)
  return p ~= nil and p[no] ~= nil
end

local function firstFree(poolName, from, count)
  count = count or 1
  local n = from or 1
  while n < 10000 do
    local free = true
    for i = 0, count - 1 do
      if exists(poolName, n + i) then free = false; break end
    end
    if free then return n end
    n = n + 1
  end
  return from
end

-- ---------------------------------------------------------------------------
--  Sélecteur graphique de pool (Page / Macro / Timecode)
--  Liste les objets existants (numéro + nom) et les numéros libres autour,
--  dans un menu déroulant MA (PopupInput). Renvoie le numéro choisi ou nil.
-- ---------------------------------------------------------------------------
local PICKERS = {
  [3] = { field = "page",  pool = "Pages",     title = "Page" },
  [4] = { field = "macro", pool = "Macros",    title = "Macro" },
  [5] = { field = "tcNo",  pool = "Timecodes", title = "Timecode" },
  [6] = { field = "seq",   pool = "Sequences", title = "Sequence" },
}

-- Lit le pool : used[no] = nom, maxNo = plus grand numéro occupé.
local function readPool(poolName)
  local p = pool(poolName)
  local used, maxNo, objs = {}, 0, {}
  if p then
    for _, obj in ipairs(p:Children()) do
      local no = tonumber(obj.no)
      if no then
        used[no] = obj.name or ""
        objs[no] = obj
        if no > maxNo then maxNo = no end
      end
    end
  end
  return used, maxNo, objs
end

-- block : nombre de numéros consécutifs nécessaires (séquence main + extras)
local function hasRoom(used, n, block)
  for k = 1, (block or 1) - 1 do
    if used[n + k] then return false end
  end
  return true
end

local function setColor(obj, prop, colorPath)
  -- Couleurs du thème MA ; ignorées si le chemin n'existe pas dans cette version
  pcall(function()
    local c = Root().ColorTheme.ColorGroups
    for part in colorPath:gmatch("[^%.]+") do c = c[part] end
    if c then obj[prop] = c end
  end)
end

-- Écran où afficher les fenêtres. Sur console, l'écran qui a le focus peut
-- être un petit écran (ou aucun) : on se rabat alors sur l'écran 1.
local function displaySize(d)
  local w, h
  pcall(function() w, h = d.AbsRect.w, d.AbsRect.h end)
  if not w then pcall(function() w, h = tonumber(d.W), tonumber(d.H) end) end
  return w, h
end

local function displayIndex(d)
  local idx
  pcall(function() idx = d:Index() end)
  if not idx then pcall(function() idx = tonumber(d.index or d.no) end) end
  return idx
end

-- Le plugin s'ouvre toujours sur l'écran 1 (choix de Jo).
local function pickDisplay()
  local d = GetDisplayByIndex(1) or GetFocusDisplay()
  local w, h = displaySize(d)
  return d, w or 1280, h or 800
end

-- MessageBox (fenêtre de secours) sur l'écran 1 ; si la console refuse le
-- paramètre "display", on réessaie sans.
local function Box(opts)
  local ok, r = pcall(function()
    local o = {}
    for k, v in pairs(opts) do o[k] = v end
    o.display = (pickDisplay())
    return MessageBox(o)
  end)
  if ok and r then return r end
  Printf("[SongCreator] MessageBox sur ecran 1 impossible (" .. tostring(r) .. "), essai sans ecran impose")
  return MessageBox(opts)
end

-- ---------------------------------------------------------------------------
--  Fenêtre sur mesure : outils communs
-- ---------------------------------------------------------------------------

-- Propriétés « confort » : ignorées une par une si la version ne les connaît pas.
local function opt(obj, props)
  for k, v in pairs(props) do
    local ok = pcall(function() obj[k] = v end)
    if not ok then Printf("[SongCreator] propriete ignoree : " .. tostring(k)) end
  end
end

local function cell(col, row, col2, row2)
  return { left = col, right = col2 or col, top = row, bottom = row2 or row }
end

-- Position (à partir de 1) d'une fenêtre parmi les fenêtres de l'écran :
-- on vérifie que c'est bien elle avant de supprimer quoi que ce soit.
local function overlayIndex(overlay, base)
  local idx
  pcall(function()
    local i = Obj.Index(base)
    if overlay:GetUIChild(i) == base then idx = i end
  end)
  if idx then return idx end
  pcall(function()
    for i = 1, overlay:GetUIChildrenCount() do
      if overlay:GetUIChild(i) == base then idx = i; break end
    end
  end)
  if idx then return idx end
  -- version de MA sans GetUIChild : l'index donné par MA (recette de GUI REPLACE V15)
  pcall(function() idx = Obj.Index(base) end)
  return idx
end

-- Ferme une fenêtre. MA supprime la fenêtre un peu plus tard : on attend
-- qu'elle ait disparu au lieu de tout effacer (en 0.6.3, choisir une case
-- de la liste effaçait aussi la fenêtre principale et fermait le plugin).
-- others = true : d'autres fenêtres du plugin restent ouvertes, on ne vide
-- jamais l'écran ; au pire la fenêtre est masquée.
local function closeWindow(overlay, base, others)
  if not IsObjectValid(base) then return end
  local idx = overlayIndex(overlay, base)
  if idx then pcall(function() Obj.Delete(overlay, idx) end) end
  for _ = 1, 20 do
    if not IsObjectValid(base) then return end
    coroutine.yield(0.05)
  end
  Printf("[SongCreator] fenetre non supprimee par MA (index " .. tostring(idx) .. ")")
  if others then
    pcall(function() base.Visible = "No" end)
  else
    pcall(function() overlay:ClearUIChildren() end)
  end
end

-- ---- Fenêtre de sélection native MA (PopupInput), en secours ----
-- Même fenêtre que les « Select ... » de la console : colonnes, filtre clavier.
-- Elle liste les objets existants du pool (« 12 'Nom' ») puis des numéros libres.
-- Pas de défilement ni d'apparences (vu sur console en 0.6.1).
local FREE_SLOTS = 12

-- title : nom du pool seul, MA ajoute « Select » devant (« Select Sequence »).
local function pickWithPopupInput(poolName, title, current, block, caller)
  local used, maxNo = readPool(poolName)
  local items, numbers, selected = {}, {}, nil
  local function add(n, label)
    items[#items + 1] = label
    numbers[#numbers + 1] = n
    if n == current then selected = label end
  end

  local nos = {}
  for n in pairs(used) do nos[#nos + 1] = n end
  table.sort(nos)
  for _, n in ipairs(nos) do add(n, string.format("%d '%s'", n, used[n])) end

  local free, n = 0, 1
  while free < FREE_SLOTS and n < 10000 do
    if not used[n] and hasRoom(used, n, block) then
      add(n, string.format("%d  - libre -", n))
      free = free + 1
    end
    n = n + 1
  end

  local args = {
    title         = title,
    caller        = caller or (pickDisplay()),
    items         = items,
    selectedValue = selected,
    add_args      = { FilterSupport = "Yes" }, -- recherche au clavier
  }
  local ok, idx, value = pcall(PopupInput, args)
  if not ok then
    -- caller refusé : on réessaie ancré sur l'écran 1
    args.caller = (pickDisplay())
    idx, value = PopupInput(args)
  end
  -- On se fie d'abord au texte choisi, puis à l'index (à partir de 0)
  if value then
    for k, label in ipairs(items) do
      if label == value then return numbers[k] end
    end
  end
  idx = tonumber(idx)
  if idx == nil then return nil end
  return numbers[idx + 1]
end

-- ---------------------------------------------------------------------------
--  Fenêtre de setup
-- ---------------------------------------------------------------------------
local F = {
  name   = "Nom de la song",
  page   = "Page",
  bpm    = "BPM",
  macro  = "Macro de rappel",
  seq    = "Sequence main",
  extras = "Nombre d'extras (0-10)",
  cues   = "Cues de song",
  tcNo   = "N° timecode",
}
local S_TC = "Créer le timecode"

local function defaultValues()
  local seq = firstFree("Sequences", 1, 1 + CFG.defaults.extras)
  return {
    name   = "",
    page   = firstFree("Pages", 1),
    bpm    = CFG.defaults.bpm,
    macro  = firstFree("Macros", 1),
    seq    = seq,
    extras = CFG.defaults.extras,
    cues   = CFG.defaults.cues,
    tcNo   = firstFree("Timecodes", 1),
    tcOn   = true,
  }
end

local function askSetup(v, errorText)
  local num = "0123456789"
  local msg = "Remplis le setup de la song puis valide.\n"
           .. "Les espaces du nom seront remplacés par _.\n"
           .. "Les extras sont placés juste après la séquence main.\n"
           .. "Page, Macro, Timecode, Sequence : tape le numéro ou ouvre la liste du pool."
  if errorText then msg = "/!\\ " .. errorText .. "\n\n" .. msg end

  local r = Box({
    title    = "Song Creator  v" .. VERSION,
    message  = msg,
    commands = {
      { value = 3, name = "Liste Pages..." },
      { value = 4, name = "Liste Macros..." },
      { value = 5, name = "Liste Timecodes..." },
      { value = 6, name = "Liste Sequences..." },
      { value = 1, name = "Suivant" },
      { value = 0, name = "Annuler" },
    },
    inputs   = {
      { name = F.name,   value = v.name,              vkPlugin = "TextInput" },
      { name = F.page,   value = tostring(v.page),    whiteFilter = num, vkPlugin = "NumericInput" },
      { name = F.bpm,    value = tostring(v.bpm),     whiteFilter = num, vkPlugin = "NumericInput" },
      { name = F.macro,  value = tostring(v.macro),   whiteFilter = num, vkPlugin = "NumericInput" },
      { name = F.seq,    value = tostring(v.seq),     whiteFilter = num, vkPlugin = "NumericInput" },
      { name = F.extras, value = tostring(v.extras),  whiteFilter = num, vkPlugin = "NumericInput" },
      { name = F.cues,   value = tostring(v.cues),    whiteFilter = num, vkPlugin = "NumericInput" },
      { name = F.tcNo,   value = tostring(v.tcNo),    whiteFilter = num, vkPlugin = "NumericInput" },
    },
    states   = { { name = S_TC, state = v.tcOn } },
  })
  if not r or r.result == 0 then return nil end

  local i = r.inputs or {}
  return r.result, {
    rawName = i[F.name] or "",
    name    = cleanName(i[F.name]),
    page    = toInt(i[F.page]),
    bpm     = toInt(i[F.bpm]),
    macro   = toInt(i[F.macro]),
    seq     = toInt(i[F.seq]),
    extras  = toInt(i[F.extras]),
    cues    = toInt(i[F.cues]),
    tcNo    = toInt(i[F.tcNo]),
    tcOn    = (r.states or {})[S_TC] and true or false,
  }
end

-- Renvoie un texte d'erreur bloquante, plus la liste des emplacements occupés.
local function validate(v)
  if v.name == "" then return "Donne un nom à la song." end
  for _, k in ipairs({ "page", "bpm", "macro", "seq", "extras", "cues", "tcNo" }) do
    if not v[k] and (k ~= "tcNo" or v.tcOn) then return "Champ invalide : " .. F[k] end
  end
  if v.extras > CFG.maxExtras then return "Maximum " .. CFG.maxExtras .. " extras (executors 121 à 130)." end
  if v.cues < 1 then return "Il faut au moins 1 cue de song." end

  local busy = {}
  local function add(poolName, label, no)
    local p = pool(poolName)
    local o = p and p[no]
    if not o then return end
    local nm = o.name and tostring(o.name) or ""
    busy[#busy + 1] = label .. " " .. no .. ((nm ~= "") and (" « " .. nm .. " »") or "")
  end
  add("Pages", "Page", v.page)
  for s = v.seq, v.seq + v.extras do add("Sequences", "Séquence", s) end
  add("Macros", "Macro", v.macro)
  if v.tcOn then add("Timecodes", "Timecode", v.tcNo) end
  return nil, busy
end

-- Apparences de la song. MA répond OK à « Assign Appearance » même quand
-- l'apparence n'existe pas dans le show (test console du 11/10) : on vérifie
-- avant, et on fait choisir une apparence du show à la place. Le choix est
-- gardé dans une variable globale du show (SongCreator_App_...).
local APP_ROLES = {
  { key = "main",   default = CFG.appMain,     label = "Executor main" },
  { key = "extras", default = CFG.appExtras,   label = "Executors extras" },
  { key = "tc",     default = CFG.appTcCues,   label = "Cues timecode" },
  { key = "bo",     default = CFG.appBlackOut, label = "Cue Black Out" },
}

local function appVarName(key) return "SongCreator_App_" .. key end

local function appName(key)
  local okV, saved = pcall(function() return GetVar(GlobalVars(), appVarName(key)) end)
  if okV and saved ~= nil and tostring(saved) ~= "" then return tostring(saved) end
  for _, r in ipairs(APP_ROLES) do
    if r.key == key then return r.default end
  end
end

-- Noms des apparences du show, dans l'ordre du pool (nil si illisible)
local function appearanceNames()
  local okA, apps = pcall(function() return ShowData().Appearances end)
  if not okA or not apps then return nil end
  local okC, list = pcall(function() return apps:Children() end)
  if not okC or type(list) ~= "table" then return nil end
  local names = {}
  for _, a in ipairs(list) do
    if a.name and tostring(a.name) ~= "" then names[#names + 1] = tostring(a.name) end
  end
  return names
end

-- Rôles dont l'apparence n'existe pas dans le show
local function missingAppearances(v)
  local names = appearanceNames()
  if not names then return {} end
  local have = {}
  for _, n in ipairs(names) do have[n:lower()] = true end
  local miss = {}
  for _, r in ipairs(APP_ROLES) do
    if (r.key ~= "extras" or (v.extras or 0) > 0) and not have[appName(r.key):lower()] then
      miss[#miss + 1] = r
    end
  end
  return miss
end

-- Ouvre la liste native des apparences du show pour chaque apparence absente
local function resolveAppearances(v, caller)
  local miss = missingAppearances(v)
  if #miss == 0 then return end
  local names = appearanceNames() or {}
  if #names == 0 then return end
  for _, r in ipairs(miss) do
    local args = {
      title    = 'Select Appearance (' .. r.label .. ' : "' .. appName(r.key) .. '" absente)',
      caller   = caller or (pickDisplay()),
      items    = names,
      add_args = { FilterSupport = "Yes" },
    }
    local ok, idx, value = pcall(PopupInput, args)
    if not ok then
      args.caller = (pickDisplay())
      ok, idx, value = pcall(PopupInput, args)
    end
    local chosen
    if ok and value and value ~= "" then
      chosen = value
    elseif ok and tonumber(idx) then
      chosen = names[tonumber(idx) + 1]
    end
    if chosen then
      pcall(function() SetVar(GlobalVars(), appVarName(r.key), chosen) end)
      Printf("[SongCreator] apparence " .. r.label .. " -> " .. chosen)
    end
  end
end

local function recapText(v, busy)
  local lastExtra = v.seq + v.extras
  local t = {
    "Song : " .. v.name,
    "Page " .. v.page .. "  |  BPM " .. v.bpm .. "  |  Macro " .. v.macro,
    "Sequence main " .. v.seq .. " -> Exec " .. CFG.execMain,
  }
  if v.extras > 0 then
    t[#t + 1] = "Extras : Seq " .. (v.seq + 1) .. " a " .. lastExtra
             .. " -> Exec " .. CFG.execExtraFrom .. " a " .. (CFG.execExtraFrom + v.extras - 1)
  else
    t[#t + 1] = "Extras : aucun"
  end
  t[#t + 1] = "Cues : 0.5 Mise, 0.6/0.7 TC, 1 a " .. v.cues
           .. ", " .. (v.cues + 1) .. " Black Out, " .. (v.cues + 2) .. " Off TC"
  t[#t + 1] = v.tcOn and ("Timecode " .. v.tcNo .. ' "' .. v.name .. '"') or "Timecode : non"
  if busy and #busy > 0 then
    t[#t + 1] = ""
    t[#t + 1] = "/!\\ DEJA OCCUPE (sera ecrase) : " .. table.concat(busy, ", ")
  end
  local miss = missingAppearances(v)
  if #miss > 0 then
    local t2 = {}
    for _, r in ipairs(miss) do t2[#t2 + 1] = appName(r.key) end
    t[#t + 1] = "/!\\ Apparence absente du show : " .. table.concat(t2, ", ")
             .. " (une liste s'ouvrira pour en choisir une)"
  end
  return table.concat(t, "\n")
end

local function confirm(v, busy)
  local r = Box({
    title    = "Song Creator - confirmation",
    message  = recapText(v, busy),
    commands = { { value = 1, name = (#busy > 0) and "Ecraser et creer" or "Creer la song" },
                 { value = 2, name = "Modifier" },
                 { value = 0, name = "Annuler" } },
  })
  return r and r.result or 0
end

-- ---------------------------------------------------------------------------
--  Création
-- ---------------------------------------------------------------------------
local function findCueByName(seqNo, cueName)
  local seq = pool("Sequences") and pool("Sequences")[seqNo]
  if not seq then return nil end
  for _, cue in ipairs(seq:Children()) do
    if cue.name == cueName then return cue end
  end
  return nil
end

-- Nom exact d'une propriété de l'objet : nil si l'objet ne sait pas lister
-- ses propriétés, false si elle n'existe pas.
local function propName(obj, wanted)
  local okC, n = pcall(function() return obj:PropertyCount() end)
  if not okC or type(n) ~= "number" then return nil end
  for i = 0, n - 1 do
    local okN, pn = pcall(function() return obj:PropertyName(i) end)
    if okN and type(pn) == "string" and pn:lower() == wanted:lower() then return pn end
  end
  return false
end

local function propList(obj)
  local okC, n = pcall(function() return obj:PropertyCount() end)
  if not okC or type(n) ~= "number" then return "?" end
  local t = {}
  for i = 0, n - 1 do
    local okN, pn = pcall(function() return obj:PropertyName(i) end)
    if okN and pn then t[#t + 1] = tostring(pn) end
  end
  return table.concat(t, ", ")
end

-- Écrit une propriété puis la relit. Sur 2.3.2, un Set refusé n'est pas
-- toujours une erreur Lua (MA l'écrit seulement en rouge) : seule la
-- relecture prouve que la valeur est posée.
local function setChecked(obj, wanted, value)
  if not obj then return false end
  local name = propName(obj, wanted)
  if name == false then return false end
  name = name or wanted
  if not pcall(function() obj:Set(name, value) end) then return false end
  local okG, got = pcall(function() return obj:Get(name) end)
  return okG and got ~= nil and trim(tostring(got)) == value
end

-- Écrit la commande d'une cue via l'API Lua (pas de souci de guillemets
-- imbriqués). Sur 2.3.2 la cue refuse « Command » (test console du 11/10) :
-- on essaie d'abord sa part 0, puis la cue.
local function setCueCommand(seqNo, cueName, command, warnings)
  local cue = findCueByName(seqNo, cueName)
  if not cue then
    warnings[#warnings + 1] = "Cue \"" .. cueName .. "\" introuvable"
    return
  end
  local okP, part = pcall(function() return cue[1] end)
  if not okP then part = nil end
  if setChecked(part, "Command", command) or setChecked(cue, "Command", command) then
    log[#log + 1] = "(lua) " .. cueName .. " : Command = " .. command
    return
  end
  warnings[#warnings + 1] = "Commande non posée sur \"" .. cueName .. "\" : " .. command
  -- pour le diagnostic : les propriétés que MA propose sur la cue et la part
  Printf("[SongCreator] proprietes cue " .. cueName .. " : " .. propList(cue))
  if part then Printf("[SongCreator] proprietes part : " .. propList(part)) end
end

local function buildSongMacro(v, warnings)
  local lines = {
    'Page "' .. v.name .. '"',
    'SetGlobalVariable currentSong "' .. v.name .. '"',
    "Off Page thru -Page $currentSong - Page " .. CFG.commonPages,
    "FaderMaster Executor " .. CFG.execMain .. " At 100",
    "Select Executor " .. CFG.execMain,
    "Goto Cue 0.5",
    "Master " .. CFG.speedMaster .. " At BPM " .. v.bpm,
  }

  C("Store Macro " .. v.macro .. " /Overwrite")
  C('Label Macro ' .. v.macro .. ' "' .. v.name .. '"')

  local macro = pool("Macros")[v.macro]
  if not macro then
    warnings[#warnings + 1] = "Macro " .. v.macro .. " non créée"
    return
  end
  -- Lignes créées par « Store Macro N.i » (la commande de l'ancienne macro),
  -- puis remplies via l'API Lua : "$currentSong" reste tel quel (il n'est pas
  -- remplacé à la création) et pas de guillemets imbriqués.
  for i = 1, #lines do C("Store Macro " .. v.macro .. "." .. i) end
  for i, text in ipairs(lines) do
    local line = macro[i]
    if not line then pcall(function() line = macro:Append() end) end
    if line and setChecked(line, "Command", text) then
      log[#log + 1] = "(lua) Macro " .. v.macro .. "." .. i .. " = " .. text
    elseif line then
      warnings[#warnings + 1] = "Ligne " .. i .. " de la macro sans commande : " .. text
    else
      warnings[#warnings + 1] = "Ligne " .. i .. " de la macro non créée"
    end
  end
end

local function createBody(v, warnings)
  local lastExtra = v.seq + v.extras
  local cueBO, cueOffTC = v.cues + 1, v.cues + 2
  local tcName = '"' .. v.name .. '"'

  -- 1. Page
  C("Store Page " .. v.page .. " /Overwrite")
  C("Page " .. v.page)
  C('Label Page ' .. v.page .. ' "' .. v.name .. '"')

  -- 2. Séquences
  C("Store Sequence " .. v.seq .. " Thru " .. lastExtra .. " /Overwrite")
  C('Label Sequence ' .. v.seq .. ' "' .. v.name .. '"')
  C('Note Sequence ' .. v.seq .. ' "' .. v.name .. '"')
  if v.extras > 0 then
    C('Note Sequence ' .. (v.seq + 1) .. " Thru " .. lastExtra .. ' "' .. v.name .. '"')
  end

  -- 3. Executors
  C("Assign Sequence " .. v.seq .. " At Executor " .. CFG.execMain)
  if v.extras > 0 then
    C("Assign Sequence " .. (v.seq + 1) .. " Thru " .. lastExtra
      .. " At Executor " .. CFG.execExtraFrom .. " Thru " .. (CFG.execExtraFrom + v.extras - 1))
    C('Assign Configuration "' .. CFG.confExtras .. '" At Executor '
      .. CFG.execExtraFrom .. " Thru " .. (CFG.execExtraFrom + v.extras - 1))
    C('Assign Appearance "' .. appName("extras") .. '" At Executor '
      .. CFG.execExtraFrom .. " Thru " .. (CFG.execExtraFrom + v.extras - 1))
  end
  C('Assign Configuration "' .. CFG.confMain .. '" At Executor ' .. CFG.execMain)
  C('Assign Appearance "' .. appName("main") .. '" At Executor ' .. CFG.execMain)

  -- 4. Cues de la séquence main (mêmes commandes que la macro d'origine)
  C("Select Executor " .. CFG.execMain)
  C('Store Cue 0.5 "Mise" /NoConfirmation')
  C('Store Cue 0.6 "Select Timecode" Property "TrigType" "Follow" /NoConfirmation')
  C('Store Cue 0.7 "Go Timecode" Property "TrigType" "Follow" /NoConfirmation')
  C("Store Cue 1 Thru " .. v.cues .. " /NoConfirmation")
  C("Store Cue " .. cueBO .. ' "Black Out" /NoConfirmation')
  C("Store Cue " .. cueOffTC .. ' "Off Timecode" Property "TrigType" "Follow" /NoConfirmation')
  C('Assign Appearance "' .. appName("tc") .. '" At Cue 0.6 + 0.7 + ' .. cueOffTC)
  C('Assign Appearance "' .. appName("bo") .. '" At Cue ' .. cueBO)

  -- 5. Timecode + commandes des cues TC (par le nom, entre guillemets)
  if v.tcOn then
    C("Store Timecode " .. v.tcNo .. " /Overwrite")
    C("Label Timecode " .. v.tcNo .. " " .. tcName)
    setCueCommand(v.seq, "Select Timecode", "Select Timecode " .. tcName, warnings)
    setCueCommand(v.seq, "Go Timecode",     "Go+ Timecode " .. tcName,    warnings)
    setCueCommand(v.seq, "Off Timecode",    "Off Timecode " .. tcName,    warnings)
  end

  -- 6. Macro de rappel
  buildSongMacro(v, warnings)

end

local function create(v)
  local warnings = {}
  cmdErrors = {}
  -- Toute la création dans une seule liste Oops : un Oops annule la song entière
  local okU, u = pcall(CreateUndo, "Song Creator " .. v.name)
  undo = okU and u or nil
  local ok, err = pcall(createBody, v, warnings)
  if undo then pcall(CloseUndo, undo) end
  undo = nil
  for _, e in ipairs(cmdErrors) do
    warnings[#warnings + 1] = "Commande refusee : " .. e
  end
  for _, r in ipairs(missingAppearances(v)) do
    warnings[#warnings + 1] = r.label .. ' : apparence "' .. appName(r.key) .. '" absente du show, pas de couleur'
  end
  if not ok then error(err, 0) end
  return warnings
end

-- ---------------------------------------------------------------------------
--  Fenêtre de setup v0.5 (écran 1). Recettes reprises de GUI REPLACE V15 de Jo,
--  validé sur console : DialogFrame pour le cadre et le fond, marges autour de
--  chaque élément, libellés sur fond transparent à gauche des champs, bouton
--  principal dans la couleur « Please » de MA. Icônes à gauche du texte
--  (IconAlignmentH, vérifié sur console en 0.4.1).
-- ---------------------------------------------------------------------------
local UI = {
  W = 1300, H = 760,             -- taille de départ (au plus 95 % de l'écran)
  title = 60, foot = 80,         -- barre de titre, barre de boutons
  modesW = 180, recapW = 430,    -- colonne des modes, panneau de droite
  row = 54, sect = 38, gap = 14, -- ligne de champ, titre de section, espace
  labelW = 190, label2W = 170, numW = 120, pickW = 56,
  fontValue = "Regular24", fontLabel = "Regular18", fontButton = "Regular20",
  fontSection = "Regular20", fontSmall = "Regular14",
}
local PANEL = 10   -- marge autour des panneaux
local RECAP_ROWS = 9   -- cases du récap « Ce qui sera créé »

-- marges autour d'un champ ou d'un bouton : c'est ce qui sépare les cases
local function itemMargin() return { left = 6, right = 0, top = 5, bottom = 5 } end
local function pad(l, r, t, b) return { left = l, right = r, top = t, bottom = b } end

-- Couleurs du thème MA (comme GUI REPLACE V15), noms en secours
local COL = { transparent = "Global.Transparent", back = "Button.Background",
              please = "Button.BackgroundPlease" }
local function loadColors()
  pcall(function()
    local g = Root().ColorTheme.ColorGroups
    COL.transparent = g.Global.Transparent or COL.transparent
    COL.back = g.Button.Background or COL.back
    COL.please = g.Button.BackgroundPlease or COL.please
  end)
end

local ui = {}
signalTable.SC_Action = function(caller) ui.action = caller.SignalValue end

local FIELD_ORDER = { "name", "page", "seq", "macro", "tcNo", "bpm", "extras", "cues" }
local SLOTS = {
  { key = "page",  pool = "Pages",     label = "Page" },
  { key = "seq",   pool = "Sequences", label = "Séquence main" },
  { key = "macro", pool = "Macros",    label = "Macro de rappel" },
  { key = "tcNo",  pool = "Timecodes", label = "Timecode" },
}

-- Réglage répété à chaque rafraîchissement : pas de message s'il est refusé.
local function quiet(obj, k, v) pcall(function() obj[k] = v end) end

local function grid(parent, anchors, cols, rows)
  local g = parent:Append("UILayoutGrid")
  g.Columns, g.Rows = cols, rows
  if anchors then g.Anchors = anchors end
  return g
end
local function fixRow(g, i, size) g[1][i].SizePolicy = "Fixed"; g[1][i].Size = tostring(size) end
local function fixCol(g, i, size) g[2][i].SizePolicy = "Fixed"; g[2][i].Size = tostring(size) end

-- Texte posé sur le fond de la fenêtre (pas de case grise)
local function label(parent, anchors, text, props)
  local t = parent:Append("UIObject")
  t.Anchors = anchors
  t.Text = text
  opt(t, { Font = UI.fontLabel, HasHover = "No", TextalignmentH = "Left",
           Padding = pad(6, 4, 0, 0), TextColor = "Global.Text", BackColor = COL.transparent })
  if props then opt(t, props) end
  return t
end

local function section(parent, anchors, text)
  return label(parent, anchors, text, { Font = UI.fontSection, TextColor = "Global.LabelText",
                                        TextalignmentV = "Bottom", Padding = pad(6, 4, 0, 6) })
end

local function field(parent, anchors, value, numeric)
  local e = parent:Append("LineEdit")
  e.Anchors = anchors
  e.Content = tostring(value or "")
  opt(e, { Font = UI.fontValue, TextalignmentH = "Left", Margin = itemMargin(),
           VkPluginName = numeric and "TextInputNumOnly" or "TextInput",
           MaxTextLength = numeric and 5 or 60 })
  if numeric then opt(e, { Filter = "0123456789" }) end
  return e
end

local function button(parent, anchors, text, value, icon)
  local b = parent:Append("Button")
  b.Anchors = anchors
  b.Text = text
  opt(b, { Font = UI.fontButton, HasHover = "Yes", Margin = itemMargin() })
  if icon then
    -- icône à gauche du texte ; si MA ne sait pas la décaler, pas d'icône
    -- (centrée, elle se poserait sur le texte, vu en 0.4.0)
    local ok = pcall(function() b.Icon = icon; b.IconAlignmentH = "Left" end)
    local got
    if ok then pcall(function() got = tostring(b.IconAlignmentH) end) end
    if got ~= "Left" then
      pcall(function() b.Icon = "" end)
      Printf("[SongCreator] icone '" .. icon .. "' retiree (IconAlignmentH refuse)")
    else
      opt(b, { Padding = pad(20, 10, 0, 0) })
    end
  end
  if value then
    b.PluginComponent = myHandle
    b.Clicked = "SC_Action"
    b.SignalValue = value
  end
  return b
end

-- Ligne « libellé | contrôles » ; widths : largeur fixe de chaque colonne, false = étirée
local function line(parent, r, widths)
  local g = grid(parent, cell(0, r), #widths, 1)
  for i, wd in ipairs(widths) do
    if wd then fixCol(g, i, wd) else g[2][i].SizePolicy = "Stretch" end
  end
  return g
end

-- ---------------------------------------------------------------------------
--  Liste d'un pool avec barre de défilement (v0.6.2)
--  Recette ScrollBox + ScrollBarV reprise de BakaCowpoke (Tags UI Helper,
--  CC0) : BaseInput, DialogFrame à 2 colonnes, ScrollBox nommée, barre dont
--  ScrollTarget est le chemin "../nom" de la ScrollBox, cases posées en X/Y.
--  Pas de Popup ni de ScrollableItemList : la liste de la v0.6.0 faite avec
--  eux plantait MA dès l'ouverture.
--  Tous les numéros du pool sont proposés comme dans la fenêtre du pool :
--  objets existants (couleur de leur apparence) et numéros libres.
-- ---------------------------------------------------------------------------
local PICK = { W = 1100, H = 860, title = 50, foot = 46,
               cellW = 210, cellH = 48, gap = 6,
               after = 30,        -- numéros libres proposés après le dernier objet
               maxCells = 1000 }  -- au-delà, seulement les objets et quelques trous
local POOL_KIND = {
  Pages     = { kind = "Page",     icon = "object_pages" },
  Sequences = { kind = "Sequence", icon = "object_sequence" },
  Macros    = { kind = "Macro",    icon = "object_macro" },
  Timecodes = { kind = "Timecode", icon = "object_timecode" },
}

-- Numéros affichés dans la liste
local function pickNumbers(used, maxNo)
  local nos, last = {}, maxNo + PICK.after
  if last <= PICK.maxCells then
    for n = 1, last do nos[#nos + 1] = n end
    return nos
  end
  -- très gros pool : tous les objets, des trous tant qu'il reste de la place, puis la suite
  local count = 0
  for _ in pairs(used) do count = count + 1 end
  local room = PICK.maxCells - count - PICK.after
  for n = 1, maxNo do
    if used[n] then
      nos[#nos + 1] = n
    elseif room > 0 then
      nos[#nos + 1] = n
      room = room - 1
    end
  end
  for n = maxNo + 1, last do nos[#nos + 1] = n end
  return nos
end

-- Couleur de l'apparence d'un objet : la propriété Color de l'apparence
-- (« 1.0,1.0,1.0,1.0 » dans l'export xml de Jo), valeurs 0..1 ou 0..255.
local function parseColor(raw)
  local t = {}
  if type(raw) == "table" then
    t = { tonumber(raw.r or raw[1]), tonumber(raw.g or raw[2]), tonumber(raw.b or raw[3]),
          tonumber(raw.a or raw[4]) }
  else
    for x in tostring(raw):gmatch("[%d%.]+") do t[#t + 1] = tonumber(x) end
  end
  if not (t[1] and t[2] and t[3]) then return nil end
  local a = t[4] or 1
  local scale = (math.max(t[1], t[2], t[3], a) <= 1) and 255 or 1
  local function c(x) return math.max(0, math.min(255, math.floor(x * scale + 0.5))) end
  return c(t[1]), c(t[2]), c(t[3]), c(a)
end

local colorLogged = false
local function appearanceColor(obj)
  local app, raw
  pcall(function() app = obj.appearance end)
  if not app then return nil end
  pcall(function() raw = app.Color end)
  if raw == nil then pcall(function() raw = app:Get("Color") end) end
  if raw == nil then return nil end
  local r, g, b, a = parseColor(raw)
  if not colorLogged then
    colorLogged = true
    local nm = ""
    pcall(function() nm = tostring(app.name) end)
    Printf("[SongCreator] apparence '" .. nm .. "' : Color = " .. tostring(raw)
           .. " -> " .. tostring(r) .. "," .. tostring(g) .. "," .. tostring(b) .. "," .. tostring(a))
  end
  return r, g, b, a
end

-- Les cases prennent la couleur de l'apparence par une couleur ajoutée au
-- thème MA (Global.SongCreator_rrggbbaa, comme la couleur ajoutée dans Tags
-- UI Helper). Elles sont retirées à la fin du plugin.
local THEME_PREFIX = "SongCreator_"
local madeColors = {}
local function themeColor(hex)
  local key = THEME_PREFIX .. hex
  if madeColors[key] ~= nil then return madeColors[key] or nil end
  local c
  local ok = pcall(function()
    local glob = Root().ColorTheme.ColorGroups.Global
    for _, x in ipairs(glob:Children()) do
      if x.name == key then c = x end
    end
    if not c then
      c = glob:Acquire()
      c:Set("name", key)
      c:Set("rgba", hex)
    end
  end)
  madeColors[key] = (ok and c) or false
  return madeColors[key] or nil
end

local function removeThemeColors()
  local removed = 0
  pcall(function()
    local glob = Root().ColorTheme.ColorGroups.Global
    for i = glob:Count(), 1, -1 do
      local x = glob:Ptr(i)
      local nm = x and tostring(x.name or "") or ""
      if nm:sub(1, #THEME_PREFIX) == THEME_PREFIX then
        glob:Delete(i)
        removed = removed + 1
      end
    end
  end)
  madeColors = {}
  if removed > 0 then Printf("[SongCreator] " .. removed .. " couleur(s) de liste retiree(s) du theme") end
end

local pickState = {}
signalTable.SC_PickCell = function(caller) pickState.value = caller.SignalValue end

local function pickWithScroll(poolName, current, block)
  loadColors()
  local used, maxNo, objs = readPool(poolName)
  local nos = pickNumbers(used, maxNo)
  local info = POOL_KIND[poolName] or { kind = poolName, icon = "object_plugin1" }
  local display, dispW, dispH = pickDisplay()
  local overlay = display.ScreenOverlay
  local W = math.min(PICK.W, math.floor(dispW * 0.9))
  local H = math.min(PICK.H, math.floor(dispH * 0.85))
  local cols = math.max(1, math.floor((W - 60) / (PICK.cellW + PICK.gap)))
  local base, nObj, nColor = nil, 0, 0
  local paint = {}   -- cases à colorier, après le premier affichage de la liste

  local okBuild, errBuild = pcall(function()
    base = overlay:Append("BaseInput")
    base.Name = "SongCreatorPick"
    base.W, base.H = W, H
    base.Columns, base.Rows = 1, 3
    fixRow(base, 1, PICK.title)
    base[1][2].SizePolicy = "Stretch"
    fixRow(base, 3, PICK.foot)
    opt(base, { AlignmentH = "Center", AlignmentV = "Center", AutoClose = "No", CloseOnEscape = "Yes" })

    local tb = base:Append("TitleBar")
    tb.Columns, tb.Rows = 2, 1
    tb.Anchors = cell(0, 0)
    fixCol(tb, 2, 50)
    opt(tb, { Texture = "corner2" })
    local tt = tb:Append("TitleButton")
    tt.Text = "Select " .. info.kind
    tt.Anchors = cell(0, 0)
    opt(tt, { Texture = "corner1", Icon = info.icon, Font = UI.fontButton })
    local close = tb:Append("CloseButton")
    close.Anchors = cell(1, 0)
    opt(close, { Texture = "corner2" })

    -- cadre à 2 colonnes : la liste, puis la barre de défilement
    local frame = base:Append("DialogFrame")
    frame.H, frame.W, frame.Columns = "98%", "100%", 2
    frame[2][2].SizePolicy = "Content"
    frame.Anchors = cell(0, 1)

    local box = frame:Append("ScrollBox")
    box.Name = "SongCreatorPickBox"

    local bar = frame:Append("ScrollBarV")
    bar.ScrollTarget = "../SongCreatorPickBox"
    bar.Anchors = "1,0"

    for i, n in ipairs(nos) do
      local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
      local b = box:Append("Button")
      b.Anchors = "0,0"
      b.W, b.H = PICK.cellW, PICK.cellH
      b.X = 5 + col * (PICK.cellW + PICK.gap)
      b.Y = 5 + row * (PICK.cellH + PICK.gap)
      local fits = hasRoom(used, n, block)
      if used[n] then
        nObj = nObj + 1
        local nm = used[n] ~= "" and used[n] or "?"
        b.Text = n .. "  " .. nm
        local r, g, bl, a = appearanceColor(objs[n])
        if r then paint[#paint + 1] = { b = b, r = r, g = g, bl = bl, a = a, current = (n == current) } end
      else
        -- libre : case noire (fond transparent sur le noir de la liste), comme
        -- les cases vides d'un pool ; occupé : case grise ou couleur de l'apparence
        b.Text = n .. (fits and "  - libre -" or "  - pas la place -")
        quiet(b, "BackColor", COL.transparent)
        quiet(b, "TextColor", "Global.LabelText")
      end
      -- quiet : un refus ne doit pas écrire une ligne par case dans le System Monitor
      quiet(b, "Font", UI.fontLabel)
      quiet(b, "TextalignmentH", "Left")
      quiet(b, "Padding", pad(8, 4, 0, 0))
      quiet(b, "HasHover", "Yes")
      if not used[n] and not fits then
        -- pas la place pour la séquence et ses extras : grisé
        quiet(b, "Enabled", "No")
      else
        b.PluginComponent = myHandle
        b.Clicked = "SC_PickCell"
        b.SignalValue = tostring(n)
      end
      if n == current then quiet(b, "TextColor", "Global.Selected") end
    end

    local txt = "Noir : libre.   Gris ou couleur : occupé."
    if block > 1 then
      txt = txt .. "   « pas la place » : la séquence et ses " .. (block - 1) .. " extras ne tiennent pas."
    end
    txt = txt .. "   " .. nObj .. " objets" .. (current and (", choix actuel : " .. current) or "") .. "."
    label(base, cell(0, 2), txt, { Font = UI.fontSmall, TextColor = "Global.LabelText",
                                   Padding = pad(14, 8, 0, 0) })
  end)
  if not okBuild then
    if base then closeWindow(overlay, base, true) end
    return false, errBuild
  end
  Printf("[SongCreator] liste " .. poolName .. " affichee : " .. #nos .. " cases, " .. nObj .. " objets")

  -- Couleurs des apparences posées une fois la liste affichée : si MA
  -- n'aimait pas ces couleurs, on verrait la liste avant le problème.
  coroutine.yield(0.1)
  if #paint > 0 and IsObjectValid(base) then
    pcall(function()
      for _, p in ipairs(paint) do
        local back = themeColor(string.format("%02x%02x%02x%02x", p.r, p.g, p.bl, p.a))
        if back then
          nColor = nColor + 1
          quiet(p.b, "BackColor", back)
          -- texte foncé sur une apparence claire (le choix actuel reste en jaune)
          if not p.current and (0.299 * p.r + 0.587 * p.g + 0.114 * p.bl) > 150 and p.a > 128 then
            local dark = themeColor("000000ff")
            if dark then quiet(p.b, "TextColor", dark) end
          end
        end
      end
    end)
    Printf("[SongCreator] liste " .. poolName .. " : " .. nColor .. " cases en couleur d'apparence")
  end

  -- attente du choix ; la croix ou Échap ferment sans rien changer
  pickState.value = nil
  local chosen
  while IsObjectValid(base) do
    coroutine.yield(0.05)
    if pickState.value then
      chosen = tonumber(pickState.value)
      break
    end
  end
  closeWindow(overlay, base, true)
  return true, chosen
end

-- Choix d'un numéro dans un pool : la liste avec défilement, ou la liste
-- native de MA si cette version refuse de construire la première.
local function pickFromPool(poolName, title, current, block, caller)
  local ok, res = pickWithScroll(poolName, current, block)
  if ok then return res end
  Printf("[SongCreator] liste avec defilement indisponible (" .. tostring(res) .. "), liste MA")
  return pickWithPopupInput(poolName, title, current, block, caller)
end

local function readFields(w)
  local raw = w.fields.name.Content or ""
  local v = { rawName = raw, name = cleanName(raw), tcOn = w.tcOn }
  for _, k in ipairs(FIELD_ORDER) do
    if k ~= "name" then v[k] = toInt(w.fields[k].Content) end
  end
  return v
end

local function signature(w)
  local t = {}
  for _, k in ipairs(FIELD_ORDER) do t[#t + 1] = tostring(w.fields[k].Content) end
  t[#t + 1] = tostring(w.tcOn)
  return table.concat(t, "|")
end

-- Panneau de droite : ce qui sera créé (lignes courtes pour tenir dans le panneau)
local function recapLines(v)
  local n = v.extras or 0
  local name = (v.name ~= "" and v.name) or "?"
  local function q(x) return x and tostring(x) or "?" end
  local c = v.cues or 0
  local t = {
    "Page " .. q(v.page) .. " « " .. name .. " »",
    "Séquence " .. q(v.seq) .. " -> Exec " .. CFG.execMain .. " (" .. appName("main") .. ")",
  }
  if n > 0 and v.seq then
    t[#t + 1] = "Extras " .. (v.seq + 1) .. " à " .. (v.seq + n) .. " -> Exec "
             .. CFG.execExtraFrom .. " à " .. (CFG.execExtraFrom + n - 1) .. " (" .. appName("extras") .. ")"
  else
    t[#t + 1] = "Extras : aucun"
  end
  t[#t + 1] = "Notes sur " .. (n + 1) .. " séquence" .. (n > 0 and "s" or "")
  t[#t + 1] = "Cues 0.5 Mise, 0.6 Select TC, 0.7 Go TC"
  t[#t + 1] = "Cues 1 à " .. q(v.cues) .. ", " .. (c + 1) .. " Black Out, " .. (c + 2) .. " Off TC"
  t[#t + 1] = "Timecode " .. (v.tcOn and (q(v.tcNo) .. " « " .. name .. " »") or ": non")
  t[#t + 1] = "Macro " .. q(v.macro) .. " « " .. name .. " » (7 lignes)"
  t[#t + 1] = "Speed Master " .. CFG.speedMaster .. " à " .. q(v.bpm) .. " BPM"
  return table.concat(t, "\n")
end

-- État d'un emplacement, affiché à droite du numéro : libre ou occupé (par quoi)
local function slotStatus(poolName, no, block)
  if not no then return "numéro invalide", "Global.ErrorText" end
  local p = pool(poolName)
  local first, count = nil, 0
  for n = no, no + block - 1 do
    local o = p and p[n]
    if o then
      count = count + 1
      if not first then
        local nm = ""
        pcall(function() nm = tostring(o.name or "") end)
        first = (nm ~= "") and ("« " .. nm .. " »") or ("n° " .. n)
      end
    end
  end
  if count == 0 then
    if block > 1 then return "libre (" .. no .. " à " .. (no + block - 1) .. ")", "Global.LabelText" end
    return "libre", "Global.LabelText"
  end
  if count == 1 then return "occupé : " .. first, "Global.WarningText" end
  return count .. " sur " .. block .. " occupés", "Global.WarningText"
end

-- Récap « Ce qui sera créé » : une ligne par case ; s'il y a plus de lignes
-- que de cases, la dernière case reçoit le reste.
local function setRecap(w, text)
  local lines = {}
  for l in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
  if #lines > RECAP_ROWS then
    local rest = {}
    for i = RECAP_ROWS, #lines do rest[#rest + 1] = lines[i] end
    lines[RECAP_ROWS] = table.concat(rest, "  ")
  end
  for i = 1, RECAP_ROWS do
    local row, l = w.recapRows[i], lines[i]
    if l and l ~= "" then
      row.Text = l
      quiet(row, "BackColor", COL.back)
    else
      row.Text = ""
      quiet(row, "BackColor", COL.transparent)
    end
  end
end

local function setAlert(w, text, color)
  w.alert.Text = text
  quiet(w.alert, "TextColor", color)
end

local function setTcButton(w)
  w.tcBtn.Text = w.tcOn and "Oui" or "Non"
  quiet(w.tcBtn, "TextColor", w.tcOn and "Global.Selected" or "Global.Text")
  local en = w.tcOn and "Yes" or "No"
  quiet(w.fields.tcNo, "Enabled", en)
  quiet(w.status.tcNo, "Enabled", en)
  quiet(w.pickBtn.tcNo, "Enabled", en)
end

-- Construit la fenêtre ; une erreur ici fait passer à la boîte MA de secours.
local function buildSetupWindow(v)
  loadColors()
  local display, dispW, dispH = pickDisplay()
  local overlay = display.ScreenOverlay
  local maxW, maxH = math.floor(dispW * 0.95), math.floor(dispH * 0.95)
  local W, H = math.min(UI.W, maxW), math.min(UI.H, maxH)

  local base = overlay:Append("BaseInput")
  base.Name = "SongCreatorSetup"
  base.W, base.H = W, H
  base.Columns, base.Rows = 1, 2
  fixRow(base, 1, UI.title)
  base[1][2].SizePolicy = "Stretch"
  opt(base, { MinSize = math.min(1000, W) .. "," .. math.min(640, H), MaxSize = maxW .. "," .. maxH,
              AlignmentH = "Center", AlignmentV = "Center", AutoClose = "No", CloseOnEscape = "Yes" })
  local w = { overlay = overlay, base = base, fields = {}, status = {}, pickBtn = {}, tcOn = v.tcOn }

  -- Barre de titre : on la fait glisser pour déplacer la fenêtre, croix à droite
  local tb = base:Append("TitleBar")
  tb.Columns, tb.Rows = 3, 1
  tb.Anchors = cell(0, 0)
  fixCol(tb, 2, 110)
  fixCol(tb, 3, 50)
  opt(tb, { Texture = "corner2" })
  local tbt = tb:Append("TitleButton")
  tbt.Text = "Song Creator"
  tbt.Anchors = cell(0, 0)
  opt(tbt, { Texture = "corner1", Icon = "object_plugin1", Font = UI.fontButton })
  label(tb, cell(1, 0), "v" .. VERSION, { TextalignmentH = "Right", Font = UI.fontSmall,
                                          TextColor = "Global.LabelText", Padding = pad(4, 12, 0, 0) })
  local close = tb:Append("CloseButton")
  close.Anchors = cell(2, 0)
  opt(close, { Texture = "corner2" })

  -- Cadre de dialogue MA : fond et contour de la fenêtre
  local frameClass = "DialogFrame"
  if ClassExists and not ClassExists(frameClass) then frameClass = "UILayoutGrid" end
  local frame = base:Append(frameClass)
  opt(frame, { H = "100%", W = "100%" })
  frame.Columns, frame.Rows = 1, 2
  frame.Anchors = cell(0, 1)
  frame[1][1].SizePolicy = "Stretch"
  fixRow(frame, 2, UI.foot)

  local body = grid(frame, cell(0, 0), 3, 1)
  fixCol(body, 1, UI.modesW)
  body[2][2].SizePolicy = "Stretch"
  fixCol(body, 3, UI.recapW)

  -- Colonne des modes (les autres modes viendront plus tard)
  local modes = grid(body, cell(0, 0), 1, 6)
  opt(modes, { Margin = pad(PANEL, 2, PANEL, PANEL) })
  fixRow(modes, 1, UI.sect)
  for r = 2, 5 do fixRow(modes, r, UI.row) end
  modes[1][6].SizePolicy = "Stretch"
  section(modes, cell(0, 0), "Mode")
  local bCreate = button(modes, cell(0, 1), "Créer")
  opt(bCreate, { TextColor = "Global.Selected", TextalignmentH = "Left", Padding = pad(14, 4, 0, 0) })
  for i, t in ipairs({ "Renommer", "Dupliquer", "Supprimer" }) do
    local b = button(modes, cell(0, i + 1), t)
    opt(b, { Enabled = "No", TextColor = "Global.Disabled", TextalignmentH = "Left",
             Padding = pad(14, 4, 0, 0), Font = UI.fontLabel })
  end

  -- Centre : la song, les emplacements, les réglages
  local main = grid(body, cell(1, 0), 1, 15)
  opt(main, { Margin = pad(8, 8, PANEL, PANEL) })
  local sizes = { UI.sect, UI.row, 30, UI.gap, UI.sect, UI.row, UI.row, UI.row, UI.row,
                  UI.gap, UI.sect, UI.row, UI.row, false, 30 }
  for i = 1, #sizes do
    if sizes[i] then fixRow(main, i, sizes[i]) else main[1][i].SizePolicy = "Stretch" end
  end

  section(main, cell(0, 0), "Song")
  local ln = line(main, 1, { UI.labelW, false })
  label(ln, cell(0, 0), "Nom de la song")
  w.fields.name = field(ln, cell(1, 0), v.name, false)
  local lm = line(main, 2, { UI.labelW, false })
  w.maName = label(lm, cell(1, 0), "", { Font = UI.fontSmall, TextColor = "Global.LabelText" })

  section(main, cell(0, 4), "Emplacements")
  for i, s in ipairs(SLOTS) do
    local g = line(main, 4 + i, { UI.labelW, UI.numW, false, UI.pickW })
    label(g, cell(0, 0), s.label)
    w.fields[s.key] = field(g, cell(1, 0), v[s.key], true)
    -- l'état (libre / occupé) ouvre aussi la liste
    local st = button(g, cell(2, 0), "", "pick_" .. s.key)
    opt(st, { TextalignmentH = "Left", Font = UI.fontLabel, Padding = pad(12, 6, 0, 0) })
    w.status[s.key] = st
    local b = button(g, cell(3, 0), "", "pick_" .. s.key)
    -- flèche de liste ; « ... » si l'icône n'existe pas sur cette version
    if not pcall(function() b.Icon = "triangle_down" end) then b.Text = "..." end
    w.pickBtn[s.key] = b
  end

  section(main, cell(0, 10), "Réglages")
  local r1 = line(main, 11, { UI.labelW, UI.numW, 24, UI.label2W, UI.numW, false })
  label(r1, cell(0, 0), "BPM")
  w.fields.bpm = field(r1, cell(1, 0), v.bpm, true)
  label(r1, cell(3, 0), "Extras (0 à 10)")
  w.fields.extras = field(r1, cell(4, 0), v.extras, true)
  local r2 = line(main, 12, { UI.labelW, UI.numW, 24, UI.label2W, UI.numW, false })
  label(r2, cell(0, 0), "Cues de song")
  w.fields.cues = field(r2, cell(1, 0), v.cues, true)
  label(r2, cell(3, 0), "Créer le timecode")
  w.tcBtn = button(r2, cell(4, 0), "", "tc_toggle")
  opt(w.tcBtn, { Font = UI.fontValue })

  label(main, cell(0, 14), "Exec main " .. CFG.execMain .. "   -   extras " .. CFG.execExtraFrom .. " à "
        .. (CFG.execExtraFrom + CFG.maxExtras - 1) .. "   -   pages communes " .. CFG.commonPages
        .. "   -   Speed Master " .. CFG.speedMaster,
        { TextColor = "Global.Disabled", Font = UI.fontSmall })

  -- Droite : ce qui sera créé, puis les alertes
  local rc = grid(body, cell(2, 0), 1, 4)
  opt(rc, { Margin = pad(4, PANEL, PANEL, PANEL) })
  fixRow(rc, 1, UI.sect)
  rc[1][2].SizePolicy = "Stretch"
  fixRow(rc, 3, UI.gap)
  fixRow(rc, 4, 110)
  section(rc, cell(0, 0), "Ce qui sera créé")
  -- une case par ligne, séparées comme les champs de gauche
  local rg = grid(rc, cell(0, 1), 1, RECAP_ROWS)
  w.recapRows = {}
  for i = 1, RECAP_ROWS do
    rg[1][i].SizePolicy = "Stretch"
    w.recapRows[i] = label(rg, cell(0, i - 1), "", { BackColor = COL.back, TextalignmentV = "Center",
                                                     Margin = pad(0, 0, 3, 3), Padding = pad(14, 8, 0, 0) })
  end
  w.alert = label(rc, cell(0, 3), "", { TextalignmentV = "Top", Padding = pad(6, 6, 4, 4) })

  -- Barre de boutons : Créer en couleur « Please », comme le Replace de V15
  local ft = grid(frame, cell(0, 1), 4, 1)
  opt(ft, { Margin = pad(PANEL - 6, PANEL, 6, PANEL) })
  fixCol(ft, 1, UI.modesW - PANEL)
  w.createBtn = button(ft, cell(1, 0), "Créer la song", "create", "ok")
  opt(w.createBtn, { BackColor = COL.please })
  button(ft, cell(2, 0), "Valeurs par défaut", "defaults", "undo")
  button(ft, cell(3, 0), "Annuler", "cancel", "cancel")

  -- Coin de redimensionnement (bas droite)
  pcall(function()
    if ClassExists and not ClassExists("ResizeCorner") then return end
    local rcorner = base:Append("ResizeCorner")
    rcorner.Anchors = cell(0, 1)
    opt(rcorner, { AlignmentH = "Right", AlignmentV = "Bottom" })
  end)

  setTcButton(w)
  return w
end

local PICK_FIELDS = {
  pick_page  = { field = "page",  pool = "Pages",     title = "Page" },
  pick_macro = { field = "macro", pool = "Macros",    title = "Macro" },
  pick_seq   = { field = "seq",   pool = "Sequences", title = "Sequence" },
  pick_tcNo  = { field = "tcNo",  pool = "Timecodes", title = "Timecode" },
}

local function runSetupWindow(w)
  ui.action, ui.dirty = nil, true
  local armed, finished, lastSig, tick = false, false, nil, 0
  local appAsked = false   -- la liste des apparences ne s'ouvre qu'une fois

  local function setCreateText(text)
    w.createBtn.Text = text
  end

  local function refresh()
    local input = readFields(w)
    local err, busy = validate(input)
    w.maName.Text = (input.name ~= "") and ("Nom dans MA : " .. input.name) or ""
    setRecap(w, recapLines(input))
    -- état de chaque emplacement à droite du numéro, numéro en orange si occupé
    for _, s in ipairs(SLOTS) do
      local txt, color
      if s.key == "tcNo" and not input.tcOn then
        txt, color = "pas de timecode", "Global.Disabled"
      else
        local block = (s.key == "seq") and (1 + (input.extras or 0)) or 1
        txt, color = slotStatus(s.pool, input[s.key], block)
      end
      w.status[s.key].Text = txt
      quiet(w.status[s.key], "TextColor", color)
      quiet(w.fields[s.key], "TextColor", (color == "Global.WarningText") and color or "Global.Text")
    end
    if err then
      setAlert(w, err, "Global.ErrorText")
    else
      local t, color = {}, "Global.SuccessText"
      if #busy > 0 then
        t[#t + 1] = "Déjà occupé, sera écrasé : " .. table.concat(busy, ", ") .. "."
        color = "Global.WarningText"
      end
      local miss = missingAppearances(input)
      if #miss > 0 then
        local names = {}
        for _, r in ipairs(miss) do names[#names + 1] = appName(r.key) end
        t[#t + 1] = "Apparence absente du show : " .. table.concat(names, ", ")
                 .. ". Une liste s'ouvrira pour en choisir une."
        color = "Global.WarningText"
      end
      setAlert(w, (#t > 0) and table.concat(t, "\n") or "Prêt.", color)
    end
    return input, err, busy
  end

  while IsObjectValid(w.base) do
    -- rafraîchit le récap quand un champ change
    tick = tick + 1
    if not finished and (ui.dirty or tick % 4 == 0) then
      local sig = signature(w)
      if ui.dirty or sig ~= lastSig then
        lastSig, ui.dirty = sig, false
        refresh()
        if armed then armed = false; setCreateText("Créer la song") end
      end
    end

    local a = ui.action
    ui.action = nil
    if a == "cancel" then
      break
    elseif a == "tc_toggle" and not finished then
      w.tcOn = not w.tcOn
      setTcButton(w)
      ui.dirty = true
    elseif a == "defaults" and not finished then
      local d = defaultValues()
      for _, k in ipairs(FIELD_ORDER) do
        if k ~= "name" then w.fields[k].Content = tostring(d[k]) end
      end
      w.tcOn = true
      setTcButton(w)
      ui.dirty = true
    elseif a and PICK_FIELDS[a] and not finished then
      local p = PICK_FIELDS[a]
      local input = readFields(w)
      local block = (p.field == "seq") and (1 + (input.extras or 0)) or 1
      local n = pickFromPool(p.pool, p.title, input[p.field], block, w.pickBtn[p.field])
      if n and IsObjectValid(w.base) then
        w.fields[p.field].Content = tostring(n)
        ui.dirty = true
      end
    elseif a == "create" then
      local input, err, busy = refresh()
      if not err and not appAsked and #missingAppearances(input) > 0 then
        appAsked = true
        resolveAppearances(input, w.createBtn)
        if not IsObjectValid(w.base) then break end
        input, err, busy = refresh()
      end
      if err then
        setAlert(w, err, "Global.ErrorText")
      elseif #busy > 0 and not armed then
        armed = true
        setAlert(w, "Déjà occupé : " .. table.concat(busy, ", ") .. ".\nAppuie encore pour écraser.",
                 "Global.WarningText")
        setCreateText("Écraser et créer")
      else
        local ok, res = pcall(create, input)
        if not ok then
          setAlert(w, "Erreur pendant la création : " .. tostring(res), "Global.ErrorText")
        elseif #res > 0 then
          setAlert(w, 'Song « ' .. input.name .. ' » créée, avec avertissements (ci-dessus).',
                   "Global.WarningText")
          setRecap(w, "- " .. table.concat(res, "\n- "))
        else
          setAlert(w, 'Song « ' .. input.name .. ' » créée.', "Global.SuccessText")
        end
        finished = true
        setCreateText("Fermer")
        w.createBtn.SignalValue = "cancel"
      end
    end
    coroutine.yield(0.05)
  end
  closeWindow(w.overlay, w.base)
end

local function messageBoxFlow(v)
  local err

  while true do
    local action, input = askSetup(v, err)
    if not action then return end
    -- garder la saisie si on revient dans la fenêtre
    v = {
      name = input.rawName, page = input.page or v.page, bpm = input.bpm or v.bpm,
      macro = input.macro or v.macro, seq = input.seq or v.seq,
      extras = input.extras or v.extras, cues = input.cues or v.cues,
      tcNo = input.tcNo or v.tcNo, tcOn = input.tcOn,
    }
    local busy
    err = nil
    local picker = PICKERS[action]
    if picker then
      local block = (picker.field == "seq") and (1 + (v.extras or 0)) or 1
      local n = pickFromPool(picker.pool, picker.title, v[picker.field], block)
      if n then v[picker.field] = n end
    else
      err, busy = validate(input)
    end
    if action == 1 and not err then
      local choice = confirm(input, busy)
      if choice == 0 then return end
      if choice == 1 then
        resolveAppearances(input)
        local ok, res = pcall(create, input)
        local text
        if not ok then
          text = "Erreur pendant la création :\n" .. tostring(res)
        elseif #res > 0 then
          text = 'Song "' .. input.name .. '" créée, avec avertissements :\n- ' .. table.concat(res, "\n- ")
        else
          text = 'Song "' .. input.name .. '" créée.'
        end
        Box({ title = "Song Creator", message = text, commands = { { value = 1, name = "OK" } } })
        return
      end
      -- choice == 2 : on revient au setup
    end
  end
end

local function RealMain(displayHandle, argument)
  log = {}
  local v = defaultValues()
  local ok, w = pcall(buildSetupWindow, v)
  if ok then
    runSetupWindow(w)
    return
  end
  -- Fenêtre sur mesure impossible sur cette version : boîte MA de secours
  Printf("[SongCreator] fenetre sur mesure indisponible, boite MA de secours : " .. tostring(w))
  pcall(function() (pickDisplay()).ScreenOverlay:ClearUIChildren() end)
  messageBoxFlow(v)
end

-- Test banane (rien n'est affiché) : MA connaît-il l'image banane du show
-- comme icône ? La baguette de MULE creator est l'icône intégrée « wizard » ;
-- une image du show n'est utilisable en icône que si FindTexture la trouve.
local function probeBanana()
  local found = {}
  pcall(function()
    for _, img in ipairs(ShowData().MediaPools.Images:Children()) do
      local nm = tostring(img.name or "")
      if nm:lower():find("banan") then
        local file = ""
        pcall(function() file = tostring(img.FileName or "") end)
        found[#found + 1] = { nm, file }
      end
    end
  end)
  if #found == 0 then
    Printf("[SongCreator] test banane : aucune image 'banane' dans le pool Images")
    return
  end
  for _, f in ipairs(found) do
    for _, key in ipairs({ f[1], f[2], (f[2]:gsub("%.%w+$", "")) }) do
      if key ~= "" then
        local ok, tex = pcall(FindTexture, key)
        Printf("[SongCreator] test banane : FindTexture('" .. key .. "') -> "
               .. ((ok and tex) and "TROUVEE" or "absente"))
      end
    end
  end
end

-- Point d'entrée protégé : toute erreur est écrite dans le System Monitor
-- et affichée, au lieu d'un plugin qui « ne fait rien ».
local function Main(displayHandle, argument)
  local okV, ver = pcall(Version)
  Printf("[SongCreator] demarrage v" .. VERSION .. " sur grandMA3 " .. (okV and tostring(ver) or "?"))
  pcall(probeBanana)
  local ok, err = xpcall(RealMain, debug.traceback, displayHandle, argument)
  -- couleurs de liste ajoutées au thème : retirées une fois les fenêtres fermées
  if next(madeColors) then pcall(removeThemeColors) end
  if not ok then
    ErrPrintf("[SongCreator] ERREUR : " .. tostring(err))
    pcall(MessageBox, { title = "Song Creator - erreur", message = tostring(err),
                        commands = { { value = 1, name = "OK" } } })
  end
  Printf("[SongCreator] fin")
end

return Main
