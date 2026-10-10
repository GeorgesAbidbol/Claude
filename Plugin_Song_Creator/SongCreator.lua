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

local VERSION = "0.3.0"

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

local function C(cmd)
  log[#log + 1] = cmd
  Printf("[SongCreator] " .. cmd)
  Cmd(cmd)
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
  [3] = { field = "page",  pool = "Pages",     title = "Choisir la page" },
  [4] = { field = "macro", pool = "Macros",    title = "Choisir la macro de rappel" },
  [5] = { field = "tcNo",  pool = "Timecodes", title = "Choisir le timecode" },
  [6] = { field = "seq",   pool = "Sequences", title = "Choisir la sequence main" },
}

-- Lit le pool : used[no] = nom, maxNo = plus grand numéro occupé.
local function readPool(poolName)
  local p = pool(poolName)
  local used, maxNo = {}, 0
  if p then
    for _, obj in ipairs(p:Children()) do
      local no = tonumber(obj.no)
      if no then
        used[no] = obj.name or ""
        if no > maxNo then maxNo = no end
      end
    end
  end
  return used, maxNo
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
--  Fenêtres sur mesure : barre de titre (on la fait glisser pour déplacer
--  la fenêtre), croix de fermeture en haut à droite, coin de
--  redimensionnement en bas à droite, taille de départ relative à l'écran.
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

