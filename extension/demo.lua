-- Creates a new unsaved document; never changes the document being edited.
return function()
  local sprite = Sprite(32,32,ColorMode.RGB)
  app.transaction("Create Slice Atelier mushroom", function()
    local first = sprite.layers[1]
    for k=0,23 do
      local layer = k == 0 and first or sprite:newLayer()
      layer.name = string.format("Slice %02d",k+1)
      local image = Image(32,32,ColorMode.RGB)
      image:clear()
      local radius = k < 12 and (k < 2 and 5 or 3) or math.sqrt(math.max(0,144-(k-12)^2))
      for y=0,31 do
        for x=0,31 do
          local dx,dz = x-15.5,y-15.5
          if dx*dx+dz*dz <= radius*radius then
            local r,g,b = 224,208,166
            if k >= 12 then
              r,g,b = 207,65,79
              if k == 12 then r,g,b=243,186,152 end
              if k > 13 and ((x-11)^2+(y-12)^2 < 6 or (x-20)^2+(y-18)^2 < 8 or (x-13)^2+(y-22)^2 < 4) then r,g,b=255,232,193 end
            elseif x < 15 then r,g,b=242,226,187 end
            image:drawPixel(x,y,app.pixelColor.rgba(r,g,b,255))
          end
        end
      end
      if k == 0 then sprite:deleteCel(first:cel(1)) end
      sprite:newCel(layer,1,image,Point(0,0))
    end
  end)
  app.sprite = sprite
  app.layer = sprite.layers[1]
  app.refresh()
  return sprite
end
