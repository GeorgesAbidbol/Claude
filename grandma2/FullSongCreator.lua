--[[
  FULL SONG CREATOR - grandMA2 3.9.60
  Portage de la macro grandMA3 "FULL SONG CREATOR".

  Ce plugin sert uniquement a CREER un titre. La macro de titre qu'il genere
  est une macro MA2 classique : aucun plugin n'est utilise pendant le show.

  Pourquoi un plugin : en MA2 une $variable entre guillemets n'est pas
  remplacee, une macro ne peut donc pas ecrire 'Page "<nom>"' ni garder
  '$faderpage' tel quel dans une autre macro. Le plugin ecrit la macro de
  titre dans un fichier XML puis l'importe.
]]

-- ============================== REGLAGES ==============================
local EXEC_MAIN        = 16             -- executor de la sequence principale
local EXEC_EXTRA_FIRST = 121            -- executors des sequences extras
local EXEC_EXTRA_LAST  = 130
local SPEEDMASTER      = '3.1'          -- SpecialMaster qui recoit le BPM
-- Pages jamais eteintes par la macro de titre, en plus de la page du titre
-- ($faderpage / $buttonpage). Equivalent MA3 : "- Page 101 Thru 120".
local EXCLUSIONS       = '- 101 Thru 120'
-- Nom sans extension : MA2 ajoute .xml a l'Export et a l'Import.
local TMP_NAME         = 'FullSongCreator_tmp'
-- DEBUG = true : le fichier XML temporaire est conserve et son contenu
-- est affiche en ligne de commande, pour diagnostiquer l'import.
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
    if n and (not integer or n == math.floor(n)) then
      if integer then return math.floor(n) end
      return n
    end
    gma.gui.msgbox(TITLE, '"' .. r .. '" n\'est pas un nombre valide.')
  end
end

local function exists(obj)
  return gma.show.getobj.handle(obj) ~= nil
end

