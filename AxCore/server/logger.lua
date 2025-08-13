Axiom = Axiom or {}

local LEVELS = { trace=1, debug=2, info=3, warn=4, error=5 }
local current = LEVELS[(Axiom.config and Axiom.config.log_level) or 'debug'] or LEVELS.debug

local function setLevel(name)
  local lvl = LEVELS[(name or ''):lower()]
  if lvl then current = lvl end
end

local function out(lvl, msg, ...)
  local want = LEVELS[lvl] or 99
  if want < current then return end
  msg = msg or ''
  local line = ('[Axiom][%s] %s'):format(lvl:upper(), msg)
  if select('#', ...) > 0 then line = line:format(...) end
  print(line)
end

function Axiom.audit(action, fmt, ...)
  local msg = fmt and string.format(fmt, ...) or ''
  print(('[Axiom][AUDIT] %-16s %s'):format(tostring(action), msg))
end

Axiom.log = setmetatable({}, {
  __index = function(_, k)
    return function(msg, ...) out(k, msg, ...) end
  end
})

exports(Axiom.ex.Log, function(level, msg, ...) out(level, msg, ...) end)
exports(Axiom.ex.SetLogLevel, function(levelName) setLevel(levelName) end)
exports(Axiom.ex.Audit, function(action, fmt, ...) Axiom.audit(action, fmt, ...) end)
