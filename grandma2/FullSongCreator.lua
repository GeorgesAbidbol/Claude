--[[
  FULL SONG CREATOR - grandMA2 3.9.60
  Portage de la macro grandMA3 "FULL SONG CREATOR".

  Ce plugin sert uniquement a CREER un titre. La macro de titre qu'il genere
  est une macro MA2 classique : aucun plugin n'est utilise pendant le show.

  La macro de titre est creee directement dans le show, ligne par ligne
  (Store / Assign /cmd), comme dans la version grandMA3. Chaque ligne est
  ensuite relue pour verifier ce que la console a reellement stocke.
]]

-- ============================== REGLAGES ==============================
local EXEC_MAIN        = 16             -- executor de la sequence principale
local EXEC_MAIN_WIDTH  = 2              -- largeur de cet executor (1 a 5 faders)
local EXEC_EXTRA_FIRST = 121            -- executors des sequences extras
local EXEC_EXTRA_LAST  = 130
local SPEEDMASTER      = '3.1'          -- SpecialMaster qui recoit le BPM
-- Pages jamais eteintes par la macro de titre, en plus de la page du titre
-- ($faderpage / $ButtonPage) : fin de la derniere ligne de la macro.
local EXCLUSIONS       = '- 101 Thru - 1'
-- DEBUG = true : detail de chaque ligne relue dans la ligne de commande.
local DEBUG            = true
-- ======================================================================

local TITLE = 'FULL SONG CREATOR'

-- gma.echo n'ecrit que dans le System Monitor ; gma.feedback ecrit dans
-- la ligne de commande. On ecrit dans les deux pour voir ce qui s'execute.
local function log(msg)
  gma.echo('[FSC] ' .. msg)
  gma.feedback('[FSC] ' .. msg)
end

local function cmd(c)
  log(c)
  gma.cmd(c)
end

local function trim(s)
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Retourne nil si l'operateur annule ou laisse vide.
local function ask(title)
  local r = gma.textinput(title, '')
  if r == nil then return nil end
  r = trim(r)
  if r == '' then return nil end
  return r
end

local function askNumber(title, integer)
  while true do
    local r = ask(title)
    if r == nil then return nil end
    local n = tonumber(r)
    if n and n > 0 and (not integer or n == math.floor(n)) then
      if integer then return math.floor(n) end
      return n
    end
    -- 0 est refuse : "Macro 1.0", "Page 0"... n'existent pas.
    gma.gui.msgbox(TITLE, '"' .. r .. '" n\'est pas valide : nombre superieur a 0 attendu.')
  end
end

local function exists(obj)
  return gma.show.getobj.handle(obj) ~= nil
end

-- Adresse MA2 d'une macro (pool 1 = Global) ou d'une de ses lignes.
local function macroAddr(macroNum, line)
  if line then return 'Macro 1.' .. macroNum .. '.' .. line end
  return 'Macro 1.' .. macroNum
end

-- Texte de commande (propriete CMD) reellement stocke dans un objet.
-- Les proprietes sont cherchees par nom pour ne pas dependre de leur ordre.
local function readCmd(addr)
  local h = gma.show.getobj.handle(addr)
  if not h then return nil end
  local p = gma.show.property
  for i = 0, p.amount(h) - 1 do
    local pname = (p.name(h, i) or ''):lower()
    if pname == 'command' or pname == 'cmd' then
      return p.get(h, i)
    end
  end
  return ''
end

local function readMacroLine(macroNum, line)
  return readCmd(macroAddr(macroNum, line))
end

-- La console renvoie le texte relu avec des codes couleur : on les retire
-- (et la casse / les espaces) avant de comparer.
local function clean(s)
  s = s:gsub('\27%[[%d;]*%a', ''):gsub('%c', '')
  s = s:gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
  return s:lower()
end

-- Texte brut avec les caracteres non imprimables affiches en <code>.
local function visible(s)
  return (s:gsub('[^\32-\126]', function(c) return '<' .. c:byte() .. '>' end))
end

