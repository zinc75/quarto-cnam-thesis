-- quartable.lua — Pandoc/Quarto filter
-- Features: colspan ([text]{cs=N}), rowspan ([text]{rs=N} + ^),
--           midrule (===), partial cline (===N-M),
--           vertical lines on colspan cells (.vl/.vr, optional rspan=N),
--           per-cell alignment override (align=l|c|r).
--
-- Pipe-table syntax:
--
--   colspan over 2 columns     :   | [Title]{cs=2} |  |
--   rowspan over 3 rows        :   | [Text]{rs=3}  | … |
--                                  | ^             | … |   ← continuation rows
--                                  | ^             | … |
--   midrule (full width)       :   | ===           |   |
--   cline (cols 2 to 4)        :   | ===2-4        |   |   |   |
--   single-col cline           :   | ===3          |   |   |
--   multiple clines            :   | ===1-2,4-5    |   |   |   |   |
--   ranges + singles           :   | ===1,2-3,4    |   |   |   |   |
--   vline on colspan (full)    :   | [Title]{cs=2 .vr}      |  |
--   vline on colspan (limited) :   | [Title]{cs=2 .vr rspan=3} |  |
--
-- IMPORTANT for colspan: write as many empty cells as additional columns
-- (placeholders required by the pipe-table syntax).

-- ── Detection ─────────────────────────────────────────────────────────────

-- Parse the first cell of a row, recognising:
--   ===              → midrule (full-width horizontal line)
--   ===N-M           → cline (partial line spanning columns N..M)
--   ===N             → single-column cline (equivalent to ===N-N)
--   ===N-M,P,Q-R,…   → multiple clines on the same row, mixing
--                       ranges and single columns
-- Returns: (is_sep, kind, ranges)
--   is_sep : false / true
--   kind   : "midrule" | "cline"
--   ranges : nil for midrule, list of {from, to} for cline
local function parse_separator(row)
  if not row or not row.cells or #row.cells == 0 then return false end
  local blocks = row.cells[1].contents
  if #blocks ~= 1 then return false end
  if blocks[1].t ~= "Para" and blocks[1].t ~= "Plain" then return false end
  local inlines = blocks[1].content
  if #inlines ~= 1 or inlines[1].t ~= "Str" then return false end

  local text = inlines[1].text
  if text == "===" then return true, "midrule", nil end

  local rest = text:match("^===(.+)$")
  if not rest then return false end
  local ranges = {}
  for part in rest:gmatch("([^,]+)") do
    local from, to = part:match("^(%d+)%-(%d+)$")
    if not from then
      -- Single-column form: `N` is shorthand for `N-N`.
      local single = part:match("^(%d+)$")
      if single then from, to = single, single
      else return false end
    end
    table.insert(ranges, { tonumber(from), tonumber(to) })
  end
  if #ranges == 0 then return false end
  return true, "cline", ranges
end

-- True if the row is any kind of separator (midrule OR cline).
local function is_separator(row)
  local s = parse_separator(row)
  return s == true
end

-- True only if the row is a full midrule (=== with no range).
local function is_midrule(row)
  local s, k = parse_separator(row)
  return s == true and k == "midrule"
end

-- True if the cell is a rowspan continuation marker (^).
local function is_rowspan_marker(cell)
  local blocks = cell.contents
  if #blocks == 1 and (blocks[1].t == "Para" or blocks[1].t == "Plain") then
    local inlines = blocks[1].content
    if #inlines == 1 and inlines[1].t == "Str" then
      return inlines[1].text == "^"
    end
  end
  return false
end

-- Extract attributes carried by a Span inside a cell's blocks:
--   cs=N, rs=N           : col_span / row_span
--   .vl, .vr (classes)   : vline left/right (works on any cell)
--   rspan=N (attribute)  : limit the vline to N rows (default: full height)
--   align=l|c|r          : horizontal alignment override (also accepts
--                          left/center/right). Default for colspan cells
--                          is center; without `align=` non-colspan cells
--                          inherit their column's alignment as usual.
-- Returns: (info, new_blocks) where info = { cs, rs, vl, vr, rspan, align }
-- (or nil if no quartable attribute was found on any Span in the cell).
local function extract_cell_attrs(blocks)
  if #blocks ~= 1 then return nil, blocks end
  if blocks[1].t ~= "Para" and blocks[1].t ~= "Plain" then return nil, blocks end
  local block_type = blocks[1].t
  local inlines = blocks[1].content
  for i, inline in ipairs(inlines) do
    if inline.t == "Span" then
      local attrs   = inline.attr.attributes
      local classes = inline.attr.classes
      local has_vl, has_vr = false, false
      for _, cls in ipairs(classes) do
        if cls == "vl" then has_vl = true end
        if cls == "vr" then has_vr = true end
      end
      local has_cs    = attrs.cs    ~= nil
      local has_rs    = attrs.rs    ~= nil
      local has_align = attrs.align ~= nil
      if has_cs or has_rs or has_vl or has_vr or has_align then
        local info = {
          cs    = has_cs and tonumber(attrs.cs) or nil,
          rs    = has_rs and tonumber(attrs.rs) or nil,
          vl    = has_vl,
          vr    = has_vr,
          rspan = attrs.rspan and tonumber(attrs.rspan) or nil,
          align = attrs.align,
        }
        -- Replace the Span with its inner inlines.
        local new_inlines = {}
        for j, il in ipairs(inlines) do
          if j == i then
            for _, inner in ipairs(inline.content) do
              table.insert(new_inlines, inner)
            end
          else
            table.insert(new_inlines, il)
          end
        end
        local new_block = block_type == "Plain"
          and pandoc.Plain(new_inlines)
          or  pandoc.Para(new_inlines)
        return info, { new_block }
      end
    end
  end
  return nil, blocks
end

-- ── Warnings ──────────────────────────────────────────────────────────────

