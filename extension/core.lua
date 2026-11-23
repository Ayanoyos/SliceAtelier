-- Pure Lua volume and orthographic rasterizer. No document mutations or GPU needed.
local M = {}
local floor, min, max = math.floor, math.min, math.max

function M.newVolume(w, h, depth, axis)
  return { width=w, height=h, depth=depth, axis=axis or "Y",
    cells={}, list={}, count=0 }
end

local function key(v, x, y, z)
  return x + v.width * (z + v.height * y)
end

function M.addPixel(v, x, y, slice, color, layer)
  if x < 0 or y < 0 or x >= v.width or y >= v.height then return end
  local cx, cy, cz = x, slice, v.height - 1 - y
  if v.axis == "Z" then cx, cy, cz = x, v.height - 1 - y, slice end
  -- Dimensions for sparse keys must match the selected axes.
  local k
  if v.axis == "Z" then k = cx + v.width * (cy + v.height * cz)
  else k = key(v, cx, cy, cz) end
  if v.cells[k] then return end
  local cell = { x=cx, y=cy, z=cz, color=color, layer=layer }
  v.cells[k] = cell
  v.list[#v.list+1] = cell
  v.count = v.count + 1
end

function M.get(v, x, y, z)
  local sy = v.axis == "Y" and v.depth or v.height
  local sz = v.axis == "Z" and v.depth or v.height
  if x < 0 or y < 0 or z < 0 or x >= v.width or y >= sy or z >= sz then return nil end
  if v.axis == "Z" then return v.cells[x + v.width * (y + v.height * z)] end
  return v.cells[key(v, x, y, z)]
end

-- Vertex order is irrelevant to rasterization; normals are explicit.
local sides = {
  { 1,0,0, .80, {{1,0,0},{1,1,0},{1,1,1},{1,0,1}} },
  {-1,0,0, .68, {{0,0,1},{0,1,1},{0,1,0},{0,0,0}} },
  {0, 1,0, 1.0, {{0,1,0},{0,1,1},{1,1,1},{1,1,0}} },
  {0,-1,0, .55, {{0,0,1},{0,0,0},{1,0,0},{1,0,1}} },
  {0,0, 1, .90, {{1,0,1},{1,1,1},{0,1,1},{0,0,1}} },
  {0,0,-1, .72, {{0,0,0},{0,1,0},{1,1,0},{1,0,0}} },
}

function M.mesh(v, thickness, gap)
  thickness, gap = thickness or 1, gap or 0
  local faces = {}
  local sx, sy, sz = 1, 1, 1
  if v.axis == "Y" then sy = thickness else sz = thickness end
  local step = thickness + gap
  local extent = max(0,v.depth*step-gap)
  local dims = {v.width, v.axis == "Y" and extent or v.height,
    v.axis == "Z" and extent or v.height}
  for _, c in ipairs(v.list) do
    local ox, oy, oz = c.x, c.y, c.z
    if v.axis == "Y" then oy = oy * step else oz = oz * step end
    for _, s in ipairs(sides) do
      local separated = gap > 0 and ((v.axis == "Y" and s[2] ~= 0) or
        (v.axis == "Z" and s[3] ~= 0))
      if separated or not M.get(v, c.x+s[1], c.y+s[2], c.z+s[3]) then
        local f = {nx=s[1], ny=s[2], nz=s[3], shade=s[4], color=c.color, layer=c.layer}
        for i, p in ipairs(s[5]) do
          f[i] = {ox+p[1]*sx, oy+p[2]*sy, oz+p[3]*sz}
        end
        faces[#faces+1] = f
      end
    end
  end
  return {faces=faces, dims=dims}
end

local function edge(a, b, x, y)
  return (b[1]-a[1])*(y-a[2]) - (b[2]-a[2])*(x-a[1])
end

local function triangle(a, b, c, color, layer, w, h, pixels, depths, hits)
  local area = edge(a,b,c[1],c[2])
  if math.abs(area) < 1e-8 then return end
  local x0, x1 = max(0,floor(min(a[1],b[1],c[1]))), min(w-1,math.ceil(max(a[1],b[1],c[1])))
  local y0, y1 = max(0,floor(min(a[2],b[2],c[2]))), min(h-1,math.ceil(max(a[2],b[2],c[2])))
  local inv = 1 / area
  local du = -(c[2]-b[2])*inv
  local dv = -(a[2]-c[2])*inv
  for y=y0,y1 do
    local u = edge(b,c,x0+.5,y+.5)*inv
    local t = edge(c,a,x0+.5,y+.5)*inv
    for x=x0,x1 do
      local q = 1-u-t
      if u >= -1e-7 and t >= -1e-7 and q >= -1e-7 then
        local d = u*a[3]+t*b[3]+q*c[3]
        local k = y*w+x+1
        if not depths[k] or d > depths[k]+1e-7 then
          depths[k], pixels[k], hits[k] = d, color, layer
        end
      end
      u, t = u+du, t+dv
    end
  end
end

function M.render(mesh, opts)
  local w, h = opts.width, opts.height
  local yaw, pitch = math.rad(opts.yaw or 35), math.rad(opts.pitch or 25)
  local cy, sy, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
  local dx, dy, dz = table.unpack(mesh.dims)
  -- Fit the complete volume, so painting or rotating doesn't unexpectedly recenter it.
  local diameter = math.sqrt(dx*dx+dy*dy+dz*dz)
  local scale = min(w,h)*.80 / max(1,diameter) * (opts.zoom or 1)
  local pixels, depths, hits = {}, {}, {}
  local function project(p)
    local x,y,z = p[1]-dx/2,p[2]-dy/2,p[3]-dz/2
    local rx, rz = cy*x-sy*z, sy*x+cy*z
    return {w/2+rx*scale+(opts.panX or 0),
      h/2-(cp*y-sp*rz)*scale+(opts.panY or 0), sp*y+cp*rz}
  end
  local visible = 0
  for _, f in ipairs(mesh.faces) do
    if sp*f.ny+cp*(sy*f.nx+cy*f.nz) > 1e-6 then
      local s = opts.shading == false and 1 or f.shade
      local color = {floor(f.color[1]*s+.5),floor(f.color[2]*s+.5),floor(f.color[3]*s+.5)}
      if opts.highlight and f.layer == opts.highlight then
        color = {floor(color[1]*.65+80),floor(color[2]*.65+70),floor(color[3]*.65+20)}
      end
      local a,b,c,d = project(f[1]),project(f[2]),project(f[3]),project(f[4])
      triangle(a,b,c,color,f.layer,w,h,pixels,depths,hits)
      triangle(a,c,d,color,f.layer,w,h,pixels,depths,hits)
      visible = visible+1
    end
  end
  return {width=w,height=h,pixels=pixels,hits=hits,faces=visible}
end

function M.rgbaBytes(render, background)
  background = background or {27,31,40}
  local rows = {}
  for y=0,render.height-1 do
    local row = {}
    for x=0,render.width-1 do
      local c = render.pixels[y*render.width+x+1]
      if not c then
        local k = (floor(x/12)+floor(y/12)) % 2 == 0 and 0 or 4
        c = {background[1]+k,background[2]+k,background[3]+k}
      end
      row[#row+1] = string.char(c[1],c[2],c[3],255)
    end
    rows[#rows+1] = table.concat(row)
  end
  return table.concat(rows)
end

return M
