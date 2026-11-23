local M = {}

local function leaves(layers, visible, result)
  for _, layer in ipairs(layers) do
    local enabled = visible and layer.isVisible
    if layer.isGroup then leaves(layer.layers, enabled, result)
    elseif layer.isImage and not layer.isTilemap then
      result[#result+1] = {layer=layer, visible=enabled}
    end
  end
end

function M.describe(sprite, frameNumber)
  if not sprite then return nil end
  local items = {}
  leaves(sprite.layers, true, items)
  local sig = {sprite.id, sprite.width, sprite.height, frameNumber, sprite.colorMode, sprite.transparentColor}
  for _, item in ipairs(items) do
    local layer = item.layer
    local cel = layer:cel(frameNumber)
    item.cel = cel
    sig[#sig+1] = table.concat({layer.stackIndex, layer.name, tostring(item.visible),layer.opacity}, ":")
    if cel then
      local img = cel.image
      sig[#sig+1] = table.concat({img.id,img.version,img.width,img.height,
        cel.position.x,cel.position.y,cel.opacity}, ":")
    else sig[#sig+1] = "empty" end
  end
  -- Indexed palette edits can change the volume without changing image.version.
  local palette = sprite.palettes[1]
  for pi=1,#sprite.palettes do
    local p=sprite.palettes[pi]
    if p.frame.frameNumber <= frameNumber then palette = p end
  end
  if sprite.colorMode == ColorMode.INDEXED then
    for i=0,#palette-1 do
      local c = palette:getColor(i)
      sig[#sig+1] = table.concat({c.red,c.green,c.blue,c.alpha}, ",")
    end
  end
  for i,n in ipairs(sig) do sig[i] = tostring(n) end
  return {sprite=sprite, items=items, frame=frameNumber, palette=palette,
    signature=table.concat(sig,"|"), width=sprite.width, height=sprite.height}
end

function M.build(core, source, opts)
  local v = core.newVolume(source.width,source.height,#source.items,opts.axis)
  if #source.items > 256 then error("Use 256 image layers or fewer.") end
  local scanned, colors = 0, {}
  local pc, mode = app.pixelColor, source.sprite.colorMode
  local visible = 0
  for i,item in ipairs(source.items) do
    if opts.includeHidden or item.visible then
      visible = visible+1
      local cel = item.cel
      if cel then
        local image = cel.image
        scanned = scanned+image.width*image.height
        if scanned > 4194304 then error("Preview limit: 4 million source pixels. Try a smaller canvas.") end
        local opacity = item.layer.opacity*cel.opacity/(255*255)
        for it in image:pixels() do
          local raw = it()
          local c = colors[raw]
          if not c then
            if mode == ColorMode.RGB then
              c = {pc.rgbaR(raw),pc.rgbaG(raw),pc.rgbaB(raw),pc.rgbaA(raw)}
            elseif mode == ColorMode.GRAY then
              local g = pc.grayaV(raw)
              c = {g,g,g,pc.grayaA(raw)}
            else
              local p = source.palette:getColor(raw)
              c = {p.red,p.green,p.blue,p.alpha}
              -- Background layers have no transparent palette index.
            end
            colors[raw] = c
          end
          local alpha = c[4]*opacity
          if mode == ColorMode.INDEXED and raw == source.sprite.transparentColor and not item.layer.isBackground then alpha=0 end
          if alpha >= 128 then
            core.addPixel(v,it.x+cel.position.x,it.y+cel.position.y,i-1,c,item.layer)
            if v.count > 100000 then error("Preview limit: 100,000 solid pixels. Try fewer or smaller slices.") end
          end
        end
      end
    end
  end
  v.visibleLayers = visible
  return v
end

return M
