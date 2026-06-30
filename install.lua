local SOURCE = "https://raw.githubusercontent.com/R15ofc/v10-ravager-rotor-control-os/main"

local FILES = {
  { source = "v10/config.lua", target = "/v10/config.lua", overwrite = false },
  { source = "v10/rotor.lua", target = "/v10/rotor.lua", overwrite = true },
  { source = "startup.lua", target = "/startup.lua", overwrite = true },
}

local function parent(path)
  return fs.getDir(path)
end

local function ensure_dir(path)
  local dir = parent(path)
  if dir and dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

local function backup(path)
  if not fs.exists(path) then
    return nil
  end
  local candidate = path .. ".bak"
  local index = 1
  while fs.exists(candidate) do
    index = index + 1
    candidate = path .. ".bak" .. tostring(index)
  end
  fs.copy(path, candidate)
  return candidate
end

local function fetch(path)
  local url = SOURCE .. "/" .. path
  local handle, err = http.get(url, { ["Accept"] = "text/plain" })
  if not handle then
    error("download failed: " .. url .. " (" .. tostring(err) .. ")")
  end
  local code = handle.getResponseCode and handle.getResponseCode() or 200
  local body = handle.readAll()
  handle.close()
  if code < 200 or code >= 300 then
    error("download failed: " .. url .. " (HTTP " .. tostring(code) .. ")")
  end
  return body or ""
end

if not http then
  error("HTTP API is disabled")
end

print("Installing V-10 rotor control")

for _, file in ipairs(FILES) do
  if file.overwrite or not fs.exists(file.target) then
    local body = fetch(file.source)
    ensure_dir(file.target)
    if file.overwrite then
      local saved = backup(file.target)
      if saved then
        print("backup " .. file.target .. " -> " .. saved)
      end
    end
    local handle = fs.open(file.target, "w")
    if not handle then
      error("cannot write " .. file.target)
    end
    handle.write(body)
    handle.close()
    print("wrote " .. file.target)
  else
    print("kept " .. file.target)
  end
end

print("Done. Run: reboot")
