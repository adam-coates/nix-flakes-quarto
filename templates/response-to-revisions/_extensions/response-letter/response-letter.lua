-- response-letter.lua
-- Handles both PDF (LaTeX) and DOCX output for the response letter template.
--
-- For PDF:  Div classes → LaTeX environments, Span classes → LaTeX commands
-- For DOCX: Applies color via OpenXML run properties directly on each inline,
--           because Pandoc's custom-style generates duplicate style defs that
--           strip the color from the reference doc styles.

-----------------------------------------------------------------------
-- PDF mappings
-----------------------------------------------------------------------
local div_envs = {
  ["reviewer-comment"] = "reviewer-comment",
  ["response"]         = "response",
  ["citation"]         = "manuscriptcitation",
  ["figcaption"]       = "figcaption",
  ["references"]       = "references",
}

local span_cmds = {
  ["response-inline"] = "responseinline",
  ["citation-inline"] = "citationinline",
}

-----------------------------------------------------------------------
-- DOCX color config
-----------------------------------------------------------------------
local div_docx_colors = {
  ["reviewer-comment"] = { color = "212121" },
  ["response"]         = { color = "2A6099" },
  ["citation"]         = { color = "729FCF", italic = true },
  ["figcaption"]       = { color = "2A6099" },
}

local span_docx_colors = {
  ["response-inline"] = { color = "2A6099" },
  ["citation-inline"] = { color = "729FCF", italic = true },
}

-----------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------
local function is_pdf()
  return quarto.doc.is_format("pdf") or quarto.doc.is_format("latex")
end

local function is_docx()
  return quarto.doc.is_format("docx")
end

-- Wrap inlines in raw OpenXML to force a specific font color
local function colorize_inlines(inlines, hex_color, italic)
  local open_rpr = '<w:rPr><w:color w:val="' .. hex_color .. '"/>'
  if italic then
    open_rpr = open_rpr .. '<w:i/><w:iCs/>'
  end
  open_rpr = open_rpr .. '</w:rPr>'

  -- We wrap each inline in its own run with the color applied.
  -- But raw OpenXML runs can't wrap Pandoc inlines directly.
  -- Instead, return a Span with custom-style won't work (duplicate style issue).
  --
  -- The reliable approach: use Pandoc's Span with direct attributes
  -- that the docx writer honors, plus a raw openxml wrapper.
  --
  -- Actually the simplest reliable approach for docx: wrap text in
  -- raw openxml <w:r> elements with the desired <w:rPr>.

  local result = pandoc.List({})

  for _, inline in ipairs(inlines) do
    if inline.t == "Str" then
      local xml = '<w:r>' .. open_rpr ..
        '<w:t xml:space="preserve">' .. inline.text:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;') ..
        '</w:t></w:r>'
      result:insert(pandoc.RawInline("openxml", xml))
    elseif inline.t == "Space" then
      local xml = '<w:r>' .. open_rpr ..
        '<w:t xml:space="preserve"> </w:t></w:r>'
      result:insert(pandoc.RawInline("openxml", xml))
    elseif inline.t == "SoftBreak" then
      result:insert(pandoc.RawInline("openxml",
        '<w:r>' .. open_rpr .. '<w:br/></w:r>'))
    elseif inline.t == "LineBreak" then
      result:insert(pandoc.RawInline("openxml",
        '<w:r>' .. open_rpr .. '<w:br/></w:r>'))
    elseif inline.t == "Strong" then
      -- Bold + color
      local bold_rpr = '<w:rPr><w:b/><w:bCs/><w:color w:val="' .. hex_color .. '"/>'
      if italic then
        bold_rpr = bold_rpr .. '<w:i/><w:iCs/>'
      end
      bold_rpr = bold_rpr .. '</w:rPr>'
      local strong_inlines = colorize_strong(inline.content, hex_color, italic)
      result:extend(strong_inlines)
    elseif inline.t == "Emph" then
      -- Italic + color
      local emph_rpr = '<w:rPr><w:i/><w:iCs/><w:color w:val="' .. hex_color .. '"/></w:rPr>'
      for _, child in ipairs(inline.content) do
        if child.t == "Str" then
          local xml = '<w:r>' .. emph_rpr ..
            '<w:t xml:space="preserve">' .. child.text:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;') ..
            '</w:t></w:r>'
          result:insert(pandoc.RawInline("openxml", xml))
        elseif child.t == "Space" then
          result:insert(pandoc.RawInline("openxml",
            '<w:r>' .. emph_rpr .. '<w:t xml:space="preserve"> </w:t></w:r>'))
        else
          -- Fallback: just insert as-is
          result:insert(child)
        end
      end
    elseif inline.t == "Link" then
      -- Keep links as-is (they have their own color)
      result:insert(inline)
    else
      -- Fallback for other inline types
      result:insert(inline)
    end
  end

  return result
