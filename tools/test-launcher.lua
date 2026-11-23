local ok,err=xpcall(function() dofile("tests/run.lua") end,debug.traceback)
if not ok then print("TEST FAILED\n"..tostring(err)) end
