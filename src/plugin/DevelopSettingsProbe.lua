--[[

DevelopSettingsProbe.lua
Read-only diagnostic: dumps develop settings keys of the selected photo and
probes LrDevelopController for candidate keys. Never modifies the photo.

This file is part of MIDI2LR. Copyright 2015 by Rory Jaffe.

MIDI2LR is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later version.

MIDI2LR is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
MIDI2LR.  If not, see <http://www.gnu.org/licenses/>.
------------------------------------------------------------------------------]]

local LrApplication     = import 'LrApplication'
local LrApplicationView = import 'LrApplicationView'
local LrDevelopController = import 'LrDevelopController'
local LrDialogs         = import 'LrDialogs'
local LrPathUtils       = import 'LrPathUtils'
local LrShell           = import 'LrShell'
local LrTasks           = import 'LrTasks'

local patterns = {'denois', 'enhance', 'rawdetail', 'superres', 'reflection',
  'distraction', 'lensblur', 'pointcolor', 'colorvariance', 'ailook',
  'aisetting', 'noise', 'filter'}
local guesses = {'Denoise', 'DenoiseAmount', 'EnableDenoise', 'AIDenoise',
  'AIDenoiseAmount', 'EnhanceDenoise', 'EnhanceDenoiseAmount', 'RawDetails',
  'EnableRawDetails', 'SuperResolution', 'EnableSuperResolution',
  'ReflectionRemoval', 'ReflectionRemovalAmount', 'EnableReflectionRemoval',
  'EnableDistractionRemoval', 'LensBlurCatEye', 'ColorVariance', 'AILook', 'FilterList'}

local function isCandidate(key)
  local lower = tostring(key):lower()
  for _, p in ipairs(patterns) do
    if lower:find(p, 1, true) then return true end
  end
  return false
end

local function truncate(s)
  if #s > 400 then return s:sub(1, 400) .. '...' end
  return s
end

local function format(v)
  if type(v) == 'table' then
    local ok, res = pcall(function()
      local serpent = require 'serpent'
      return serpent.line(v, {comment = false, nocode = true, maxlevel = 4})
    end)
    return truncate(ok and tostring(res) or ('<serpent error: ' .. tostring(res) .. '>'))
  end
  return truncate(tostring(v))
end

local function formatFull(v)
  if type(v) == 'table' then
    local ok, res = pcall(function()
      local serpent = require 'serpent'
      return serpent.block(v, {comment = false, nocode = true, sortkeys = true, maxlevel = 12})
    end)
    return ok and tostring(res) or ('<serpent error: ' .. tostring(res) .. '>')
  end
  return tostring(v)
end

local function probe(key)
  local line = key .. ': '
  local ok, a = LrTasks.pcall(function() return LrDevelopController.getValue(key) end)
  line = line .. 'getValue ' .. (ok and ('ok ' .. format(a)) or ('ERR ' .. tostring(a)))
  local ok2, mn, mx = LrTasks.pcall(function() return LrDevelopController.getRange(key) end)
  line = line .. ' | getRange ' .. (ok2 and ('ok ' .. tostring(mn) .. ',' .. tostring(mx)) or ('ERR ' .. tostring(mn)))
  return line
end

local function run()
  local photo = LrApplication.activeCatalog():getTargetPhoto()
  if photo == nil then
    LrDialogs.message('Select a photo first')
    return
  end
  local settings = photo:getDevelopSettings()
  local module = LrApplicationView.getCurrentModuleName()
  local path = LrPathUtils.child(require('Utilities').applogpath(), 'DevelopSettingsDump.txt')
  local f = assert(io.open(path, 'w'))
  f:write('Lightroom version: ', tostring(LrApplication.versionString()), '\n')
  f:write('Date: ', os.date(), '\n')
  f:write('File: ', tostring(photo:getFormattedMetadata('fileName')), '\n')
  f:write('Module: ', tostring(module), '\n\n')

  local keys, cands = {}, {}
  for k in pairs(settings) do
    keys[#keys + 1] = tostring(k)
    if isCandidate(k) then cands[#cands + 1] = tostring(k) end
  end
  table.sort(keys)
  table.sort(cands)

  f:write('==== CANDIDATES ====\n')
  for _, k in ipairs(cands) do
    f:write(k, '\t', type(settings[k]), '\t', format(settings[k]), '\n')
  end

  f:write('\n==== API PROBE ====\n')
  if module == 'develop' then
    local seen, probeKeys = {}, {}
    for _, k in ipairs(cands) do
      if not seen[k] then seen[k] = true; probeKeys[#probeKeys + 1] = k end
    end
    for _, k in ipairs(guesses) do
      if not seen[k] then seen[k] = true; probeKeys[#probeKeys + 1] = k end
    end
    for _, k in ipairs(probeKeys) do f:write(probe(k), '\n') end
  else
    f:write('API probe skipped: not in Develop module. Rerun from the Develop module.\n')
  end

  f:write('\n==== FILTERLIST (full) ====\n')
  local okf, resf = pcall(function() return formatFull(settings.FilterList) end)
  f:write(okf and (settings.FilterList == nil and '<nil>' or resf) or ('ERR ' .. tostring(resf)), '\n')

  if module == 'develop' then
    f:write('\n==== FILTERLIST via getValue (full) ====\n')
    local okg, resg = LrTasks.pcall(function() return LrDevelopController.getValue('FilterList') end)
    if okg then
      f:write(resg == nil and '<nil>' or formatFull(resg), '\n')
    else
      f:write('ERR ', tostring(resg), '\n')
    end
  end

  f:write('\n==== ALL SETTINGS ====\n')
  for _, k in ipairs(keys) do
    f:write(k, '\t', type(settings[k]), '\t', format(settings[k]), '\n')
  end
  f:close()

  local summary = (#cands > 0) and ('Candidate keys: ' .. table.concat(cands, ', '))
    or 'no candidate keys found'
  LrDialogs.message('MIDI2LR develop settings dump', summary .. '\n\nFile: ' .. path)
  LrShell.revealInShell(path)
end

LrTasks.startAsyncTask(function()
  local ok, err = LrTasks.pcall(run)
  if not ok then
    LrDialogs.message('MIDI2LR develop settings dump failed', tostring(err))
  end
end)
