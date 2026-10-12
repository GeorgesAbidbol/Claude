-- ============================================================================
--  Song Creator  -  plugin grandMA3 (cible 2.3.2.0)
--  Remplace la macro "FULL SONG CREATOR" : une fenêtre de setup, puis
--  création de la page, des séquences, des cues, du timecode, des executors
--  et de la macro de rappel de la song.
--  Depuis la 0.7 : renommer, dupliquer et supprimer une song existante.
-- ============================================================================

local pluginName    = select(1, ...)
local componentName = select(2, ...)
local signalTable   = select(3, ...)
local myHandle      = select(4, ...)

local VERSION = "0.7.2"

-- ---------------------------------------------------------------------------
--  Réglages fixes (ceux de la macro d'origine)
-- ---------------------------------------------------------------------------
local CFG = {
  execMain      = 216,            -- executor de la séquence principale
  execExtraFrom = 121,            -- 1er executor des extras
  maxExtras     = 10,             -- 121..130
  commonPages   = "101 thru 120", -- pages qui restent allumées au rappel
  commonFrom    = 101,            -- (les mêmes, pour ne pas y placer une song)
  commonTo      = 120,
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
  -- les tags ne sont plus dans DataPool (2.x) mais dans ShowData().Tags
  if name == "Tags" then
    local ok, t = pcall(function() return ShowData().Tags end)
    return ok and t or nil
  end
  local dp = DataPool()
  return dp and dp[name]
end

-- Lit le pool : used[no] = nom, maxNo = plus grand numéro occupé.
local function readPool(poolName)
  local p = pool(poolName)
  local used, maxNo, objs = {}, 0, {}
  if p then
    local okK, kids = pcall(function() return p:Children() end)
    for i, obj in ipairs(okK and type(kids) == "table" and kids or {}) do
      local no = tonumber(obj.no)
      if not no and poolName == "Tags" then no = i end
      if no then
        used[no] = obj.name or ""
        objs[no] = obj
        if no > maxNo then maxNo = no end
      end
    end
  end
  return used, maxNo, objs
end

-- Objet n° no d'un pool (les tags sont cherchés par leur numéro)
local function poolObj(poolName, no)
  if not no then return nil end
  if poolName == "Tags" then
    local _, _, objs = readPool(poolName)
    return objs[no]
  end
  local p = pool(poolName)
  return p and p[no]
end

local function exists(poolName, no)
  return poolObj(poolName, no) ~= nil
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
  [7] = { field = "tagNo", pool = "Tags",      title = "Tag" },
}


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

-- Ferme une fenêtre du plugin avec la recette de GUI REPLACE V15, validée sur
-- la console de Jo : Obj.Delete(écran, Obj.Index(fenêtre)). Vu sur console :
--  - Obj.Index compte à partir de 0 et Obj.Delete prend ce même index
--    (Delete avec un index de GetUIChild a donné « deletion of the child
--    object is prohibited » en 0.6.4) ;
--  - le contrôle par GetUIChild ajouté en 0.6.5 échouait (0.7.0 : « index 3,
--    controle false ») et faisait vider tout l'écran 1 : il n'est plus bloquant ;
--  - MA supprime la fenêtre un peu plus tard : on attend qu'elle ait disparu.
-- others = true : d'autres fenêtres du plugin restent ouvertes, on ne vide
-- jamais l'écran ; au pire la fenêtre est masquée.
local function closeWindow(overlay, base, others)
  if not IsObjectValid(base) then return end
  local idx
  pcall(function() idx = Obj.Index(base) end)
  if idx then
    pcall(function() Obj.Delete(overlay, idx) end)
    for _ = 1, 20 do
      if not IsObjectValid(base) then return end
      coroutine.yield(0.05)
    end
  end
  Printf("[SongCreator] fenetre non supprimee (index " .. tostring(idx) .. "), "
         .. (others and "masquee" or "ecran vide"))
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
  tagNo  = "N° tag",
}
local S_TC = "Créer le timecode"
local S_TAG = "Poser le tag"

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
    tagNo  = firstFree("Tags", 1),
    tagOn  = true,
  }
end

