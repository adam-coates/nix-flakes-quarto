--[[
  spinner — a fruit-machine style random draw for Quarto revealjs.

  Authoring:

      ::: {#draw .spinner groups="9" duration="6s" theme="casino"}
      - Topic one
      - Topic two
      :::

      ::: {.spinner-summary for="draw"}
      :::

  This filter only collects the options and the list items and hands them to
  the reveal plugin (spinner.js) as data-attributes. All behaviour lives there.
--]]

-- Options that may be set on the div, or globally under `spinner:` in the YAML
-- header. Kebab-case here, camelCase in JS via dataset.
local OPTIONS = {
  "groups", "group-label", "duration", "cycles", "blur", "sound",
  "rows", "row-height", "font-size", "theme", "accent", "results",
  "results-title", "keep-drawn", "shuffle-reel", "button-label", "label"
}

local doc_defaults = {}

local function esc_attr(s)
  s = s:gsub("&", "&amp;"):gsub('"', "&quot;"):gsub("<", "&lt;"):gsub(">", "&gt;")
  return s
end

local function json_string(s)
  s = s:gsub("\\", "\\\\"):gsub('"', '\\"')
  s = s:gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
  return '"' .. s .. '"'
end

local function json_array(items)
  local parts = {}
  for _, v in ipairs(items) do
    table.insert(parts, json_string(v))
  end
  return "[" .. table.concat(parts, ",") .. "]"
end

-- `spinner:` block in the document YAML supplies defaults for every spinner
local function get_meta(meta)
  local s = meta.spinner
  -- pandoc >= 2.17 hands a MetaMap over as a plain Lua table, so test the type
  -- rather than looking for a `.t` tag.
  if s == nil or type(s) ~= "table" then return nil end
  for _, key in ipairs(OPTIONS) do
    local v = s[key]
    if v ~= nil then
      doc_defaults[key] = pandoc.utils.stringify(v)
    end
  end
  return nil
end

-- pull the options list out of the div: every bullet / numbered item is one option
local function collect_options(blocks)
  local opts = {}
  for _, blk in ipairs(blocks) do
    if blk.t == "BulletList" or blk.t == "OrderedList" then
      for _, item in ipairs(blk.content) do
        local text = pandoc.utils.stringify(item)
        text = text:gsub("^%s+", ""):gsub("%s+$", "")
        if text ~= "" then table.insert(opts, text) end
      end
    elseif blk.t == "LineBlock" then
      for _, line in ipairs(blk.content) do
        local text = pandoc.utils.stringify(line)
        text = text:gsub("^%s+", ""):gsub("%s+$", "")
        if text ~= "" then table.insert(opts, text) end
      end
    end
  end
  return opts
end

local function data_attrs(el)
  local out = {}
  for _, key in ipairs(OPTIONS) do
    local v = el.attributes[key] or doc_defaults[key]
    if v ~= nil and v ~= "" then
      table.insert(out, string.format(' data-%s="%s"', key, esc_attr(v)))
    end
  end
  return table.concat(out)
end

local function spinner_div(el)
  local options = collect_options(el.content)

  if #options == 0 then
    quarto.log.warning(
      "[spinner] a .spinner div contains no list items — nothing to draw from.")
  end

  local id = el.identifier
  if id == nil or id == "" then id = "" end

  local html = string.format(
    '<div class="spinner-machine"%s data-options="%s"%s></div>',
    (id ~= "" and (' id="' .. esc_attr(id) .. '"') or ""),
    esc_attr(json_array(options)),
    data_attrs(el))

  return pandoc.RawBlock("html", html)
end

local function summary_div(el)
  local target = el.attributes["for"] or ""
  local title = el.attributes["title"] or ""
  local columns = el.attributes["columns"] or ""
  return pandoc.RawBlock("html", string.format(
    '<div class="spinner-summary" data-for="%s"%s%s></div>',
    esc_attr(target),
    (title ~= "" and (' data-title="' .. esc_attr(title) .. '"') or ""),
    (columns ~= "" and (' data-columns="' .. esc_attr(columns) .. '"') or "")))
end

local function Div(el)
  if not quarto.doc.is_format("revealjs") then return nil end
  if el.classes:includes("spinner") then return spinner_div(el) end
  if el.classes:includes("spinner-summary") then return summary_div(el) end
  return nil
end

return {
  { Meta = get_meta },
  { Div = Div }
}
