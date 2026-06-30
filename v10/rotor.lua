local CONFIG_PATH = "/v10/config.lua"

local FLAP_ORDER = { "front", "right", "rear", "left" }
local TAIL_MODES = {
  normal = true,
  reverse = true,
  stop = true,
  double = true,
}

local GLFW = {
  space = 32,
  one = 49,
  two = 50,
  three = 51,
  four = 52,
  a = 65,
  b = 66,
  c = 67,
  d = 68,
  e = 69,
  f = 70,
  n = 78,
  q = 81,
  r = 82,
  s = 83,
  w = 87,
  x = 88,
}

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
  if value >= 0 then
    return math.floor(value + 0.5)
  end
  return math.ceil(value - 0.5)
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
  if config.config_version ~= 2 then
    error("bad config: install v2 config or delete " .. CONFIG_PATH .. " and run installer again")
  end
  return config
end

local function wrap_native_redstone()
  if not redstone then
    return nil
  end
  return {
    name = "native_redstone",
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

local function peripheral_has_type(name, expected)
  if not peripheral or not peripheral.getType then
    return false
  end
  local result = { pcall(peripheral.getType, name) }
  if not result[1] then
    return false
  end
  for index = 2, #result do
    if result[index] == expected then
      return true
    end
  end
  return false
end

local function wrap_named(name, expected_type)
  if name == "native" then
    return wrap_native_redstone()
  end
  if not peripheral or not peripheral.wrap then
    return nil
  end
  if peripheral.isPresent and not peripheral.isPresent(name) then
    return nil
  end
  if expected_type and not peripheral_has_type(name, expected_type) then
    return nil
  end
  local wrapped = peripheral.wrap(name)
  return wrapped
end

local function find_first_port(port_type)
  if peripheral and peripheral.find then
    local port = peripheral.find(port_type)
    if port then
      return port
    end
  end
  return wrap_native_redstone()
end

local function make_io(config)
  local io = {
    config = config,
    ports = {},
    writes = {},
  }

  function io:port_name(ref)
    if ref and self.config.ports and self.config.ports[ref] then
      return self.config.ports[ref], ref
    end
    return ref, ref
  end

  function io:resolve_port(ref)
    local real_name, alias = self:port_name(ref)
    local cache_key = alias or real_name or "__default"
    if self.ports[cache_key] then
      return self.ports[cache_key]
    end

    local port = nil
    if real_name and real_name ~= "" and real_name ~= "auto" then
      port = wrap_named(real_name, self.config.port_type or "tm_rsPort")
    else
      port = find_first_port(self.config.port_type or "tm_rsPort")
    end

    if not port then
      error("redstone port not found: " .. tostring(alias or real_name or "auto"))
    end
    if not port.setAnalogOutput then
      error("port has no setAnalogOutput: " .. tostring(alias or real_name or "auto"))
    end

    self.ports[cache_key] = port
    return port
  end

  function io:has_side(port, side)
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

  function io:write(spec, value, label)
    if not spec or spec.disabled then
      return nil
    end
    if type(spec) ~= "table" then
      error("bad output spec for " .. tostring(label))
    end
    if type(spec.side) ~= "string" then
      error("missing side for " .. tostring(label))
    end

    local port = self:resolve_port(spec.port)
    if not self:has_side(port, spec.side) then
      error("port has no side '" .. spec.side .. "' for " .. tostring(label))
    end

    value = clamp(round(value), spec.min or 0, spec.max or 15)
    port.setAnalogOutput(spec.side, value)
    self.writes[label or spec.side] = value
    return value
  end

  function io:write_bool(spec, enabled, label)
    if not spec or spec.disabled then
      return nil
    end
    local on_value = spec.on
    if on_value == nil then
      on_value = 15
    end
    local off_value = spec.off
    if off_value == nil then
      off_value = 0
    end
    return self:write(spec, enabled and on_value or off_value, label)
  end

  return io
end

local function setup_keyboard(config)
  if not peripheral or not peripheral.find then
    return "none"
  end
  local keyboard = peripheral.find(config.keyboard_type or "tm_keyboard")
  if not keyboard then
    return "none"
  end
  if keyboard.setFireNativeEvents then
    keyboard.setFireNativeEvents(false)
    return "tm_keyboard"
  end
  return "tm_keyboard"
end

local function add_action(map, key_code, action)
  if key_code then
    map[key_code] = action
  end
end

local function build_keymap()
  local cc = {}
  if keys then
    add_action(cc, keys.r, "collective_up")
    add_action(cc, keys.f, "collective_down")
    add_action(cc, keys.w, "pitch_forward")
    add_action(cc, keys.s, "pitch_back")
    add_action(cc, keys.a, "roll_left")
    add_action(cc, keys.d, "roll_right")
    add_action(cc, keys.q, "yaw_reverse_hold")
    add_action(cc, keys.e, "yaw_double_hold")
    add_action(cc, keys.one, "tail_normal")
    add_action(cc, keys.two, "tail_reverse")
    add_action(cc, keys.three, "tail_stop")
    add_action(cc, keys.four, "tail_double")
    add_action(cc, keys.c, "toggle_clutch")
    add_action(cc, keys.space, "neutral_cyclic")
    add_action(cc, keys.n, "neutral_all")
    add_action(cc, keys.x, "zero_flaps")
    add_action(cc, keys.b, "panic")
  end

  local glfw = {}
  add_action(glfw, GLFW.r, "collective_up")
  add_action(glfw, GLFW.f, "collective_down")
  add_action(glfw, GLFW.w, "pitch_forward")
  add_action(glfw, GLFW.s, "pitch_back")
  add_action(glfw, GLFW.a, "roll_left")
  add_action(glfw, GLFW.d, "roll_right")
  add_action(glfw, GLFW.q, "yaw_reverse_hold")
  add_action(glfw, GLFW.e, "yaw_double_hold")
  add_action(glfw, GLFW.one, "tail_normal")
  add_action(glfw, GLFW.two, "tail_reverse")
  add_action(glfw, GLFW.three, "tail_stop")
  add_action(glfw, GLFW.four, "tail_double")
  add_action(glfw, GLFW.c, "toggle_clutch")
  add_action(glfw, GLFW.space, "neutral_cyclic")
  add_action(glfw, GLFW.n, "neutral_all")
  add_action(glfw, GLFW.x, "zero_flaps")
  add_action(glfw, GLFW.b, "panic")

  return cc, glfw
end

local function action_from_event(event, a, b)
  local cc_map, glfw_map = build_keymap()
  if event == "key" then
    return cc_map[a] or glfw_map[a], false
  end
  if event == "key_up" then
    return cc_map[a] or glfw_map[a], true
  end
  if event == "tm_keyboard_key" then
    return glfw_map[b], false
  end
  if event == "tm_keyboard_key_up" then
    return glfw_map[b], true
  end
  return nil, false
end

local function active_tail_mode(state)
  return state.yaw_hold or state.tail_mode or "normal"
end

local function limit_state(config, state)
  local limits = config.limits or {}
  state.collective = clamp(state.collective, limits.collective_min or 0, limits.collective_max or 15)
  state.pitch = clamp(state.pitch, -(limits.pitch or 15), limits.pitch or 15)
  state.roll = clamp(state.roll, -(limits.roll or 15), limits.roll or 15)
  if not TAIL_MODES[state.tail_mode] then
    state.tail_mode = "normal"
  end
end

local function startup_state(config)
  local startup = config.startup or {}
  local state = {
    collective = startup.collective or 0,
    pitch = startup.pitch or 0,
    roll = startup.roll or 0,
    lift_clutch = startup.lift_clutch ~= false,
    tail_mode = startup.tail_mode or "normal",
    yaw_hold = nil,
  }
  limit_state(config, state)
  return state
end

local function neutral_cyclic(state)
  state.pitch = 0
  state.roll = 0
  state.yaw_hold = nil
end

local function zero_flaps(state)
  state.collective = 0
  state.pitch = 0
  state.roll = 0
  state.yaw_hold = nil
end

local function neutral_all(config, state)
  local startup = startup_state(config)
  state.collective = startup.collective
  state.pitch = startup.pitch
  state.roll = startup.roll
  state.lift_clutch = startup.lift_clutch
  state.tail_mode = "normal"
  state.yaw_hold = nil
end

local function panic_state(state)
  state.collective = 0
  state.pitch = 0
  state.roll = 0
  state.yaw_hold = nil
  state.tail_mode = "stop"
  state.lift_clutch = false
end

local function flap_target(config, state, flap)
  local value =
    (state.collective * (flap.collective or 0)) +
    (state.pitch * (flap.pitch or 0)) +
    (state.roll * (flap.roll or 0)) +
    (flap.trim or 0)

  if flap.invert then
    value = -value
  end
  return clamp(round(value), -(config.limits and config.limits.flap or 15), config.limits and config.limits.flap or 15)
end

local function apply_flap(io, config, state, name, flap, values)
  local target = flap_target(config, state, flap)
  local positive = target > 0 and target or 0
  local negative = target < 0 and -target or 0

  values.flaps[name] = {
    target = target,
    positive = io:write(flap.positive, positive, name .. "+") or 0,
    negative = io:write(flap.negative, negative, name .. "-") or 0,
  }
end

local function apply_clutch(io, config, state, values)
  local clutch = config.lift_clutch
  if not clutch or not clutch.output then
    values.clutch = nil
    return
  end
  local powered = state.lift_clutch
  if clutch.powered_stops ~= false then
    powered = not state.lift_clutch
  end
  values.clutch = io:write_bool(clutch.output, powered, "lift_clutch") or 0
end

local function apply_tail(io, config, state, values)
  local tail = config.tail_prop or {}
  local mode = active_tail_mode(state)
  values.tail_mode = mode
  values.tail = {
    reverse = io:write_bool(tail.reverse, mode == "reverse", "tail_reverse") or 0,
    stop = io:write_bool(tail.stop, mode == "stop", "tail_stop") or 0,
    double = io:write_bool(tail.double, mode == "double", "tail_double") or 0,
  }
end

local function apply_outputs(io, config, state)
  local values = {
    flaps = {},
    tail = {},
  }

  for _, name in ipairs(FLAP_ORDER) do
    local flap = config.flaps and config.flaps[name]
    if not flap then
      error("missing flap config: " .. name)
    end
    apply_flap(io, config, state, name, flap, values)
  end

  apply_clutch(io, config, state, values)
  apply_tail(io, config, state, values)
  return values
end

local function clear()
  if term and term.clear and term.setCursorPos then
    term.clear()
    term.setCursorPos(1, 1)
  end
end

local function draw(config, state, values, keyboard_status, status)
  clear()
  print("V-10 rotor control")
  print("keyboard: " .. keyboard_status)
  print("")
  print("R/F lift  W/S pitch  A/D roll  Q/E yaw hold")
  print("1 normal  2 reverse  3 stop    4 x2")
  print("C clutch  SPACE level  X zero  B panic")
  print("")
  print(string.format(
    "collective:%2d pitch:%+3d roll:%+3d clutch:%s tail:%s",
    state.collective,
    state.pitch,
    state.roll,
    state.lift_clutch and "on " or "off",
    values.tail_mode or active_tail_mode(state)
  ))
  print("")

  for _, name in ipairs(FLAP_ORDER) do
    local flap = values.flaps[name] or { target = 0, positive = 0, negative = 0 }
    print(string.format("%-5s target:%+3d  +%2d -%2d", name, flap.target, flap.positive, flap.negative))
  end

  print("")
  print(string.format(
    "clutch:%2s  tail reverse:%2d stop:%2d x2:%2d",
    values.clutch == nil and "--" or tostring(values.clutch),
    values.tail.reverse or 0,
    values.tail.stop or 0,
    values.tail.double or 0
  ))

  if status then
    print("")
    print(status)
  end
end

local function handle_action(config, state, action, released)
  local step = config.key_step or 1
  if released then
    if action == "yaw_reverse_hold" and state.yaw_hold == "reverse" then
      state.yaw_hold = nil
    elseif action == "yaw_double_hold" and state.yaw_hold == "double" then
      state.yaw_hold = nil
    end
    return
  end

  if action == "collective_up" then
    state.collective = state.collective + step
  elseif action == "collective_down" then
    state.collective = state.collective - step
  elseif action == "pitch_forward" then
    state.pitch = state.pitch + step
  elseif action == "pitch_back" then
    state.pitch = state.pitch - step
  elseif action == "roll_left" then
    state.roll = state.roll - step
  elseif action == "roll_right" then
    state.roll = state.roll + step
  elseif action == "yaw_reverse_hold" then
    state.yaw_hold = "reverse"
  elseif action == "yaw_double_hold" then
    state.yaw_hold = "double"
  elseif action == "tail_normal" then
    state.tail_mode = "normal"
    state.yaw_hold = nil
  elseif action == "tail_reverse" then
    state.tail_mode = "reverse"
    state.yaw_hold = nil
  elseif action == "tail_stop" then
    state.tail_mode = "stop"
    state.yaw_hold = nil
  elseif action == "tail_double" then
    state.tail_mode = "double"
    state.yaw_hold = nil
  elseif action == "toggle_clutch" then
    state.lift_clutch = not state.lift_clutch
  elseif action == "neutral_cyclic" then
    neutral_cyclic(state)
  elseif action == "neutral_all" then
    neutral_all(config, state)
  elseif action == "zero_flaps" then
    zero_flaps(state)
  elseif action == "panic" then
    panic_state(state)
  end

  limit_state(config, state)
end

local function main()
  local config = load_config()
  local io = make_io(config)
  local keyboard_status = setup_keyboard(config)
  local state = startup_state(config)
  local values = apply_outputs(io, config, state)
  draw(config, state, values, keyboard_status)

  local timer = os.startTimer(config.refresh or 0.05)
  while true do
    local event, a, b = os.pullEventRaw()

    if event == "timer" and a == timer then
      values = apply_outputs(io, config, state)
      timer = os.startTimer(config.refresh or 0.05)
    elseif event == "key" or event == "key_up" or event == "tm_keyboard_key" or event == "tm_keyboard_key_up" then
      local action, released = action_from_event(event, a, b)
      if action then
        handle_action(config, state, action, released)
        values = apply_outputs(io, config, state)
        draw(config, state, values, keyboard_status)
      end
    elseif event == "terminate" or event == "tm_keyboard_terminate" then
      panic_state(state)
      values = apply_outputs(io, config, state)
      draw(config, state, values, keyboard_status, "terminated: flaps zero, tail stopped, lift clutch off")
      return
    end
  end
end

main()
