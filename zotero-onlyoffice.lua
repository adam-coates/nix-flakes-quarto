--
-- zotero-onlyoffice.lua
--
-- Pandoc Lua filter that generates DOCX files with Zotero citation fields
-- compatible with the OnlyOffice Zotero plugin.
--
-- Works with Better BibTeX for Zotero (JSON-RPC on localhost:23119).
-- Designed for use with Quarto/Pandoc -> DOCX -> OnlyOffice workflow.
--
-- Usage in Quarto:
--   citeproc: false
--   format:
--     docx:
--       filters:
--         - zotero-onlyoffice.lua
--       metadata:
--         zotero_author-in-text: "true"
--
-- Based on reverse-engineering of:
--   - zotero.lua (zotero-live-citations by Emiliano Heyns, MIT License)
--   - OnlyOffice Zotero plugin source (AGPL v3, Ascensio System SIA)
--
-- OnlyOffice's native Zotero plugin stores citations as complex field codes:
--   instrText: " ADDIN ZOTERO_CITATION {json}"
-- where json is a FLAT format: each citationItem contains CSL fields directly
-- (no itemData wrapper), plus groupID, index, suppress-author.
--
-- Bibliography field: " ADDIN ZOTERO_BIBLIOGRAPHY"
--

-- ===================================================================
-- Minimal JSON encoder
-- ===================================================================

local json_encode_value -- forward declaration

local function json_encode_string(s)
	s = s:gsub("\\", "\\\\")
	s = s:gsub('"', '\\"')
	s = s:gsub("\n", "\\n")
	s = s:gsub("\r", "\\r")
	s = s:gsub("\t", "\\t")
	s = s:gsub("[\x00-\x1f]", function(c)
		return string.format("\\u%04x", string.byte(c))
	end)
	return '"' .. s .. '"'
end

local function is_array(t)
	if type(t) ~= "table" then
		return false
	end
	local n = #t
	if n == 0 then
		-- check if completely empty
		for _ in pairs(t) do
			return false
		end
		return true -- empty table = empty array
	end
	for i = 1, n do
		if t[i] == nil then
			return false
		end
	end
	-- check no extra keys beyond 1..n
	local count = 0
	for _ in pairs(t) do
		count = count + 1
	end
	return count == n
end

local function json_encode_array(arr)
	local parts = {}
	for i = 1, #arr do
		parts[i] = json_encode_value(arr[i])
	end
	return "[" .. table.concat(parts, ",") .. "]"
end