-- Warn if a rowspan crosses a midrule separator (invalid in LaTeX).
-- Clines (===N-M) are partial separators and are not flagged here — the user
-- is left to judge case by case whether the partial overlap is acceptable.
local function warn_rowspan_crosses_separator(rows)
  for r, row in ipairs(rows) do
    if not is_separator(row) then
      for _, cell in ipairs(row.cells) do
        local info = extract_cell_attrs(cell.contents)
        local rs = info and info.rs
        if rs and rs > 1 then
          for dr = 1, rs - 1 do
            if rows[r + dr] and is_midrule(rows[r + dr]) then
              io.stderr:write(
                "[quartable] WARNING: rs=" .. rs ..
                " on row " .. r ..
                " crosses a === separator on row " .. (r + dr) ..
                " — LaTeX rendering will be incorrect.\n"
              )
            end
          end
        end
      end
    end
  end
end

-- True if any cell of `rows` declares an rs= attribute > 1.
local function rows_have_rowspan(rows)
  for _, row in ipairs(rows or {}) do
    for _, cell in ipairs(row.cells) do
      local info = extract_cell_attrs(cell.contents)
      if info and info.rs and info.rs > 1 then return true end
    end
  end
  return false
end

-- Parse the value of an `align=` attribute. Accepts both short (`l`,
-- `c`, `r`) and long (`left`, `center`, `right`) forms. Returns the
-- corresponding Pandoc alignment constant or nil for unknown values.
local function parse_align(s)
  if s == "l" or s == "left"   then return pandoc.AlignLeft   end
  if s == "c" or s == "center" then return pandoc.AlignCenter end
  if s == "r" or s == "right"  then return pandoc.AlignRight  end
  return nil
end

-- Same as `parse_align`, but returns the LaTeX letter `l`/`c`/`r`
-- (or nil) — used for raw `\multicolumn{1}{<letter>}{...}` injection.
local function parse_align_letter(s)
  if s == "l" or s == "left"   then return "l" end
  if s == "c" or s == "center" then return "c" end
  if s == "r" or s == "right"  then return "r" end
  return nil
end

-- ── Colspan + rowspan processing ──────────────────────────────────────────