local function askSetup(v, errorText)
  local num = "0123456789"
  local msg = "Remplis le setup de la song puis valide.\n"
           .. "Les espaces du nom seront remplacés par _.\n"
           .. "Les extras sont placés juste après la séquence main.\n"
           .. "Page, Macro, Timecode, Sequence, Tag : tape le numéro ou ouvre la liste du pool."
  if errorText then msg = "/!\\ " .. errorText .. "\n\n" .. msg end

  local r = Box({
    title    = "Song Creator  v" .. VERSION,
    message  = msg,
    commands = {
      { value = 3, name = "Liste Pages..." },
      { value = 4, name = "Liste Macros..." },
      { value = 5, name = "Liste Timecodes..." },
      { value = 6, name = "Liste Sequences..." },
      { value = 7, name = "Liste Tags..." },
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
      { name = F.tagNo,  value = tostring(v.tagNo),   whiteFilter = num, vkPlugin = "NumericInput" },
    },
    states   = { { name = S_TC, state = v.tcOn }, { name = S_TAG, state = v.tagOn } },
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
    tagNo   = toInt(i[F.tagNo]),
    tagOn   = (r.states or {})[S_TAG] and true or false,
  }
end

-- Ajoute « Page 3 « nom » » à la liste si l'emplacement est occupé
local function busyAdd(busy, poolName, label, no)
  local o = poolObj(poolName, no)
  if not o then return end
  local nm = o.name and tostring(o.name) or ""
  busy[#busy + 1] = label .. " " .. no .. ((nm ~= "") and (" « " .. nm .. " »") or "")
end

-- Renvoie un texte d'erreur bloquante, plus la liste des emplacements occupés.
local function validate(v)
  if v.name == "" then return "Donne un nom à la song." end
  for _, k in ipairs({ "page", "bpm", "macro", "seq", "extras", "cues", "tcNo", "tagNo" }) do
    if not v[k] and (k ~= "tcNo" or v.tcOn) and (k ~= "tagNo" or v.tagOn) then
      return "Champ invalide : " .. F[k]
    end
  end
  if v.extras > CFG.maxExtras then return "Maximum " .. CFG.maxExtras .. " extras (executors 121 à 130)." end
  if v.cues < 1 then return "Il faut au moins 1 cue de song." end

  local busy = {}
  busyAdd(busy, "Pages", "Page", v.page)
  for s = v.seq, v.seq + v.extras do busyAdd(busy, "Sequences", "Séquence", s) end
  busyAdd(busy, "Macros", "Macro", v.macro)
  if v.tcOn then busyAdd(busy, "Timecodes", "Timecode", v.tcNo) end
  if v.tagOn then busyAdd(busy, "Tags", "Tag", v.tagNo) end
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
  t[#t + 1] = v.tagOn and ("Tag " .. v.tagNo .. ' "' .. v.name .. '"') or "Tag : non"
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

local function noteOf(o)
  local n
  pcall(function() n = o:Get("Note") end)
  if n == nil then pcall(function() n = o.note end) end
  return trim(tostring(n or ""))
end

-- Note d'un timecode ou d'une macro = nom de la song (Jo, 12/10), comme les
-- séquences : par commande, puis vérifiée et posée par Lua si besoin.
local function setNote(poolName, keyword, no, name, warnings, what)
  C("Note " .. keyword .. " " .. no .. ' "' .. name .. '"')
  local o = pool(poolName)[no]
  if o and noteOf(o) ~= name and not setChecked(o, "Note", name) then
    warnings[#warnings + 1] = "Note " .. what .. " " .. no .. " non posée"
  end
end

-- Commande dont le refus n'est pas une erreur (écrite dans le System Monitor
-- seulement), par exemple retirer un tag que l'objet n'a peut-être pas.
local function Cq(cmd)
  log[#log + 1] = cmd
  local ok, res
  if undo then ok, res = pcall(Cmd, cmd, undo) else ok, res = pcall(Cmd, cmd) end
  Printf("[SongCreator] " .. cmd .. " -> " .. tostring(ok and res or "erreur"))
end

-- ---- Tag de la song (Jo, 12/10) : un tag au nom de la song sur la page, les
-- séquences, le timecode et la macro, pour filtrer et pour d'autres plugins.
-- Les tags sont dans ShowData().Tags (plus dans DataPool), numérotés comme un
-- pool ; on vise toujours le tag par son numéro (deux tags peuvent avoir le
-- même nom). Commandes comme Tags UI Helper (BakaCowpoke, CC0) :
-- Assign Tag ... At Sequence 5, Assign Off Tag ... At ...

-- « Page 3 », « Sequence 101 Thru 104 », « Timecode 7 », « Macro 413 »
local function songObjects(page, seq, extras, tc, macro)
  local t = { "Page " .. page,
              "Sequence " .. seq .. ((extras > 0) and (" Thru " .. (seq + extras)) or "") }
  if tc then t[#t + 1] = "Timecode " .. tc end
  if macro then t[#t + 1] = "Macro " .. macro end
  return t
end

-- Crée le tag n° no au nom de la song. Un tag déjà à ce numéro est d'abord
-- supprimé (écrasement confirmé par un second appui, comme les autres pools).
local function storeTag(no, name, warnings)
  if exists("Tags", no) then C("Delete Tag " .. no .. " /NoConfirmation") end
  local before = #cmdErrors
  C("Store Tag " .. no)
  C("Label Tag " .. no .. ' "' .. name .. '"')
  if #cmdErrors > before then
    warnings[#warnings + 1] = "Tag " .. no .. " non créé, objets non taggés"
    return false
  end
  return true
end

-- off = true : retire le tag (refus seulement noté : l'objet peut ne pas l'avoir)
local function tagObjects(no, objs, off)
  for _, o in ipairs(objs) do
    if off then Cq("Assign Off Tag " .. no .. " At " .. o)
    else C("Assign Tag " .. no .. " At " .. o) end
  end
end

-- Noms des tags d'un objet, nil si MA ne les donne pas à lire. Format pas
-- encore vu sur console : texte (« A B » ou « A, B ») ou objet avec enfants.
local tagFormatLogged = false
local function tagsOf(o)
  local v
  pcall(function() v = o:Get("Tags") end)
  if v == nil then pcall(function() v = o.tags end) end
  if not tagFormatLogged then
    tagFormatLogged = true
    if v == nil then
      Printf("[SongCreator] tags des objets illisibles : pas de verification par le tag")
    else
      Printf("[SongCreator] tags lus sur " .. tostring(o.name) .. " : " .. type(v) .. " « " .. tostring(v) .. " »")
    end
  end
  if v == nil then return nil end
  local names = {}
  if type(v) == "userdata" then
    local okK, kids = pcall(function() return v:Children() end)
    if not (okK and type(kids) == "table") then return nil end
    for _, k in ipairs(kids) do
      local nm
      pcall(function() nm = k.name end)
      if nm then names[tostring(nm)] = true end
    end
  else
    for tok in tostring(v):gmatch("[^%s,;]+") do names[(tok:gsub(":%d+$", ""))] = true end
  end
  return names
end

-- true / false, ou nil si on ne peut pas savoir
local function hasTag(o, name)
  local t = tagsOf(o)
  if not t then return nil end
  return t[name] == true
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
  setNote("Macros", "Macro", v.macro, v.name, warnings, "de la macro")

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

-- Executors de la song sur la page en cours : main sur 216, extras sur 121...
-- (aussi pour la page d'une song dupliquée)
local function assignSongExecs(seq, extras)
  local lastExtra = seq + extras
  C("Assign Sequence " .. seq .. " At Executor " .. CFG.execMain)
  if extras > 0 then
    C("Assign Sequence " .. (seq + 1) .. " Thru " .. lastExtra
      .. " At Executor " .. CFG.execExtraFrom .. " Thru " .. (CFG.execExtraFrom + extras - 1))
    C('Assign Configuration "' .. CFG.confExtras .. '" At Executor '
      .. CFG.execExtraFrom .. " Thru " .. (CFG.execExtraFrom + extras - 1))
    C('Assign Appearance "' .. appName("extras") .. '" At Executor '
      .. CFG.execExtraFrom .. " Thru " .. (CFG.execExtraFrom + extras - 1))
  end
  C('Assign Configuration "' .. CFG.confMain .. '" At Executor ' .. CFG.execMain)
  C('Assign Appearance "' .. appName("main") .. '" At Executor ' .. CFG.execMain)
end

local function createBody(v, warnings)
  local lastExtra = v.seq + v.extras
  local cueBO, cueOffTC = v.cues + 1, v.cues + 2
  local tcName = '"' .. v.name .. '"'

  -- 1. Page
  C("Store Page " .. v.page .. " /Overwrite")
  C("Page " .. v.page)
  C('Label Page ' .. v.page .. ' "' .. v.name .. '"')
  setNote("Pages", "Page", v.page, v.name, warnings, "de la page")

  -- 2. Séquences
  C("Store Sequence " .. v.seq .. " Thru " .. lastExtra .. " /Overwrite")
  C('Label Sequence ' .. v.seq .. ' "' .. v.name .. '"')
  C('Note Sequence ' .. v.seq .. ' "' .. v.name .. '"')
  if v.extras > 0 then
    C('Note Sequence ' .. (v.seq + 1) .. " Thru " .. lastExtra .. ' "' .. v.name .. '"')
  end

  -- 3. Executors
  assignSongExecs(v.seq, v.extras)

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
    setNote("Timecodes", "Timecode", v.tcNo, v.name, warnings, "du timecode")
    setCueCommand(v.seq, "Select Timecode", "Select Timecode " .. tcName, warnings)
    setCueCommand(v.seq, "Go Timecode",     "Go+ Timecode " .. tcName,    warnings)
    setCueCommand(v.seq, "Off Timecode",    "Off Timecode " .. tcName,    warnings)
  end

  -- 6. Macro de rappel
  buildSongMacro(v, warnings)

  -- 7. Tag de la song sur tous ses objets (réglage « Poser le tag »)
  if v.tagOn and storeTag(v.tagNo, v.name, warnings) then
    tagObjects(v.tagNo, songObjects(v.page, v.seq, v.extras, v.tcOn and v.tcNo or nil, v.macro))
  end

end

-- Toute une opération dans une seule liste Oops : un Oops l'annule en entier
-- (sauf ce qui est écrit par Lua sur des objets qui existaient avant :
-- commandes des cues et lignes de macro d'une song renommée).
local function runUndo(title, body, ...)
  local warnings = {}
  cmdErrors = {}
  local okU, u = pcall(CreateUndo, title)
  undo = okU and u or nil
  local ok, res = pcall(body, warnings, ...)
  if undo then pcall(CloseUndo, undo) end
  undo = nil
  for _, e in ipairs(cmdErrors) do
    warnings[#warnings + 1] = "Commande refusee : " .. e
  end
  if not ok then error(res, 0) end
  return warnings, res
end

local function create(v)
  local warnings = runUndo("Song Creator " .. v.name, function(wn) createBody(v, wn) end)
  for _, r in ipairs(missingAppearances(v)) do
    warnings[#warnings + 1] = r.label .. ' : apparence "' .. appName(r.key) .. '" absente du show, pas de couleur'
  end
  return warnings
end

-- ---------------------------------------------------------------------------
--  Songs existantes (0.7) : retrouver, renommer, dupliquer, supprimer
--  Une song = une page et une séquence qui portent le même nom (ce que font
--  le plugin et la macro d'origine). Extras = séquences qui suivent la main
--  avec ce nom en note. Timecode et macro de rappel = ceux du même nom.
-- ---------------------------------------------------------------------------
-- nom -> plus petit numéro qui le porte
local function numbersByName(poolName)
  local used, _, objs = readPool(poolName)
  local byName = {}
  for no, nm in pairs(used) do
    nm = tostring(nm)
    if nm ~= "" and (not byName[nm] or no < byName[nm]) then byName[nm] = no end
  end
  return byName, used, objs
end

local function findSongs()
  local pages = readPool("Pages")
  local seqByName, _, seqObjs = numbersByName("Sequences")
  local tcByName = numbersByName("Timecodes")
  local macroByName = numbersByName("Macros")
  local tagByName = numbersByName("Tags")
  local nos = {}
  for no in pairs(pages) do nos[#nos + 1] = no end
  table.sort(nos)
  local songs = {}
  for _, p in ipairs(nos) do
    local name = tostring(pages[p] or "")
    local s = (name ~= "") and seqByName[name]
    if s then
      -- extras : séquences qui suivent avec ce nom en note, ou qui portent le tag
      local k = 0
      while k < CFG.maxExtras and seqObjs[s + k + 1] do
        local o = seqObjs[s + k + 1]
        if noteOf(o) ~= name and hasTag(o, name) ~= true then break end
        k = k + 1
      end
      songs[#songs + 1] = { name = name, page = p, seq = s, extras = k, seqObj = seqObjs[s],
                            tc = tcByName[name], macro = macroByName[name], tag = tagByName[name] }
    end
  end
  return songs
end

-- La même song relue dans le show (page et nom inchangés), nil si elle n'existe plus
local function resolveSong(song)
  if not song then return nil end
  for _, s in ipairs(findSongs()) do
    if s.page == song.page and s.name == song.name then return s end
  end
  return nil
end

-- Vérification par le tag (Jo, 12/10) : objets des pools qui portent le tag
-- de la song. outside = ceux qui ne font pas partie de la song (page,
-- séquences main + extras, timecode, macro) ; readable = false si MA ne
-- donne pas les tags des objets à lire.
local MEMBER_POOLS = { { "Pages", "Page" }, { "Sequences", "Séquence" },
                       { "Timecodes", "Timecode" }, { "Macros", "Macro" } }
local function tagMembers(s)
  local r = { count = 0, outside = {}, readable = false }
  if not s.tag then return r end
  local mine = { Pages = { [s.page] = true }, Sequences = {}, Timecodes = {}, Macros = {} }
  for n = s.seq, s.seq + s.extras do mine.Sequences[n] = true end
  if s.tc then mine.Timecodes[s.tc] = true end
  if s.macro then mine.Macros[s.macro] = true end
  for _, P in ipairs(MEMBER_POOLS) do
    local _, _, objs = readPool(P[1])
    local nos = {}
    for no in pairs(objs) do nos[#nos + 1] = no end
    table.sort(nos)
    for _, no in ipairs(nos) do
      local has = hasTag(objs[no], s.name)
      if has ~= nil then r.readable = true end
      if has then
        r.count = r.count + 1
        if not mine[P[1]][no] then r.outside[#r.outside + 1] = P[2] .. " " .. no end
      end
    end
  end
  return r
end

-- Objets qui portent déjà ce nom (Page 3, Séquence 101...)
local NAMED_POOLS = { { "Pages", "Page" }, { "Sequences", "Séquence" },
                      { "Timecodes", "Timecode" }, { "Macros", "Macro" }, { "Tags", "Tag" } }
local function nameUsers(name)
  local t = {}
  for _, p in ipairs(NAMED_POOLS) do
    local used = readPool(p[1])
    local nos = {}
    for no, nm in pairs(used) do
      if tostring(nm) == name then nos[#nos + 1] = no end
    end
    table.sort(nos)
    for _, no in ipairs(nos) do t[#t + 1] = p[2] .. " " .. no end
  end
  return t
end

-- « 216 », « 216 et 121 », « 216 et 121 à 124 »
local function execText(extras, sep)
  local first, last = CFG.execExtraFrom, CFG.execExtraFrom + extras - 1
  if extras <= 0 then return tostring(CFG.execMain) end
  return CFG.execMain .. (sep or " et ") .. first .. ((last > first) and (" à " .. last) or "")
end

local function seqRange(seq, extras)
  return (extras > 0) and (seq .. " Thru " .. (seq + extras)) or tostring(seq)
end

-- Remplacement de texte simple (sans motif Lua), renvoie aussi le nombre
local function replacePlain(s, a, b)
  local out, i, n = {}, 1, 0
  while true do
    local j, k = s:find(a, i, true)
    if not j then break end
    out[#out + 1] = s:sub(i, j - 1)
    out[#out + 1] = b
    i, n = k + 1, n + 1
  end
  out[#out + 1] = s:sub(i)
  return table.concat(out), n
end

-- Notes des séquences : par commande (comme à la création), puis vérifiées
-- et posées par Lua si la note n'est pas exactement le nom.
local function setNotes(seq, extras, name, warnings)
  C('Note Sequence ' .. seqRange(seq, extras) .. ' "' .. name .. '"')
  for n = seq, seq + extras do
    local o = pool("Sequences")[n]
    if o and noteOf(o) ~= name and not setChecked(o, "Note", name) then
      warnings[#warnings + 1] = "Note de la séquence " .. n .. " non posée"
    end
  end
end

-- Objets qui portent une commande : parts des cues (la part 0 sur 2.3.2),
-- ou la cue elle-même si ses parts n'en ont pas.
local function cueCommandHolders(seq, extras)
  local list = {}
  for n = seq, seq + extras do
    local sq = pool("Sequences")[n]
    local okC, cues = pcall(function() return sq:Children() end)
    for _, cue in ipairs(okC and type(cues) == "table" and cues or {}) do
      local found = false
      local okP, parts = pcall(function() return cue:Children() end)
      for _, part in ipairs(okP and type(parts) == "table" and parts or {}) do
        if propName(part, "Command") ~= false then list[#list + 1] = part; found = true end
      end
      if not found and propName(cue, "Command") ~= false then list[#list + 1] = cue end
    end
  end
  return list
end

local function macroLines(macroNo)
  local m = macroNo and pool("Macros")[macroNo]
  local okC, lines = pcall(function() return m:Children() end)
  return okC and type(lines) == "table" and lines or {}
end

-- Remplace "ancien nom" (entre guillemets) par "nouveau nom" dans les
-- commandes. dry = true : compte seulement. Renvoie le nombre de commandes.
local function renameInCommands(holders, old, new, warnings, dry)
  local oldQ, newQ = '"' .. old .. '"', '"' .. new .. '"'
  local count = 0
  for _, o in ipairs(holders) do
    local okG, cmd = pcall(function() return o:Get("Command") end)
    cmd = (okG and cmd ~= nil) and tostring(cmd) or ""
    if cmd:find(oldQ, 1, true) then
      count = count + 1
      if not dry then
        local newCmd = trim((replacePlain(cmd, oldQ, newQ)))
        if setChecked(o, "Command", newCmd) then
          log[#log + 1] = "(lua) " .. cmd .. "  ->  " .. newCmd
        else
          warnings[#warnings + 1] = "Commande non modifiée : " .. cmd
        end
      end
    end
  end
  return count
end

local function currentSongVar()
  local ok, v = pcall(function() return GetVar(GlobalVars(), "currentSong") end)
  return ok and v ~= nil and tostring(v) or nil
end

-- ---- Renommer ----
local function renameBody(warnings, s, new)
  local q = '"' .. new .. '"'
  C("Label Page " .. s.page .. " " .. q)
  setNote("Pages", "Page", s.page, new, warnings, "de la page")
  C("Label Sequence " .. s.seq .. " " .. q)
  setNotes(s.seq, s.extras, new, warnings)
  if s.tc then
    C("Label Timecode " .. s.tc .. " " .. q)
    setNote("Timecodes", "Timecode", s.tc, new, warnings, "du timecode")
  end
  if s.macro then
    C("Label Macro " .. s.macro .. " " .. q)
    setNote("Macros", "Macro", s.macro, new, warnings, "de la macro")
  end
  local nCues = renameInCommands(cueCommandHolders(s.seq, s.extras), s.name, new, warnings)
  local nMacro = renameInCommands(macroLines(s.macro), s.name, new, warnings)
  if currentSongVar() == s.name then C("SetGlobalVariable currentSong " .. q) end
  -- tag de la song renommé : les objets qui le portent le gardent
  if s.tag then C("Label Tag " .. s.tag .. " " .. q) end
  return { "Page " .. s.page .. ", séquence " .. s.seq .. " et notes : « " .. new .. " »",
           s.tag and ("Tag " .. s.tag .. " : « " .. new .. " »") or "Pas de tag",
           s.tc and ("Timecode " .. s.tc .. " : « " .. new .. " »") or "Pas de timecode",
           s.macro and ("Macro " .. s.macro .. " : « " .. new .. " »") or "Pas de macro de rappel",
           nCues .. " commande(s) de cue et " .. nMacro .. " ligne(s) de macro modifiée(s)" }
end

local function renameSong(s, new)
  return runUndo("Song Creator renommer " .. s.name, renameBody, s, new)
end

-- ---- Supprimer ----
local function deleteBody(warnings, s)
  if s.macro then C("Delete Macro " .. s.macro .. " /NoConfirmation") end
  if s.tc then C("Delete Timecode " .. s.tc .. " /NoConfirmation") end
  C("Delete Page " .. s.page .. " /NoConfirmation")
  C("Delete Sequence " .. seqRange(s.seq, s.extras) .. " /NoConfirmation")
  -- tag : supprimé, sauf s'il reste porté par des objets hors de la song
  local tag, kept = s.tag, nil
  if tag then
    local m = tagMembers(s)
    if #m.outside > 0 then
      kept = m.outside
      warnings[#warnings + 1] = "Tag " .. tag .. " gardé : encore porté par " .. table.concat(kept, ", ")
    else
      C("Delete Tag " .. tag .. " /NoConfirmation")
    end
  end
  local left = {}
  if exists("Pages", s.page) then left[#left + 1] = "Page " .. s.page end
  for n = s.seq, s.seq + s.extras do
    if exists("Sequences", n) then left[#left + 1] = "Séquence " .. n end
  end
  if s.tc and exists("Timecodes", s.tc) then left[#left + 1] = "Timecode " .. s.tc end
  if s.macro and exists("Macros", s.macro) then left[#left + 1] = "Macro " .. s.macro end
  if tag and not kept and exists("Tags", tag) then left[#left + 1] = "Tag " .. tag end
  if #left > 0 then
    warnings[#warnings + 1] = "Toujours dans le show : " .. table.concat(left, ", ")
  end
  return { "Page " .. s.page .. " supprimée",
           "Séquence" .. (s.extras > 0 and ("s " .. s.seq .. " à " .. (s.seq + s.extras)) or (" " .. s.seq))
             .. " supprimée" .. (s.extras > 0 and "s" or ""),
           s.tc and ("Timecode " .. s.tc .. " supprimé") or "Pas de timecode",
           s.macro and ("Macro " .. s.macro .. " supprimée") or "Pas de macro de rappel",
           tag and ("Tag " .. tag .. (kept and " gardé" or " supprimé")) or "Pas de tag",
           "Un Oops remet toute la song" }
end

local function deleteSong(s)
  return runUndo("Song Creator supprimer " .. s.name, deleteBody, s)
end

-- ---- Dupliquer : liens du timecode copié ----
local function classOf(o)
  local ok, c = pcall(function() return o:GetClass() end)
  return ok and tostring(c) or "?"
end

-- Identité d'un objet MA : même objet, même clé
local function handleKey(h)
  local ok, n = pcall(HandleToInt, h)
  if ok and n ~= nil then return n end
  return tostring(h)
end

-- Adresse « Sequence 101 Cue 3 » d'un objet. Seulement pour les objets qui en
-- ont une : sur les objets internes d'un timecode (TrackGroup, pistes...),
-- ToAddr écrit « Could not resolve object address » en rouge (console 0.7.0).
-- Une seule demande par objet (cache vidé à chaque opération).
local ADDR_CLASSES = { Sequence = true, Cue = true, Part = true, Page = true, Exec = true,
                       Timecode = true, Macro = true }
local addrCache = {}
local function addrOf(h)
  local key = handleKey(h)
  local c = addrCache[key]
  if c ~= nil then return c or nil end
  local a
  if ADDR_CLASSES[classOf(h)] then
    local ok, r = pcall(function() return ToAddr(h, false) end)
    if not ok then ok, r = pcall(function() return h:ToAddr() end) end
    if ok and type(r) == "string" then a = r end
  end
  addrCache[key] = a or false
  return a
end

-- Valeur d'une propriété quand c'est un lien vers un autre objet (handle)
local function linkValue(o, pn)
  local ok, v = pcall(function() return o:Get(pn) end)
  if ok and type(v) == "userdata" then return v end
  ok, v = pcall(function() return o[pn] end)
  if ok and type(v) == "userdata" then return v end
  return nil
end

-- Adresse d'un objet de l'ancienne song -> même objet dans la copie :
-- « Sequence 101 Cue 3 » -> « Sequence 201 Cue 3 » ; un executor de
-- l'ancienne page -> le même executor sur la nouvelle page.
local function remapAddr(addr, map)
  local changed = false
  local out = addr:gsub("(Sequence%s+)(%d+)", function(pre, n)
    n = tonumber(n)
    if n >= map.oldSeq and n <= map.oldSeq + map.extras then
      changed = true
      return pre .. (n - map.oldSeq + map.newSeq)
    end
  end)
  out = out:gsub("(Page%s+)(%d+)", function(pre, n)
    if tonumber(n) == map.oldPage then changed = true; return pre .. map.newPage end
  end)
  out = out:gsub("(Executor%s+)(%d+)(%.)", function(pre, n, dot)
    if tonumber(n) == map.oldPage then changed = true; return pre .. map.newPage .. dot end
  end)
  return changed and out or nil
end

-- Ancien objet -> objet copié : séquences de la song avec leurs cues et
-- parts (la copie garde le même ordre), page et executors (même numéro).
local function copyMap(map)
  local t = {}
  local function kids(o)
    local ok, k = pcall(function() return o:Children() end)
    return (ok and type(k) == "table") and k or {}
  end
  local function pair(a, b, depth)
    if not a or not b then return end
    t[handleKey(a)] = b
    if depth > 0 then
      local kb = kids(b)
      for i, c in ipairs(kids(a)) do pair(c, kb[i], depth - 1) end
    end
  end
  for n = 0, map.extras do
    pair(pool("Sequences")[map.oldSeq + n], pool("Sequences")[map.newSeq + n], 2)
  end
  local oldP, newP = pool("Pages")[map.oldPage], pool("Pages")[map.newPage]
  if oldP and newP then
    t[handleKey(oldP)] = newP
    local byNo = {}
    for _, e in ipairs(kids(newP)) do
      local no
      pcall(function() no = tonumber(e.no) end)
      if no then byNo[no] = e end
    end
    for _, e in ipairs(kids(oldP)) do
      local no
      pcall(function() no = tonumber(e.no) end)
      if no and byNo[no] then t[handleKey(e)] = byNo[no] end
    end
  end
  return t
end

-- Rebranche une propriété sur le nouvel objet, vérifié par relecture.
-- Trois façons : le handle, l'adresse en texte, l'adresse MA interne. La
-- façon qui a marché passe en premier pour les liens suivants, celles qui
-- ont échoué à côté d'elle ne sont plus essayées (pas une ligne rouge par event).
local function relink(o, pn, oldH, newH, newAddr, ways)
  if not newH and newAddr then
    pcall(function() local l = ObjectList(newAddr); newH = l and l[1] end)
    if type(newH) ~= "userdata" then newH = nil end
  end
  local target = newH and handleKey(newH)
  -- l'adresse n'est demandée que si le handle ne suffit pas (ToAddr peut
  -- écrire une ligne rouge sur console)
  local targetAddr = newAddr
  local function getTargetAddr()
    if targetAddr == nil and newH then targetAddr = addrOf(newH) or false end
    return targetAddr or nil
  end
  local function isNew(byAddr)
    local h = linkValue(o, pn)
    if not h then return false end
    if target ~= nil and handleKey(h) == target then return true end
    if not byAddr then return false end
    local ta = getTargetAddr()
    return ta ~= nil and addrOf(h) == ta
  end
  local function try(way)
    if way == "handle" and newH then
      pcall(function() o[pn] = newH end)
      return isNew(false)
    elseif way == "adresse" and getTargetAddr() then
      pcall(function() o:Set(pn, getTargetAddr()) end)
    elseif way == "adresse MA" and newH then
      local okA, root = pcall(function() return newH:Addr() end)
      if not (okA and type(root) == "string") then return false end
      pcall(function() o:Set(pn, root) end)
    else
      return false
    end
    return isNew(true)
  end
  local w = ways[pn]
  if not w then w = { skip = {} }; ways[pn] = w end
  local order = {}
  if w.best then order[1] = w.best end
  for _, way in ipairs({ "handle", "adresse", "adresse MA" }) do
    if way ~= w.best and not w.skip[way] then order[#order + 1] = way end
  end
  local tried = {}
  for _, way in ipairs(order) do
    if try(way) then
      for _, f in ipairs(tried) do w.skip[f] = true end
      w.best = way
      return true
    end
    tried[#tried + 1] = way
  end
  -- échec : remettre l'ancien lien s'il a bougé (sur la copie seulement)
  local oldKey = handleKey(oldH)
  local function isOld()
    local h = linkValue(o, pn)
    return h ~= nil and handleKey(h) == oldKey
  end
  if not isOld() then pcall(function() o[pn] = oldH end) end
  if not isOld() then
    local a = addrOf(oldH)
    if a then pcall(function() o:Set(pn, a) end) end
  end
  return false
end

-- Pour le System Monitor : propriétés d'un objet (diagnostic sur console)
local function dumpProps(o)
  local t = {}
  local okC, n = pcall(function() return o:PropertyCount() end)
  for i = 0, (okC and type(n) == "number") and (n - 1) or -1 do
    local okN, pn = pcall(function() return o:PropertyName(i) end)
    if okN and type(pn) == "string" then
      local h = linkValue(o, pn)
      local val
      if h then
        val = "@" .. (addrOf(h) or classOf(h))
      else
        local okV, v = pcall(function() return o:Get(pn) end)
        val = okV and tostring(v) or "?"
      end
      t[#t + 1] = pn .. "=" .. val:sub(1, 40)
    end
  end
  return table.concat(t, ", ")
end

-- Parcourt tout le timecode copié et rebranche chaque lien qui vise un objet
-- de l'ancienne song (séquence, cue, part, page, executor) sur le même objet
-- de la copie. Reconnu par identité (copyMap), sinon par son adresse.
-- Deuxième passage : compte les liens qui visent encore l'ancienne song.
local function retargetTimecode(tcNo, map)
  local tc = pool("Timecodes")[tcNo]
  local st = { objects = 0, links = 0, ok = 0, failed = 0, readonly = 0, left = 0 }
  addrCache = {}
  local cmap = copyMap(map)
  local ways = {}
  -- objets du timecode lui-même (TrackGroup, pistes, plages...) : leurs liens
  -- entre eux ne visent jamais la song, on ne les touche pas
  local inside = {}
  local function mark(o)
    inside[handleKey(o)] = true
    local okK, kids = pcall(function() return o:Children() end)
    for _, c in ipairs(okK and type(kids) == "table" and kids or {}) do mark(c) end
  end
  if tc then mark(tc) end
  local firstOfClass, classes, visits = {}, {}, 0
  -- d'abord par identité seulement (marche sur console, 0.7.0) ; par adresse
  -- seulement si l'identité ne trouve rien
  local byAddr, firstPass = false, true
  local function walk(o, fix)
    if fix and firstPass then
      st.objects = st.objects + 1
      local cls = classOf(o)
      if not firstOfClass[cls] then firstOfClass[cls] = o; classes[#classes + 1] = cls end
    end
    visits = visits + 1
    if visits % 100 == 0 then coroutine.yield(0) end   -- gros timecode : MA respire
    local okC, n = pcall(function() return o:PropertyCount() end)
    for i = 0, (okC and type(n) == "number") and (n - 1) or -1 do
      local okN, pn = pcall(function() return o:PropertyName(i) end)
      local h = okN and type(pn) == "string" and pn ~= "" and linkValue(o, pn)
      local newH, addr, newAddr
      if h and inside[handleKey(h)] then h = nil end
      if h then
        newH = cmap[handleKey(h)]
        if not newH and byAddr then
          addr = addrOf(h)
          newAddr = addr and remapAddr(addr, map)
        end
      end
      if (newH or newAddr) and not fix then
        st.left = st.left + 1
        if st.left <= 5 then
          Printf("[SongCreator] TC " .. tcNo .. " : " .. classOf(o) .. "." .. pn .. " vise encore "
                 .. tostring(addr or addrOf(h)))
        end
      elseif newH or newAddr then
        st.links = st.links + 1
        local ro = false
        pcall(function() local inf = o:PropertyInfo(i); ro = inf and inf.ReadOnly and true or false end)
        if ro then
          st.readonly = st.readonly + 1
        elseif relink(o, pn, h, newH, newAddr, ways) then
          st.ok = st.ok + 1
        else
          st.failed = st.failed + 1
          if st.failed <= 5 then
            Printf("[SongCreator] TC " .. tcNo .. " : " .. classOf(o) .. "." .. pn .. " non rebranche ("
                   .. tostring(addr or addrOf(h)) .. " -> " .. tostring(newAddr or (newH and addrOf(newH))) .. ")")
          end
        end
      end
    end
    local okK, kids = pcall(function() return o:Children() end)
    for _, c in ipairs(okK and type(kids) == "table" and kids or {}) do walk(c, fix) end
  end
  if tc then
    walk(tc, true)
    firstPass = false
    if st.links == 0 then
      byAddr = true
      walk(tc, true)
    end
    walk(tc, false)
  end
  local used = {}
  for pn, w in pairs(ways) do used[#used + 1] = pn .. " par " .. tostring(w.best or "-") end
  Printf(string.format("[SongCreator] TC %d : %d objets lus, %d liens vers la song d'origine, "
    .. "%d rebranches, %d en echec, %d en lecture seule, %d visent encore l'origine (%s)",
    tcNo, st.objects, st.links, st.ok, st.failed, st.readonly, st.left, table.concat(used, ", ")))
  -- rien trouvé ou pas tout rebranché : on écrit la structure pour comprendre
  if st.left > 0 or st.failed > 0 or (st.links == 0 and st.objects > 1) then
    for i = 1, math.min(#classes, 10) do
      Printf("[SongCreator] TC classe " .. classes[i] .. " : " .. dumpProps(firstOfClass[classes[i]]))
    end
  end
  return st
end

-- Executors de la page copiée qui visent encore une séquence de l'ancienne
-- song, en dehors de 216 et 121... (refaits par assignSongExecs)
local function assignedSeqNo(ex)
  local o
  pcall(function() o = ex:GetAssignedObj() end)
  if type(o) ~= "userdata" then o = linkValue(ex, "Object") end
  if type(o) ~= "userdata" then return nil end
  local cls = classOf(o)
  if cls ~= "?" and cls ~= "Sequence" then return nil end
  local no
  pcall(function() no = tonumber(o.no) end)
  return no
end

local function relinkOtherExecs(map)
  local page = pool("Pages")[map.newPage]
  local std = { [CFG.execMain] = true }
  for i = 0, map.extras - 1 do std[CFG.execExtraFrom + i] = true end
  local n = 0
  local okC, execs = pcall(function() return page:Children() end)
  for _, ex in ipairs(okC and type(execs) == "table" and execs or {}) do
    local exNo
    pcall(function() exNo = tonumber(ex.no) end)
    local sNo = assignedSeqNo(ex)
    if exNo and sNo and not std[exNo] and sNo >= map.oldSeq and sNo <= map.oldSeq + map.extras then
      C("Assign Sequence " .. (sNo - map.oldSeq + map.newSeq) .. " At Executor " .. exNo)
      n = n + 1
    end
  end
  return n
end

-- ---- Dupliquer ----
-- d : { name, page, seq, macro, tcNo } (emplacements de la copie)
local function duplicateBody(warnings, s, d)
  local k = s.extras
  local done = {}
  local map = { oldSeq = s.seq, newSeq = d.seq, extras = k, oldPage = s.page, newPage = d.page }

  -- 0. emplacements occupés (écrasement confirmé par un second appui) : vidés d'abord
  if s.macro and exists("Macros", d.macro) then C("Delete Macro " .. d.macro .. " /NoConfirmation") end
  if s.tc and exists("Timecodes", d.tcNo) then C("Delete Timecode " .. d.tcNo .. " /NoConfirmation") end
  if exists("Pages", d.page) then C("Delete Page " .. d.page .. " /NoConfirmation") end
  for n = d.seq, d.seq + k do
    if exists("Sequences", n) then C("Delete Sequence " .. n .. " /NoConfirmation") end
  end

  -- 1. Séquences (main + extras, avec leurs cues)
  C("Copy Sequence " .. seqRange(s.seq, k) .. " At " .. d.seq .. " /NoConfirmation")
  if not exists("Sequences", d.seq) then
    warnings[#warnings + 1] = "Séquence " .. s.seq .. " non copiée : duplication arrêtée"
    return done
  end
  C('Label Sequence ' .. d.seq .. ' "' .. d.name .. '"')
  setNotes(d.seq, k, d.name, warnings)
  local nCues = renameInCommands(cueCommandHolders(d.seq, k), s.name, d.name, warnings)
  done[#done + 1] = "Séquence" .. (k > 0 and ("s " .. d.seq .. " à " .. (d.seq + k)) or (" " .. d.seq))
                 .. " (" .. nCues .. " commande(s) de cue avec le nouveau nom)"

  -- 2. Page copiée, puis ses executors rebranchés sur les nouvelles séquences
  C("Copy Page " .. s.page .. " At " .. d.page .. " /NoConfirmation")
  if not exists("Pages", d.page) then
    warnings[#warnings + 1] = "Page " .. s.page .. " non copiée : page " .. d.page .. " créée vide"
    C("Store Page " .. d.page .. " /Overwrite")
  end
  C("Page " .. d.page)
  C('Label Page ' .. d.page .. ' "' .. d.name .. '"')
  setNote("Pages", "Page", d.page, d.name, warnings, "de la page")
  assignSongExecs(d.seq, k)
  local nOther = relinkOtherExecs(map)
  done[#done + 1] = "Page " .. d.page .. ", executors " .. execText(k)
                 .. ((nOther > 0) and (" + " .. nOther .. " autre(s)") or "")

  -- 3. Timecode copié tel quel, puis ses liens rebranchés sur la copie
  if s.tc then
    C("Copy Timecode " .. s.tc .. " At " .. d.tcNo .. " /NoConfirmation")
    if exists("Timecodes", d.tcNo) then
      C('Label Timecode ' .. d.tcNo .. ' "' .. d.name .. '"')
      setNote("Timecodes", "Timecode", d.tcNo, d.name, warnings, "du timecode")
      local st = retargetTimecode(d.tcNo, map)
      done[#done + 1] = "Timecode " .. d.tcNo .. " : " .. st.ok .. " lien(s) rebranché(s)"
      if st.failed > 0 then
        warnings[#warnings + 1] = "Timecode " .. d.tcNo .. " : " .. st.failed
          .. " lien(s) non rebranché(s) (détail dans le System Monitor)"
      end
      if st.left > 0 then
        warnings[#warnings + 1] = "Timecode " .. d.tcNo .. " : " .. st.left
          .. " lien(s) visent encore la song d'origine (détail dans le System Monitor)"
      elseif st.links == 0 and st.objects > 1 then
        warnings[#warnings + 1] = "Timecode " .. d.tcNo .. " : aucun lien vers la song d'origine trouvé"
          .. " (détail dans le System Monitor)"
      end
    else
      warnings[#warnings + 1] = "Timecode " .. s.tc .. " non copié"
    end
  end

  -- 4. Macro de rappel copiée, nom remplacé dans ses lignes
  if s.macro then
    C("Copy Macro " .. s.macro .. " At " .. d.macro .. " /NoConfirmation")
    if exists("Macros", d.macro) then
      C('Label Macro ' .. d.macro .. ' "' .. d.name .. '"')
      setNote("Macros", "Macro", d.macro, d.name, warnings, "de la macro")
      local nLines = renameInCommands(macroLines(d.macro), s.name, d.name, warnings)
      done[#done + 1] = "Macro " .. d.macro .. " (" .. nLines .. " ligne(s) avec le nouveau nom)"
    else
      warnings[#warnings + 1] = "Macro " .. s.macro .. " non copiée"
    end
  end

  -- 5. Tag : la copie perd celui de l'origine (s'il a suivi la copie) et prend
  -- le sien si un numéro est donné (champ vide = pas de tag)
  local objs = songObjects(d.page, d.seq, k,
                           (s.tc and exists("Timecodes", d.tcNo)) and d.tcNo or nil,
                           (s.macro and exists("Macros", d.macro)) and d.macro or nil)
  if s.tag then tagObjects(s.tag, objs, true) end
  if d.tagNo and storeTag(d.tagNo, d.name, warnings) then
    tagObjects(d.tagNo, objs)
    done[#done + 1] = "Tag " .. d.tagNo .. " « " .. d.name .. " » sur la copie"
  elseif not d.tagNo then
    done[#done + 1] = "Pas de tag pour la copie"
  end
  return done
end

local function duplicateSong(s, d)
  return runUndo("Song Creator dupliquer " .. s.name, duplicateBody, s, d)
end

-- ---------------------------------------------------------------------------
--  Fenêtre de setup v0.5 (écran 1). Recettes reprises de GUI REPLACE V15 de Jo,
--  validé sur console : DialogFrame pour le cadre et le fond, marges autour de
--  chaque élément, libellés sur fond transparent à gauche des champs, bouton
--  principal dans la couleur « Please » de MA. Icônes à gauche du texte
--  (IconAlignmentH, vérifié sur console en 0.4.1).
-- ---------------------------------------------------------------------------
local UI = {
  W = 1300, H = 870,             -- taille de départ (au plus 95 % de l'écran)
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

local FIELD_ORDER = { "name", "page", "seq", "macro", "tcNo", "tagNo", "bpm", "extras", "cues" }
local SLOTS = {
  { key = "page",  pool = "Pages",     label = "Page" },
  { key = "seq",   pool = "Sequences", label = "Séquence main" },
  { key = "macro", pool = "Macros",    label = "Macro de rappel" },
  { key = "tcNo",  pool = "Timecodes", label = "Timecode" },
  { key = "tagNo", pool = "Tags",      label = "Tag" },
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
--  Liste d'un pool avec barre de défilement (v0.6.2, dans la fenêtre en 0.6.5)
--  Recette ScrollBox + ScrollBarV reprise de BakaCowpoke (Tags UI Helper,
--  CC0) : ScrollBox nommée, barre dont ScrollTarget est le chemin "../nom"
--  de la ScrollBox, barre dans une colonne « Content », cases posées en X/Y.
--  Pas de Popup ni de ScrollableItemList : la liste de la v0.6.0 faite avec
--  eux plantait MA dès l'ouverture.
--  Tous les numéros du pool sont proposés comme dans la fenêtre du pool :
--  objets existants (couleur de leur apparence) et numéros libres.
-- ---------------------------------------------------------------------------
local PICK = { cellW = 210, cellH = 48, gap = 6,
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

local function readFields(w)
  local raw = w.fields.name.Content or ""
  local v = { rawName = raw, name = cleanName(raw), tcOn = w.tcOn, tagOn = w.tagOn }
  for _, k in ipairs(FIELD_ORDER) do
    if k ~= "name" then v[k] = toInt(w.fields[k].Content) end
  end
  return v
end

-- Tout ce que l'on peut changer dans la fenêtre : un changement relance le récap
local function signature(w)
  local t = { w.mode or "", w.song and (w.song.page .. ":" .. w.song.name) or "-" }
  for _, k in ipairs(FIELD_ORDER) do t[#t + 1] = tostring(w.fields[k].Content) end
  t[#t + 1] = tostring(w.tcOn) .. tostring(w.tagOn)
  if w.sp then
    t[#t + 1] = tostring(w.sp.name.Content)
    for _, s in ipairs(SLOTS) do t[#t + 1] = tostring(w.dup.fields[s.key].Content) end
  end
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
  t[#t + 1] = v.tagOn and ("Tag " .. q(v.tagNo) .. " et notes « " .. name .. " »")
                       or ("Notes « " .. name .. " », pas de tag")
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
  local first, count = nil, 0
  for n = no, no + block - 1 do
    local o = poolObj(poolName, n)
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

local function setTagButton(w)
  w.tagBtn.Text = w.tagOn and "Oui" or "Non"
  quiet(w.tagBtn, "TextColor", w.tagOn and "Global.Selected" or "Global.Text")
  local en = w.tagOn and "Yes" or "No"
  quiet(w.fields.tagNo, "Enabled", en)
  quiet(w.status.tagNo, "Enabled", en)
  quiet(w.pickBtn.tagNo, "Enabled", en)
end

local pickState = {}
signalTable.SC_PickCell = function(caller) pickState.value = caller.SignalValue end

-- Calque « liste » posé dans la fenêtre principale, dans la même case que le
-- cadre du setup (comme les calques de UI Compact Layout de BakaCowpoke, CC0,
-- qui passent de l'un à l'autre avec Visible / Enabled). Pas de seconde
-- fenêtre : MA a refusé de supprimer la fenêtre liste séparée (0.6.4,
-- « deletion of the child object is prohibited »).
-- Construit une seule fois, au premier choix dans un pool.
local function buildPickLayer(w)
  local layer = w.base:Append("DialogFrame")
  layer.Name = "SongCreatorPickLayer"
  opt(layer, { H = "100%", W = "100%" })
  layer.Columns, layer.Rows = 2, 3
  layer.Anchors = cell(0, 1)
  fixRow(layer, 1, UI.sect + 18)
  layer[1][2].SizePolicy = "Stretch"
  fixRow(layer, 3, UI.foot)
  layer[2][1].SizePolicy = "Stretch"
  layer[2][2].SizePolicy = "Content"   -- colonne de la barre de défilement
  quiet(layer, "Visible", "No")
  quiet(layer, "Enabled", "No")

  -- en-tête : « Select Sequence », puis le message (avertissement)
  local head = grid(layer, cell(0, 0, 1, 0), 2, 1)
  opt(head, { Margin = pad(PANEL, PANEL, PANEL, 0) })
  fixCol(head, 1, 260)
  head[2][2].SizePolicy = "Stretch"
  local title = section(head, cell(0, 0), "")
  quiet(title, "Font", UI.fontButton)
  quiet(title, "TextColor", "Global.Text")
  local msg = label(head, cell(1, 0), "", { TextalignmentV = "Bottom", Padding = pad(6, 6, 0, 6) })

  local box = layer:Append("ScrollBox")
  box.Name = "SongCreatorPickBox"
  box.Anchors = cell(0, 1)
  opt(box, { Margin = pad(PANEL, 0, 4, 4) })
  local bar = layer:Append("ScrollBarV")
  bar.ScrollTarget = "../SongCreatorPickBox"
  bar.Anchors = cell(1, 1)

  -- pied : légende, puis Annuler (même place que les boutons du setup)
  local ft = grid(layer, cell(0, 2, 1, 2), 2, 1)
  opt(ft, { Margin = pad(PANEL - 6, PANEL, 6, PANEL) })
  ft[2][1].SizePolicy = "Stretch"
  fixCol(ft, 2, 300)
  local legend = label(ft, cell(0, 0), "", { Font = UI.fontSmall, TextColor = "Global.LabelText",
                                             Padding = pad(8, 8, 0, 0) })
  local cancel = button(ft, cell(1, 0), "Annuler", nil, "cancel")
  cancel.PluginComponent = myHandle
  cancel.Clicked = "SC_PickCell"
  cancel.SignalValue = "cancel"

  w.pick = { layer = layer, title = title, msg = msg, box = box, legend = legend }
end

local function showPickLayer(w, on)
  local a, b = on and "No" or "Yes", on and "Yes" or "No"
  quiet(w.frame, "Visible", a)
  quiet(w.frame, "Enabled", a)
  quiet(w.pick.layer, "Visible", b)
  quiet(w.pick.layer, "Enabled", b)
  -- remet l'affichage du mode (panneaux, champs grisés), que MA a pu réactiver
  if not on then
    if w.restore then w.restore(w) else setTcButton(w) end
  end
end

-- Remplit la liste : une case par numéro du pool. Toutes les listes marchent
-- pareil : une case libre (noire) ou occupée (grise ou couleur de son
-- apparence) se choisit d'un clic ; pour la séquence, une case « pas la
-- place » affiche un avertissement et la liste reste ouverte.
local function fillPickLayer(w, poolName, current, block)
  local used, maxNo, objs = readPool(poolName)
  local nos = pickNumbers(used, maxNo)
  local info = POOL_KIND[poolName] or { kind = poolName }
  local P = w.pick
  P.title.Text = "Select " .. info.kind
  P.msg.Text = ""
  pcall(function() P.box:ClearUIChildren() end)

  local width = tonumber(w.base.W) or UI.W
  local cols = math.max(1, math.floor((width - 2 * PANEL - 50) / (PICK.cellW + PICK.gap)))
  local paint, nObj = {}, 0
  for i, n in ipairs(nos) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local b = P.box:Append("Button")
    b.Anchors = "0,0"
    b.W, b.H = PICK.cellW, PICK.cellH
    b.X = 5 + col * (PICK.cellW + PICK.gap)
    b.Y = 5 + row * (PICK.cellH + PICK.gap)
    local value = tostring(n)
    if used[n] then
      nObj = nObj + 1
      b.Text = n .. "  " .. ((used[n] ~= "") and used[n] or "?")
      local r, g, bl, a = appearanceColor(objs[n])
      if r then paint[#paint + 1] = { b = b, r = r, g = g, bl = bl, a = a, current = (n == current) } end
    else
      -- libre : case noire (fond transparent sur le noir de la liste)
      local fits = hasRoom(used, n, block)
      b.Text = n .. (fits and "  - libre -" or "  - pas la place -")
      if not fits then value = "full:" .. n end
      quiet(b, "BackColor", COL.transparent)
      quiet(b, "TextColor", fits and "Global.LabelText" or "Global.Disabled")
    end
    -- quiet : un refus ne doit pas écrire une ligne par case dans le System Monitor
    quiet(b, "Font", UI.fontLabel)
    quiet(b, "TextalignmentH", "Left")
    quiet(b, "Padding", pad(8, 4, 0, 0))
    quiet(b, "HasHover", "Yes")
    b.PluginComponent = myHandle
    b.Clicked = "SC_PickCell"
    b.SignalValue = value
    if n == current then quiet(b, "TextColor", "Global.Selected") end
  end

  local txt = "Noir : libre.   Gris ou couleur : occupé."
  if block > 1 then
    txt = txt .. "   « pas la place » : la séquence et ses " .. (block - 1) .. " extras ne tiennent pas."
  end
  P.legend.Text = txt .. "   " .. nObj .. " objets" .. (current and (", choix actuel : " .. current) or "") .. "."
  Printf("[SongCreator] liste " .. poolName .. " affichee : " .. #nos .. " cases, " .. nObj .. " objets")
  return used, paint
end

-- Couleurs des apparences, posées une fois la liste affichée
local function paintPickLayer(poolName, paint)
  if #paint == 0 then return end
  local nColor = 0
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

-- Ouvre le calque liste et attend un clic. fill() remplit la liste et renvoie
-- les couleurs d'apparence à poser ; onValue(valeur du clic) renvoie true et
-- le résultat pour fermer la liste. Renvoie ok (la liste a pu s'ouvrir) et
-- le résultat (nil si Annuler).
local function runPickLayer(w, what, fill, onValue)
  loadColors()
  local okBuild, paint = pcall(function()
    if not w.pick then buildPickLayer(w) end
    return fill()
  end)
  if not okBuild then
    if w.pick then pcall(showPickLayer, w, false) end
    return false, paint
  end
  showPickLayer(w, true)
  coroutine.yield(0.1)
  if IsObjectValid(w.base) then paintPickLayer(what, paint or {}) end

  local chosen
  pickState.value = nil
  while IsObjectValid(w.base) do
    coroutine.yield(0.05)
    local v = pickState.value
    pickState.value = nil
    if v == "cancel" then break end
    if v then
      local done, res = onValue(tostring(v))
      if done then chosen = res; break end
    end
  end
  if IsObjectValid(w.base) then showPickLayer(w, false) end
  return true, chosen
end

-- Choix d'un numéro dans la liste d'un pool, dans la fenêtre principale
local function pickInWindow(w, poolName, current, block)
  local used = {}
  return runPickLayer(w, poolName,
    function()
      local u, paint = fillPickLayer(w, poolName, current, block)
      used = u
      return paint
    end,
    function(v)
      if v:find("^full:") then
        local n = tonumber(v:sub(6))
        local stop
        for k = n + 1, n + block - 1 do
          if used[k] then stop = k; break end
        end
        w.pick.msg.Text = "Séquence " .. n .. " : pas la place pour la main et ses " .. (block - 1)
                       .. " extras" .. (stop and (", la " .. stop .. " est occupée.") or ".")
        quiet(w.pick.msg, "TextColor", "Global.WarningText")
        return false
      end
      local n = tonumber(v)
      return n ~= nil, n
    end)
end

-- Choix dans la fenêtre principale ; liste native de MA si le calque ne peut
-- pas se construire sur cette version.
local function pickInSetup(w, p, current, block, caller)
  if not w.pickFailed then
    local ok, res = pickInWindow(w, p.pool, current, block)
    if ok then return res end
    w.pickFailed = true   -- on ne retente pas : liste MA jusqu'à la fin
    Printf("[SongCreator] liste dans la fenetre indisponible (" .. tostring(res) .. "), liste MA")
  end
  return pickWithPopupInput(p.pool, p.title, current, block, caller or w.pickBtn[p.field])
end

-- ---- Liste des songs du show (même calque que les pools) ----
local SONG_CELL = { w = 420, h = 54 }

local function songLabel(s)
  return s.name .. "   (page " .. s.page .. ", séq " .. s.seq .. ")"
end

local function fillSongLayer(w, songs, current)
  local P = w.pick
  P.title.Text = "Select Song"
  P.msg.Text = ""
  pcall(function() P.box:ClearUIChildren() end)
  local width = tonumber(w.base.W) or UI.W
  local cols = math.max(1, math.floor((width - 2 * PANEL - 50) / (SONG_CELL.w + PICK.gap)))
  local paint = {}
  for i, s in ipairs(songs) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local b = P.box:Append("Button")
    b.Anchors = "0,0"
    b.W, b.H = SONG_CELL.w, SONG_CELL.h
    b.X = 5 + col * (SONG_CELL.w + PICK.gap)
    b.Y = 5 + row * (SONG_CELL.h + PICK.gap)
    b.Text = songLabel(s)
    local isCur = current ~= nil and current.page == s.page and current.name == s.name
    local r, g, bl, a = appearanceColor(s.seqObj)
    if r then paint[#paint + 1] = { b = b, r = r, g = g, bl = bl, a = a, current = isCur } end
    quiet(b, "Font", UI.fontLabel)
    quiet(b, "TextalignmentH", "Left")
    quiet(b, "Padding", pad(10, 4, 0, 0))
    quiet(b, "HasHover", "Yes")
    b.PluginComponent = myHandle
    b.Clicked = "SC_PickCell"
    b.SignalValue = "song:" .. i
    if isCur then quiet(b, "TextColor", "Global.Selected") end
  end
  if #songs == 0 then
    P.msg.Text = "Aucune song dans ce show."
    quiet(P.msg, "TextColor", "Global.WarningText")
  end
  P.legend.Text = #songs .. " song(s). Une song = une page et une séquence qui portent le même nom."
  Printf("[SongCreator] liste des songs affichee : " .. #songs .. " song(s)")
  return paint
end

-- Secours sans calque : liste native de MA (« Select Song »)
local function pickSongPopup(songs, caller)
  local items = {}
  for i, s in ipairs(songs) do items[i] = songLabel(s) end
  if #items == 0 then return nil end
  local args = { title = "Song", caller = caller or (pickDisplay()), items = items,
                 add_args = { FilterSupport = "Yes" } }
  local ok, idx, value = pcall(PopupInput, args)
  if not ok then
    args.caller = (pickDisplay())
    ok, idx, value = pcall(PopupInput, args)
  end
  if not ok then return nil end
  if value then
    for i, it in ipairs(items) do
      if it == value then return songs[i] end
    end
  end
  idx = tonumber(idx)
  return idx and songs[idx + 1] or nil
end

local function pickSong(w)
  local songs = findSongs()
  if not w.pickFailed then
    local ok, res = runPickLayer(w, "songs",
      function() return fillSongLayer(w, songs, w.song) end,
      function(v)
        local i = tonumber(v:match("^song:(%d+)$") or "")
        return (i ~= nil and songs[i] ~= nil), songs[i or 0]
      end)
    if ok then return res end
    w.pickFailed = true
    Printf("[SongCreator] liste dans la fenetre indisponible (" .. tostring(res) .. "), liste MA")
  end
  return pickSongPopup(songs, w.sp and w.sp.pickBtn)
end

-- Boîte MA de secours (sans fenêtre) : liste native de MA
local function pickFromPool(poolName, title, current, block, caller)
  return pickWithPopupInput(poolName, title, current, block, caller)
end

-- ---------------------------------------------------------------------------
--  Modes de la fenêtre (0.7) : Créer, Renommer, Dupliquer, Supprimer.
--  Le centre change selon le mode (panneau Créer ou panneau Song, passés de
--  l'un à l'autre avec Visible / Enabled comme le calque liste).
-- ---------------------------------------------------------------------------
local MODE_LIST = {
  { key = "create", text = "Créer" },
  { key = "rename", text = "Renommer" },
  { key = "dup",    text = "Dupliquer" },
  { key = "delete", text = "Supprimer" },
}
local MODES = {
  create = { recap = "Ce qui sera créé",     go = "Créer la song",     armed = "Écraser et créer" },
  rename = { recap = "Ce qui sera renommé",  go = "Renommer la song",  armed = "Renommer la song" },
  dup    = { recap = "Ce qui sera copié",    go = "Dupliquer la song", armed = "Écraser et dupliquer" },
  delete = { recap = "Ce qui sera supprimé", go = "Supprimer la song", armed = "Confirmer la suppression" },
}

local function show(obj, on)
  if not obj then return end
  quiet(obj, "Visible", on and "Yes" or "No")
  quiet(obj, "Enabled", on and "Yes" or "No")
end

-- Ligne d'emplacement : libellé | numéro | état (libre / occupé) | ▾
local function slotLine(parent, r, s, store, prefix, value)
  local g = line(parent, r, { UI.labelW, UI.numW, false, UI.pickW })
  label(g, cell(0, 0), s.label)
  store.fields[s.key] = field(g, cell(1, 0), value, true)
  -- l'état (libre / occupé) ouvre aussi la liste
  local st = button(g, cell(2, 0), "", prefix .. s.key)
  opt(st, { TextalignmentH = "Left", Font = UI.fontLabel, Padding = pad(12, 6, 0, 0) })
  store.status[s.key] = st
  local b = button(g, cell(3, 0), "", prefix .. s.key)
  -- flèche de liste ; « ... » si l'icône n'existe pas sur cette version
  if not pcall(function() b.Icon = "triangle_down" end) then b.Text = "..." end
  store.pickBtn[s.key] = b
end

-- Panneau Song (Renommer, Dupliquer, Supprimer), dans la même case que Créer
local function buildSongPanel(w, body)
  local sp = grid(body, cell(1, 0), 1, 8)
  opt(sp, { Margin = pad(8, 8, PANEL, PANEL) })
  local sizes = { UI.sect, UI.row, 30, UI.gap, UI.row + 30, UI.gap, UI.sect + #SLOTS * UI.row, false }
  for i = 1, #sizes do
    if sizes[i] then fixRow(sp, i, sizes[i]) else sp[1][i].SizePolicy = "Stretch" end
  end

  section(sp, cell(0, 0), "Song")
  local g = line(sp, 1, { UI.labelW, false, UI.pickW })
  label(g, cell(0, 0), "Song")
  local songBtn = button(g, cell(1, 0), "", "pick_song")
  opt(songBtn, { TextalignmentH = "Left", Font = UI.fontValue, Padding = pad(12, 6, 0, 0) })
  local pickBtn = button(g, cell(2, 0), "", "pick_song")
  if not pcall(function() pickBtn.Icon = "triangle_down" end) then pickBtn.Text = "..." end
  local li = line(sp, 2, { UI.labelW, false })
  local info = label(li, cell(1, 0), "", { Font = UI.fontSmall, TextColor = "Global.LabelText" })

  -- nouveau nom (Renommer, Dupliquer)
  local ng = grid(sp, cell(0, 4), 1, 2)
  fixRow(ng, 1, UI.row)
  fixRow(ng, 2, 30)
  local l1 = line(ng, 0, { UI.labelW, false })
  label(l1, cell(0, 0), "Nouveau nom")
  local name = field(l1, cell(1, 0), "", false)
  local l2 = line(ng, 1, { UI.labelW, false })
  local maName = label(l2, cell(1, 0), "", { Font = UI.fontSmall, TextColor = "Global.LabelText" })

  -- emplacements de la copie (Dupliquer)
  local sg = grid(sp, cell(0, 6), 1, 1 + #SLOTS)
  fixRow(sg, 1, UI.sect)
  for r = 2, 1 + #SLOTS do fixRow(sg, r, UI.row) end
  section(sg, cell(0, 0), "Emplacements de la copie")
  w.dup = { fields = {}, status = {}, pickBtn = {} }
  for i, s in ipairs(SLOTS) do slotLine(sg, i, s, w.dup, "dpick_", "") end

  w.sp = { panel = sp, songBtn = songBtn, pickBtn = pickBtn, info = info, name = name,
           maName = maName, nameGroup = ng, slotGroup = sg }
  show(sp, false)
end

-- Champs timecode et macro de la copie : grisés si la song n'en a pas
local function setDupSlotsEnabled(w)
  local s = w.song
  for _, k in ipairs({ "tcNo", "macro" }) do
    local has = s ~= nil and ((k == "tcNo" and s.tc) or (k == "macro" and s.macro)) and true or false
    local en = has and "Yes" or "No"
    quiet(w.dup.fields[k], "Enabled", en)
    quiet(w.dup.status[k], "Enabled", en)
    quiet(w.dup.pickBtn[k], "Enabled", en)
  end
end

-- Affichage du mode en cours : panneau du centre, boutons, titres
local function applyView(w)
  local m = w.mode
  show(w.createPanel, m == "create")
  show(w.sp.panel, m ~= "create")
  show(w.sp.nameGroup, m == "rename" or m == "dup")
  show(w.sp.slotGroup, m == "dup")
  for key, b in pairs(w.modeBtn) do
    quiet(b, "TextColor", (key == m) and "Global.Selected" or "Global.Text")
  end
  w.recapTitle.Text = MODES[m].recap
  quiet(w.defaultsBtn, "Enabled", (m ~= "delete") and "Yes" or "No")
  quiet(w.defaultsBtn, "TextColor", (m ~= "delete") and "Global.Text" or "Global.Disabled")
  if m == "create" then setTcButton(w); setTagButton(w) end
  if m == "dup" then setDupSlotsEnabled(w) end
end

-- Bouton principal : action du mode, confirmation (« armed »), ou Fermer
local function setGo(w, state)
  local M = MODES[w.mode]
  if state == "done" then
    w.createBtn.Text = "Fermer"
    w.createBtn.SignalValue = "cancel"
  else
    w.createBtn.Text = (state == "armed") and M.armed or M.go
    w.createBtn.SignalValue = "go"
  end
  -- Supprimer : bouton gris à texte rouge ; on ne touche au texte des autres
  -- modes que pour enlever ce rouge
  if w.mode == "delete" and state ~= "done" then
    quiet(w.createBtn, "BackColor", COL.back)
    quiet(w.createBtn, "TextColor", "Global.ErrorText")
    w.goRed = true
  else
    quiet(w.createBtn, "BackColor", COL.please)
    if w.goRed then
      local tc = w.goText
      if tc == nil or tc == "" then tc = "Global.Text" end
      quiet(w.createBtn, "TextColor", tc)
      w.goRed = false
    end
  end
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
  local w = { overlay = overlay, base = base, fields = {}, status = {}, pickBtn = {}, tcOn = v.tcOn,
              tagOn = v.tagOn }

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
  w.frame = frame   -- la liste d'un pool prend sa place le temps du choix

  local body = grid(frame, cell(0, 0), 3, 1)
  fixCol(body, 1, UI.modesW)
  body[2][2].SizePolicy = "Stretch"
  fixCol(body, 3, UI.recapW)

  -- Colonne des modes
  local modes = grid(body, cell(0, 0), 1, 6)
  opt(modes, { Margin = pad(PANEL, 2, PANEL, PANEL) })
  fixRow(modes, 1, UI.sect)
  for r = 2, 5 do fixRow(modes, r, UI.row) end
  modes[1][6].SizePolicy = "Stretch"
  section(modes, cell(0, 0), "Mode")
  w.modeBtn = {}
  for i, m in ipairs(MODE_LIST) do
    local b = button(modes, cell(0, i), m.text, "mode_" .. m.key)
    opt(b, { TextalignmentH = "Left", Padding = pad(14, 4, 0, 0) })
    w.modeBtn[m.key] = b
  end

  -- Centre : la song, les emplacements, les réglages
  -- lignes : Song (3), espace, Emplacements (titre + une par pool), espace,
  -- Réglages (titre + 3), reste, note du bas
  local sizes = { UI.sect, UI.row, 30, UI.gap, UI.sect }
  for _ = 1, #SLOTS do sizes[#sizes + 1] = UI.row end
  for _, sz in ipairs({ UI.gap, UI.sect, UI.row, UI.row, UI.row, false, 30 }) do sizes[#sizes + 1] = sz end
  local main = grid(body, cell(1, 0), 1, #sizes)
  opt(main, { Margin = pad(8, 8, PANEL, PANEL) })
  w.createPanel = main
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
  for i, s in ipairs(SLOTS) do slotLine(main, 4 + i, s, w, "pick_", v[s.key]) end

  local rr = 5 + #SLOTS   -- titre « Réglages »
  section(main, cell(0, rr), "Réglages")
  local r1 = line(main, rr + 1, { UI.labelW, UI.numW, 24, UI.label2W, UI.numW, false })
  label(r1, cell(0, 0), "BPM")
  w.fields.bpm = field(r1, cell(1, 0), v.bpm, true)
  label(r1, cell(3, 0), "Extras (0 à 10)")
  w.fields.extras = field(r1, cell(4, 0), v.extras, true)
  local r2 = line(main, rr + 2, { UI.labelW, UI.numW, 24, UI.label2W, UI.numW, false })
  label(r2, cell(0, 0), "Cues de song")
  w.fields.cues = field(r2, cell(1, 0), v.cues, true)
  label(r2, cell(3, 0), "Créer le timecode")
  w.tcBtn = button(r2, cell(4, 0), "", "tc_toggle")
  opt(w.tcBtn, { Font = UI.fontValue })
  local r3 = line(main, rr + 3, { UI.labelW, UI.numW, 24, UI.label2W, UI.numW, false })
  label(r3, cell(3, 0), "Poser le tag")
  w.tagBtn = button(r3, cell(4, 0), "", "tag_toggle")
  opt(w.tagBtn, { Font = UI.fontValue })

  label(main, cell(0, #sizes - 1), "Exec main " .. CFG.execMain .. "   -   extras " .. CFG.execExtraFrom .. " à "
        .. (CFG.execExtraFrom + CFG.maxExtras - 1) .. "   -   pages communes " .. CFG.commonPages
        .. "   -   Speed Master " .. CFG.speedMaster,
        { TextColor = "Global.Disabled", Font = UI.fontSmall })

  -- Centre, autres modes : la song existante
  buildSongPanel(w, body)

  -- Droite : ce qui sera créé, puis les alertes
  local rc = grid(body, cell(2, 0), 1, 4)
  opt(rc, { Margin = pad(4, PANEL, PANEL, PANEL) })
  fixRow(rc, 1, UI.sect)
  rc[1][2].SizePolicy = "Stretch"
  fixRow(rc, 3, UI.gap)
  fixRow(rc, 4, 110)
  w.recapTitle = section(rc, cell(0, 0), "Ce qui sera créé")
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
  w.createBtn = button(ft, cell(1, 0), "Créer la song", "go", "ok")
  opt(w.createBtn, { BackColor = COL.please })
  pcall(function() w.goText = w.createBtn.TextColor end)   -- remise après Supprimer (texte rouge)
  w.defaultsBtn = button(ft, cell(2, 0), "Valeurs par défaut", "defaults", "undo")
  button(ft, cell(3, 0), "Annuler", "cancel", "cancel")

  -- Coin de redimensionnement (bas droite)
  pcall(function()
    if ClassExists and not ClassExists("ResizeCorner") then return end
    local rcorner = base:Append("ResizeCorner")
    rcorner.Anchors = cell(0, 1)
    opt(rcorner, { AlignmentH = "Right", AlignmentV = "Bottom" })
  end)

  w.mode = "create"
  setTcButton(w)
  setTagButton(w)
  return w
end

local PICK_FIELDS = {
  pick_page  = { field = "page",  pool = "Pages",     title = "Page" },
  pick_macro = { field = "macro", pool = "Macros",    title = "Macro" },
  pick_seq   = { field = "seq",   pool = "Sequences", title = "Sequence" },
  pick_tcNo  = { field = "tcNo",  pool = "Timecodes", title = "Timecode" },
  pick_tagNo = { field = "tagNo", pool = "Tags",      title = "Tag" },
}
local DUP_PICK = {
  dpick_page  = PICK_FIELDS.pick_page,
  dpick_macro = PICK_FIELDS.pick_macro,
  dpick_seq   = PICK_FIELDS.pick_seq,
  dpick_tcNo  = PICK_FIELDS.pick_tcNo,
  dpick_tagNo = PICK_FIELDS.pick_tagNo,
}

-- ---- Panneau Song : contenu selon le mode ----
local function songInfo(s, m)
  local t = { "Séquence " .. s.seq .. ((s.extras > 0)
                and (" + " .. s.extras .. " extras (" .. (s.seq + 1) .. " à " .. (s.seq + s.extras) .. ")")
                or ", sans extras") }
  t[#t + 1] = s.tc and ("timecode " .. s.tc) or "pas de timecode"
  t[#t + 1] = s.macro and ("macro " .. s.macro) or "pas de macro"
  if not s.tag then
    t[#t + 1] = "pas de tag"
  elseif m and m.readable then
    t[#t + 1] = "tag " .. s.tag .. " (" .. m.count .. " objet" .. (m.count > 1 and "s" or "") .. ")"
  else
    t[#t + 1] = "tag " .. s.tag
  end
  return table.concat(t, "   -   ")
end

-- Vérification par le tag, refaite seulement quand la song change
local function songMembers(w, s)
  local key = s.page .. ":" .. s.name .. ":" .. s.seq .. ":" .. s.extras .. ":" .. tostring(s.tag)
  if w.memberKey ~= key then
    w.memberKey = key
    w.members = tagMembers(s)
  end
  return w.members
end

-- Ligne d'alerte : objets taggés hors de la song (ils ne sont pas touchés)
local function outsideText(m, s)
  if not m or #m.outside == 0 then return nil end
  return "Aussi taggés « " .. s.name .. " » hors de la song : " .. table.concat(m.outside, ", ")
         .. ". Ils ne sont pas touchés."
end

local function showSongRow(w)
  local s, sp = w.song, w.sp
  if s then
    sp.songBtn.Text = s.name .. "   (page " .. s.page .. ")"
    quiet(sp.songBtn, "TextColor", "Global.Text")
    sp.info.Text = songInfo(s, songMembers(w, s))
  else
    sp.songBtn.Text = w.lost and ("« " .. w.lost .. " » n'existe plus : choisis une song")
                      or "Choisis une song"
    quiet(sp.songBtn, "TextColor", "Global.LabelText")
    sp.info.Text = "Une song = une page et une séquence qui portent le même nom."
  end
end

-- Première page libre, en évitant les pages communes (101 à 120)
local function freePage(from)
  local n = firstFree("Pages", from)
  if n >= CFG.commonFrom and n <= CFG.commonTo then n = firstFree("Pages", CFG.commonTo + 1) end
  return n
end

-- Emplacements proposés pour la copie : les premiers libres après la song
local function setDupDefaults(w, s)
  local f = w.dup.fields
  f.page.Content = tostring(freePage(s.page + 1))
  f.seq.Content = tostring(firstFree("Sequences", s.seq + s.extras + 1, 1 + s.extras))
  f.macro.Content = s.macro and tostring(firstFree("Macros", s.macro + 1)) or ""
  f.tcNo.Content = s.tc and tostring(firstFree("Timecodes", s.tc + 1)) or ""
  -- tag : comme la song (vide = pas de tag pour la copie)
  f.tagNo.Content = s.tag and tostring(firstFree("Tags", s.tag + 1)) or ""
  w.dupFor = s.page .. ":" .. s.name
end

-- Nouveau nom proposé : le nom actuel (Renommer), nom_copie (Dupliquer).
-- Un nom tapé par Jo n'est pas remplacé en changeant de mode.
local function enterMode(w, songChanged)
  local s, sp = w.song, w.sp
  if not s or w.mode == "create" then return end
  local cur = sp.name.Content or ""
  if w.mode ~= "delete" then
    local auto = (w.mode == "dup") and (s.name .. "_copie") or s.name
    if songChanged or cur == "" or cur == w.autoName then
      sp.name.Content = auto
      w.autoName = auto
    end
  end
  if w.mode == "dup" and (songChanged or w.dupFor ~= s.page .. ":" .. s.name) then
    setDupDefaults(w, s)
  end
end

local function readDup(w)
  local d = { name = cleanName(w.sp.name.Content or "") }
  for _, sl in ipairs(SLOTS) do d[sl.key] = toInt(w.dup.fields[sl.key].Content) end
  return d
end

-- Erreur bloquante sur le nouveau nom (nil si bon), et sa couleur
local function checkNewName(name, s)
  if name == "" or name == s.name then return "Tape le nouveau nom de la song.", "Global.LabelText" end
  local users = nameUsers(name)
  if #users > 0 then
    return "Nom déjà utilisé : " .. table.concat(users, ", ") .. ".", "Global.ErrorText"
  end
  return nil
end

local function validateDup(s, d)
  local err, color = checkNewName(d.name, s)
  if err then return err, nil, color end
  local k = s.extras
  if not d.page then return "Numéro de page invalide." end
  if not d.seq then return "Numéro de séquence invalide." end
  if s.macro and not d.macro then return "Numéro de macro invalide." end
  if s.tc and not d.tcNo then return "Numéro de timecode invalide." end
  if d.page == s.page then return "La copie doit aller sur une autre page que la " .. s.page .. "." end
  if d.seq <= s.seq + k and d.seq + k >= s.seq then
    return "Les séquences de la copie (" .. d.seq .. " à " .. (d.seq + k) .. ") chevauchent celles de la song ("
           .. s.seq .. " à " .. (s.seq + k) .. ")."
  end
  if s.macro and d.macro == s.macro then return "La copie doit avoir une autre macro que la " .. s.macro .. "." end
  if s.tc and d.tcNo == s.tc then return "La copie doit avoir un autre timecode que le " .. s.tc .. "." end
  if s.tag and d.tagNo == s.tag then return "La copie doit avoir un autre tag que le " .. s.tag .. "." end
  local busy = {}
  busyAdd(busy, "Pages", "Page", d.page)
  for n = d.seq, d.seq + k do busyAdd(busy, "Sequences", "Séquence", n) end
  if s.macro then busyAdd(busy, "Macros", "Macro", d.macro) end
  if s.tc then busyAdd(busy, "Timecodes", "Timecode", d.tcNo) end
  if d.tagNo then busyAdd(busy, "Tags", "Tag", d.tagNo) end
  return nil, busy
end

-- Commandes qui contiennent le nom de la song (compté une fois par song)
local function songCounts(w, s)
  local key = s.page .. ":" .. s.name .. ":" .. s.seq .. ":" .. s.extras .. ":" .. tostring(s.macro)
  if w.countKey ~= key then
    w.countKey = key
    w.counts = { cues = renameInCommands(cueCommandHolders(s.seq, s.extras), s.name, s.name, nil, true),
                 macro = renameInCommands(macroLines(s.macro), s.name, s.name, nil, true) }
  end
  return w.counts
end

local function seqText(seq, extras)
  return (extras > 0) and ("Séquences " .. seq .. " à " .. (seq + extras)) or ("Séquence " .. seq)
end

local function renameLines(w, s, new)
  local nn = (new ~= "" and new ~= s.name) and new or "?"
  local c = songCounts(w, s)
  return table.concat({
    "Page " .. s.page .. " -> « " .. nn .. " »",
    "Séquence " .. s.seq .. " -> « " .. nn .. " »",
    "Notes -> « " .. nn .. " »",
    s.tag and ("Tag " .. s.tag .. " -> « " .. nn .. " »") or "Pas de tag à ce nom",
    s.tc and ("Timecode " .. s.tc .. " -> « " .. nn .. " »") or "Pas de timecode à ce nom",
    s.macro and ("Macro " .. s.macro .. " -> « " .. nn .. " »") or "Pas de macro à ce nom",
    c.cues .. " commande(s) de cue avec ce nom",
    c.macro .. " ligne(s) de macro avec ce nom",
    "Oops remet les noms, pas les commandes",
  }, "\n")
end

local function dupLines(s, d)
  local function q(x) return x and tostring(x) or "?" end
  local k = s.extras
  local t = {
    seqText(s.seq, k) .. " -> " .. q(d.seq) .. ((k > 0 and d.seq) and (" à " .. (d.seq + k)) or ""),
    "Page " .. s.page .. " -> " .. q(d.page),
    "Exec " .. execText(k, ", ") .. " sur la page " .. q(d.page),
    s.tc and ("Timecode " .. s.tc .. " -> " .. q(d.tcNo) .. ", liens rebranchés") or "Pas de timecode à copier",
    s.macro and ("Macro " .. s.macro .. " -> " .. q(d.macro)) or "Pas de macro à copier",
    d.tagNo and ("Tag " .. (s.tag and (s.tag .. " -> ") or "") .. d.tagNo) or "Pas de tag pour la copie",
    "Nom et notes « " .. ((d.name ~= "") and d.name or "?") .. " » partout",
    "Un Oops annule toute la copie",
  }
  return table.concat(t, "\n")
end

local function deleteLines(s)
  return table.concat({
    "Page " .. s.page .. " « " .. s.name .. " »",
    "Séquence " .. s.seq .. " (main)",
    (s.extras > 0) and ("Extras " .. (s.seq + 1) .. " à " .. (s.seq + s.extras)) or "Pas d'extras",
    s.tc and ("Timecode " .. s.tc) or "Pas de timecode à ce nom",
    s.macro and ("Macro " .. s.macro) or "Pas de macro à ce nom",
    s.tag and ("Tag " .. s.tag .. " « " .. s.name .. " »") or "Pas de tag à ce nom",
    "Un Oops remet toute la song",
  }, "\n")
end

-- Rafraîchit le panneau Song et le récap ; renvoie l'état pour le bouton principal
local function refreshSongMode(w)
  local s = w.song and resolveSong(w.song)
  if w.song and not s then w.lost = w.song.name end
  w.song = s
  showSongRow(w)
  local m, sp = w.mode, w.sp
  local newName = cleanName(sp.name.Content or "")
  sp.maName.Text = (m ~= "delete" and newName ~= "") and ("Nom dans MA : " .. newName) or ""
  if m == "dup" then setDupSlotsEnabled(w) end

  if not s then
    if m == "dup" then
      for _, sl in ipairs(SLOTS) do w.dup.status[sl.key].Text = "" end
    end
    setRecap(w, "")
    setAlert(w, "Choisis la song avec Song ▾.", "Global.LabelText")
    return { err = "pas de song" }
  end

  local outside = outsideText(songMembers(w, s), s)
  if m == "rename" then
    local err, color = checkNewName(newName, s)
    setRecap(w, renameLines(w, s, newName))
    if err then
      setAlert(w, err, color)
    else
      setAlert(w, outside and ("Prêt.\n" .. outside) or "Prêt.", "Global.SuccessText")
    end
    return { song = s, err = err, name = newName, busy = {} }

  elseif m == "dup" then
    local d = readDup(w)
    for _, sl in ipairs(SLOTS) do
      local txt, color
      if sl.key == "tcNo" and not s.tc then
        txt, color = "pas de timecode dans la song", "Global.Disabled"
      elseif sl.key == "macro" and not s.macro then
        txt, color = "pas de macro dans la song", "Global.Disabled"
      elseif sl.key == "tagNo" and not d.tagNo then
        txt, color = "vide : la copie n'aura pas de tag", "Global.LabelText"
      else
        txt, color = slotStatus(sl.pool, d[sl.key], (sl.key == "seq") and (1 + s.extras) or 1)
      end
      w.dup.status[sl.key].Text = txt
      quiet(w.dup.status[sl.key], "TextColor", color)
      quiet(w.dup.fields[sl.key], "TextColor", (color == "Global.WarningText") and color or "Global.Text")
    end
    local err, busy, color = validateDup(s, d)
    setRecap(w, dupLines(s, d))
    if err then
      setAlert(w, err, color or "Global.ErrorText")
    elseif #busy > 0 then
      setAlert(w, "Déjà occupé, sera écrasé : " .. table.concat(busy, ", ") .. "."
               .. (outside and ("\n" .. outside) or ""), "Global.WarningText")
    elseif outside then
      setAlert(w, outside, "Global.WarningText")
    else
      setAlert(w, "Prêt.", "Global.SuccessText")
    end
    return { song = s, err = err, busy = busy or {}, dup = d }
  end

  -- Supprimer
  setRecap(w, deleteLines(s))
  setAlert(w, "Toute la song sera supprimée. Un Oops la remet."
           .. (outside and ("\n" .. outside .. " Le tag est gardé.") or ""), "Global.WarningText")
  return { song = s, busy = {} }
end

local function runSetupWindow(w)
  ui.action, ui.dirty = nil, true
  local armed, lastSig, tick = false, nil, 0
  local appAsked = false   -- la liste des apparences ne s'ouvre qu'une fois
  w.restore = applyView
  applyView(w)
  setGo(w, "normal")

  local function refreshCreate()
    local input = readFields(w)
    local err, busy = validate(input)
    w.maName.Text = (input.name ~= "") and ("Nom dans MA : " .. input.name) or ""
    setRecap(w, recapLines(input))
    -- état de chaque emplacement à droite du numéro, numéro en orange si occupé
    for _, s in ipairs(SLOTS) do
      local txt, color
      if s.key == "tcNo" and not input.tcOn then
        txt, color = "pas de timecode", "Global.Disabled"
      elseif s.key == "tagNo" and not input.tagOn then
        txt, color = "pas de tag", "Global.Disabled"
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
      -- les songs se retrouvent par leur nom : un nom en double les mélangerait
      local users = nameUsers(input.name)
      if #users > 0 then
        t[#t + 1] = "Nom déjà porté par : " .. table.concat(users, ", ") .. "."
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
    return { input = input, err = err, busy = busy or {} }
  end

  local function refresh()
    if w.mode == "create" then return refreshCreate() end
    return refreshSongMode(w)
  end

  -- Résultat d'une opération : avertissements ou résumé dans le récap
  local function showResult(ok, warnings, summary, okText)
    if not ok then
      setAlert(w, "Erreur : " .. tostring(warnings), "Global.ErrorText")
    elseif #warnings > 0 then
      setAlert(w, okText .. ", avec avertissements (ci-dessus).", "Global.WarningText")
      setRecap(w, "- " .. table.concat(warnings, "\n- "))
    else
      setAlert(w, okText .. ".", "Global.SuccessText")
      if summary and #summary > 0 then setRecap(w, table.concat(summary, "\n")) end
    end
  end

  -- Après une opération : le résultat reste affiché, le bouton devient Fermer.
  -- Toucher à un champ, au mode ou à la song remet la fenêtre en saisie.
  local function hold()
    armed = false
    ui.action = nil   -- un clic fait pendant l'opération ne la relance pas
    w.countKey, w.memberKey = nil, nil
    setGo(w, "done")
    lastSig = signature(w)
  end

  while IsObjectValid(w.base) do
    -- rafraîchit le récap quand un champ change
    tick = tick + 1
    if ui.dirty or tick % 4 == 0 then
      local sig = signature(w)
      if ui.dirty or sig ~= lastSig then
        lastSig, ui.dirty = sig, false
        armed = false
        setGo(w, "normal")
        refresh()
      end
    end

    local a = ui.action
    ui.action = nil
    if a == "cancel" then
      break
    elseif a and a:find("^mode_") then
      local m = a:sub(6)
      if MODES[m] and m ~= w.mode then
        w.mode = m
        enterMode(w, false)
        applyView(w)
        ui.dirty = true
      end
    elseif a == "tc_toggle" and w.mode == "create" then
      w.tcOn = not w.tcOn
      setTcButton(w)
      ui.dirty = true
    elseif a == "tag_toggle" and w.mode == "create" then
      w.tagOn = not w.tagOn
      setTagButton(w)
      ui.dirty = true
    elseif a == "defaults" then
      if w.mode == "create" then
        local d = defaultValues()
        for _, k in ipairs(FIELD_ORDER) do
          if k ~= "name" then w.fields[k].Content = tostring(d[k]) end
        end
        w.tcOn, w.tagOn = true, true
        setTcButton(w)
        setTagButton(w)
      elseif w.song and w.mode == "rename" then
        w.sp.name.Content = w.song.name
        w.autoName = w.song.name
      elseif w.song and w.mode == "dup" then
        w.sp.name.Content = w.song.name .. "_copie"
        w.autoName = w.sp.name.Content
        setDupDefaults(w, w.song)
      end
      ui.dirty = true
    elseif a and PICK_FIELDS[a] and w.mode == "create" then
      local p = PICK_FIELDS[a]
      local input = readFields(w)
      local block = (p.field == "seq") and (1 + (input.extras or 0)) or 1
      local n = pickInSetup(w, p, input[p.field], block)
      -- un clic resté en attente pendant la liste ne doit pas agir ensuite
      -- (en 0.6.4, un clic sur une case grisée passait au bouton Annuler dessous)
      ui.action = nil
      if n and IsObjectValid(w.base) then
        w.fields[p.field].Content = tostring(n)
        ui.dirty = true
      end
    elseif a and DUP_PICK[a] and w.mode == "dup" and w.song then
      local p, s = DUP_PICK[a], w.song
      if not ((p.field == "tcNo" and not s.tc) or (p.field == "macro" and not s.macro)) then
        local block = (p.field == "seq") and (1 + s.extras) or 1
        local n = pickInSetup(w, p, toInt(w.dup.fields[p.field].Content), block, w.dup.pickBtn[p.field])
        ui.action = nil
        if n and IsObjectValid(w.base) then
          w.dup.fields[p.field].Content = tostring(n)
          ui.dirty = true
        end
      end
    elseif a == "pick_song" and w.mode ~= "create" then
      local s = pickSong(w)
      ui.action = nil
      if s and IsObjectValid(w.base) then
        local changed = not (w.song and w.song.page == s.page and w.song.name == s.name)
        w.song, w.lost = s, nil
        enterMode(w, changed)
        applyView(w)
      end
      ui.dirty = true

    elseif a == "go" and w.mode == "create" then
      local r = refresh()
      local input, err, busy = r.input, r.err, r.busy
      if not err and not appAsked and #missingAppearances(input) > 0 then
        appAsked = true
        resolveAppearances(input, w.createBtn)
        if not IsObjectValid(w.base) then break end
        r = refresh()
        input, err, busy = r.input, r.err, r.busy
      end
      if err then
        setAlert(w, err, "Global.ErrorText")
      elseif #busy > 0 and not armed then
        armed = true
        setAlert(w, "Déjà occupé : " .. table.concat(busy, ", ") .. ".\nAppuie encore pour écraser.",
                 "Global.WarningText")
        setGo(w, "armed")
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
        hold()
      end

    elseif a == "go" and w.mode == "rename" then
      local r = refresh()
      if r.song and not r.err then
        local old = r.song.name
        local ok, warnings, summary = pcall(renameSong, r.song, r.name)
        showResult(ok, warnings, summary, "Song « " .. old .. " » renommée en « " .. r.name .. " »")
        if ok then
          w.song = resolveSong({ page = r.song.page, name = r.name })
          w.autoName = r.name
        end
        showSongRow(w)
        hold()
      end

    elseif a == "go" and w.mode == "dup" then
      local r = refresh()
      if r.song and not r.err then
        if #r.busy > 0 and not armed then
          armed = true
          setAlert(w, "Déjà occupé : " .. table.concat(r.busy, ", ") .. ".\nAppuie encore pour écraser.",
                   "Global.WarningText")
          setGo(w, "armed")
        else
          local ok, warnings, summary = pcall(duplicateSong, r.song, r.dup)
          showResult(ok, warnings, summary,
                     "Song « " .. r.song.name .. " » dupliquée en « " .. r.dup.name .. " »")
          hold()
        end
      end

    elseif a == "go" and w.mode == "delete" then
      local r = refresh()
      if r.song and not armed then
        armed = true
        setAlert(w, "Appuie encore pour supprimer « " .. r.song.name .. " » (liste ci-dessus).",
                 "Global.ErrorText")
        setGo(w, "armed")
      elseif r.song then
        local ok, warnings, summary = pcall(deleteSong, r.song)
        showResult(ok, warnings, summary, "Song « " .. r.song.name .. " » supprimée")
        if ok then w.song, w.lost = nil, nil end
        showSongRow(w)
        hold()
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
      tagNo = input.tagNo or v.tagNo, tagOn = input.tagOn,
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

-- Point d'entrée protégé : toute erreur est écrite dans le System Monitor
-- et affichée, au lieu d'un plugin qui « ne fait rien ».
local function Main(displayHandle, argument)
  local okV, ver = pcall(Version)
  Printf("[SongCreator] demarrage v" .. VERSION .. " sur grandMA3 " .. (okV and tostring(ver) or "?"))
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
