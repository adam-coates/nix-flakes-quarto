-- Turn a deck into the Moodle handout. Runs for plate-pdf only; every function
-- below returns early in any other format, so the same source still renders to
-- revealjs untouched.
--
-- Two jobs:
--
--   1. Take out what only makes sense on a screen. A slide carries things the
--      handout must not: speaker notes (written to be said, not read, and often
--      blunter than anything you would hand a student), live poll widgets, the
--      countdown timer. Pandoc has no idea these are stage furniture — left
--      alone, the notes for the Moodle slide land in the PDF as body text.
--
--   2. Carry the brand into LaTeX. _brand.yml is the single source of truth for
--      colour, and quarto.brand can read it at render time, so the preamble gets
--      \definecolor lines rather than a second copy of the palette that drifts.

local session_support = require("session")

-- Loaded once, at first use: the recording of the class this deck was given in,
-- if there is one beside the deck. nil for a handout produced before the class,
-- which is the ordinary case and must stay the fast, unchanged one.
local session = nil
local session_loaded = false

local function is_handout()
  return quarto.doc.is_format("pdf") or quarto.doc.is_format("latex")
end

local function current_session()
  if not session_loaded then
    session_loaded = true
    session = session_support.load()
  end
  return session
end

-- ---------------------------------------------------------------- deck-only

-- Classes that exist to drive Reveal and have no meaning on paper. `.notes` is
-- Quarto's speaker-note div; the poll pair belongs to the livepoll extension.
local drop_classes = {
  notes = true,
  poll = true,
  ["poll-results"] = true,
  -- A word cloud is one div that both asks and displays, so unlike a poll there
  -- is no separate results block to drop. Take the whole thing: what belongs in
  -- the handout is the words the room actually gave, which arrive from
  -- session.json and carry the question with them.
  wordcloud = true,
  -- A rating scale is the same: the question and its buttons are for the room.
  likert = true,
  ["poll-qr"] = true,
}

-- Removing the div is only half the job: a slide whose whole content was a poll
-- widget or a results chart leaves its heading behind, and the handout gets a
-- page with a title and nothing under it. So rather than deleting outright,
-- leave a marker where the widget was — the document pass below uses it to tell
-- "this slide is empty because we emptied it" from "this slide is empty in the
-- source", which are not the same thing and must not be treated alike.
local REMOVED = "plate-removed"

