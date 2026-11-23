-- Development launcher, no installation required. The CLI script param is optional.
local root=app.params.root or app.fs.currentPath
local path=app.fs.joinPath(root,"extension")
local command
dofile(app.fs.joinPath(path,"plugin.lua"))
init({path=path,newCommand=function(_,spec) command=spec.onclick end})
dofile(app.fs.joinPath(path,"demo.lua"))()
command()