local function json_encode_object(obj)
	local parts = {}
	local keys = {}
	for k, _ in pairs(obj) do
		if type(k) == "string" then
			keys[#keys + 1] = k
		end
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local v = obj[k]
		if v ~= nil then
			parts[#parts + 1] = json_encode_string(k) .. ":" .. json_encode_value(v)
		end
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

json_encode_value = function(v)
	if v == nil then
		return "null"
	elseif type(v) == "boolean" then
		return v and "true" or "false"
	elseif type(v) == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "null"
		end
		if v == math.floor(v) and v >= -2 ^ 53 and v <= 2 ^ 53 then
			return string.format("%d", v)
		end
		return string.format("%.17g", v)
	elseif type(v) == "string" then
		return json_encode_string(v)
	elseif type(v) == "table" then
		if is_array(v) then
			return json_encode_array(v)
		else
			return json_encode_object(v)
		end
	else
		return "null"
	end
end

local function json_encode(v)
	return json_encode_value(v)
end

-- ===================================================================
-- Minimal JSON decoder
-- ===================================================================

local decode_value -- forward declaration

local function skip_ws(s, pos)
	return s:match("^[ \t\n\r]*()", pos)
end

local function decode_string(s, pos)
	if s:byte(pos) ~= 0x22 then
		return nil, pos
	end
	local i = pos + 1
	local parts = {}
	while i <= #s do
		local c = s:byte(i)
		if c == 0x22 then
			return table.concat(parts), i + 1
		elseif c == 0x5C then
			i = i + 1
			local nc = s:sub(i, i)
			if nc == '"' or nc == "\\" or nc == "/" then
				parts[#parts + 1] = nc
			elseif nc == "n" then
				parts[#parts + 1] = "\n"
			elseif nc == "r" then
				parts[#parts + 1] = "\r"
			elseif nc == "t" then
				parts[#parts + 1] = "\t"
			elseif nc == "b" then
				parts[#parts + 1] = "\b"
			elseif nc == "f" then
				parts[#parts + 1] = "\f"
			elseif nc == "u" then
				local hex = s:sub(i + 1, i + 4)
				local code = tonumber(hex, 16)
				if code and code < 0x80 then
					parts[#parts + 1] = string.char(code)
				elseif code and code < 0x800 then
					parts[#parts + 1] = string.char(0xC0 + math.floor(code / 64), 0x80 + (code % 64))
				elseif code then
					parts[#parts + 1] = string.char(
						0xE0 + math.floor(code / 4096),
						0x80 + math.floor((code % 4096) / 64),
						0x80 + (code % 64)
					)
				end
				i = i + 4
			end
			i = i + 1
		else
			parts[#parts + 1] = s:sub(i, i)
			i = i + 1
		end
	end
	return nil, pos
end

local function decode_number(s, pos)
	local numend = s:match("^-?[0-9]+%.?[0-9]*[eE]?[+-]?[0-9]*()", pos)
	if not numend then
		return nil, pos
	end
	return tonumber(s:sub(pos, numend - 1)), numend
end

local function decode_object(s, pos)
	if s:byte(pos) ~= 0x7B then
		return nil, pos
	end
	local obj = {}
	pos = skip_ws(s, pos + 1)
	if s:byte(pos) == 0x7D then
		return obj, pos + 1
	end
	while true do
		pos = skip_ws(s, pos)
		local key
		key, pos = decode_string(s, pos)
		if not key then
			return nil, pos
		end
		pos = skip_ws(s, pos)
		if s:byte(pos) ~= 0x3A then
			return nil, pos
		end
		pos = skip_ws(s, pos + 1)
		local val
		val, pos = decode_value(s, pos)
		obj[key] = val
		pos = skip_ws(s, pos)
		if s:byte(pos) == 0x7D then
			return obj, pos + 1
		end
		if s:byte(pos) ~= 0x2C then
			return nil, pos
		end
		pos = pos + 1
	end
end

local function decode_array(s, pos)
	if s:byte(pos) ~= 0x5B then
		return nil, pos
	end
	local arr = {}
	pos = skip_ws(s, pos + 1)
	if s:byte(pos) == 0x5D then
		return arr, pos + 1
	end
	while true do
		local val
		val, pos = decode_value(s, pos)
		arr[#arr + 1] = val
		pos = skip_ws(s, pos)
		if s:byte(pos) == 0x5D then
			return arr, pos + 1
		end
		if s:byte(pos) ~= 0x2C then
			return nil, pos
		end
		pos = skip_ws(s, pos + 1)
	end
end

decode_value = function(s, pos)
	pos = skip_ws(s, pos)
	local c = s:byte(pos)
	if c == 0x22 then
		return decode_string(s, pos)
	elseif c == 0x7B then
		return decode_object(s, pos)
	elseif c == 0x5B then
		return decode_array(s, pos)
	elseif c == 0x74 and s:sub(pos, pos + 3) == "true" then
		return true, pos + 4
	elseif c == 0x66 and s:sub(pos, pos + 4) == "false" then
		return false, pos + 5
	elseif c == 0x6E and s:sub(pos, pos + 3) == "null" then
		return nil, pos + 4
	else
		return decode_number(s, pos)
	end
end

local function json_decode(s)
	local val, _ = decode_value(s, 1)
	return val
end

-- ===================================================================
-- Utilities
-- ===================================================================

local function trim(s)
	if s == nil then
		return s
	end
	return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function urlencode(str)
	return string.gsub(str, "[^%w]", function(c)
		return string.format("%%%X", string.byte(c))
	end)
end

local function xmlescape(str)
	return string.gsub(str, "[<>&]", {
		["&"] = "&amp;",
		["<"] = "&lt;",
		[">"] = "&gt;",
	})
end

-- ===================================================================
-- Zotero / Better BibTeX communication
-- ===================================================================

local config = {
	client = "zotero",
	csl_style = "apa",
	author_in_text = false,
}

local citekeys_needed = {}
local fetched_items = nil

local function fetch_items(citekeys)
	if fetched_items ~= nil then
		return
	end
	fetched_items = { items = {}, errors = {} }
	if #citekeys == 0 then
		return
	end

	local url = (config.client == "jurism") and "http://127.0.0.1:24119/better-bibtex/json-rpc?"
		or "http://127.0.0.1:23119/better-bibtex/json-rpc?"

	local request = {
		jsonrpc = "2.0",
		method = "item.pandoc_filter",
		params = {
			citekeys = citekeys,
			style = config.csl_style or "apa",
			asCSL = true,
		},
	}

	local ok, mt, body = pcall(pandoc.mediabag.fetch, url .. urlencode(json_encode(request)), ".")
	if not ok then
		io.stderr:write("zotero-onlyoffice: Cannot connect to Zotero/Better BibTeX.\n")
		io.stderr:write("  Make sure Zotero is running with Better BibTeX installed.\n")
		return
	end

	local parse_ok, response = pcall(json_decode, body)
	if not parse_ok or response == nil then
		io.stderr:write("zotero-onlyoffice: Cannot parse Zotero response\n")
		return
	end
	if response.error then
		io.stderr:write("zotero-onlyoffice: Zotero error: " .. tostring(response.error.message) .. "\n")
		return
	end
	fetched_items = response.result
end

local function get_item(citekey)
	if not fetched_items then
		return nil
	end
	if fetched_items.errors and fetched_items.errors[citekey] ~= nil then
		io.stderr:write(
			"zotero-onlyoffice: @"
				.. citekey
				.. ": "
				.. (fetched_items.errors[citekey] == 0 and "not found" or "duplicates found")
				.. "\n"
		)
		return nil
	end
	if not fetched_items.items or not fetched_items.items[citekey] then
		io.stderr:write("zotero-onlyoffice: @" .. citekey .. " not in Zotero\n")
		return nil
	end
	return fetched_items.items[citekey]
end

-- ===================================================================
-- Build OnlyOffice-native FLAT citation JSON
-- (matches ZOTERO_CITATION format exactly)
-- ===================================================================

local citation_index = 0

local function build_flat_citation(cite)
	local items = {}

	for _, ref in ipairs(cite.citations) do
		local itemData = get_item(ref.id)
		if itemData == nil then
			return nil
		end

		-- Extract the Zotero item key from the URI
		-- URI looks like: http://zotero.org/users/12345/items/ABCD1234
		-- or: http://zotero.org/groups/12345/items/ABCD1234
		local item_key = ref.id -- fallback to citekey
		local group_id = nil
		local user_id = nil

		if itemData.custom and itemData.custom.uri then
			local uri = itemData.custom.uri
			local captured_key = uri:match("/items/(%w+)$")
			if captured_key then
				item_key = captured_key
			end

			local gid = uri:match("/groups/(%d+)/items/")
			if gid then
				group_id = gid
			end

			local uid = uri:match("/users/(%d+)/items/")
			if uid then
				user_id = uid
			end
		end

		-- Build FLAT citation item: all CSL fields at top level
		-- (this matches what OnlyOffice's Zotero plugin creates natively)
		citation_index = citation_index + 1
		local flat_item = {}

		-- Copy all CSL fields except 'custom' and 'id'
		for k, v in pairs(itemData) do
			if k ~= "custom" and k ~= "id" then
				flat_item[k] = v
			end
		end

		-- Set the ID to the Zotero item key (string)
		flat_item.id = item_key
		-- OnlyOffice also uses citation-key
		flat_item["citation-key"] = ref.id

		-- Add OnlyOffice-specific metadata
		flat_item.index = citation_index
		if group_id then
			flat_item.groupID = group_id
		end
		if user_id then
			flat_item.userID = user_id
		end

		-- Handle suppress-author
		if ref.mode == "SuppressAuthor" then
			flat_item["suppress-author"] = true
		else
			flat_item["suppress-author"] = false
		end

		-- Handle author-in-text
		if ref.mode == "AuthorInText" then
			if config.author_in_text and itemData.custom and itemData.custom.author then
				flat_item["suppress-author"] = true
			else
				return nil -- can't handle, return original cite
			end
		end

		-- Prefix/suffix
		local prefix_str = pandoc.utils.stringify(ref.prefix)
		if prefix_str and prefix_str ~= "" then
			flat_item.prefix = prefix_str
		end

		local suffix_str = pandoc.utils.stringify(ref.suffix)
		if suffix_str and suffix_str ~= "" then
			-- Parse locator from suffix
			local loc_patterns = {
				{ pat = "^,?%s*pp?%.%s*(.+)", label = "page" },
				{ pat = "^,?%s*pages?%s+(.+)", label = "page" },
				{ pat = "^,?%s*chaps?%.%s*(.+)", label = "chapter" },
				{ pat = "^,?%s*secs?%.%s*(.+)", label = "section" },
				{ pat = "^,?%s*vols?%.%s*(.+)", label = "volume" },
			}
			local found = false
			for _, lp in ipairs(loc_patterns) do
				local match = suffix_str:match(lp.pat)
				if match then
					flat_item.label = lp.label
					flat_item.locator = trim(match)
					found = true
					break
				end
			end
			if not found then
				local num = suffix_str:match("^,?%s*(%d[%d%s,%-]*)$")
				if num then
					flat_item.label = "page"
					flat_item.locator = trim(num)
				else
					flat_item.suffix = trim(suffix_str)
				end
			end
		end

		items[#items + 1] = flat_item
	end

	-- Build the top-level object (OLD/flat format, matching OnlyOffice native)
	return { citationItems = items }
end

-- ===================================================================
-- Generate DOCX field code
-- ===================================================================

local function make_docx_field(cite)
	local csl_obj = build_flat_citation(cite)
	if csl_obj == nil then
		return cite
	end

	local author_prefix = ""
	if config.author_in_text then
		for _, ref in ipairs(cite.citations) do
			if ref.mode == "AuthorInText" then
				local itemData = get_item(ref.id)
				if itemData and itemData.custom and itemData.custom.author then
					author_prefix = '<w:r><w:t xml:space="preserve">'
						.. xmlescape(itemData.custom.author .. " ")
						.. "</w:t></w:r>"
				end
			end
		end
	end

	local citation_json = json_encode(csl_obj)
	local display_text = pandoc.utils.stringify(cite.content)
	if display_text == "" then
		display_text = "<Do Zotero Refresh>"
	end

	-- Use ZOTERO_CITATION (old format) - this is what OnlyOffice natively creates
	local field = author_prefix
		.. '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
		.. '<w:r><w:instrText xml:space="preserve">'
		.. " ADDIN ZOTERO_CITATION "
		.. xmlescape(citation_json)
		.. "</w:instrText></w:r>"
		.. '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
		.. "<w:r><w:rPr><w:noProof/></w:rPr><w:t>"
		.. xmlescape(display_text)
		.. "</w:t></w:r>"
		.. '<w:r><w:fldChar w:fldCharType="end"/></w:r>'

	return pandoc.RawInline("openxml", field)
end

-- ===================================================================
-- Pandoc filter callbacks
-- ===================================================================

function Meta(meta)
	if not meta.zotero then
		meta.zotero = {}
	end

	for k, v in pairs(meta) do
		local _, _, key = string.find(k, "^zotero[-_](.*)")
		if key then
			meta.zotero[key:gsub("_", "-")] = v
		end
	end

	for k, v in pairs(meta.zotero) do
		if type(v) ~= "string" then
			meta.zotero[k] = pandoc.utils.stringify(v)
		end
	end

	if meta.zotero["author-in-text"] then
		config.author_in_text = (pandoc.utils.stringify(meta.zotero["author-in-text"]) == "true")
	end
	if meta.zotero["csl-style"] then
		config.csl_style = pandoc.utils.stringify(meta.zotero["csl-style"])
		if config.csl_style == "apa7" then
			config.csl_style = "apa"
		end
	end
	if meta.zotero.client then
		config.client = pandoc.utils.stringify(meta.zotero.client)
	end

	return meta
end

function Cite_collect(cite)
	if not FORMAT:match("docx") then
		return nil
	end
	for _, item in ipairs(cite.citations) do
		citekeys_needed[item.id] = true
	end
	return nil
end

function Cite_replace(cite)
	if not FORMAT:match("docx") then
		return nil
	end

	if fetched_items == nil then
		local keys = {}
		for k, _ in pairs(citekeys_needed) do
			keys[#keys + 1] = k
		end
		fetch_items(keys)
	end

	return make_docx_field(cite)
end

return {
	{ Meta = Meta },
	{ Cite = Cite_collect },
	{ Cite = Cite_replace },
}