function Div(div)
  if not is_handout() then
    return nil
  end

  for class in pairs(drop_classes) do
    if div.classes:includes(class) then
      return pandoc.Div({}, pandoc.Attr("", { REMOVED }))
    end
  end

  -- Reveal's .columns/.column → LaTeX minipages so the handout keeps the
  -- side-by-side layout the slides have.
  if div.classes:includes("columns") then
    local cols = {}
    local rest = pandoc.Blocks({})

    for _, block in ipairs(div.content) do
      if block.t == "Div" and block.classes:includes("column") then
        table.insert(cols, block)
      else
        rest:insert(block)
      end
    end

    if #cols == 0 then
      return nil
    end

    local widths = {}
    for i, col in ipairs(cols) do
      local w = col.attributes.width
      local frac = (1 / #cols) - 0.02
      if w then
        local pct = w:match("(%d+)%%")
        if pct then
          frac = tonumber(pct) / 100 - 0.02
        end
      end
      widths[i] = frac
    end

    local out = pandoc.Blocks({})
    out:insert(pandoc.RawBlock("latex",
      string.format("\\noindent\\begin{minipage}[t]{%.2f\\textwidth}\\vspace{0pt}\\RaggedRight",
        widths[1])))
    out:extend(cols[1].content)

    for i = 2, #cols do
      out:insert(pandoc.RawBlock("latex",
        string.format(
          "\\end{minipage}%%\\hfill%%\n\\begin{minipage}[t]{%.2f\\textwidth}\\vspace{0pt}\\RaggedRight",
          widths[i])))
      out:extend(cols[i].content)
    end

    out:insert(pandoc.RawBlock("latex", "\\end{minipage}"))
    out:extend(rest)
    return out
  end

  return nil
end

local function is_marker(block)
  return block.t == "Div" and block.classes:includes(REMOVED)
end

-- Drop the heading of any slide left holding nothing but markers, and clear the
-- markers everywhere else.
--
-- Deliberately narrow. A heading with no content that we did *not* empty is left
-- alone, because it is not necessarily empty yet: `## References` carries no
-- blocks at this point and has its bibliography appended later, and dropping it
-- here would strand the references under no heading at all. Same for a divider
-- like `# Course`, which owns the slides that follow rather than any content of
-- its own — hence the check that the next heading is not a child.
local function prune_emptied_slides(doc)
  local out = pandoc.Blocks({})
  local blocks = doc.blocks
  local i = 1

  while i <= #blocks do
    local block = blocks[i]

    if block.t == "Header" then
      -- Everything up to the next heading at this level or above is this
      -- slide's own content.
      local j = i + 1
      local emptied, kept = false, false

      while j <= #blocks and not (blocks[j].t == "Header" and blocks[j].level <= block.level) do
        if is_marker(blocks[j]) then
          emptied = true
        else
          kept = true
        end
        j = j + 1
      end

      -- A child heading means this is a divider, not an empty slide.
      local has_children = j <= #blocks and blocks[j].t == "Header" and blocks[j].level > block.level

      if emptied and not kept and not has_children then
        i = j -- skip the heading and its markers alike
      else
        out:insert(block)
        i = i + 1
      end
    elseif is_marker(block) then
      i = i + 1
    else
      out:insert(block)
      i = i + 1
    end
  end

  doc.blocks = out
  return doc
end

-- The document-level pass. Runs after the per-element filters above have taken
-- the deck-only material out, so what session.lua inserts is the last thing on
-- each slide rather than sitting next to a poll widget it just removed.
--
-- Order matters between the two steps: the session's results are inserted first,
-- so a poll slide that has results to show still counts as having content and
-- keeps its heading. Without a recording the same slide holds only a marker and
-- goes entirely, which is right — there is nothing to print.
function Pandoc(doc)
  if not is_handout() then
    return nil
  end

  local recording = current_session()
  if recording then
    doc = session_support.apply(doc, recording)
  end

  return prune_emptied_slides(doc)
end

-- The timer and spinner shortcodes expand to HTML. Pandoc passes a RawBlock it
-- cannot convert straight through to the output, which in a PDF surfaces as
-- either nothing or a stray fragment of markup, depending on the shortcode.
-- Dropping raw HTML outright is safe here: the deck's own content is markdown,
-- and anything hand-written in HTML was written for the screen.
function RawBlock(el)
  if not is_handout() then
    return nil
  end
  if el.format:match("^html") then
    return {}
  end
  return nil
end

function RawInline(el)
  if not is_handout() then
    return nil
  end
  if el.format:match("^html") then
    return {}
  end
  return nil
end

-- -------------------------------------------------- image width scaling
--
-- Percentage widths target the container: the RevealJS slide (~1050 px
-- ≈ 27.8 cm) or the A4 text width (~15.4 cm).  Because the slide is
-- ~1.8× wider, a small percentage leaves the image visibly undersized
-- on paper.  Scale up widths ≤ 55 % so the image takes a comparable
-- share of the page.

function Image(img)
  if not is_handout() then return nil end

  local w = img.attributes.width
  if not w then return nil end

  local pct = tonumber(w:match("^(%d+)%%$"))
  if not pct or pct > 55 then return nil end

  local scaled = math.min(math.floor(pct * 1.8), 100)
  img.attributes.width = scaled .. "%"
  return img
end

-- ------------------------------------------------------------------- emoji

-- Inter carries no emoji, and LaTeX drops a glyph it cannot set *without
-- failing* — the deck shows 📧 before the address, the PDF shows a gap. These
-- are the ones the decks use; each maps to the nearest FontAwesome glyph, which
-- is monochrome, sits on the baseline and prints properly.
--
-- Anything not listed is removed rather than passed through, because the
-- alternative is not "the emoji" but a silent hole in the sentence. Add a line
-- here when a deck starts using a new one.
local emoji_replacements = {
  ["\u{1F4E7}"] = "\\faEnvelope", -- 📧 e-mail
  ["\u{1F3DB}"] = "\\faUniversity", -- 🏛 institute address
  ["\u{1F4CD}"] = "\\faMapMarker", -- 📍 location
  ["\u{1F4C5}"] = "\\faCalendar", -- 📅 date
  ["\u{1F4DA}"] = "\\faBook", -- 📚 reading
  ["\u{1F4A1}"] = "\\faLightbulb", -- 💡 tip
  ["\u{26A0}"] = "\\faExclamationTriangle", -- ⚠ warning
}

-- U+FE0F is the variation selector that asks for the colour form of the
-- preceding character. It carries no meaning of its own and has no glyph, so it
-- goes whether or not its base character was replaced.
local VARIATION_SELECTOR = "\u{FE0F}"

function Str(el)
  if not is_handout() then
    return nil
  end

  local text = el.text
  if not text:find("[\u{2600}-\u{27BF}\u{1F300}-\u{1FAFF}\u{FE0F}]") then
    return nil
  end

  local out = {}
  local buffer = {}

  local function flush()
    if #buffer > 0 then
      table.insert(out, pandoc.Str(table.concat(buffer)))
      buffer = {}
    end
  end

  for _, code in utf8.codes(text) do
    local char = utf8.char(code)
    local replacement = emoji_replacements[char]

    if replacement then
      flush()
      table.insert(out, pandoc.RawInline("latex", replacement .. "{}"))
    elseif char == VARIATION_SELECTOR then
      -- drop
    elseif code >= 0x1F300 or (code >= 0x2600 and code <= 0x27BF) then
      -- An emoji with no mapping: drop it rather than leave a gap where a
      -- glyph should be.
      flush()
    else
      table.insert(buffer, char)
    end
  end

  flush()

  if #out == 0 then
    return {}
  end

  return out
end

-- ------------------------------------------------------------------- brand

-- quarto.brand.get_color returns the colour in output format — for LaTeX that is
-- a name the document may not have defined, so ask for the CSS value and convert
-- the hex ourselves. Anything that is not a plain #rrggbb (a named colour, a
-- gradient) is skipped rather than guessed at.
local function hex_for(name)
  local ok, value = pcall(quarto.brand.get_color_css, "light", name)
  if not ok or type(value) ~= "string" then
    return nil
  end

  local hex = value:match("^#(%x%x%x%x%x%x)$")
  if hex then
    return hex:upper()
  end

  -- #abc shorthand, expanded pairwise.
  local short = value:match("^#(%x%x%x)$")
  if short then
    local r, g, b = short:sub(1, 1), short:sub(2, 2), short:sub(3, 3)
    return (r .. r .. g .. g .. b .. b):upper()
  end

  return nil