local function xmlEscape(s)
  return (s:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;'))
end

-- Meme structure qu'un Export Macro fait par la console (voir
-- ref_export_macro_3.9.60.xml) : index = numero de macro - 1.
local function writeMacroXml(path, macroNum, name, lines)
  local out = {
    '<?xml version="1.0" encoding="utf-8"?>',
    '<MA xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://schemas.malighting.de/grandma2/xml/MA" xsi:schemaLocation="http://schemas.malighting.de/grandma2/xml/MA http://schemas.malighting.de/grandma2/xml/3.9.60/MA.xsd" major_vers="3" minor_vers="9" stream_vers="60">',
    '\t<Info datetime="' .. os.date('%Y-%m-%dT%H:%M:%S') .. '" showfile="" />',
    '\t<Macro index="' .. (macroNum - 1) .. '" name="' .. xmlEscape(name) .. '">',
  }
  for i, text in ipairs(lines) do
    out[#out + 1] = '\t\t<Macroline index="' .. (i - 1) .. '">'
    out[#out + 1] = '\t\t\t<text>' .. xmlEscape(text) .. '</text>'
    out[#out + 1] = '\t\t</Macroline>'
  end
  out[#out + 1] = '\t</Macro>'
  out[#out + 1] = '</MA>'

  local f = io.open(path, 'w')
  if not f then return false end
  f:write(table.concat(out, '\n'), '\n')
  f:close()
  if DEBUG then
    log('XML ecrit : ' .. path)
    for _, l in ipairs(out) do log('  ' .. l) end
  end
  return true
end

-- Nombre de lignes de la macro (0 si elle n'existe pas).
local function macroLineCount(macroNum)
  local h = gma.show.getobj.handle('Macro ' .. macroNum)
  if not h then return nil end
  return gma.show.getobj.amount(h)
end

local function Start()
  -- 1. Questions (equivalent des SetUserVariable de la version MA3)
  local name = ask('Nom du titre ?')
  if not name then return end
  if name:find('"') then
    gma.gui.msgbox(TITLE, 'Le nom ne doit pas contenir de guillemets (").')
    return
  end
  local page = askNumber('Numero de page ?', true);                     if not page then return end
  local bpm = askNumber('BPM du titre ?', false);                        if not bpm then return end
  local seqMain = askNumber('Sequence principale ?', true);              if not seqMain then return end
  local exStart = askNumber('Premiere sequence extra ?', true);          if not exStart then return end
  local exEnd = askNumber('Derniere sequence extra ?', true);            if not exEnd then return end
  local macroNum = askNumber('Numero de la macro du titre ?', true);     if not macroNum then return end

  local nbExtras = exEnd - exStart + 1
  local maxExtras = EXEC_EXTRA_LAST - EXEC_EXTRA_FIRST + 1
  if nbExtras < 1 or nbExtras > maxExtras then
    gma.gui.msgbox(TITLE, 'Extras : de 1 a ' .. maxExtras .. ' sequences (executors '
      .. EXEC_EXTRA_FIRST .. ' a ' .. EXEC_EXTRA_LAST .. ').')
    return
  end
  if seqMain >= exStart and seqMain <= exEnd then
    gma.gui.msgbox(TITLE, 'La sequence principale ne peut pas faire partie des extras.')
    return
  end

  local recap = string.format(
    'Titre : %s|Page : %d|BPM : %s|Sequence principale : %d (exec %d)|Extras : %d a %d (exec %d a %d)|Macro : %d',
    name, page, tostring(bpm), seqMain, EXEC_MAIN, exStart, exEnd,
    EXEC_EXTRA_FIRST, EXEC_EXTRA_FIRST + nbExtras - 1, macroNum)
  if exists('Macro ' .. macroNum) then
    recap = recap .. '||ATTENTION : la macro ' .. macroNum .. ' existe deja et sera remplacee.'
  end
  if not gma.gui.confirm(TITLE, recap) then return end

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
  cmd('Assign ' .. S .. ' Cue 0.6 /trig=follow')
  cmd('Assign ' .. S .. ' Cue 0.7 /trig=follow')
  cmd('Assign ' .. S .. ' Cue 22 /trig=follow')
  cmd(string.format('Label %s "%s"', S, name))
  cmd(string.format('Assign %s At Executor %d.%d', S, page, EXEC_MAIN))

  -- 4. Extras (crees vides s'ils n'existent pas, jamais modifies sinon)
  for i = 0, nbExtras - 1 do
    local E = 'Sequence ' .. (exStart + i)
    if not exists(E) then
      cmd('Store ' .. E .. ' Cue 1 /nc')
    end
    cmd(string.format('Assign %s At Executor %d.%d', E, page, EXEC_EXTRA_FIRST + i))
  end

  -- 5. Macro de titre : appel par NOM de page, jamais par numero
  local lines = {
    string.format('Page "%s"', name),
    string.format('SetVar $currentSong = "%s"', name),
    'Off Page Thru - $faderpage - $buttonpage ' .. EXCLUSIONS,
    'Executor ' .. EXEC_MAIN .. ' At 100',
    'Select Executor ' .. EXEC_MAIN,
    'Goto Cue 0.5',
    'SpecialMaster ' .. SPEEDMASTER .. ' At ' .. tostring(bpm),
  }
  local path = gma.show.getvar('PATH') .. '/importexport/' .. TMP_NAME .. '.xml'
  if not writeMacroXml(path, macroNum, name, lines) then
    gma.gui.msgbox(TITLE, 'Impossible d\'ecrire ' .. path .. '|La macro de titre n\'a pas ete creee.')
    return
  end
  cmd('SelectDrive 1')
  if exists('Macro ' .. macroNum) then
    cmd('Delete Macro ' .. macroNum .. ' /nc')
  end
  cmd('Import "' .. TMP_NAME .. '" At Macro ' .. macroNum .. ' /nc')

  -- 6. Verification : la macro importee contient-elle bien ses lignes ?
  -- gma.cmd est asynchrone : on attend la fin de l'import (3 s max).
  local n
  for _ = 1, 15 do
    gma.sleep(0.2)
    n = macroLineCount(macroNum)
    if n == #lines then break end
  end
  log('Controle macro ' .. macroNum .. ' : '
    .. (n == nil and 'introuvable' or (n .. ' ligne(s) sur ' .. #lines .. ' attendue(s)')))

  if n ~= #lines then
    gma.gui.msgbox(TITLE,
      'La macro ' .. macroNum .. ' n\'a pas ete importee correctement|'
      .. (n == nil and 'Macro introuvable.' or (n .. ' ligne(s) au lieu de ' .. #lines .. '.')) .. '|'
      .. 'Fichier XML conserve : ' .. path .. '|'
      .. 'Detail dans la ligne de commande / System Monitor ([FSC]).')
    return
  end

  if not DEBUG then os.remove(path) end
  log('Titre "' .. name .. '" cree.')
end

return Start
