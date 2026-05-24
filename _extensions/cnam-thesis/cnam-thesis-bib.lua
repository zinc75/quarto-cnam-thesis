--[[
  cnam-thesis-bib.lua — post-citeproc bibliography cleanup filter

  Runs AFTER citeproc (positioned via "citeproc" sentinel in _quarto.yml filters).
  Removes the bibliography div that citeproc auto-places at the end of every HTML
  chapter page. Only the dedicated bibliography page (bibliographie.qmd /
  bibliography.qmd) should display references — citeproc auto-places there too,
  and we leave it untouched.
--]]

local function is_bibliography_page()
  for _, f in ipairs(PANDOC_STATE.input_files or {}) do
    if f:match("bibliograph") then return true end
  end
  return false
end

local on_bib_page = is_bibliography_page()

function Div(el)
  if FORMAT:match("html") and not on_bib_page then
    if el.identifier == "refs" then
      return {}
    end
  end
  return el
end
