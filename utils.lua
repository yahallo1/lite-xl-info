local utils = {}

---@return lines without \n
function utils.lines(str)
  local lines = {}
  local i = 1
  while i <= #str do
    local sep = "\n"
    local j = str:find(sep, i)
    if j == nil then j = #str + 1 end
    table.insert(lines, str:sub(i, j-1))
    i = j+1
  end
  return lines
end 

function utils.trim(str)
  local start = string.find(str, "[^%s]") or 1
  local finish = string.find(string.reverse(str), "[^%s]") or 1
  return string.sub(str, start, #str - finish + 1)
end

function utils.append(dest, other)
  for i=1, #other do
    table.insert(dest, other[i])
  end
end

function utils.info_locate(str)
  local p = io.popen("info -w \""..str.."\"")
  local path = p:read("*line")
  p:close()
  return path
end

return utils