-- rows : liste { {policy, size}, ... } pour le contenu sous la barre de titre.
local function makeWindow(overlay, name, title, dispW, dispH, ratioW, ratioH, rows)
  local base = overlay:Append("BaseInput")
  base.Name = name
  base.W = math.floor(dispW * ratioW)
  base.H = math.floor(dispH * ratioH)
  base.Columns, base.Rows = 1, 1 + #rows
  base[1][1].SizePolicy = "Fixed"; base[1][1].Size = "60"
  for i, r in ipairs(rows) do
    base[1][i + 1].SizePolicy = r[1]
    if r[2] then base[1][i + 1].Size = tostring(r[2]) end
  end
  opt(base, {
    MinSize = "600,400",
    MaxSize = math.floor(dispW) .. "," .. math.floor(dispH),
    AlignmentH = "Center", AlignmentV = "Center",
    AutoClose = "No", CloseOnEscape = "Yes",
  })

  local tb = base:Append("TitleBar")
  tb.Columns, tb.Rows = 2, 1
  tb.Anchors = cell(0, 0)
  tb[2][2].SizePolicy = "Fixed"; tb[2][2].Size = "60"
  opt(tb, { Texture = "corner2" })
  local tbt = tb:Append("TitleButton")
  tbt.Text = title
  tbt.Anchors = cell(0, 0)
  opt(tbt, { Texture = "corner1", Icon = "object_plugin1" })
  local close = tb:Append("CloseButton")
  close.Anchors = cell(1, 0)
  opt(close, { Texture = "corner2" })

  -- Coin de redimensionnement (bas droite)
  pcall(function()
    local rc = base:Append("ResizeCorner")
    rc.Anchors = cell(0, #rows)
    opt(rc, { AlignmentH = "Right", AlignmentV = "Bottom" })
  end)
  return base
end

local function closeWindow(overlay, base)
  if not IsObjectValid(base) then return end
  local ok = pcall(function() Obj.Delete(overlay, Obj.Index(base)) end)
  if not ok or IsObjectValid(base) then
    pcall(function() overlay:ClearUIChildren() end)
  end
end

local function addButton(parent, anchors, text, signal, value)
  local b = parent:Append("Button")
  b.Anchors = anchors
  b.Text = text
  opt(b, { Font = "Medium20", TextalignmentH = "Centre", Textshadow = 1, HasHover = "Yes",
           Margin = { left = 2, right = 2, top = 2, bottom = 2 } })
  if signal then
    b.PluginComponent = myHandle
    b.Clicked = signal
    if value then b.SignalValue = value end
  end
  return b
end

local function addText(parent, anchors, text)
  local t = parent:Append("UIObject")
  t.Anchors = anchors
  t.Text = text
  opt(t, { Font = "Medium20", TextalignmentH = "Left", TextalignmentV = "Top",
           Padding = { left = 10, right = 10, top = 6, bottom = 6 } })
  return t
end

-- ---- Fenêtre de sélection native MA (PopupInput) ----
-- Même fenêtre que les « Select ... » de la console : colonnes, filtre clavier.
-- Elle liste les objets existants du pool (« 12 'Nom' ») puis des numéros libres.
local FREE_SLOTS = 12

local function pickFromPool(poolName, title, current, block, caller)
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
    if not v[k] then return "Champ invalide : " .. F[k] end
  end
  if v.extras > CFG.maxExtras then return "Maximum " .. CFG.maxExtras .. " extras (executors 121 à 130)." end
  if v.cues < 1 then return "Il faut au moins 1 cue de song." end

  local busy = {}
  if exists("Pages", v.page) then busy[#busy + 1] = "Page " .. v.page end
  for s = v.seq, v.seq + v.extras do
    if exists("Sequences", s) then busy[#busy + 1] = "Sequence " .. s end
  end
  if exists("Macros", v.macro) then busy[#busy + 1] = "Macro " .. v.macro end
  if v.tcOn and exists("Timecodes", v.tcNo) then busy[#busy + 1] = "Timecode " .. v.tcNo end
  return nil, busy
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

-- Écrit la commande d'une cue via l'API Lua (pas de souci de guillemets
-- imbriqués). Selon la version, la commande vit sur la cue ou sur sa part 0.
local function setCueCommand(seqNo, cueName, command, warnings)
  local cue = findCueByName(seqNo, cueName)
  if not cue then
    warnings[#warnings + 1] = "Cue \"" .. cueName .. "\" introuvable"
    return
  end
  local ok = pcall(function() cue:Set("Command", command) end)
  if not ok then
    local part = cue[1]
    ok = part and pcall(function() part:Set("Command", command) end)
  end
  if ok then
    log[#log + 1] = "(lua) " .. cueName .. " : Command = " .. command
  else
    warnings[#warnings + 1] = "Commande non posée sur \"" .. cueName .. "\" : " .. command
  end
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
  -- Les lignes sont posées via l'API Lua : "$currentSong" reste tel quel
  -- (il n'est pas remplacé à la création comme dans l'ancienne macro).
  for i, text in ipairs(lines) do
    local line = macro[i] or macro:Append()
    if line then
      line:Set("Command", text)
      log[#log + 1] = "(lua) Macro " .. v.macro .. "." .. i .. " = " .. text
    else
      warnings[#warnings + 1] = "Ligne " .. i .. " de la macro non créée"
    end
  end
end

local function create(v)
  local warnings = {}
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
    C('Assign Appearance "' .. CFG.appExtras .. '" At Executor '
      .. CFG.execExtraFrom .. " Thru " .. (CFG.execExtraFrom + v.extras - 1))
  end
  C('Assign Configuration "' .. CFG.confMain .. '" At Executor ' .. CFG.execMain)
  C('Assign Appearance "' .. CFG.appMain .. '" At Executor ' .. CFG.execMain)

  -- 4. Cues de la séquence main (mêmes commandes que la macro d'origine)
  C("Select Executor " .. CFG.execMain)
  C('Store Cue 0.5 "Mise" /NoConfirmation')
  C('Store Cue 0.6 "Select Timecode" Property "TrigType" "Follow" /NoConfirmation')
  C('Store Cue 0.7 "Go Timecode" Property "TrigType" "Follow" /NoConfirmation')
  C("Store Cue 1 Thru " .. v.cues .. " /NoConfirmation")
  C("Store Cue " .. cueBO .. ' "Black Out" /NoConfirmation')
  C("Store Cue " .. cueOffTC .. ' "Off Timecode" Property "TrigType" "Follow" /NoConfirmation')
  C('Assign Appearance "' .. CFG.appTcCues .. '" At Cue 0.6 + 0.7 + ' .. cueOffTC)
  C('Assign Appearance "' .. CFG.appBlackOut .. '" At Cue ' .. cueBO)

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

  return warnings
end

-- ---------------------------------------------------------------------------
--  Fenêtre de setup sur mesure (écran 1, déplaçable, redimensionnable)
-- ---------------------------------------------------------------------------
local ui = {}
signalTable.SC_Action = function(caller) ui.action = caller.SignalValue end
signalTable.SC_Toggle = function(caller)
  caller.State = (tonumber(caller.State) == 1) and 0 or 1
  ui.dirty = true
end

local FIELD_ORDER = { "name", "page", "bpm", "macro", "seq", "extras", "cues", "tcNo" }

local function readFields(fields, tcBox)
  local raw = fields.name.Content or ""
  local v = { rawName = raw, name = cleanName(raw) }
  for _, k in ipairs(FIELD_ORDER) do
    if k ~= "name" then v[k] = toInt(fields[k].Content) end
  end
  v.tcOn = tonumber(tcBox.State) == 1
  return v
end

local function signature(fields, tcBox)
  local t = {}
  for _, k in ipairs(FIELD_ORDER) do t[#t + 1] = tostring(fields[k].Content) end
  t[#t + 1] = tostring(tcBox.State)
  return table.concat(t, "|")
end

-- Construit la fenêtre ; une erreur ici fait passer à la boîte MA de secours.
local function buildSetupWindow(v)
  local display, dispW, dispH = pickDisplay()
  local overlay = display.ScreenOverlay
  local base = makeWindow(overlay, "SongCreatorSetup", "Song Creator  v" .. VERSION,
                          dispW, dispH, 0.6, 0.7,
                          { { "Fixed", 60 }, { "Stretch" }, { "Fixed", 200 }, { "Fixed", 80 } })
  local w = { overlay = overlay, base = base, fields = {}, pickBtn = {} }

  w.msg = addText(base, cell(0, 1), "Remplis le setup puis appuie sur Creer la song.")

  -- Formulaire : chaque case de pool a son bouton « ... » qui ouvre
  -- la fenêtre de sélection native de MA, ancrée sur le bouton.
  local form = base:Append("UILayoutGrid")
  form.Columns, form.Rows = 4, 4
  form.Anchors = cell(0, 2)
  form[2][2].SizePolicy = "Fixed"; form[2][2].Size = "90"
  form[2][4].SizePolicy = "Fixed"; form[2][4].Size = "90"

  local function edit(key, prompt, anchors, numeric)
    local e = form:Append("LineEdit")
    e.Anchors = anchors
    e.Content = tostring(v[key] or "")
    opt(e, { Prompt = prompt .. " : ", Padding = "5,5",
             Margin = { left = 2, right = 2, top = 2, bottom = 2 },
             VkPluginName = numeric and "TextInputNumOnly" or "TextInput",
             MaxTextLength = numeric and 5 or 60 })
    if numeric then opt(e, { Filter = "0123456789" }) end
    w.fields[key] = e
  end
  local function picker(key, col, row)
    w.pickBtn[key] = addButton(form, cell(col, row), "...", "SC_Action", "pick_" .. key)
  end

  edit("name",   "Nom de la song",  cell(0, 0, 3), false)
  edit("page",   "Page",            cell(0, 1), true);  picker("page", 1, 1)
  edit("macro",  "Macro de rappel", cell(2, 1), true);  picker("macro", 3, 1)
  edit("seq",    "Sequence main",   cell(0, 2), true);  picker("seq", 1, 2)
  edit("tcNo",   "N° timecode",     cell(2, 2), true);  picker("tcNo", 3, 2)

  local opts = form:Append("UILayoutGrid")
  opts.Columns, opts.Rows = 4, 1
  opts.Anchors = cell(0, 3, 3)
  local function edit2(key, prompt, col)
    local e = opts:Append("LineEdit")
    e.Anchors = cell(col, 0)
    e.Content = tostring(v[key] or "")
    opt(e, { Prompt = prompt .. " : ", Padding = "5,5",
             Margin = { left = 2, right = 2, top = 2, bottom = 2 },
             VkPluginName = "TextInputNumOnly", MaxTextLength = 5, Filter = "0123456789" })
    w.fields[key] = e
  end
  edit2("bpm",    "BPM",           0)
  edit2("extras", "Extras (0-10)", 1)
  edit2("cues",   "Cues de song",  2)

  local tc = opts:Append("CheckBox")
  tc.Anchors = cell(3, 0)
  tc.Text = "Creer le timecode"
  tc.State = v.tcOn and 1 or 0
  tc.PluginComponent = myHandle
  tc.Clicked = "SC_Toggle"
  w.tcBox = tc

  w.recap = addText(base, cell(0, 3), "")

  local btns = base:Append("UILayoutGrid")
  btns.Columns, btns.Rows = 2, 1
  btns.Anchors = cell(0, 4)
  w.createBtn = addButton(btns, cell(0, 0), "Creer la song", "SC_Action", "create")
  addButton(btns, cell(1, 0), "Annuler", "SC_Action", "cancel")
  return w
end

local PICK_FIELDS = {
  pick_page  = { field = "page",  pool = "Pages",     title = "Select Page" },
  pick_macro = { field = "macro", pool = "Macros",    title = "Select Macro" },
  pick_seq   = { field = "seq",   pool = "Sequences", title = "Select Sequence" },
  pick_tcNo  = { field = "tcNo",  pool = "Timecodes", title = "Select Timecode" },
}

local function runSetupWindow(w)
  ui.action, ui.dirty = nil, true
  local armed, finished, lastSig, tick = false, false, nil, 0

  local function refresh()
    local input = readFields(w.fields, w.tcBox)
    local err, busy = validate(input)
    if err then
      w.recap.Text = "/!\\ " .. err
    else
      w.recap.Text = recapText(input, busy)
    end
    return input, err, busy
  end

  while IsObjectValid(w.base) do
    -- rafraîchit le récapitulatif quand un champ change
    tick = tick + 1
    if not finished and (ui.dirty or tick % 4 == 0) then
      local sig = signature(w.fields, w.tcBox)
      if ui.dirty or sig ~= lastSig then
        lastSig, ui.dirty = sig, false
        refresh()
        if armed then armed = false; w.createBtn.Text = "Creer la song" end
      end
    end

    local a = ui.action
    ui.action = nil
    if a == "cancel" then
      break
    elseif a and PICK_FIELDS[a] then
      local p = PICK_FIELDS[a]
      local input = readFields(w.fields, w.tcBox)
      local block = (p.field == "seq") and (1 + (input.extras or 0)) or 1
      local n = pickFromPool(p.pool, p.title, input[p.field], block, w.pickBtn[p.field])
      if n and IsObjectValid(w.base) then
        w.fields[p.field].Content = tostring(n)
        ui.dirty = true
      end
    elseif a == "create" then
      local input, err, busy = refresh()
      if err then
        w.msg.Text = "/!\\ " .. err
      elseif #busy > 0 and not armed then
        armed = true
        w.msg.Text = "/!\\ Deja occupe : " .. table.concat(busy, ", ")
                  .. ". Appuie encore pour ecraser."
        w.createBtn.Text = "Ecraser et creer"
      else
        local ok, res = pcall(create, input)
        if not ok then
          w.msg.Text = "Erreur pendant la creation : " .. tostring(res)
        elseif #res > 0 then
          w.msg.Text = 'Song "' .. input.name .. '" creee, avec avertissements (voir ci-dessous).'
          w.recap.Text = "- " .. table.concat(res, "\n- ")
        else
          w.msg.Text = 'Song "' .. input.name .. '" creee.'
        end
        finished = true
        w.createBtn.Text = "Fermer"
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
  Printf("[SongCreator] demarrage v" .. VERSION)
  local ok, err = xpcall(RealMain, debug.traceback, displayHandle, argument)
  if not ok then
    ErrPrintf("[SongCreator] ERREUR : " .. tostring(err))
    pcall(MessageBox, { title = "Song Creator - erreur", message = tostring(err),
                        commands = { { value = 1, name = "OK" } } })
  end
  Printf("[SongCreator] fin")
end

return Main
