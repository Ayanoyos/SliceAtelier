local core, source, createDemo
local active

local function openPreview(plugin)
  if not app.isUIAvailable then return end
  if active then active.dialog:close() end
  local state = {yaw=35,pitch=25,zoom=1,panX=0,panY=0,axis="Y",
    thickness=1,gap=0,includeHidden=false,shading=true,highlight=false,
    dirty=true,meshDirty=true,renderDirty=true,closed=false,bindings={},status="Open a sprite to begin"}
  local dlg, timer
  local function repaint() if not state.closed then dlg:repaint() end end
  local function dirty() state.dirty=true end
  local function disconnectSprite()
    for _, b in ipairs(state.bindings) do pcall(function() b.events:off(b.id) end) end
    state.bindings={}
    state.sprite=nil
  end
  local function bindSprite(sprite)
    disconnectSprite()
    state.sprite=sprite
    if sprite then
      for _, name in ipairs({"change","layername","layeropacity","layervisibility"}) do
        local ok,id = pcall(function() return sprite.events:on(name,dirty) end)
        if ok then state.bindings[#state.bindings+1]={events=sprite.events,id=id} end
      end
    end
  end
  local function close()
    if state.closed then return end
    state.closed=true
    if timer then timer:stop() end
    disconnectSprite()
    if state.siteListener then app.events:off(state.siteListener) end
    if state.commandListener then app.events:off(state.commandListener) end
    if active == state then active=nil end
  end
  local function update()
    if state.closed then return end
    local sprite = app.sprite
    if sprite ~= state.sprite then bindSprite(sprite); state.dirty=true; state.signature=nil end
    if not sprite then
      state.volume,state.mesh,state.image,state.render=nil,nil,nil,nil
      state.status="Open a sprite, or click New demo"
      state.signature=nil
      repaint()
      return
    end
    local desc = source.describe(sprite, app.frame and app.frame.frameNumber or 1)
    if state.dirty or desc.signature ~= state.signature then
      -- Build atomically: invalid/large documents never leave stale volume visible.
      local volume = source.build(core,desc,state)
      state.volume=volume
      state.signature=desc.signature
      state.dirty=false
      state.meshDirty=true
      state.status=string.format("%d slices | %d solid pixels | frame %d",#desc.items,volume.count,desc.frame)
      if #desc.items == 0 then state.status="Add regular image layers to create slices" end
      if volume.count == 0 then state.status="No solid pixels (alpha must be 128 or above)" end
    end
    if state.meshDirty and state.volume then
      state.mesh=core.mesh(state.volume,state.thickness,state.gap)
      state.meshDirty=false
      state.renderDirty=true
    end
    local selected=state.highlight and app.layer or nil
    if selected ~= state.selected then state.selected=selected; state.renderDirty=true end
    if state.renderDirty then repaint() end
  end
  local function safeUpdate()
    local ok,err=pcall(update)
    if not ok then
      state.volume,state.mesh,state.image,state.render=nil,nil,nil,nil
      state.status=tostring(err):match("[^:]+$") or tostring(err)
      state.dirty=false
      -- Retain signature until another edit/Refresh, instead of repeatedly rebuilding a bad document.
      local good,desc=pcall(function()
        return source.describe(app.sprite,app.frame and app.frame.frameNumber or 1)
      end)
      if good and desc then state.signature=desc.signature end
      repaint()
    end
  end
  local function renderChange() state.renderDirty=true; repaint() end
  local function reset(yaw,pitch)
    state.yaw,state.pitch,state.zoom,state.panX,state.panY=yaw,pitch,1,0,0
    renderChange()
  end
  dlg=Dialog{title="Slice Atelier - Live 3D", onclose=close}
  state.dialog=dlg
  active=state
  dlg:canvas{id="preview",width=300,height=220,autoscaling=true,
    onpaint=function(ev)
      local gc=ev.context
      gc.antialias=false
      gc.color=Color(27,31,40)
      gc:fillRect(Rectangle(0,0,gc.width,gc.height))
      local w,h=math.max(1,math.floor(gc.width)),math.max(1,math.floor(gc.height))
      -- Cap CPU rasterization; keep nearest-neighbor display when the window grows.
      local ratio=math.min(1,420/w,320/h)
      local rw,rh=math.max(1,math.floor(w*ratio)),math.max(1,math.floor(h*ratio))
      if state.mesh and (state.renderDirty or state.rw~=rw or state.rh~=rh) then
        state.render=core.render(state.mesh,{width=rw,height=rh,yaw=state.yaw,pitch=state.pitch,
          zoom=state.zoom,panX=state.panX*ratio,panY=state.panY*ratio,
          shading=state.shading,highlight=state.selected})
        state.image=Image(rw,rh,ColorMode.RGB)
        state.image.bytes=core.rgbaBytes(state.render)
        state.rw,state.rh,state.renderDirty=rw,rh,false
      end
      if state.image then gc:drawImage(state.image,0,0,state.rw,state.rh,0,0,w,h) end
      gc.color=Color(224,231,241)
      gc:fillText(state.status,8,8)
      gc.color=Color(149,165,187)
      gc:fillText(string.format("YAW %03d   TILT %+03d   %d%%",math.floor(state.yaw%360),math.floor(state.pitch),math.floor(state.zoom*100)),8,h-16)
    end,
    onmousedown=function(ev)
      state.drag={x=ev.x,y=ev.y,yaw=state.yaw,pitch=state.pitch,
        px=state.panX,py=state.panY,pan=ev.button==MouseButton.RIGHT or ev.button==MouseButton.MIDDLE or ev.shiftKey}
    end,
    onmouseup=function() state.drag=nil end,
    onmousemove=function(ev)
      local d=state.drag
      if not d then return end
      if d.pan then state.panX,state.panY=d.px+ev.x-d.x,d.py+ev.y-d.y
      else
        state.yaw=(d.yaw+(ev.x-d.x)*.7)%360
        state.pitch=math.max(-90,math.min(90,d.pitch+(ev.y-d.y)*.5))
      end
      renderChange()
    end,
    onwheel=function(ev)
      state.zoom=math.max(.25,math.min(8,state.zoom*1.12^(-ev.deltaY)))
      renderChange()
    end,
    ondblclick=function() reset(35,25) end}
  dlg:label{text="Drag: rotate | Shift/right drag: pan | Wheel: zoom"}
  dlg:newrow()
  dlg:combobox{id="axis",label="Stack",option="Horizontal slices (Y)",
    options={"Horizontal slices (Y)","Front-facing slices (Z)"},onchange=function()
      state.axis=dlg.data.axis=="Horizontal slices (Y)" and "Y" or "Z"
      dirty(); safeUpdate()
    end}
  dlg:slider{id="thickness",label="Thickness %",min=25,max=400,value=100,onchange=function()
    state.thickness=dlg.data.thickness/100; state.meshDirty=true; safeUpdate()
  end}
  dlg:slider{id="gap",label="Explode %",min=0,max=400,value=0,onchange=function()
    state.gap=dlg.data.gap/100; state.meshDirty=true; safeUpdate()
  end}
  dlg:check{id="hidden",text="Include hidden",selected=false,onclick=function()
    state.includeHidden=dlg.data.hidden; dirty(); safeUpdate()
  end}
  dlg:check{id="shade",text="Shading",selected=true,onclick=function()
    state.shading=dlg.data.shade; renderChange()
  end}
  dlg:check{id="highlight",text="Highlight layer",selected=false,onclick=function()
    state.highlight=dlg.data.highlight; safeUpdate()
  end}
  dlg:newrow()
  dlg:button{text="3D",onclick=function() reset(35,25) end}
  dlg:button{text="Top",onclick=function() reset(0,90) end}
  dlg:button{text="Front",onclick=function() reset(0,0) end}
  dlg:button{text="Fit",onclick=function() state.zoom,state.panX,state.panY=1,0,0; renderChange() end}
  dlg:newrow()
  dlg:button{text="Refresh",onclick=function() dirty(); safeUpdate() end}
  dlg:button{text="New demo",onclick=function()
    createDemo()
    state.axis="Y"
    dlg:modify{id="axis",option="Horizontal slices (Y)"}
    dirty(); safeUpdate()
  end}
  dlg:button{text="Close",onclick=function() dlg:close() end}
  state.siteListener=app.events:on("sitechange",dirty)
  state.commandListener=app.events:on("aftercommand",dirty)
  timer=Timer{interval=.18,ontick=safeUpdate}
  dlg:show{wait=false}
  safeUpdate()
  timer:start()
end

function init(plugin)
  core=dofile(app.fs.joinPath(plugin.path,"core.lua"))
  source=dofile(app.fs.joinPath(plugin.path,"source.lua"))
  createDemo=dofile(app.fs.joinPath(plugin.path,"demo.lua"))
  plugin:newCommand{id="SliceAtelierPreview",title="Slice Atelier: Live 3D Preview",
    group="view_new",onclick=function() openPreview(plugin) end}
end

function exit(plugin)
  if active then active.dialog:close() end
end
