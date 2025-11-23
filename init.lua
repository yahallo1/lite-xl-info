-- mod-version:3
local core = require "core"
local common = require "core.common"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local View = require "core.view"
local command = require "core.command"
local process = require "core.process"
local Node = require "plugins.infoview.node"

local InfoView = View:extend()

function InfoView:__tostring() return "InfoView" end

function InfoView:new(file_name, node_name, line_number)
  InfoView.super.new(self)
  
  self.scrollable = true
  self.yoffset = 10
  
  self.stack = {}
  self.content_v_size = math.huge
  
  self:switch_to(file_name, node_name, line_number)
end

function InfoView.new_info(info)
  local view = InfoView(info)
  --view:switch_to_id(info)
  return view
end

function InfoView:get_name()
  if self.current_file then
    return "info: "..self.current_file
  else
    return "info"
  end
end

function InfoView:get_scrollable_size()
  return self.content_v_size
end

function InfoView:switch_to(file_name, node_name, line_number)
  if file_name == nil and node_name == nil and line_number == nil then return end
  if file_name == nil then file_name = self.current_file end
  if node_name == nil then node_name = "" end
  
  local p = io.popen("info --output=- \"("..file_name..")"..node_name.."\"")
  local text = p:read("*a")
  p:close()
  
  if text == "" then
    assert(false,  "info: Cannot find node ("..file_name..")"..node_name)
    return
  end
  
  self.scroll.y = 0
  self.scroll.to.y = 0
  self.current_file = file_name
  self.current_node = Node(text)
  table.insert(self.stack, {file=file_name, node=node_name, line=line_number})

  local n_lines = 1
  for _, span in ipairs(self.current_node.spans) do
    if span.type == "newline" then n_lines = n_lines + 1 end
  end
  self.content_v_size = n_lines * style.code_font:get_height()
end

function InfoView:on_mouse_pressed(button, x, y, clicks)
  if self.highlighted and not keymap.modkeys["ctrl"] then
    local link = self.highlighted
    self:switch_to(link.file, link.node, link.line)
  elseif self.highlighted and keymap.modkeys["ctrl"] then
    local link = self.highlighted
    local file = link.file or self.current_file
    local node = core.root_view:get_active_node_default()
    node:add_view(InfoView(file, link.node, link.line))
  end

  InfoView.super.on_mouse_pressed(self)
end

function InfoView:on_mouse_moved(x, y, dx, dy)
  if self.current_node == nil then return end

  local x0, y0 = self:get_content_offset()
  x0, y0 = x0 + style.padding.x, y0 + style.padding.y
  local charwidth, charheight = style.code_font:get_width(" "), style.code_font:get_height()
  local line, col = (y - y0) // charheight, (x - x0) // charwidth
  
  self.highlighted = nil
  local tx, ty = 0, 0
  for _, span in ipairs(self.current_node.spans) do
    if span.type == "newline" then
      tx = 0
      ty = ty + 1
      goto continue
    end
    
    if span.type == "link" and col >= tx and col < tx + #span.text and line == ty then
      self.highlighted = span.link
      break
    end
    
    tx = tx + #span.text

    ::continue::
  end

  InfoView.super.on_mouse_moved(self)
end

function InfoView:draw()
  self:draw_background(style.background)
  local x0, y0 = self:get_content_offset()
  x0, y0 = x0 + style.padding.x, y0 + style.padding.y
  local x1, y1 = x0 + self.size.x, y0 + self.size.y

  local x, y = x0, y0
  local tw, th = style.code_font:get_width(" "), style.code_font:get_height()
  if self.current_node == nil then return end

  for _, span in ipairs(self.current_node.spans) do
    if span.type == "text" then
        x = renderer.draw_text(style.code_font, span.text, x, y, style.syntax.normal)
    elseif span.type == "newline" then
        x = x0
        y = y + th
    elseif span.type == "link" then
        local text_color = style.syntax.normal
        if self.highlighted == span.link then
          renderer.draw_rect(x, y, style.code_font:get_width(span.text), style.code_font:get_height(), style.accent)
          text_color = style.background
        end
        local advx = renderer.draw_text(style.code_font, span.text, x, y, text_color)
        local advy = y + th
        renderer.draw_rect(x, advy-3, advx-x, 1, text_color)
        x = advx
    else
      assert(false)
    end
  end

  InfoView.super.draw_scrollbar(self)
end

command.add(nil, {
  ["core:open-info"] = function()
    core.command_view:enter("Entry name", {
      submit = function(text)
        local node = core.root_view:get_active_node_default()
        node:add_view(InfoView.new_info(text))
      end
    })
  end,
})

command.add(InfoView, {
  ["info:up-node"] = function(view)
    if view.current_node.up then
      view:switch_to(nil, view.current_node.up.node)
    end
  end,
  
  ["info:next-node"] = function(view)
    if view.current_node.next then
      view:switch_to(nil, view.current_node.next.node)
    end
  end,

  ["info:previous-node"] = function(view)
    if view.current_node.prev then
      view:switch_to(nil, view.current_node.prev.node)
    end
  end,

  ["info:go-back-node"] = function(view)
    if #view.stack > 1 then
      local to = view.stack[#view.stack - 1]
      view.stack[#view.stack] = nil
      view:switch_to(to.file, to.node, to.line)
      view.stack[#view.stack] = nil
    end
  end,
})

keymap.add({
  ["u"] = "info:up-node",
  ["p"] = "info:previous-node",
  ["n"] = "info:next-node",
  ["l"] = "info:go-back-node",
})


return InfoView
