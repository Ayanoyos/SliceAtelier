-- Smoke test for real extension registration (in a separate test profile).
local root=app.params.root or app.fs.currentPath
dofile(app.fs.joinPath(root,"extension","demo.lua"))()
app.command.SliceAtelierPreview()