end

-- The four the preamble uses, mapped from brand role to the name plate-pdf.tex
-- expects. `foreground` rather than a palette key, because that is the role
-- _brand.yml assigns to ink.
local brand_colours = {
  ["plate-ink"] = "foreground",
  ["plate-primary"] = "primary",
  ["plate-danger"] = "danger",
  ["plate-muted"] = "secondary",
}

-- Callouts. Quarto emits its own \definecolor block for these — Bootstrap blue,
-- green and red, the same palette the deck overrides in SCSS — and hardcodes the
-- names into every tcolorbox it writes. Redefining the colours under those names
-- is therefore the whole job: no need to touch the boxes themselves.
--
-- This works only because Quarto puts that block *earlier* in the preamble than
-- the filter's own injection, so the later \definecolor wins. Same five pairings
-- as $callout-colours in plate.scss; keep the two in step.
local callout_colours = {
  note = "primary",
  tip = "success",
  important = "danger",
  warning = "warning",
  caution = "tertiary",
}

-- Where the header logo comes from. `brand.logo.images.right` is the course
-- mark, but it is not reachable as document metadata — the brand is a separate
-- layer Quarto resolves itself, and meta.brand is empty here. quarto.brand is
-- the way in; it hands back a table of {path, alt} keyed by mode.
--
-- The path it returns is relative to the project root while LaTeX runs one
-- folder down in the deck's own directory, so it has to be made absolute or
-- graphicx will not find it.
local function logo_command()
  if not (quarto and quarto.brand and quarto.brand.get_logo) then
    return nil
  end

  local ok, logo = pcall(quarto.brand.get_logo, "light", "right")
  if not ok or type(logo) ~= "table" then
    return nil
  end

  -- get_logo usually returns { light = {path, alt}, dark = {...} }, but hands
  -- back a flat { path, alt } when the brand names only one image. Falling
  -- through to `logo` itself covers both; without it the flat shape silently
  -- yields no logo at all, which is exactly how it fails — no error, no header.
  local entry = logo.light or logo.dark or logo
  if type(entry) ~= "table" or entry.path == nil then
    return nil
  end

  local path = pandoc.utils.stringify(entry.path)
  if path == "" then
    return nil
  end

  if not path:match("^/") and quarto.project and quarto.project.directory then
    path = quarto.project.directory .. "/" .. path
  end

  return string.format("\\includegraphics[height=6mm]{%s}", path)
end

function Meta(meta)
  if not is_handout() then
    return nil
  end

  local preamble = {}

  for tex_name, brand_role in pairs(brand_colours) do
    local hex = hex_for(brand_role)
    if hex then
      table.insert(preamble, string.format("\\definecolor{%s}{HTML}{%s}", tex_name, hex))
    end
  end

  -- Both the icon/title colour and the frame rule get the same value, because on
  -- the slides the rule and the icon are one colour and the callout reads as a
  -- single mark rather than a box with trim.
  for callout, brand_role in pairs(callout_colours) do
    local hex = hex_for(brand_role)
    if hex then
      table.insert(
        preamble,
        string.format("\\definecolor{quarto-callout-%s-color}{HTML}{%s}", callout, hex)
      )
      table.insert(
        preamble,
        string.format("\\definecolor{quarto-callout-%s-color-frame}{HTML}{%s}", callout, hex)
      )
    end
  end

  -- The running header. Falls back to the title when no short form is given;
  -- `subtitle` is deliberately not used, since on these decks it is the week's
  -- topic in caps and would shout across every page.
  local short = meta["short-title"] or meta.title
  if short then
    table.insert(
      preamble,
      string.format("\\renewcommand{\\platehandoutshorttitle}{%s}", pandoc.utils.stringify(short))
    )
  end

  local logo = logo_command()
  if logo then
    table.insert(preamble, string.format("\\renewcommand{\\platehandoutlogo}{%s}", logo))
  end

  if #preamble > 0 then
    quarto.doc.include_text("in-header", table.concat(preamble, "\n"))
  end

  return meta
end
