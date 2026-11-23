-- Run from SliceAtelier with Aseprite --batch --script tests/run.lua.
local root=app.fs.currentPath
local core=dofile(app.fs.joinPath(root,"extension","core.lua"))
local source=dofile(app.fs.joinPath(root,"extension","source.lua"))
local passed=0
local function test(name,fn)
  fn()
  passed=passed+1
  print("PASS "..name)
end
local red,blue={240,50,60,255},{40,90,240,255}
local function render(v,opts)
  local args={width=120,height=120,yaw=0,pitch=0,shading=false}
  for k,x in pairs(opts or {}) do args[k]=x end
  return core.render(core.mesh(v,1,0),args)
end

test("single pixel has six faces; adjacent pixels share hidden faces",function()
  local v=core.newVolume(2,1,1,"Y")
  core.addPixel(v,0,0,0,red,"one")
  assert(#core.mesh(v,1,0).faces==6)
  core.addPixel(v,1,0,0,blue,"two")
  assert(#core.mesh(v,1,0).faces==10)
end)
test("slice neighbors, exploded view, and bounds cannot alias",function()
  for _,axis in ipairs({"Y","Z"}) do
    local v=core.newVolume(2,2,2,axis)
    core.addPixel(v,0,0,0,red,1)
    core.addPixel(v,0,0,1,blue,2)
    assert(#core.mesh(v,1,0).faces==10)
    assert(#core.mesh(v,1,1).faces==12)
    assert(not core.get(v,-1,0,0))
    assert(not core.get(v,2,0,0))
  end
end)
test("depth buffer keeps front slice visible from either side",function()
  local v=core.newVolume(1,1,2,"Z")
  core.addPixel(v,0,0,0,red,"back")
  core.addPixel(v,0,0,1,blue,"front")
  local front=render(v)
  local k=60*120+60+1
  assert(front.hits[k]=="front")
  assert(front.pixels[k][3]==240)
  assert(render(v,{yaw=180}).hits[k]=="back")
  -- Also reverse traversal: visibility must not rely on drawing order.
  v.list[1],v.list[2]=v.list[2],v.list[1]
  assert(render(v).hits[k]=="front")
end)
test("top view, orthographic edges, output RGBA size",function()
  local v=core.newVolume(1,1,2,"Y")
  core.addPixel(v,0,0,0,red,"bottom")
  core.addPixel(v,0,0,1,blue,"top")
  local r=render(v,{pitch=90})
  assert(r.hits[60*120+60+1]=="top")
  assert(#core.rgbaBytes(r)==120*120*4)
  assert(render(v,{pitch=-90}).hits[60*120+60+1]=="bottom")
end)

local sprite=Sprite(8,8,ColorMode.RGB)
local bottom=sprite.layers[1]
bottom.name="Bottom"
local image=Image(3,2,ColorMode.RGB)
image:clear()
image:drawPixel(0,0,app.pixelColor.rgba(240,50,60,255))
image:drawPixel(1,0,app.pixelColor.rgba(240,50,60,127))
sprite:deleteCel(bottom:cel(1))
sprite:newCel(bottom,1,image,Point(2,3))
local top=sprite:newLayer()
top.name="Top"
sprite:newCel(top,1,image,Point(4,2))
local opts={axis="Y",includeHidden=false}
test("real Aseprite cels use positions, alpha threshold and layer order",function()
  local d=source.describe(sprite,1)
  local v=source.build(core,d,opts)
  assert(v.count==2 and v.depth==2)
  assert(core.get(v,2,0,4).layer==bottom)
  assert(core.get(v,4,1,5).layer==top)
end)
test("hidden slices preserve depth, including hidden parent groups",function()
  top.isVisible=false
  local v=source.build(core,source.describe(sprite,1),opts)
  assert(v.count==1 and v.depth==2)
  opts.includeHidden=true
  assert(source.build(core,source.describe(sprite,1),opts).count==2)
  opts.includeHidden=false
  local group=sprite:newGroup()
  top.parent=group
  top.isVisible=true
  group.isVisible=false
  assert(source.build(core,source.describe(sprite,1),opts).count==1)
  group.isVisible=true
end)
test("signature observes paint, move, reorder and undo",function()
  local before=source.describe(sprite,1).signature
  app.transaction("Test paint",function()
    local copy=bottom:cel(1).image:clone()
    copy:drawPixel(2,1,app.pixelColor.rgba(20,200,40,255))
    bottom:cel(1).image=copy
  end)
  assert(source.describe(sprite,1).signature~=before)
  assert(source.build(core,source.describe(sprite,1),opts).count==3)
  app.command.Undo()
  assert(source.build(core,source.describe(sprite,1),opts).count==2)
  local old=source.describe(sprite,1).signature
  bottom:cel(1).position=Point(-1,0)
  assert(source.describe(sprite,1).signature~=old)
  assert(source.build(core,source.describe(sprite,1),opts).count==1)
end)
test("empty cels and frame switching retain slice slots",function()
  sprite:newEmptyFrame()
  local v=source.build(core,source.describe(sprite,2),opts)
  assert(v.depth==2 and v.count==0)
end)
sprite:close()

test("indexed palette, transparency and grayscale pixels",function()
  local s=Sprite(2,2,ColorMode.INDEXED)
  local p=s.palettes[1]
  p:setColor(1,Color(12,34,56,255))
  local im=Image(2,2,ColorMode.INDEXED)
  im:clear(0)
  im:drawPixel(1,1,1)
  s.layers[1]:cel(1).image=im
  local d=source.describe(s,1)
  local v=source.build(core,d,opts)
  assert(v.count==1 and v.list[1].color[2]==34)
  p:setColor(1,Color(90,80,70,255))
  assert(source.describe(s,1).signature~=d.signature)
  s:close()
  s=Sprite(2,2,ColorMode.GRAY)
  im=Image(2,2,ColorMode.GRAY)
  im:clear()
  im:drawPixel(0,0,app.pixelColor.graya(99,255))
  s.layers[1]:cel(1).image=im
  v=source.build(core,source.describe(s,1),opts)
  assert(v.count==1 and v.list[1].color[1]==99)
  s:close()
end)
test("demo builds in real Aseprite and renders preview artifact",function()
  local demo=dofile(app.fs.joinPath(root,"extension","demo.lua"))()
  local v=source.build(core,source.describe(demo,1),opts)
  assert(v.depth==24 and v.count>2000)
  local mesh=core.mesh(v,1,0)
  local start=os.clock()
  local r=core.render(mesh,{width=360,height=280,yaw=35,pitch=25,shading=true})
  print(string.format("Demo: %d cells, %d surface faces, render %.3fs",v.count,#mesh.faces,os.clock()-start))
  local image=Image(r.width,r.height,ColorMode.RGB)
  image.bytes=core.rgbaBytes(r)
  image:saveAs(app.fs.joinPath(root,"artifacts","demo-preview.png"))
  demo:saveAs(app.fs.joinPath(root,"artifacts","mushroom.aseprite"))
  demo:close()
end)
print(string.format("ALL %d TESTS PASSED",passed))
