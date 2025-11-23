local Object = require "core.object"
local utils = require "plugins.infoview.utils"
local core = require "core"

local Node = Object:extend()

function Node:new(text)
  self.text = text

  self:parse()
end

function Node.split_into_lines(text)
  local lines = {}
  local i = 0
  while i <= #text do
    local j = text:find("\n", i, true)
    local t = text:sub(i, j and (j-1) or -1)
    if t ~= "" then
      table.insert(lines, { type="text", text = t })
    end
    if j then
      table.insert(lines, { type="newline"  })
    end
    i = (j or #text) + 1
  end
  
  return lines
end

function Node:parse_header()
  local headerline = self.text:sub(1, self.text:find("\n")-1)
  self.spans = {}
  
  local _, start, file = headerline:find("^File:%s+([^,]+),")

  local header = { file = file }
  local first = true
  for keyval in headerline:gmatch("([^,]+)", start+1) do
    local sep = string.find(keyval, ":")
    local key = utils.trim(string.sub(keyval, 1, sep-1))
    local val = utils.trim(string.sub(keyval, sep+1, -1))
    local link
    do
      local filename, nodename
      if val:sub(1,1) == "(" then
        filename, nodename = val:match("%((.+)%)([^,]+)")
        if filename == nil then
          filename = val:match("%((.+)%)")
        end
        core.log("%s %s", filename, nodename)
      else
        nodename = val:match("^([^,]*)?")
      end
      
      if filename then
        link = { file= filename }
        if nodename then
          link.node = utils.trim(nodename)
        end
      else
        link = { node = val }
      end

    end  
    
    header[key] = link

    if not first then
      table.insert(self.spans, { type = "text", text=", "  })
    end
    table.insert(self.spans, { type = "text", text=key..": "  })
    table.insert(self.spans, { type = "link", text=val, link = link })
    first = false
  end

  table.insert(self.spans, { type = "newline" })
  
  self.up = header.Up 
  self.next = header.Next
  self.prev = header.Prev
end

function Node:parse()
  self:parse_header()

  local text = self.text  
  local spans = self.spans

  local i = self.text:find("\n") + 1 -- skip the first line, which is the header
  local inside_menu = false
  local function into_link_lines(text, link, no_multiple_lines)
      local lines = Node.split_into_lines(text)
      if no_multiple_lines and #lines > 1 then
        for _, line in ipairs(lines) do
          table.insert(spans, line)
        end
        return
      end
        
      
      for _, line in ipairs(lines) do
        if line.type ~= "newline" then
          line.type = "link"
          line.link = link
        end
        table.insert(spans, line)
      end
  end

   local function add_lines(text)
      local lines = Node.split_into_lines(text)      
      for _, line in ipairs(lines) do
        table.insert(spans, line)
      end
  end
  
  while i <= #text do
    local start0 = text:find("*", i, true)
    if start0 == nil then
      utils.append(spans, Node.split_into_lines(text:sub(i,-1)))
      break
    end
    utils.append(spans, Node.split_into_lines(text:sub(i, start0-1)))

    -- *[Nn]ote <node-name>::
    local start, finish, node = text:find("%*[Nn]ote%s+([^:]+)::", start0)
    local is_found = start == start0
    if is_found then
      into_link_lines(text:sub(start, finish), { file = nil, line = nil, node = node  })
      i = finish + 1
      goto continue
    end
    
    -- *[Nn]ote <label>: (<file-name>)<node-name>.
    local start, finish, label, file, node = text:find("%*[Nn]ote%s+([^:]+):%s+%(([^%)]+)%)%s*([^%.,]+)[.,]", start0)
    local is_found = start == start0
    if is_found then
      into_link_lines(text:sub(start, finish), { file = file, line = nil, node = node })
      i = finish + 1
      goto continue
    end

    -- *[Nn]ote <label>: <node-name>.
    local start, finish, label, node = text:find("%*[Nn]ote%s+([^:]+):%s+([^%.,]+)[.,]", start0)
    local is_found = start == start0
    if is_found then
      into_link_lines(text:sub(start, finish), { file = nil, line = nil, node = node })
      i = finish + 1
      goto continue
    end
    
    local is_beginning_of_line = start0 == 0 or text:sub(start0-1, start0 - 1) == "\n"

    -- * Menu
    local start, finish = text:find("%* Menu", start0)
    local is_found = start == start0 and is_beginning_of_line
    if is_found then
      table.insert(spans, { type="text", text=text:sub(start, finish) })
      inside_menu = true
      i = finish + 1
      goto continue
    end
  
    --if not inside_menu then goto continue end
    
    -- * <node-name>::
    local start, finish, node = text:find("%*%s+([^:\n]+)::", start0)
    local is_found = start == start0 and is_beginning_of_line
    if is_found then
      into_link_lines(text:sub(start, finish), { file = nil, line = nil, node = node })
      i = finish + 1
      goto continue
    end
    
    -- * <label>: <node-name>. (line number)
    local start, finish, label, node, line_number = text:find("%*%s+([^:\n]+):%s+([^%.\n]+)%.%s+%(line%s+(%d+)%)", start0)
    local finish2 = text:find(":", start0)
    local is_found = start == start0
    if is_found then
      into_link_lines(text:sub(start, finish2), { file = nil, line = math.tointeger(line_number), node = node })
      add_lines(text:sub(finish2+1, finish))
      i = finish + 1
      goto continue
    end

    -- * <label>: (file)<node-name>.
    local start, finish, label, file, node = text:find("%*%s+([^:\n]+):%s+%(([^%)]+)%)%s*([^%.\n]+)%.", start0)
    local finish2 = text:find(":", start0)
    local is_found = start == start0 and is_beginning_of_line
    if is_found then
      into_link_lines(text:sub(start, finish2), { file = file, line = nil, node = node })
      add_lines(text:sub(finish2+1, finish))
      i = finish + 1
      goto continue
    end

    -- * <label>: (file).
    local start, finish, label, file = text:find("%*%s+([^:\n]+):%s+%(([^%)]+)%)%.", start0)
    local finish2 = text:find(":", start0)
    local is_found = start == start0 and is_beginning_of_line
    if is_found then
      into_link_lines(text:sub(start, finish2), { file = file, line = nil, node = nil })
      add_lines(text:sub(finish2+1, finish))
      i = finish + 1
      goto continue
    end

    -- * <label>: <node-name>.
    local start, finish, label, node = text:find("%*%s+([^:\n]+):%s+([^%.\n]+)%.", start0)
    local finish2 = text:find(":", start0)
    local is_found = start == start0 and is_beginning_of_line
    if is_found then
      --into_link_lines(text:sub(start, finish), { file = nil, line = nil, node = node })
      
      into_link_lines(text:sub(start, finish2), { file = nil, line = nil, node = node })
      add_lines(text:sub(finish2+1, finish))
      i = finish + 1
      goto continue
    end

    -- otherwise
    table.insert(spans, { type="text", text=text:sub(start0, start0) })
    i = start0 + 1
    
    ::continue::
  end
end

return Node
