-- The rules version of this copy of the game: the first 16 hex digits of the SHA-256 of
-- the files in online/manifest.lua. scripts/publish_rules.py computes the same value.
local Rules={}
-- read(path) returns the file's bytes; sha256(text) returns lower-case hex.
function Rules.version(read,sha256)
  local parts={}
  for _,entry in ipairs(require('online.manifest')) do
    local text=read(entry[2])
    if not text then return nil,'Missing rules file '..entry[2] end
    parts[#parts+1]=entry[1]..'\0'..text..'\0'
  end
  return sha256(table.concat(parts)):sub(1,16)
end
return Rules