local function run()
  -- 1. Questions (equivalent des SetUserVariable de la version MA3)
  local name = ask('Nom du titre ?')
  if not name then return end
  if name:find('["\']') then
    gma.gui.msgbox(TITLE, 'Le nom ne doit contenir ni " ni \'.')
    return
  end
  local page = askNumber('Numero de page ?', true);                     if not page then return end
  local bpm = askNumber('BPM du titre ?', false);                        if not bpm then return end
  local seqMain = askNumber('Sequence principale ?', true);              if not seqMain then return end
  -- Extras : en cas d'erreur, on explique et on redemande (au lieu d'arreter).
  local maxExtras = EXEC_EXTRA_LAST - EXEC_EXTRA_FIRST + 1
  local exStart, exEnd, nbExtras
  while true do
    exStart = askNumber('Premiere sequence extra ?', true);              if not exStart then return end
    exEnd = askNumber('Derniere sequence extra ?', true);                if not exEnd then return end
    nbExtras = exEnd - exStart + 1
    local problem
    if nbExtras < 1 then
      problem = 'la derniere sequence (' .. exEnd .. ') est avant la premiere (' .. exStart .. ').'
    elseif nbExtras > maxExtras then
      problem = exStart .. ' a ' .. exEnd .. ' = ' .. nbExtras .. ' sequences, maximum '
        .. maxExtras .. ' (executors ' .. EXEC_EXTRA_FIRST .. ' a ' .. EXEC_EXTRA_LAST .. ').'
    elseif seqMain >= exStart and seqMain <= exEnd then
      problem = 'la sequence principale (' .. seqMain .. ') est dans la plage ' .. exStart .. ' a ' .. exEnd .. '.'
    end
    if not problem then break end
    log('Extras refuses : ' .. problem)
    gma.gui.msgbox(TITLE, 'Extras : ' .. problem .. '|Saisis a nouveau les sequences extras.')
  end
  local macroNum = askNumber('Numero de la macro du titre ?', true);     if not macroNum then return end

  local recap = string.format(
    'Titre : %s|Page : %d|BPM : %s|Sequence principale : %d (exec %d)|Extras : %d a %d (exec %d a %d)|Macro : %d',
    name, page, tostring(bpm), seqMain, EXEC_MAIN, exStart, exEnd,
    EXEC_EXTRA_FIRST, EXEC_EXTRA_FIRST + nbExtras - 1, macroNum)
  if exists(macroAddr(macroNum)) then
    recap = recap .. '|ATTENTION : macro ' .. macroNum .. ' deja existante, elle sera remplacee'
  end
  log('Reponses : titre="' .. name .. '" page=' .. page .. ' bpm=' .. tostring(bpm)
    .. ' seq=' .. seqMain .. ' extras=' .. exStart .. '-' .. exEnd .. ' macro=' .. macroNum)
  local confirmed = gma.gui.confirm(TITLE, recap)
  log('Recapitulatif : ' .. tostring(confirmed) .. ' (' .. type(confirmed) .. ')')
  if not confirmed then return end

  -- 2. Page
  if not exists('Page ' .. page) then
    cmd('Store Page ' .. page)
  end
  cmd('Page ' .. page)
  cmd(string.format('Label Page %d "%s"', page, name))

  -- 3. Sequence principale et ses cues
  local S = 'Sequence ' .. seqMain
  cmd('Store ' .. S .. ' Cue 0.5 /nc')
  cmd('Store ' .. S .. ' Cue 0.6 /nc')
  cmd('Store ' .. S .. ' Cue 0.7 /nc')
  cmd('Store ' .. S .. ' Cue 1 Thru 20 /nc')
  cmd('Store ' .. S .. ' Cue 21 /nc')
  cmd('Store ' .. S .. ' Cue 22 /nc')
  cmd('Label ' .. S .. ' Cue 0.5 "Mise"')
  cmd('Label ' .. S .. ' Cue 0.6 "Select Timecode"')
  cmd('Label ' .. S .. ' Cue 0.7 "Go Timecode"')
  cmd('Label ' .. S .. ' Cue 21 "Black Out"')
  cmd('Label ' .. S .. ' Cue 22 "Off Timecode"')
  -- Commandes des cues timecode avec le titre entre apostrophes.
  -- MA2 n'accepte pas de " dans /cmd="..." (ni /cmd='...', teste sur
  -- console) : les " sont a remettre a la main dans la sequence.
  local cueCmds = {
    { '0.6', "Select Timecode '" .. name .. "'" },
    { '0.7', "Go Timecode '" .. name .. "'" },
    { '22',  "Off Timecode '" .. name .. "'" },
  }
  for _, c in ipairs(cueCmds) do
    cmd(string.format('Assign %s Cue %s /cmd="%s"', S, c[1], c[2]))
  end
  cmd('Assign ' .. S .. ' Cue 0.6 /trig=follow')
  cmd('Assign ' .. S .. ' Cue 0.7 /trig=follow')
  cmd('Assign ' .. S .. ' Cue 22 /trig=follow')
  cmd(string.format('Label %s "%s"', S, name))
  cmd(string.format('Assign %s At Executor %d.%d', S, page, EXEC_MAIN))
  cmd(string.format('Assign Executor %d.%d /width=%d', page, EXEC_MAIN, EXEC_MAIN_WIDTH))

  -- 4. Extras (crees vides s'ils n'existent pas, jamais modifies sinon)
  for i = 0, nbExtras - 1 do
    local E = 'Sequence ' .. (exStart + i)
    if not exists(E) then
      cmd('Store ' .. E .. ' Cue 1 /nc')
    end
    cmd(string.format('Assign %s At Executor %d.%d', E, page, EXEC_EXTRA_FIRST + i))
  end

  -- 5. Macro de titre : appel par NOM de page, jamais par numero.
  -- MA2 n'accepte pas de " a l'interieur de /cmd="..." : le nom de la
  -- page est donc entre apostrophes.
  local lines = {
    string.format("Page '%s'", name),
    'Select Executor ' .. EXEC_MAIN,
    'Executor ' .. EXEC_MAIN .. ' At 100',
    'SpecialMaster ' .. SPEEDMASTER .. ' At ' .. tostring(bpm),
    'Goto Cue 0.5',
    'Off Page Thru - $faderpage - $ButtonPage ' .. EXCLUSIONS,
  }
  local M = macroAddr(macroNum)
  if exists(M) then
    cmd('Delete ' .. M .. ' /nc')
  end
  cmd('Store ' .. M)
  cmd(string.format('Label %s "%s"', M, name))
  for i, text in ipairs(lines) do
    cmd('Store ' .. macroAddr(macroNum, i))
    cmd(string.format('Assign %s /cmd="%s"', macroAddr(macroNum, i), text))
  end

  -- 6. Verification : relecture de chaque ligne stockee
  gma.sleep(0.3)  -- gma.cmd est asynchrone
  -- Les commandes des cues ne sont pas relues : la console ne les expose pas
  -- sur l'objet cue (relecture toujours vide alors qu'elles sont inscrites).
  local errors = {}
  for i, text in ipairs(lines) do
    local got = readMacroLine(macroNum, i)
    local ok = got ~= nil and clean(got) == clean(text)
    log(string.format('Ligne %d %s : %s', i, ok and 'OK' or 'ERREUR',
      got == nil and '(absente)' or got))
    if not ok and DEBUG and got then log('    brut : ' .. visible(got)) end
    if not ok then
      errors[#errors + 1] = 'Ligne ' .. i .. ' attendue : ' .. text
    end
  end

  if #errors > 0 then
    gma.gui.msgbox(TITLE, #errors .. ' commande(s) incorrecte(s)|'
      .. table.concat(errors, '|') .. '||Detail dans la ligne de commande ([FSC]).')
    return
  end

  log('Titre "' .. name .. '" cree.')
end

-- Toute erreur Lua est affichee a l'ecran au lieu d'arreter le plugin
-- sans rien dire.
local function Start()
  log('Demarrage')
  local ok, err = pcall(run)
  if not ok then
    log('ERREUR Lua : ' .. tostring(err))
    gma.gui.msgbox(TITLE, 'Erreur Lua :|' .. tostring(err))
  end
end

return Start
