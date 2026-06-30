local CONFIG_PATH = "/v10/config.lua"
local CHANNEL_ORDER = { "front", "right", "rear", "left" }

local function clamp(value, min_value, max_value)
  value = tonumber(value) or 0
  if value < min_value then
    return min_value
  end
  if value > max_value then
    return max_value
  end
  return value
end

local function round(value)
  return math.floor(value + 0.5)
end

local function load_config()
  if not fs.exists(CONFIG_PATH) then
    error("missing " .. CONFIG_PATH)
  end

  local ok, config = pcall(dofile, CONFIG_PATH)
  if not ok then
    error("bad config: " .. tostring(config))
  end
  if type(config) ~= "table" then
    error("bad config: expected table")
  end
  return config
end

local function wrap_native_redstone()
  if not redstone then
    return nil
  end
  return {
    getSides = function()
      return redstone.getSides()
    end,
    setAnalogOutput = function(side, value)
      redstone.setAnalogOutput(side, value)
    end,
    getAnalogOutput = function(side)
      return redstone.getAnalogOutput(side)
    end,
  }
end

local function find_port(config)
  if peripheral and peripheral.find then
    local port = peripheral.find(config.port_type or "tm_rsPort")
    if port then
      return port, config.port_type or "tm_rsPort"
    end
  end

  local native = wrap_native_redstone()
  if native then
    return native, "native_redstone"
  end

  return nil, nil
end

local function has_side(port, side)
  if not port.getSides then
    return true
  end
  local ok, sides = pcall(port.getSides)
  if not ok or type(sides) ~= "table" then
    return true
  end
  for _, candidate in ipairs(sides) do
    if candidate == side then
      return true
    end
  end
  return false
end

local function validate_channels(port, config)
  for _, name in ipairs(CHANNEL_ORDER) do
    local channel = config.channels and config.channels[name]
    if not channel then
      error("missing channel: " .. name)
    end
    if type(channel.side) ~= "string" then
      error("bad side for channel: " .. name)
    end
    if not has_side(port, channel.side) then
      error("port has no side '" .. channel.side .. "' for channel " .. name)
    end
  end
end

local function channel_value(config, state, channel)
  local min_output = config.min_output or 0
  local max_output = config.max_output or 15
  local neutral = config.neutral_output or 7
  local value =
    neutral +
    ((state.collective - neutral) * (channel.collective or 0)) +
    (state.pitch * (channel.pitch or 0)) +
    (state.roll * (channel.roll or 0)) +
    (channel.trim or 0)

  value = clamp(round(value), min_output, max_output)
  if channel.invert then
    value = min_output + max_output - value
  end
  return value
end

local function apply_outputs(port, config, state)
  local values = {}
  for _, name in ipairs(CHANNEL_ORDER) do
    local channel = config.channels[name]
    local value = channel_value(config, state, channel)
    port.setAnalogOutput(channel.side, value)
    values[name] = value
  end
  return values
end

local function clear()
  if term and term.clear and term.setCursorPos then
    term.clear()
    term.setCursorPos(1, 1)
  end
end

local function draw(port_name, config, state, values, status)
  clear()
  print("V-10 rotor control")
  print("port: " .. port_name)
  print("")
  print("R/F collective  W/S pitch  A/D roll")
  print("SPACE neutral   X zero     CTRL+T exit")
  print("")
  print(string.format("collective: %2d  pitch: %+2d  roll: %+2d", state.collective, state.pitch, state.roll))
  print("")
  for _, name in ipairs(CHANNEL_ORDER) do
    local channel = config.channels[name]
    print(string.format("%-5s %-5s -> %2d", name, channel.side, values[name] or 0))
  end
  if status then
    print("")
    print(status)
  end
end

local function limit_state(config, state)
  local limits = config.limits or {}
  state.collective = clamp(
    state.collective,
    limits.collective_min or config.min_output or 0,
    limits.collective_max or config.max_output or 15
  )
  state.pitch = clamp(state.pitch, -(limits.pitch or 7), limits.pitch or 7)
  state.roll = clamp(state.roll, -(limits.roll or 7), limits.roll or 7)
end

local function neutral_state(config)
  return {
    collective = config.neutral_output or 7,
    pitch = 0,
    roll = 0,
  }
end

local function zero_state(config)
  return {
    collective = config.min_output or 0,
    pitch = 0,
    roll = 0,
  }
end

local function startup_state(config)
  local startup = config.startup or {}
  local state = {
    collective = startup.collective or config.neutral_output or 7,
    pitch = startup.pitch or 0,
    roll = startup.roll or 0,
  }
  limit_state(config, state)
  return state
end

local function main()
  local config = load_config()
  local port, port_name = find_port(config)
  if not port then
    error("tm_rsPort peripheral not found")
  end
  validate_channels(port, config)

  local state = startup_state(config)
  local step = config.key_step or 1
  local refresh = config.refresh or 0.05
  local values = apply_outputs(port, config, state)
  draw(port_name, config, state, values)

  local timer = os.startTimer(refresh)
  while true do
    local event, a = os.pullEventRaw()

    if event == "timer" and a == timer then
      values = apply_outputs(port, config, state)
      timer = os.startTimer(refresh)
    elseif event == "key" then
      if a == keys.r then
        state.collective = state.collective + step
      elseif a == keys.f then
        state.collective = state.collective - step
      elseif a == keys.w then
        state.pitch = state.pitch + step
      elseif a == keys.s then
        state.pitch = state.pitch - step
      elseif a == keys.d then
        state.roll = state.roll + step
      elseif a == keys.a then
        state.roll = state.roll - step
      elseif a == keys.space then
        state = neutral_state(config)
      elseif a == keys.x then
        state = zero_state(config)
      end

      limit_state(config, state)
      values = apply_outputs(port, config, state)
      draw(port_name, config, state, values)
    elseif event == "terminate" then
      state = neutral_state(config)
      limit_state(config, state)
      values = apply_outputs(port, config, state)
      draw(port_name, config, state, values, "terminated: outputs set to neutral")
      return
    end
  end
end

main()
