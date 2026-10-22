-- Feed the title slide's two logo slots from _brand.yml, inlining each file as a
-- data URI.
--
-- The title-slide template can only see document metadata, not the brand, so
-- copy brand.logo.images.left / .right into `logo-left` / `logo-right`. A value
-- written directly in a deck's YAML wins, which is how a one-off deck swaps in a
-- co-host's logo without touching the shared brand.
--
-- Why inline rather than pass the path through: the template writes the value
-- straight into `src`, and Pandoc does not rewrite it, so a plain relative path
-- is resolved against wherever the *output* lands. That works only when the deck
-- and logos/ are siblings; a deck one folder down (course/week-03/index.qmd
-- against course/logos/) silently 404s. Inlining removes the question, and it
-- matches how the theme already ships its fonts — a deck is one file that works
-- offline, and `deploy` has nothing to copy alongside it.

local mime_types = {
  svg = "image/svg+xml",
  png = "image/png",
  jpg = "image/jpeg",
  jpeg = "image/jpeg",
  gif = "image/gif",
  webp = "image/webp",
  avif = "image/avif",
}

-- Candidate roots for a relative logo path, in the order worth trying: the
-- working directory, the project root (where _brand.yml lives, so where its
-- paths are anchored) and the deck's own folder (for a deck-level override).
local function candidates(path)
  local list = { path }

  local project = nil
  if quarto and quarto.project and quarto.project.directory then
    project = quarto.project.directory
  end
  if project then
    list[#list + 1] = project .. "/" .. path
  end

  local input = PANDOC_STATE and PANDOC_STATE.input_files and PANDOC_STATE.input_files[1]
  if input then
    local dir = input:match("^(.*)[/\\][^/\\]*$")
    if dir then
      list[#list + 1] = dir .. "/" .. path
    end
  end

  return list
end

local function read_binary(path)
  for _, candidate in ipairs(candidates(path)) do
    local handle = io.open(candidate, "rb")
    if handle then
      local bytes = handle:read("a")
      handle:close()
      if bytes and #bytes > 0 then
        return bytes, candidate
      end
    end
  end
  return nil
end

local function data_uri(path)
  -- Already inlined, or hosted somewhere: nothing to do.
  if path:match("^data:") or path:match("^%a[%w+.-]*://") then
    return path
  end

  local ext = path:match("%.([%a%d]+)$")
  local mime = ext and mime_types[ext:lower()]
  if not mime then
    return nil
  end

  local bytes, found = read_binary(path)
  if not bytes then
    quarto.log.warning(
      "plate: could not read logo '" .. path .. "'; leaving the path as written, "
        .. "which will only resolve if the file sits next to the rendered deck"
    )
    return nil
  end

  if #bytes > 1024 * 1024 then
    quarto.log.warning(
      "plate: "
        .. found
        .. " is "
        .. math.floor(#bytes / 1024)
        .. " KB and is inlined into every deck that uses it — worth optimising, or converting to SVG"
    )
  end

  return "data:" .. mime .. ";base64," .. quarto.base64.encode(bytes)
end

local function logo_from_brand(name)
  if not (quarto and quarto.brand and quarto.brand.get_logo) then
    return nil
  end
  local ok, logo = pcall(quarto.brand.get_logo, "light", name)
  if not ok or logo == nil then
    return nil
  end
  -- get_logo returns { light = { path = ..., alt = ... }, dark = { ... } }.
  local entry = logo.light or logo.dark or logo
  if type(entry) ~= "table" or entry.path == nil then
    return nil
  end
  return pandoc.utils.stringify(entry.path), entry.alt and pandoc.utils.stringify(entry.alt) or nil
end

function Meta(meta)
  for _, name in ipairs({ "left", "right" }) do
    local key = "logo-" .. name

    local path, alt = nil, nil
    if meta[key] == nil then
      path, alt = logo_from_brand(name)
    else
      path = pandoc.utils.stringify(meta[key])
    end

    if path then
      meta[key] = pandoc.Str(data_uri(path) or path)
      if alt and meta[key .. "-alt"] == nil then
        meta[key .. "-alt"] = pandoc.Str(alt)
      end
    end
  end
  return meta
end
