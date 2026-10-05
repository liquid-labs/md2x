-- md2x-links.lua: the Pandoc Lua filter md2x applies to every conversion.
--
-- It does two things:
--
--   1. Rewrites a relative link whose target ends in '.md' or '.markdown' (any case) to
--      end in '.<format>', keeping any '?query' or '#fragment' ('c.md#sec' becomes
--      'c.html#sec'). Absolute paths, URL-scheme targets ('http:', 'mailto:', ...) and
--      pure '#fragment' links are left alone. Pandoc has already parsed the document, so
--      links inside code spans and fenced code never reach this filter, and reference
--      style definitions arrive as ordinary links.
--
--   2. Resolves each relative image against the directory of the source file that
--      contains it, and rewrites it by output format: an absolute path for pdf and docx,
--      a path relative to the output file's directory for html (so the HTML works where
--      it is written). Every relative image whose file does not exist is recorded, once
--      per source and target, in the miss file for the CLI to report as a warning.
--
-- The CLI hands the filter its settings as pandoc metadata ('-M name=value'):
--
--   md2x-format      output format: pdf, html or docx
--   md2x-source-dir  absolute directory images are resolved against, until a marker says
--                    otherwise (the source file's directory; the cwd for stdin)
--   md2x-source      name of that source, for messages
--   md2x-out-dir     html only: absolute directory of the output file
--   md2x-miss-file   file the missing-image records are appended to
--
-- '--single-page' concatenates several sources into one document, so before each source
-- the CLI inserts a one-line marker block, surrounded by blank lines:
--
--   <!-- md2x:source-dir=<ENC> source=<ENC> -->
--
-- where <ENC> is the percent-encoded absolute directory and source name (so neither can
-- contain '-->', spaces or newlines). The filter tracks the current source from these
-- RawBlocks, in document order, and removes them from the output.
--
-- Plain Lua 5.1-compatible code; the only pandoc APIs used are the 'Pandoc' filter
-- function, 'pandoc.utils.stringify', the 'walk' method on blocks, and the Link, Image
-- and RawBlock element fields.

local format = 'html'
local base_dir = nil
local source_name = 'stdin'
local out_dir = nil
local miss_file = nil
local misses = {}
local seen_misses = {}

local function decode(text)
  return (text:gsub('%%(%x%x)', function(hex) return string.char(tonumber(hex, 16)) end))
end

-- Encodes only what would break a path used as a URL or by pandoc's own resource fetch.
local function encode_path(text)
  return (text:gsub('[%c %%#?"<>\\`|^{}%[%]]', function(ch)
    return string.format('%%%02X', string.byte(ch))
  end))
end

local function printable(text)
  return (text:gsub('[%c]', '?'))
end

local function meta_string(meta, key)
  local value = meta[key]
  if value == nil then return nil end
  local text = pandoc.utils.stringify(value)
  if text == '' then return nil end
  return text
end

local function split_path(path)
  local parts = {}
  for part in path:gmatch('[^/]+') do parts[#parts + 1] = part end
  return parts
end

-- Joins and lexically normalizes an absolute directory and a relative path.
local function resolve(dir, rel)
  local stack = {}
  local combined = split_path(dir)
  for _, part in ipairs(split_path(rel)) do combined[#combined + 1] = part end
  for _, part in ipairs(combined) do
    if part == '..' then
      stack[#stack] = nil
    elseif part ~= '.' then
      stack[#stack + 1] = part
    end
  end
  return '/' .. table.concat(stack, '/')
end

-- Path of 'target' relative to the directory 'from' (both absolute and normalized).
local function relative_path(from, target)
  local from_parts, target_parts = split_path(from), split_path(target)
  local common = 0
  while common < #from_parts and common < #target_parts - 1
        and from_parts[common + 1] == target_parts[common + 1] do
    common = common + 1
  end
  local out = {}
  for _ = common + 1, #from_parts do out[#out + 1] = '..' end
  for i = common + 1, #target_parts do out[#out + 1] = target_parts[i] end
  return table.concat(out, '/')
end

local function has_scheme(target)
  return target:match('^[A-Za-z][A-Za-z0-9+.%-]*:') ~= nil
end

local function file_exists(path)
  local handle = io.open(path, 'rb')
  if not handle then return false end
  -- Opening a directory succeeds on POSIX systems; reading from it does not.
  local _, err = handle:read(0)
  handle:close()
  return err == nil
end

local function convert_link(target)
  local first = target:sub(1, 1)
  if target == '' or first == '#' or first == '/' or has_scheme(target) then return nil end
  local path, suffix = target:match('^([^?#]*)(.*)$')
  local lower = path:lower()
  local stem
  if lower:match('%.markdown$') then
    stem = path:sub(1, #path - 9)
  elseif lower:match('%.md$') then
    stem = path:sub(1, #path - 3)
  else
    return nil
  end
  if stem:match('[^/]*$') == '' then return nil end
  return stem .. '.' .. format .. suffix
end

local function record_miss(target)
  local key = source_name .. '\0' .. target
  if seen_misses[key] then return end
  seen_misses[key] = true
  misses[#misses + 1] = printable(target) .. '\t' .. printable(source_name)
end

local function convert_image(target)
  local first = target:sub(1, 1)
  if target == '' or first == '/' or has_scheme(target) or not base_dir then return nil end
  local path, suffix = target:match('^([^?#]*)(.*)$')
  if path == '' then return nil end
  local resolved = resolve(base_dir, decode(path))
  if not file_exists(resolved) then
    -- A file whose name really contains a '%XX' sequence.
    local literal = resolve(base_dir, path)
    if literal ~= resolved and file_exists(literal) then
      resolved = literal
    else
      record_miss(target)
    end
  end
  if format == 'html' and out_dir then
    return encode_path(relative_path(out_dir, resolved)) .. suffix
  end
  return encode_path(resolved) .. suffix
end

local function marker_state(block)
  if block.t ~= 'RawBlock' or block.format ~= 'html' then return nil end
  local dir, name = block.text:match(
    '^%s*<!%-%-%s*md2x:source%-dir=(%S+)%s+source=(%S+)%s*%-%->%s*$')
  if not dir then return nil end
  return decode(dir), decode(name)
end

local walker = {
  Link = function(link)
    local converted = convert_link(link.target)
    if converted then
      link.target = converted
      return link
    end
  end,
  Image = function(image)
    local converted = convert_image(image.src)
    if converted then
      image.src = converted
      return image
    end
  end,
  -- A marker nested inside another block (it should not be) is still removed.
  RawBlock = function(block)
    local dir, name = marker_state(block)
    if dir then
      base_dir, source_name = dir, name
      return {}
    end
  end,
}

function Pandoc(doc)
  local meta = doc.meta
  format = meta_string(meta, 'md2x-format') or format
  base_dir = meta_string(meta, 'md2x-source-dir')
  source_name = meta_string(meta, 'md2x-source') or 'single-page'
  out_dir = meta_string(meta, 'md2x-out-dir')
  miss_file = meta_string(meta, 'md2x-miss-file')
  for _, key in ipairs({'md2x-format', 'md2x-source-dir', 'md2x-source', 'md2x-out-dir',
                        'md2x-miss-file'}) do
    meta[key] = nil
  end

  local blocks = {}
  for _, block in ipairs(doc.blocks) do
    local dir, name = marker_state(block)
    if dir then
      base_dir, source_name = dir, name
    else
      blocks[#blocks + 1] = block:walk(walker)
    end
  end
  doc.blocks = blocks

  if miss_file and #misses > 0 then
    local handle = io.open(miss_file, 'a')
    if handle then
      handle:write(table.concat(misses, '\n'), '\n')
      handle:close()
    end
  end
  return doc
end
