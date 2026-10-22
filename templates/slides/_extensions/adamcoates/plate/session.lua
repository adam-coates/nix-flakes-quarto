-- Fold a recorded class into the handout.
--
-- session.js writes session.json in the browser at the end of a class: what the
-- polls came out as, and the drawings made on the Excalidraw overlay. Put that
-- file next to the week's index.qmd, re-render, and each result lands at the end
-- of the slide it belongs to.
--
-- Required by handout.lua rather than registered as a filter of its own, so the
-- whole handout stays one pass over the document.
--
-- The design rule throughout: a handout rendered *without* session.json must
-- come out exactly as it did before this file existed. Every entry point below
-- returns early when there is no recording, and a malformed recording is a
-- warning and no content — never a failed build the evening before a class.

local M = {}

-- --------------------------------------------------------------- reading

-- Written next to the deck, because that is the file it belongs to: a week's
-- recording is no more shareable between weeks than its slides are.
local SESSION_FILE = "session.json"

local function read_file(path)
  local handle = io.open(path, "rb")
  if not handle then
    return nil
  end
  local contents = handle:read("a")
  handle:close()
  return contents
end

-- The deck's own folder. Quarto runs the filter with the input file's directory
-- as the working directory, so a bare relative name is right — but be explicit
-- about it, because that is exactly the sort of thing that quietly stops being
-- true.
function M.load()
  local raw = read_file(SESSION_FILE)
  if not raw then
    return nil
  end

  local ok, decoded = pcall(quarto.json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    quarto.log.warning("session: " .. SESSION_FILE .. " is not readable JSON; ignoring it")
    return nil
  end

  if decoded.version ~= 1 then
    quarto.log.warning(
      "session: " .. SESSION_FILE .. " is version " .. tostring(decoded.version)
        .. ", this filter understands version 1; ignoring it"
    )
    return nil
  end

  -- A recording written by an exporter older than the one in the extension. The
  -- usual cause is a browser that had the deck open across a rebuild: Reveal
  -- plugins are served from site_libs at a stable URL with no cache-busting, so
  -- the page keeps running the script it loaded first and exports a file with
  -- whatever that version knew about. The missing part is then simply absent
  -- from the handout, with nothing to say why — hence this.
  if decoded.clouds == nil then
    quarto.log.warning(
      "session: " .. SESSION_FILE .. " has no `clouds` key, so it was written by an "
        .. "exporter that predates word-cloud support. Word clouds will be missing "
        .. "from this handout. Hard-reload the deck (Ctrl+Shift+R) and export again."
    )
  end

  return decoded
end

-- --------------------------------------------------------------- polls

-- A bar drawn as a rule, because a chart package for five numbers is not worth
-- the dependency. Width is a share of \linewidth, so it scales with the page.
local function bar(share)
  if share <= 0 then
    return pandoc.RawInline("latex", "")
  end
  return pandoc.RawInline(
    "latex",
    string.format("\\textcolor{plate-primary}{\\rule{%.3f\\linewidth}{7pt}}", share * 0.42)
  )
end

-- One poll as a small table: label, bar, count, share. The correct answer is
-- marked, since by handout time there is no reason to withhold it — that is
-- half of why a student wants the file.
local function poll_blocks(poll)
  local total = 0
  for _, option in ipairs(poll.options or {}) do
    total = total + (option.votes or 0)
  end
  if total == 0 then
    return {}
  end

  local rows = {}
  for _, option in ipairs(poll.options or {}) do
    local votes = option.votes or 0
    local share = votes / total

    local label = pandoc.Inlines(pandoc.read(option.label or "", "markdown").blocks[1].content)
    if option.correct then
      label:insert(pandoc.Space())
      label:insert(pandoc.RawInline("latex", "\\textcolor{plate-primary}{\\faCheck}"))
    end

    rows[#rows + 1] = {
      pandoc.Plain(label),
      pandoc.Plain({ bar(share) }),
      pandoc.Plain({ pandoc.Str(tostring(votes)) }),
      pandoc.Plain({ pandoc.Str(string.format("%.0f%%", share * 100)) }),
    }
  end

  local caption = "In class: " .. tostring(poll.voters or total) .. " responded"
  if poll.question and poll.question ~= "" then
    caption = poll.question .. " — " .. caption
  end

  local blocks = pandoc.Blocks({})
  blocks:insert(pandoc.Para({
    pandoc.RawInline("latex", "\\medskip\\noindent\\textcolor{plate-muted}{\\small "),
    pandoc.Str(caption),
    pandoc.RawInline("latex", "}\\par\\smallskip"),
  }))

  -- SimpleTable is the easy constructor but not a document node; from_simple_table
  -- turns it into the real Table that the writers understand.
  blocks:insert(pandoc.utils.from_simple_table(pandoc.SimpleTable(
    pandoc.Inlines({}),
    { pandoc.AlignLeft, pandoc.AlignLeft, pandoc.AlignRight, pandoc.AlignRight },
    { 0.45, 0.30, 0.08, 0.10 },
    {
      pandoc.Plain({ pandoc.Str("Answer") }),
      pandoc.Plain({}),
      pandoc.Plain({ pandoc.Str("n") }),
      pandoc.Plain({ pandoc.Str("%") }),
    },
    rows
  )))

  return blocks
end

-- --------------------------------------------------------- word clouds

-- A cloud is a bag of words with counts, and on paper the useful thing is not a
-- picture of the canvas but the words themselves, set at a size that carries how
-- often each was said. Frequency is the whole content; the scatter on screen was
-- only ever decoration.
local CLOUD_MIN_PT = 11
local CLOUD_MAX_PT = 26

local function cloud_blocks(cloud)
  local words = cloud.words or {}
  if #words == 0 then
    return {}
  end

  local most, total = 0, 0
  for _, entry in ipairs(words) do
    local count = entry.count or 0
    if count > most then
      most = count
    end
    total = total + count
  end
  if most == 0 then
    return {}
  end

  local caption = "In class: " .. tostring(total) .. " words"
  if cloud.question and cloud.question ~= "" then
    caption = cloud.question .. " — " .. caption
  end

  local blocks = pandoc.Blocks({})
  blocks:insert(pandoc.Para({
    pandoc.RawInline("latex", "\\medskip\\noindent\\textcolor{plate-muted}{\\small "),
    pandoc.Str(caption),
    pandoc.RawInline("latex", "}\\par\\smallskip"),
  }))

  local inlines = pandoc.Inlines({})

  for _, entry in ipairs(words) do
    local count = entry.count or 0
    -- Linear between the smallest and the largest count. With a single distinct
    -- count every word is the same size, which is honest: nothing distinguishes
    -- them.
    local share = most > 1 and ((count - 1) / (most - 1)) or 1
    local size = CLOUD_MIN_PT + share * (CLOUD_MAX_PT - CLOUD_MIN_PT)

    -- A word said more than once earns the accent colour; the rest stay quiet,
    -- so the eye lands on what the room agreed on.
    local colour = count > 1 and "plate-primary" or "plate-ink"

    -- \mbox so an entry never breaks across lines. Without it LaTeX hyphenates
    -- mid-word — "writing & read-/ing" — and in a list of words a fragment
    -- reads as a different answer. Setting \hyphenpenalty here does not work:
    -- it is a paragraph parameter, read at \par, by which point the group that
    -- set it has already closed and restored the old value.
    --
    -- The trade is that a single entry wider than the text block will run into
    -- the margin rather than break. For one-to-three-word answers that is not a
    -- case worth handling; if a class ever writes an essay into the cloud, this
    -- is the line to revisit.
    inlines:insert(pandoc.RawInline(
      "latex",
      string.format(
        "{\\fontsize{%.1f}{%.1f}\\selectfont\\textcolor{%s}{\\mbox{",
        size,
        size * 1.15,
        colour
      )
    ))
    -- The word itself goes through as a Str so Pandoc escapes it. These come
    -- from students typing into a phone: & % _ # $ all turn up eventually, and
    -- any of them would break the build if pasted into raw LaTeX.
    inlines:insert(pandoc.Str(entry.word or ""))
    inlines:insert(pandoc.RawInline("latex", "}}}"))
    inlines:insert(pandoc.Space())
    -- A little extra air, since the sizes vary and words set solid read as one
    -- long string.
    inlines:insert(pandoc.RawInline("latex", "\\hspace{0.35em}"))
  end

  blocks:insert(pandoc.Para(inlines))

  return blocks
end

-- ------------------------------------------------------------ drawings

-- Excalidraw hands over a data: URI. LaTeX needs a file, so decode it into the
-- mediabag under a stable name and let Pandoc write it out at render time —
-- which keeps the deck folder clean of generated PNGs.
local counter = 0

local function drawing_blocks(drawing)
  local data = drawing.png
  if type(data) ~= "string" then
    return {}
  end

  local b64 = data:match("^data:image/png;base64,(.+)$")
  if not b64 then
    quarto.log.warning("session: a drawing is not a base64 PNG data URI; skipping it")
    return {}
  end

  local ok, bytes = pcall(quarto.base64.decode, b64)
  if not ok or not bytes then
    quarto.log.warning("session: could not decode a drawing; skipping it")
    return {}
  end

  counter = counter + 1
  local name = string.format("session-drawing-%02d.png", counter)
  pandoc.mediabag.insert(name, "image/png", bytes)

  -- Labelled the same way as a poll result, rather than as a figure caption: an
  -- image alone in a Para only becomes a captioned figure under conditions
  -- Quarto's own figure handling overrides, so the caption silently disappears.
  -- A muted line above the image always renders, and reads better anyway — these
  -- are marginalia, not numbered figures.
  local label = pandoc.Para({
    pandoc.RawInline("latex", "\\medskip\\noindent\\textcolor{plate-muted}{\\small "),
    pandoc.Str("Drawn in class"),
    pandoc.RawInline("latex", "}\\par\\smallskip"),
  })

  -- Held to the text width rather than its natural size: an Excalidraw export is
  -- as wide as whatever was drawn, which is usually far wider than an A4 measure.
  local image = pandoc.Image({}, name, "", pandoc.Attr("", {}, { width = "100%" }))

  return pandoc.Blocks({ label, pandoc.Para({ image }) })
end

-- ------------------------------------------------------------ assembly

-- Group everything by the slide it belongs to. A poll or drawing with no slide
-- id (an older recording, or a drawing made before the first slide change) is
-- collected under `nil` and appended at the end of the document, where it is at
-- least present rather than silently dropped.
local function index_by_slide(session)
  local by_slide, orphans = {}, pandoc.Blocks({})

  for _, poll in ipairs(session.polls or {}) do
    local blocks = poll_blocks(poll)
    if #blocks > 0 then
      if poll.slide then
        by_slide[poll.slide] = by_slide[poll.slide] or pandoc.Blocks({})
        by_slide[poll.slide]:extend(blocks)
      else
        orphans:extend(blocks)
      end
    end
  end

  for _, cloud in ipairs(session.clouds or {}) do
    local blocks = cloud_blocks(cloud)
    if #blocks > 0 then
      if cloud.slide then
        by_slide[cloud.slide] = by_slide[cloud.slide] or pandoc.Blocks({})
        by_slide[cloud.slide]:extend(blocks)
      else
        orphans:extend(blocks)
      end
    end
  end

  for _, drawing in ipairs(session.drawings or {}) do
    local blocks = drawing_blocks(drawing)
    if #blocks > 0 then
      if drawing.slide then
        by_slide[drawing.slide] = by_slide[drawing.slide] or pandoc.Blocks({})
        by_slide[drawing.slide]:extend(blocks)
      else
        orphans:extend(blocks)
      end
    end
  end

  return by_slide, orphans
end

-- Walk the top level once, tracking which slide we are inside. A slide ends
-- where the next heading of the same level or higher begins, which is where its
-- session content is inserted — so results sit at the foot of their own page
-- rather than at the head of the following one.
function M.apply(doc, session)
  local by_slide, orphans = index_by_slide(session)

  local out = pandoc.Blocks({})
  local open_slide = nil
  local open_level = nil
  local used = {}

  local function close_slide()
    if open_slide and by_slide[open_slide] then
      out:extend(by_slide[open_slide])
      used[open_slide] = true
    end
    open_slide, open_level = nil, nil
  end

  for _, block in ipairs(doc.blocks) do
    if block.t == "Header" then
      if open_level and block.level <= open_level then
        close_slide()
      end
      out:insert(block)
      if block.identifier and block.identifier ~= "" then
        open_slide, open_level = block.identifier, block.level
      end
    else
      out:insert(block)
    end
  end

  close_slide()

  -- Anything whose slide is gone from the deck since the class — a renamed or
  -- deleted heading — would otherwise vanish without a word.
  for slide, blocks in pairs(by_slide) do
    if not used[slide] then
      quarto.log.warning(
        "session: no slide '" .. slide .. "' in this deck; its results are appended at the end"
      )
      orphans:extend(blocks)
    end
  end

  if #orphans > 0 then
    out:insert(pandoc.Header(2, pandoc.Inlines({ pandoc.Str("From the class") })))
    out:extend(orphans)
  end

  doc.blocks = out
  return doc
end

return M