local function process_spans(rows)
  -- cell_at[r][c]  : "owner" cell of logical position (r, c)
  -- occupied[r][c] : true if (r, c) is covered by a rowspan from above
  local cell_at  = {}
  local occupied = {}

  for r = 1, #rows do
    cell_at[r]  = cell_at[r]  or {}
    occupied[r] = occupied[r] or {}

    -- Separator rows are kept intact (handled by split_body).
    if not is_separator(rows[r]) then
      local new_cells = {}
      local c = 1   -- current logical column
      local i = 1   -- physical index in the cell list

      while i <= #rows[r].cells do
        local cell = rows[r].cells[i]

        if occupied[r][c] then
          -- Rowspan placeholder: ^ or empty cell at an occupied position.
          -- Pre-marking has already filled cell_at[r][c] from the origin row.
          -- Advance by eff_cs to consume as many physical placeholders as
          -- the colspan of the origin cell (convention: as many ^ or empty
          -- cells as the colspan width of the rowspan origin).
          local origin = cell_at[r][c]
          local eff_cs = origin and (origin.col_span or 1) or 1
          c = c + eff_cs
          i = i + eff_cs

        elseif is_rowspan_marker(cell) then
          -- Orphan ^: no origin cell at this position.
          io.stderr:write(
            "[quartable] WARNING: ^ marker without a matching origin cell" ..
            " (row " .. r .. ", logical column " .. c .. ").\n"
          )
          c = c + 1
          i = i + 1

        else
          -- Regular cell at a free position.
          local info, new_contents = extract_cell_attrs(cell.contents)
          cell.contents = new_contents

          local cs    = info and info.cs
          local rs    = info and info.rs
          local vl    = info and info.vl
          local vr    = info and info.vr
          local rspan = info and info.rspan

          local eff_cs = cs or (cell.col_span or 1)
          local eff_rs = rs or (cell.row_span or 1)

          if cs then cell.col_span = eff_cs end
          if rs then cell.row_span = eff_rs end

          -- Alignment: explicit `align=` wins on any cell (overrides the
          -- column's Markdown alignment). Without `align=`, colspan
          -- cells default to center, and regular cells inherit their
          -- column's alignment from the Markdown column spec
          -- (`|:---:|`, `|---:|`, etc.).
          local explicit = info and info.align and parse_align(info.align)
          if info and info.align and not explicit then
            io.stderr:write(
              "[quartable] WARNING: unknown align=\"" .. info.align ..
              "\" (use l/c/r or left/center/right) at row " .. r ..
              ", col " .. c .. ".\n"
            )
          end
          if explicit then
            cell.alignment = explicit
          elseif cs and eff_cs > 1 then
            cell.alignment = pandoc.AlignCenter
          end

          -- Store vline declarations as cell attributes. Vlines work on
          -- any cell — for a regular (cs=1) cell the boundary is just at
          -- the cell's left/right edge.
          if vl or vr then
            if not cell.attr then cell.attr = pandoc.Attr() end
            cell.attr.attributes = cell.attr.attributes or {}
            local val = rspan and tostring(rspan) or "full"
            if vl then cell.attr.attributes["quartable-vl"] = val end
            if vr then cell.attr.attributes["quartable-vr"] = val end
          end

          -- Store the explicit align= value (if any) so a later pass can
          -- inject `\multicolumn{1}{<align>}{...}` markers on cs=1 cells
          -- (Pandoc only auto-wraps cs>1 cells, not cs=1 cells).
          if explicit then
            if not cell.attr then cell.attr = pandoc.Attr() end
            cell.attr.attributes = cell.attr.attributes or {}
            cell.attr.attributes["quartable-align"] = info.align
          end

          -- Register the cell in cell_at for all of its logical positions.
          for dc = 0, eff_cs - 1 do
            cell_at[r][c + dc] = cell
          end

          -- Pre-mark following rows as occupied (rowspan > 1).
          if eff_rs > 1 then
            for dr = 1, eff_rs - 1 do
              occupied[r + dr] = occupied[r + dr] or {}
              cell_at[r + dr]  = cell_at[r + dr]  or {}
              for dc = 0, eff_cs - 1 do
                occupied[r + dr][c + dc] = true
                cell_at[r + dr][c + dc]  = cell
              end
            end
          end

          table.insert(new_cells, cell)
          -- Advance by eff_cs: skip colspan placeholders in the physical list.
          c = c + eff_cs
          i = i + eff_cs
        end
      end

      rows[r].cells = new_cells
    end
  end

  return rows
end

-- ── Splitting into multiple TableBody (midrule) ───────────────────────────

-- pandoc.TableBody() is not exposed as a constructor in every Pandoc version
-- shipped with Quarto: clone the existing body by copying its fields instead.
local function clone_body(body, rows)
  local nb = setmetatable({}, getmetatable(body))
  for k, v in pairs(body) do nb[k] = v end
  nb.body = rows
  return nb
end

-- Split a body ONLY on midrule (===). Clines (===N-M) stay inside their body
-- and are processed later (per-format strategy).
local function split_body(body)
  local bodies  = {}
  local current = {}

  for _, row in ipairs(body.body) do
    if is_midrule(row) then
      if #current > 0 then
        table.insert(bodies, clone_body(body, current))
        current = {}
      end
    else
      table.insert(current, row)
    end
  end

  if #current > 0 then
    table.insert(bodies, clone_body(body, current))
  end

  -- No midrule found: return the original body untouched.
  if #bodies == 0 then return { body } end
  return bodies
end

-- True if the table has at least one cell with row_span > 1.
local function table_has_rowspan(tbl)
  local function check(rows)
    for _, row in ipairs(rows or {}) do
      for _, cell in ipairs(row.cells) do
        if (cell.row_span or 1) > 1 then return true end
      end
    end
    return false
  end
  if tbl.head and tbl.head.rows and check(tbl.head.rows) then return true end
  for _, body in ipairs(tbl.bodies or {}) do
    if check(body.body) then return true end
  end
  return false
end

-- ── Markers used in the LaTeX post-processing pipeline ────────────────────

local MIDRULE_MARKER = "QUARTABLEMIDRULEMARKER"
local CLINE_MARKER   = "QUARTABLECLINEMARKER"
local VR_START       = "QUARTABLEVRSTART"
local VR_END         = "QUARTABLEVREND"
local VL_START       = "QUARTABLEVLSTART"
local VL_END         = "QUARTABLEVLEND"
-- Alignment-only markers used for cs=1 cells with an explicit `align=`
-- attribute. Pandoc's LaTeX writer only wraps cs>1 cells with
-- `\multicolumn{N}{align}{...}`; cs=1 cells emit raw content even when
-- cell.alignment is set, so the alignment is silently dropped. We
-- restore it here by wrapping the cell in `\multicolumn{1}{align}{...}`
-- via marker injection.
local AL_START       = "QUARTABLEALSTART"
local AL_END         = "QUARTABLEALEND"

-- True if any body contains a cline row (===N-M).
local function table_has_cline(tbl)
  for _, body in ipairs(tbl.bodies or {}) do
    for _, row in ipairs(body.body or {}) do
      local s, k = parse_separator(row)
      if s and k == "cline" then return true end
    end
  end
  return false
end

-- Build the marker text for a cline row, encoding its ranges:
--   "QUARTABLECLINEMARKER:2-3:5-6"
local function encode_cline_marker(ranges)
  local s = CLINE_MARKER
  for _, r in ipairs(ranges) do
    s = s .. ":" .. r[1] .. "-" .. r[2]
  end
  return s
end

-- Replace a cline row by a marker row (single cell, col_span = n_cols).
local function cline_row_to_marker(ranges, n_cols)
  local marker_cell = pandoc.Cell({
    pandoc.Plain({ pandoc.RawInline("latex", encode_cline_marker(ranges)) })
  })
  marker_cell.col_span = n_cols
  return pandoc.Row({ marker_cell })
end

-- ── Cline rendering for HTML/Reveal ───────────────────────────────────────
--
-- HTML has no native cline. For each cline row, apply the CSS class
-- `quartable-cline-bottom` to the cells of the previous row whose logical
-- column range overlaps any of the [N, M] ranges, then drop the cline row.
-- The accompanying CSS adds `border-bottom` on the marked cells.
--
-- Logical column tracking is rebuilt while walking the rows (so rowspans
-- spanning earlier rows are accounted for).
local function add_cline_class(cell)
  if not cell.attr then cell.attr = pandoc.Attr() end
  cell.attr.classes = cell.attr.classes or {}
  for _, cls in ipairs(cell.attr.classes) do
    if cls == "quartable-cline-bottom" then return end
  end
  table.insert(cell.attr.classes, "quartable-cline-bottom")
end

local function ranges_overlap(cell_start, cell_end, ranges)
  for _, r in ipairs(ranges) do
    if cell_start <= r[2] and cell_end >= r[1] then return true end
  end
  return false
end

local function apply_html_clines(body)
  if not body.body then return end
  local new_rows = {}
  local occupied = {}

  for _, row in ipairs(body.body) do
    local s, k, ranges = parse_separator(row)
    if s and k == "cline" then
      -- Mark the cells of the most recently inserted row that overlap.
      if #new_rows > 0 then
        local prev_idx = #new_rows
        local prev_row = new_rows[prev_idx]
        local c = 1
        for _, cell in ipairs(prev_row.cells) do
          while occupied[prev_idx] and occupied[prev_idx][c] do c = c + 1 end
          local cs = cell.col_span or 1
          if ranges_overlap(c, c + cs - 1, ranges) then
            add_cline_class(cell)
          end
          c = c + cs
        end
      end
      -- The cline row itself is not appended to new_rows.
    else
      -- Regular row: append and update the rowspan-occupied tracking.
      local idx = #new_rows + 1
      occupied[idx] = occupied[idx] or {}
      local c = 1
      for _, cell in ipairs(row.cells) do
        while occupied[idx][c] do c = c + 1 end
        local cs = cell.col_span or 1
        local rs = cell.row_span or 1
        if rs > 1 then
          for dr = 1, rs - 1 do
            local fr = idx + dr
            occupied[fr] = occupied[fr] or {}
            for dc = 0, cs - 1 do
              occupied[fr][c + dc] = true
            end
          end
        end
        c = c + cs
      end
      table.insert(new_rows, row)
    end
  end

  body.body = new_rows
end

-- ── Vlines: collection + LaTeX application ────────────────────────────────
--
-- LaTeX strategy:
--   * Full-height vline (`.vl`/`.vr` without rspan) → inject `|` into the
--     column spec via post-processing of `\begin{longtable}{...}`.
--   * Vline with rspan=N → inject markers around the content of the cells
--     in the next N rows; markers are turned into `\multicolumn{1}{l|}{...}`
--     (or the alignment of an existing `\multicolumn` is modified) after
--     pandoc.write.

-- True if any cell of the table declares a vline.
local function table_has_vline(tbl)
  local function check(rows)
    for _, row in ipairs(rows or {}) do
      for _, cell in ipairs(row.cells) do
        if cell.attr and cell.attr.attributes
           and (cell.attr.attributes["quartable-vl"]
                or cell.attr.attributes["quartable-vr"]) then
          return true
        end
      end
    end
    return false
  end
  if tbl.head and tbl.head.rows and check(tbl.head.rows) then return true end
  for _, body in ipairs(tbl.bodies or {}) do
    if check(body.body) then return true end
  end
  return false
end

-- True if any cell of the table declares an explicit `align=`.
local function table_has_align(tbl)
  local function check(rows)
    for _, row in ipairs(rows or {}) do
      for _, cell in ipairs(row.cells) do
        if cell.attr and cell.attr.attributes
           and cell.attr.attributes["quartable-align"] then
          return true
        end
      end
    end
    return false
  end
  if tbl.head and tbl.head.rows and check(tbl.head.rows) then return true end
  for _, body in ipairs(tbl.bodies or {}) do
    if check(body.body) then return true end
  end
  return false
end

-- Build grid[r][c] = cell occupying logical position (r, c) within a row
-- list, accounting for both col_span and row_span. Also returns
-- cell_info[cell] = { col_start, col_end } so callers know each cell's
-- logical column range (used to preserve @{} markers on cells at the
-- table edges when wrapping them in \multicolumn).
local function build_grid(rows)
  local grid = {}
  local cell_info = {}
  for r, row in ipairs(rows or {}) do
    grid[r] = grid[r] or {}
    local c = 1
    for _, cell in ipairs(row.cells) do
      while grid[r][c] do c = c + 1 end
      local cs = cell.col_span or 1
      local rs = cell.row_span or 1
      cell_info[cell] = { col_start = c, col_end = c + cs - 1 }
      for dr = 0, rs - 1 do
        grid[r + dr] = grid[r + dr] or {}
        for dc = 0, cs - 1 do
          grid[r + dr][c + dc] = cell
        end
      end
      c = c + cs
    end
  end
  return grid, cell_info
end

-- Inject align-only start/end markers around the content of a cs=1
-- cell with an explicit `align=` attribute. `letter` is one of l/c/r.
-- Pandoc's LaTeX writer does NOT honour `cell.alignment` for cs=1
-- cells; it only generates `\multicolumn{N}{align}{...}` for cs>1.
-- These markers are expanded in the LaTeX post-process to
-- `\multicolumn{1}{<letter>}{content}`, which forces the alignment.
local function inject_align_only_marker(cell, letter, col_start, col_end)
  local s_text = AL_START .. "_S" .. col_start .. "_E" .. col_end ..
                 "_A" .. letter .. "_"
  local e_text = AL_END
  if not cell.contents or #cell.contents == 0 then
    cell.contents = { pandoc.Plain({}) }
  end
  local block = cell.contents[1]
  if block.t == "Plain" or block.t == "Para" then
    table.insert(block.content, 1, pandoc.RawInline("latex", s_text))
    table.insert(block.content, pandoc.RawInline("latex", e_text))
  else
    table.insert(cell.contents, 1, pandoc.Plain({pandoc.RawInline("latex", s_text)}))
    table.insert(cell.contents, pandoc.Plain({pandoc.RawInline("latex", e_text)}))
  end
end

-- Walk the table and inject align-only markers on cs=1 cells that
-- carry an explicit `quartable-align` attribute. Skip cells that
-- already have a vline marker (their wrapping is handled by the vline
-- expansion path; combining the two on a cs=1 cell is an edge case
-- documented as such).
local function inject_align_only_markers_for_cs1(tbl, n_cols)
  local function process_rows(rows, row_offset)
    if not rows then return end
    local occ = {}
    for r, row in ipairs(rows) do
      occ[r] = occ[r] or {}
      local c = 1
      for _, cell in ipairs(row.cells) do
        while occ[r][c] do c = c + 1 end
        local cs = cell.col_span or 1
        local rs = cell.row_span or 1
        local attrs = cell.attr and cell.attr.attributes
        if cs == 1 and attrs then
          local align  = attrs["quartable-align"]
          local has_vl = attrs["quartable-vl"]
          local has_vr = attrs["quartable-vr"]
          if align and not (has_vl or has_vr) then
            local letter = parse_align_letter(align)
            if letter then
              inject_align_only_marker(cell, letter, c, c)
            end
          end
        end
        if rs > 1 then
          for dr = 1, rs - 1 do
            occ[r + dr] = occ[r + dr] or {}
            for dc = 0, cs - 1 do
              occ[r + dr][c + dc] = true
            end
          end
        end
        c = c + cs
      end
    end
  end
  if tbl.head then process_rows(tbl.head.rows) end
  for _, body in ipairs(tbl.bodies or {}) do
    process_rows(body.body)
  end
end

-- Inject vline start/end markers around a cell's content. The start
-- marker encodes the cell's logical column range (col_start, col_end)
-- so the post-process step can preserve `@{}` for cells at the table's
-- left/right edges (avoiding visible horizontal shift when the wrapped
-- \multicolumn loses the outer column spec's @{} marker).
local function inject_vline_markers(cell, side, col_start, col_end)
  local base_start = side == "vr" and VR_START or VL_START
  local s_text = base_start .. "_S" .. col_start .. "_E" .. col_end .. "_"
  local e_text = side == "vr" and VR_END or VL_END
  if not cell.contents or #cell.contents == 0 then
    cell.contents = { pandoc.Plain({}) }
  end
  local block = cell.contents[1]
  if block.t == "Plain" or block.t == "Para" then
    table.insert(block.content, 1, pandoc.RawInline("latex", s_text))
    table.insert(block.content, pandoc.RawInline("latex", e_text))
  else
    -- Non-inline block: prepend / append a Plain wrapping the markers.
    table.insert(cell.contents, 1, pandoc.Plain({pandoc.RawInline("latex", s_text)}))
    table.insert(cell.contents, pandoc.Plain({pandoc.RawInline("latex", e_text)}))
  end
end

-- Walk the table (head + bodies merged into a single absolute row sequence)
-- and collect:
--   full_positions  : set { boundary_pos = true } for full-height vlines
--   to_mark         : list of { cell, side } for limited-rspan vlines
-- Merging head and bodies allows an rspan declared in the head to extend
-- into the bodies.
local function collect_vlines(tbl)
  local full_positions = {}
  local to_mark = {}

  -- Concatenate head + bodies into a single row list (absolute numbering).
  local all_rows = {}
  if tbl.head and tbl.head.rows then
    for _, row in ipairs(tbl.head.rows) do
      table.insert(all_rows, row)
    end
  end
  for _, body in ipairs(tbl.bodies or {}) do
    for _, row in ipairs(body.body or {}) do
      table.insert(all_rows, row)
    end
  end
  if #all_rows == 0 then return full_positions, to_mark end

  local grid, cell_info = build_grid(all_rows)
  local function add_mark(target_cell, side)
    if not target_cell then return end
    local info = cell_info[target_cell] or { col_start = 0, col_end = 0 }
    table.insert(to_mark, {
      cell      = target_cell,
      side      = side,
      col_start = info.col_start,
      col_end   = info.col_end,
    })
  end
  local occ = {}
  for r, row in ipairs(all_rows) do
    occ[r] = occ[r] or {}
    local c = 1
    for _, cell in ipairs(row.cells) do
      while occ[r][c] do c = c + 1 end
      local cs = cell.col_span or 1
      local rs = cell.row_span or 1
      local attrs = cell.attr and cell.attr.attributes
      if attrs then
        local vl = attrs["quartable-vl"]
        local vr = attrs["quartable-vr"]
        -- VL: vline at boundary (c-1, c).
        if vl == "full" then
          full_positions[c - 1] = true
        elseif vl then
          local n = tonumber(vl)
          for dr = 0, n - 1 do
            if c == 1 then
              if grid[r + dr] and grid[r + dr][1] then
                add_mark(grid[r + dr][1], "vl")
              end
            else
              if grid[r + dr] and grid[r + dr][c - 1] then
                add_mark(grid[r + dr][c - 1], "vr")
              end
            end
          end
        end
        -- VR: vline at boundary (c+cs-1, c+cs).
        if vr == "full" then
          full_positions[c + cs - 1] = true
        elseif vr then
          local n = tonumber(vr)
          for dr = 0, n - 1 do
            if grid[r + dr] and grid[r + dr][c + cs - 1] then
              add_mark(grid[r + dr][c + cs - 1], "vr")
            end
          end
        end
      end
      if rs > 1 then
        for dr = 1, rs - 1 do
          occ[r + dr] = occ[r + dr] or {}
          for dc = 0, cs - 1 do
            occ[r + dr][c + dc] = true
          end
        end
      end
      c = c + cs
    end
  end

  -- Second pass: a full-height vline put in the column spec is overridden by
  -- any \multicolumn whose range covers the boundary. To keep the vline
  -- visible inside such rows, we mark every colspan cell whose edges align
  -- with a full-height position (its multicolumn alignment will get `|`).
  if next(full_positions) then
    local occ2 = {}
    for r, row in ipairs(all_rows) do
      occ2[r] = occ2[r] or {}
      local c = 1
      for _, cell in ipairs(row.cells) do
        while occ2[r][c] do c = c + 1 end
        local cs = cell.col_span or 1
        local rs = cell.row_span or 1
        if cs > 1 then
          if full_positions[c - 1] then
            add_mark(cell, "vl")
          end
          if full_positions[c + cs - 1] then
            add_mark(cell, "vr")
          end
        end
        if rs > 1 then
          for dr = 1, rs - 1 do
            occ2[r + dr] = occ2[r + dr] or {}
            for dc = 0, cs - 1 do
              occ2[r + dr][c + dc] = true
            end
          end
        end
        c = c + cs
      end
    end
  end

  return full_positions, to_mark
end

-- Apply markers on collected cells (deduplicated per cell × side).
local function apply_vline_markers(to_mark)
  local marked = {}  -- cell -> { vl=bool, vr=bool, col_start, col_end }
  for _, m in ipairs(to_mark) do
    local entry = marked[m.cell]
    if not entry then
      entry = { col_start = m.col_start, col_end = m.col_end }
      marked[m.cell] = entry
    end
    entry[m.side] = true
  end
  for cell, info in pairs(marked) do
    if info.vl then
      inject_vline_markers(cell, "vl", info.col_start, info.col_end)
    end
    if info.vr then
      inject_vline_markers(cell, "vr", info.col_start, info.col_end)
    end
  end
end

-- Modify the column spec inside `\begin{longtable}[OPT]{COLSPEC}` by
-- injecting `|` at the requested boundaries. Returns the string unchanged
-- if the column spec is too complex to parse (e.g. uses p{...}).
--
-- Note: when both vertical lines (`|`) and booktabs rules coexist, the
-- vertical lines have small visible gaps where they cross the horizontal
-- rules. This is intrinsic to booktabs (the package author actively
-- discourages vertical rules) and we do not attempt to work around it.
local function modify_colspec_for_vlines(latex_str, full_positions, n_cols)
  if not next(full_positions) then return latex_str end
  return latex_str:gsub("(\\begin{longtable}%b[])(%b{})",
    function(prefix, colspec_braced)
      local inner = colspec_braced:sub(2, -2)
      -- Match the simple form: @{}<letters>@{} or just <letters>.
      local lpre, letters, lsuf = inner:match("^(@{})([lrcLRC]+)(@{})$")
      if not letters then
        letters = inner:match("^([lrcLRC]+)$")
        lpre, lsuf = "", ""
      end
      if not letters or #letters ~= n_cols then
        io.stderr:write(
          "[quartable] full-height vline: complex column spec, " ..
          "modification skipped (use rspan=N instead).\n"
        )
        return prefix .. colspec_braced
      end
      local out = lpre
      for i = 0, n_cols do
        if full_positions[i] then out = out .. "|" end
        if i < n_cols then out = out .. letters:sub(i + 1, i + 1) end
      end
      out = out .. lsuf
      return prefix .. "{" .. out .. "}"
    end)
end

-- Expand VR/VL markers in the rendered LaTeX string. Each start marker
-- carries the cell's logical column range as `_S{col_start}_E{col_end}_`
-- so we can preserve the outer column spec's `@{}` markers when wrapping
-- cells at the table edges (avoids horizontal shift).
--
-- Case A: marker inside an existing \multicolumn{N}{ALIGN}{...} (Pandoc
--         already wrapped a colspan cell) → modify ALIGN instead of wrapping.
-- Case B: marker in a regular cell → wrap with \multicolumn{1}{...}{...},
--         picking @{}l|, l|@{}, l|, etc. depending on column position.
local function expand_vline_markers(latex_str, n_cols)
  local vr_start_pat = VR_START .. "_S(%d+)_E(%d+)_"
  local vl_start_pat = VL_START .. "_S(%d+)_E(%d+)_"

  -- Case A: existing \multicolumn (colspan cell). %b{} is required for ALIGN
  -- because it may itself contain nested braces (e.g. `l@{}`). Pandoc
  -- already preserves @{} in ALIGN for first/last-column multicolumn
  -- cells, so we just need to add `|` (the encoded col positions are
  -- redundant here and are simply stripped along with the markers).
  latex_str = latex_str:gsub("(\\multicolumn){(%d+)}(%b{})(%b{})",
    function(mc, n, align_b, content_b)
      local content = content_b:sub(2, -2)
      local has_vr = content:find(VR_START, 1, true)
      local has_vl = content:find(VL_START, 1, true)
      if not (has_vr or has_vl) then
        return mc .. "{" .. n .. "}" .. align_b .. content_b
      end
      -- Strip markers (with their encoded col positions).
      content = content:gsub(vr_start_pat, ""):gsub(VR_END, "")
      content = content:gsub(vl_start_pat, ""):gsub(VL_END, "")
      local align = align_b:sub(2, -2)
      if has_vl then align = "|" .. align end
      if has_vr then align = align .. "|" end
      return mc .. "{" .. n .. "}{" .. align .. "}{" .. content .. "}"
    end)

  -- Case B: remaining markers → wrap with \multicolumn{1}{...}{...}.
  -- We preserve `@{}` if the cell sits at col 1 (left edge of the table)
  -- or at the last column (right edge), so the wrapped cell stays aligned
  -- with surrounding rows.
  latex_str = latex_str:gsub(vr_start_pat .. "(.-)" .. VR_END,
    function(cs, ce, content)
      cs = tonumber(cs); ce = tonumber(ce)
      local prefix = (cs == 1)      and "@{}" or ""
      local suffix = (ce == n_cols) and "@{}" or ""
      return "\\multicolumn{1}{" .. prefix .. "l|" .. suffix .. "}{" .. content .. "}"
    end)
  latex_str = latex_str:gsub(vl_start_pat .. "(.-)" .. VL_END,
    function(cs, ce, content)
      cs = tonumber(cs); ce = tonumber(ce)
      local prefix = (cs == 1)      and "@{}" or ""
      local suffix = (ce == n_cols) and "@{}" or ""
      return "\\multicolumn{1}{" .. prefix .. "|l" .. suffix .. "}{" .. content .. "}"
    end)

  -- Align-only markers (for cs=1 cells with explicit `align=`).
  -- Pandoc emits cs=1 cells as raw content; we wrap them manually with
  -- `\multicolumn{1}{<a>}{content}` to force the alignment, preserving
  -- `@{}` on the table-edge columns the same way the vline path does.
  local al_start_pat = AL_START .. "_S(%d+)_E(%d+)_A([lcr])_"
  latex_str = latex_str:gsub(al_start_pat .. "(.-)" .. AL_END,
    function(cs, ce, a, content)
      cs = tonumber(cs); ce = tonumber(ce)
      local prefix = (cs == 1)      and "@{}" or ""
      local suffix = (ce == n_cols) and "@{}" or ""
      return "\\multicolumn{1}{" .. prefix .. a .. suffix .. "}{" .. content .. "}"
    end)
  latex_str = latex_str:gsub(al_start_pat, ""):gsub(AL_END, "")
  latex_str = latex_str:gsub(AL_START, "")

  -- Defensive cleanup: remove any leftover marker (with or without col info).
  latex_str = latex_str:gsub(vr_start_pat, ""):gsub(VR_END, "")
  latex_str = latex_str:gsub(vl_start_pat, ""):gsub(VL_END, "")
  latex_str = latex_str:gsub(VR_START, ""):gsub(VL_START, "")
  return latex_str
end

-- ── Filter entry point ────────────────────────────────────────────────────

function Table(tbl)
  -- Pandoc does NOT honour row_span on cells inside tbl.head: if the
  -- header contains a rowspan, move all header rows into the first body.
  -- The <thead> ends up empty. By design quartable does NOT redraw a
  -- head/body separator afterwards — booktabs explicitly leaves that
  -- decision to the author, especially when the head contains spans.
  -- Use `===` (or `===N-M`) explicitly to insert a separator if needed.
  local move_head = false
  if tbl.head and tbl.head.rows and #tbl.head.rows > 0 then
    move_head = rows_have_rowspan(tbl.head.rows)
  end

  if move_head and #tbl.bodies > 0 then
    local body = tbl.bodies[1]
    local new_body = {}
    for _, row in ipairs(tbl.head.rows) do
      table.insert(new_body, row)
    end
    for _, row in ipairs(body.body) do
      table.insert(new_body, row)
    end
    body.body = new_body
    tbl.head.rows = {}
  end

  -- Leading separator: a `===` (or `===N-M`) placed as the FIRST row of
  -- the first body is the user's way to ask for an explicit head/body
  -- separator. We detect it here (before split_body would silently drop
  -- a leading midrule) and use the flag to:
  --   * keep Pandoc's automatic \midrule\endhead in LaTeX
  --   * tag the table with `quartable-head-sep` for HTML/Reveal CSS.
  local has_leading_midrule = false
  if tbl.bodies[1] and tbl.bodies[1].body and #tbl.bodies[1].body > 0 then
    if is_midrule(tbl.bodies[1].body[1]) then
      has_leading_midrule = true
    end
  end

  -- Process the header (if any rows remain).
  if tbl.head and tbl.head.rows and #tbl.head.rows > 0 then
    tbl.head.rows = process_spans(tbl.head.rows)
  end

  -- Process each body: spans, then split on midrules.
  local new_bodies = {}
  for _, body in ipairs(tbl.bodies) do
    warn_rowspan_crosses_separator(body.body)
    body.body = process_spans(body.body)
    for _, b in ipairs(split_body(body)) do
      table.insert(new_bodies, b)
    end
  end
  tbl.bodies = new_bodies

  -- ── LaTeX strategy ────────────────────────────────────────────────────
  -- Pandoc 3.x does not insert \midrule between consecutive TableBody, and
  -- it generates \multirow{N}{=}{...} which overflows with l/r/c columns.
  -- We work around both by:
  --   1. Injecting marker rows at the start of each non-first TableBody.
  --   2. Rendering the table with pandoc.write.
  --   3. Post-processing the LaTeX string to replace marker rows with
  --      \midrule / \cline{...}, and \multirow{N}{=} with \multirow{N}{*}.
  -- This pipeline is only triggered when needed (rowspan, multiple bodies,
  -- clines or vlines).
  local is_latex = quarto and quarto.doc
                   and (quarto.doc.is_format("latex") or quarto.doc.is_format("pdf"))
  local n_cols = (tbl.colspecs and #tbl.colspecs) or 0
  local has_rowspan = table_has_rowspan(tbl)
  local has_cline   = table_has_cline(tbl)

  -- HTML/Reveal: render clines via CSS classes on the previous row's cells
  -- (border-bottom limited to the targeted columns).
  if has_cline and not is_latex then
    for _, body in ipairs(tbl.bodies) do
      apply_html_clines(body)
    end
  end


  local has_vline = table_has_vline(tbl)
  local has_align = table_has_align(tbl)

  -- Detect if any colspan cell exists (post process_spans).
  local has_colspan = false
  do
    local function check(rows)
      for _, row in ipairs(rows or {}) do
        for _, cell in ipairs(row.cells) do
          if (cell.col_span or 1) > 1 then return true end
        end
      end
      return false
    end
    if tbl.head and tbl.head.rows and check(tbl.head.rows) then has_colspan = true end
    if not has_colspan then
      for _, body in ipairs(tbl.bodies or {}) do
        if check(body.body) then has_colspan = true; break end
      end
    end
  end

  -- Tag tables that use any quartable feature with a `quartable` class so the
  -- bundled CSS can switch them to a clean booktabs-like style (instead of
  -- Quarto/Bootstrap's default per-row borders, which compete visually with
  -- our midrules and clines).
  local has_any_feature = #tbl.bodies > 1 or has_rowspan or has_cline
                          or has_vline or has_colspan or has_leading_midrule
                          or has_align
  if has_any_feature then
    if not tbl.attr then tbl.attr = pandoc.Attr() end
    tbl.attr.classes = tbl.attr.classes or {}
    local function ensure_class(cls)
      for _, c in ipairs(tbl.attr.classes) do
        if c == cls then return end
      end
      table.insert(tbl.attr.classes, cls)
    end
    ensure_class("quartable")
    -- Tag tables that ask for an explicit head/body separator so the CSS
    -- draws a border-bottom on the last header row.
    if has_leading_midrule then
      ensure_class("quartable-head-sep")
    end
  end

  -- Run the LaTeX post-process pipeline whenever the table uses any
  -- quartable feature: it is required for inter-body midrules, clines,
  -- vlines AND for stripping Pandoc's auto \midrule\endhead (so the
  -- design "no automatic head/body separator" applies even on tables
  -- whose only feature is a colspan).
  local needs_post = is_latex and n_cols > 0 and has_any_feature

  if needs_post then
    -- 1a. Mark non-first bodies with a midrule marker row.
    for b = 2, #tbl.bodies do
      local body = tbl.bodies[b]
      local marker_cell = pandoc.Cell({
        pandoc.Plain({ pandoc.RawInline("latex", MIDRULE_MARKER) })
      })
      marker_cell.col_span = n_cols
      local marker_row = pandoc.Row({ marker_cell })
      table.insert(body.body, 1, marker_row)
    end


    -- 1b. Replace cline rows with a marker row encoding their ranges.
    if has_cline then
      for _, body in ipairs(tbl.bodies) do
        for i, row in ipairs(body.body) do
          local s, k, ranges = parse_separator(row)
          if s and k == "cline" then
            body.body[i] = cline_row_to_marker(ranges, n_cols)
          end
        end
      end
    end

    -- 1c. Collect vlines + inject markers on the targeted cells (for
    --     limited-rspan vlines). Full-height vlines are recorded in
    --     full_positions and applied via the column spec.
    local full_positions, to_mark = collect_vlines(tbl)
    apply_vline_markers(to_mark)

    -- 1d. Inject align-only markers on cs=1 cells with explicit
    --     `align=`. Pandoc only auto-wraps cs>1 cells with
    --     `cell.alignment`; cs=1 cells need manual wrapping.
    inject_align_only_markers_for_cs1(tbl, n_cols)

    -- 2. Render the table to LaTeX.
    local doc = pandoc.Pandoc({ tbl }, pandoc.Meta({}))
    local ok, latex_str = pcall(pandoc.write, doc, "latex")

    if ok and latex_str and latex_str ~= "" then
      -- 3a. \multirow{N}{=} → \multirow{N}{*} (avoids overflow).
      latex_str = latex_str:gsub("\\multirow{(%d+)}{=}", "\\multirow{%1}{*}")
      latex_str = latex_str:gsub("\\multirow%[([^%]]+)%]{(%d+)}{=}",
                                 "\\multirow[%1]{%2}{*}")

      -- 3a'. Remove the \midrule that Pandoc inserts between <thead> and
      --      <tbody>. By design, quartable does not draw an automatic
      --      head/body separator (booktabs leaves that decision to the
      --      author). Use `===` or `===N-M` explicitly to insert one.
      --      Exception: when the user writes a leading `===` as the
      --      first row of the first body, we keep Pandoc's auto midrule
      --      to honour that explicit request.
      if not has_leading_midrule then
        latex_str = latex_str:gsub("\\midrule\\noalign{}(%s*)\\endhead",
                                   "%1\\endhead")
      end

      -- 3b. Full-height vlines: column-spec injection.
      latex_str = modify_colspec_for_vlines(latex_str, full_positions, n_cols)

      -- 3c. Limited-rspan vlines: expand VR/VL markers.
      latex_str = expand_vline_markers(latex_str, n_cols)

      -- 3d. Replace marker rows with \midrule or \cmidrule(lr){N-M}…
      --     The full \multicolumn{}{}{} \\ structure is captured via %b{}
      --     to handle nested braces and embedded newlines.
      --     We use booktabs' \cmidrule(lr){...} rather than the LaTeX-
      --     standard \cline{...} so partial horizontal rules match the
      --     booktabs aesthetic (lighter, with consistent spacing and
      --     trimmed left/right ends).

      -- Pre-pass: strip leading `&` placeholders that Pandoc emits before
      -- a \multicolumn marker row when a rowspan from above occupies the
      -- leftmost columns. Without this, our replacement would leave the
      -- `&` orphaned in inter-row context — TeX then complains about a
      -- misplaced \noalign as soon as the next \cmidrule fires. We loop
      -- because multiple rowspans can stack multiple leading `&`s.
      do
        local prev
        repeat
          prev = latex_str
          latex_str = latex_str:gsub(
            "&%s+(\\multicolumn%s*%b{}%s*%b{}%s*%b{}%s*\\\\)",
            function(after_amp)
              if after_amp:find(CLINE_MARKER, 1, true)
                 or after_amp:find(MIDRULE_MARKER, 1, true) then
                return after_amp
              end
              return nil
            end)
        until prev == latex_str
      end

      -- Trim is decided per range based on adjacency to other ranges on
      -- the SAME line:
      --   * a side that touches another range gets booktabs' standard
      --     trim (so the two segments don't visually merge);
      --   * a free side on a multi-column range keeps the booktabs
      --     default `(lr)` look;
      --   * a free side on an ISOLATED single-column range is left
      --     untrimmed, since trimming both ends of a one-column span
      --     would reduce the segment to almost nothing.
      local function expand_cline(text)
        local ranges = {}
        for from, to in text:gmatch("(%d+)%-(%d+)") do
          table.insert(ranges, { tonumber(from), tonumber(to) })
        end
        local function has_neighbor(side, r)
          for _, r2 in ipairs(ranges) do
            if side == "left"  and r2[2] + 1 == r[1] then return true end
            if side == "right" and r2[1] - 1 == r[2] then return true end
          end
          return false
        end
        local out = ""
        for _, r in ipairs(ranges) do
          local l        = has_neighbor("left",  r)
          local rt       = has_neighbor("right", r)
          local single   = (r[1] == r[2])
          local opts
          if     l and rt              then opts = "lr"
          elseif l                     then opts = "l"
          elseif rt                    then opts = "r"
          elseif single                then opts = nil  -- isolated single col
          else                              opts = "lr" -- isolated multi  col
          end
          if out ~= "" then out = out .. "\n" end
          if opts then
            out = out .. "\\cmidrule(" .. opts .. "){"
                       .. r[1] .. "-" .. r[2] .. "}"
          else
            out = out .. "\\cmidrule{" .. r[1] .. "-" .. r[2] .. "}"
          end
        end
        return out
      end

      latex_str = latex_str:gsub(
        "\\multicolumn%s*%b{}%s*%b{}%s*%b{}%s*\\\\%s*\n?",
        function(match)
          if match:find(CLINE_MARKER, 1, true) then
            return expand_cline(match) .. "\n"
          elseif match:find(MIDRULE_MARKER, 1, true) then
            return "\\midrule\n"
          end
          return match
        end
      )

      -- 3e. Fallback: if a marker was not captured (e.g. single-column
      --     table), replace any line containing it.
      latex_str = latex_str:gsub("[^\n]*" .. CLINE_MARKER .. "[^\n]*\n?",
        function(match) return expand_cline(match) .. "\n" end)
      latex_str = latex_str:gsub("[^\n]*" .. MIDRULE_MARKER .. "[^\n]*\n?",
                                 "\\midrule\n")

      return pandoc.RawBlock("latex", latex_str)
    end
  end

  return tbl
end

-- ── Dependency injection (CSS for HTML/Reveal, packages for LaTeX) ────────

function Pandoc(doc)
  if quarto and quarto.doc then
    if quarto.doc.is_format("html:js") or quarto.doc.is_format("revealjs") then
      quarto.doc.add_html_dependency({
        name = "quartable",
        version = "0.1.0",
        stylesheets = { "quartable.css" }
      })
    end
    if quarto.doc.is_format("latex") then
      quarto.doc.use_latex_package("multirow")
      quarto.doc.use_latex_package("booktabs")
    end
  end
  return doc
end