end

-- Handle Strong (bold) content with color
function colorize_strong(inlines, hex_color, italic)
  local bold_rpr = '<w:rPr><w:b/><w:bCs/><w:color w:val="' .. hex_color .. '"/>'
  if italic then
    bold_rpr = bold_rpr .. '<w:i/><w:iCs/>'
  end
  bold_rpr = bold_rpr .. '</w:rPr>'

  local result = pandoc.List({})
  for _, child in ipairs(inlines) do
    if child.t == "Str" then
      local xml = '<w:r>' .. bold_rpr ..
        '<w:t xml:space="preserve">' .. child.text:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;') ..
        '</w:t></w:r>'
      result:insert(pandoc.RawInline("openxml", xml))
    elseif child.t == "Space" then
      result:insert(pandoc.RawInline("openxml",
        '<w:r>' .. bold_rpr .. '<w:t xml:space="preserve"> </w:t></w:r>'))
    else
      result:insert(child)
    end
  end
  return result
end

-----------------------------------------------------------------------
-- Div handler
-----------------------------------------------------------------------
function Div(el)
  if is_pdf() then
    for cls, env in pairs(div_envs) do
      if el.classes:includes(cls) then
        local begin_env = pandoc.RawBlock("latex", "\\begin{" .. env .. "}")
        local end_env   = pandoc.RawBlock("latex", "\\end{" .. env .. "}")
        local blocks = pandoc.List({begin_env})
        blocks:extend(el.content)
        blocks:insert(end_env)
        return blocks
      end
    end

  elseif is_docx() then
    for cls, cfg in pairs(div_docx_colors) do
      if el.classes:includes(cls) then
        local new_blocks = pandoc.List({})
        for _, block in ipairs(el.content) do
          if block.t == "Para" or block.t == "Plain" then
            local colored = colorize_inlines(block.content, cfg.color, cfg.italic)
            if block.t == "Para" then
              new_blocks:insert(pandoc.Para(colored))
            else
              new_blocks:insert(pandoc.Plain(colored))
            end
          else
            new_blocks:insert(block)
          end
        end
        return new_blocks
      end
    end
  end

  return el
end

-----------------------------------------------------------------------
-- Span handler
-----------------------------------------------------------------------
function Span(el)
  if is_pdf() then
    for cls, cmd in pairs(span_cmds) do
      if el.classes:includes(cls) then
        local raw_open  = pandoc.RawInline("latex", "\\" .. cmd .. "{")
        local raw_close = pandoc.RawInline("latex", "}")
        local inlines = pandoc.List({raw_open})
        inlines:extend(el.content)
        inlines:insert(raw_close)
        return inlines
      end
    end

  elseif is_docx() then
    for cls, cfg in pairs(span_docx_colors) do
      if el.classes:includes(cls) then
        return colorize_inlines(el.content, cfg.color, cfg.italic)
      end
    end
  end

  return el
end
