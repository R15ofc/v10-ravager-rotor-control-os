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
  left = 263,
  right = 262,
  down = 264,
  up = 265,
  a = 65,
  b = 66,
  c = 67,
  d = 68,
  e = 69,
  f = 70,
  i = 73,
  j = 74,
  k = 75,
  l = 76,
  m = 77,
  n = 78,
  p = 80,
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
  if config.config_version ~= 6 and config.config_version ~= 7 and config.config_version ~= 8 then
    error("bad config: install v8 config or delete " .. CONFIG_PATH .. " and run installer again")
  end
  config.controls = config.controls or {}
  if config.config_version == 6 then
    config.controls.collective = math.min(config.controls.collective or 6, 6)
    config.controls.pitch = math.min(config.controls.pitch or 4, 4)
    config.controls.roll = math.min(config.controls.roll or 4, 4)
    config.refresh = 0.05
  end
  config.ramp = config.ramp or {}
  config.ramp.collective = config.ramp.collective or 1
  config.ramp.pitch = config.ramp.pitch or 1
  config.ramp.roll = config.ramp.roll or 1
  config.ramp.release = config.ramp.release or 2
  config.refresh = config.refresh or 0.05
  return config
end

local function serialize_value(value, indent)
  indent = indent or ""
  local next_indent = indent .. "  "
  if type(value) == "string" then
    return string.format("%q", value)
  end
  if type(value) == "number" or type(value) == "boolean" then
    return tostring(value)
  end
  if type(value) ~= "table" then
    return "nil"
  end

  local keys = {}
  for key in pairs(value) do
    table.insert(keys, key)
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)

  local out = { "{" }
  for _, key in ipairs(keys) do
    local key_text
    if type(key) == "string" and key:match("^[%a_][%w_]*$") then
      key_text = key
    else
      key_text = "[" .. serialize_value(key, next_indent) .. "]"
    end
    table.insert(out, next_indent .. key_text .. " = " .. serialize_value(value[key], next_indent) .. ",")
  end
  table.insert(out, indent .. "}")
  return table.concat(out, "\n")
end

local function save_config(config)
  local handle = fs.open(CONFIG_PATH, "w")
  if not handle then
    return false
  end
  handle.write("return " .. serialize_value(config, "") .. "\n")
  handle.close()
  return true
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
    label = label or spec.side
    if self.writes[label] ~= value then
      port.setAnalogOutput(spec.side, value)
      self.writes[label] = value
    end
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
    add_action(cc, keys.i, "pitch_forward")
    add_action(cc, keys.up, "pitch_forward")
    add_action(cc, keys.s, "pitch_back")
    add_action(cc, keys.k, "pitch_back")
    add_action(cc, keys.down, "pitch_back")
    add_action(cc, keys.a, "roll_left")
    add_action(cc, keys.j, "roll_left")
    add_action(cc, keys.left, "roll_left")
    add_action(cc, keys.d, "roll_right")
    add_action(cc, keys.l, "roll_right")
    add_action(cc, keys.right, "roll_right")
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
    add_action(cc, keys.m, "cal_toggle")
    add_action(cc, keys.p, "cal_save")
  end

  local glfw = {}
  add_action(glfw, GLFW.r, "collective_up")
  add_action(glfw, GLFW.f, "collective_down")
  add_action(glfw, GLFW.w, "pitch_forward")
  add_action(glfw, GLFW.i, "pitch_forward")
  add_action(glfw, GLFW.up, "pitch_forward")
  add_action(glfw, GLFW.s, "pitch_back")
  add_action(glfw, GLFW.k, "pitch_back")
  add_action(glfw, GLFW.down, "pitch_back")
  add_action(glfw, GLFW.a, "roll_left")
  add_action(glfw, GLFW.j, "roll_left")
  add_action(glfw, GLFW.left, "roll_left")
  add_action(glfw, GLFW.d, "roll_right")
  add_action(glfw, GLFW.l, "roll_right")
  add_action(glfw, GLFW.right, "roll_right")
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
  add_action(glfw, GLFW.m, "cal_toggle")
  add_action(glfw, GLFW.p, "cal_save")

  return cc, glfw
end

local function action_from_event(event, a, b, c, cc_map, glfw_map)
  if event == "key" then
    return cc_map[a] or glfw_map[a], false, b == true
  end
  if event == "key_up" then
    return cc_map[a] or glfw_map[a], true, false
  end
  if event == "tm_keyboard_key" then
    return glfw_map[b], false, c == true
  end
  if event == "tm_keyboard_key_up" then
    return glfw_map[b], true, false
  end
  return nil, false, false
end

local function log_key_event(state, event, a, b, c, action)
  if not state.events then
    state.events = {}
  end
  table.insert(state.events, string.format(
    "%s %s %s %s -> %s",
    tostring(event),
    tostring(a),
    tostring(b),
    tostring(c),
    tostring(action or "-")
  ))
  while #state.events > 8 do
    table.remove(state.events, 1)
  end
end

local function active_tail_mode(state)
  return state.yaw_hold or state.tail_mode or "normal"
end

local function held_axis(hold, positive, negative, amount)
  local pos = hold[positive] == true
  local neg = hold[negative] == true
  if pos and not neg then
    return amount
  end
  if neg and not pos then
    return -amount
  end
  return 0
end

local function update_held_axes(config, state)
  local controls = config.controls or {}
  state.target_collective = held_axis(state.hold, "collective_up", "collective_down", controls.collective or 6)
  state.target_pitch = held_axis(state.hold, "pitch_forward", "pitch_back", controls.pitch or 4)
  state.target_roll = held_axis(state.hold, "roll_right", "roll_left", controls.roll or 4)

  if state.hold.yaw_reverse_hold and not state.hold.yaw_double_hold then
    state.yaw_hold = "reverse"
  elseif state.hold.yaw_double_hold and not state.hold.yaw_reverse_hold then
    state.yaw_hold = "double"
  else
    state.yaw_hold = nil
  end
end

local function approach(current, target, step)
  if current < target then
    return math.min(current + step, target)
  end
  if current > target then
    return math.max(current - step, target)
  end
  return current
end

local function axis_step(config, axis, current, target)
  local ramp = config.ramp or {}
  if target == 0 and current ~= 0 then
    return ramp.release or 2
  end
  return ramp[axis] or 1
end

local function slew_axes(config, state)
  local changed = false
  local next_collective = approach(
    state.collective,
    state.target_collective or 0,
    axis_step(config, "collective", state.collective, state.target_collective or 0)
  )
  local next_pitch = approach(
    state.pitch,
    state.target_pitch or 0,
    axis_step(config, "pitch", state.pitch, state.target_pitch or 0)
  )
  local next_roll = approach(
    state.roll,
    state.target_roll or 0,
    axis_step(config, "roll", state.roll, state.target_roll or 0)
  )

  changed = next_collective ~= state.collective or next_pitch ~= state.pitch or next_roll ~= state.roll
  state.collective = next_collective
  state.pitch = next_pitch
  state.roll = next_roll
  return changed
end

local function limit_state(config, state)
  if not TAIL_MODES[state.tail_mode] then
    state.tail_mode = "normal"
  end
end

local function startup_state(config)
  local startup = config.startup or {}
  local state = {
    collective = 0,
    pitch = 0,
    roll = 0,
    target_collective = 0,
    target_pitch = 0,
    target_roll = 0,
    hold = {},
    lift_clutch = startup.lift_clutch ~= false,
    tail_mode = startup.tail_mode or "normal",
    yaw_hold = nil,
    calibration = false,
    cal_index = 1,
    cal_raise = false,
    cal_lower = false,
    status = nil,
    events = {},
  }
  update_held_axes(config, state)
  limit_state(config, state)
  return state
end

local function neutral_cyclic(state)
  state.hold.pitch_forward = nil
  state.hold.pitch_back = nil
  state.hold.roll_left = nil
  state.hold.roll_right = nil
  state.hold.yaw_reverse_hold = nil
  state.hold.yaw_double_hold = nil
  state.target_pitch = 0
  state.target_roll = 0
  state.pitch = 0
  state.roll = 0
  state.yaw_hold = nil
end

local function zero_flaps(state)
  state.hold.collective_up = nil
  state.hold.collective_down = nil
  neutral_cyclic(state)
  state.target_collective = 0
  state.collective = 0
end

local function neutral_all(config, state)
  local startup = startup_state(config)
  state.hold = {}
  state.collective = startup.collective
  state.pitch = startup.pitch
  state.roll = startup.roll
  state.target_collective = 0
  state.target_pitch = 0
  state.target_roll = 0
  state.lift_clutch = startup.lift_clutch
  state.tail_mode = "normal"
  state.yaw_hold = nil
end

local function panic_state(state)
  state.hold = {}
  state.collective = 0
  state.pitch = 0
  state.roll = 0
  state.target_collective = 0
  state.target_pitch = 0
  state.target_roll = 0
  state.yaw_hold = nil
  state.tail_mode = "stop"
  state.lift_clutch = false
end

local function mix_for(config, name)
  local mix = config.mix and config.mix[name] or {}
  return {
    collective = mix.collective or 1,
    pitch = mix.pitch or 0,
    roll = mix.roll or 0,
  }
end

local function flap_target(config, state, name, flap)
  local mix = mix_for(config, name)
  local value =
    (state.collective * mix.collective) +
    (state.pitch * mix.pitch) +
    (state.roll * mix.roll) +
    (flap.trim or 0)

  if flap.invert then
    value = -value
  end
  return clamp(round(value), -15, 15)
end

local function channel_name(flap, target)
  if target >= 0 then
    return flap.raise or "positive"
  end
  return flap.lower or "negative"
end

local function opposite_channel(channel)
  if channel == "positive" then
    return "negative"
  end
  return "positive"
end

local function apply_flap(io, config, state, name, flap, values)
  local target = flap_target(config, state, name, flap)
  local active = channel_name(flap, target)
  local inactive = opposite_channel(active)
  local strength = math.abs(target)

  if not flap[active] then
    error("bad flap channel for " .. name .. ": " .. tostring(active))
  end
  if not flap[inactive] then
    error("bad flap inactive channel for " .. name .. ": " .. tostring(inactive))
  end

  local positive = 0
  local negative = 0
  if active == "positive" then
    positive = strength
  else
    negative = strength
  end

  io:write(flap[inactive], 0, name .. (inactive == "positive" and "+" or "-"))

  values.flaps[name] = {
    target = target,
    positive = io:write(flap.positive, positive, name .. "+") or 0,
    negative = io:write(flap.negative, negative, name .. "-") or 0,
  }
end

local function selected_flap_name(state)
  return FLAP_ORDER[state.cal_index] or FLAP_ORDER[1]
end

local function zero_all_flaps(io, config, values)
  for _, name in ipairs(FLAP_ORDER) do
    local flap = config.flaps and config.flaps[name]
    if not flap then
      error("missing flap config: " .. name)
    end
    io:write(flap.positive, 0, name .. "+")
    io:write(flap.negative, 0, name .. "-")
    values.flaps[name] = { target = 0, positive = 0, negative = 0 }
  end
end

local apply_clutch
local apply_tail

local function apply_calibration(io, config, state)
  local values = {
    flaps = {},
    tail = {},
    tail_mode = "normal",
  }
  zero_all_flaps(io, config, values)

  local name = selected_flap_name(state)
  local flap = config.flaps[name]
  local raise_value = state.cal_raise and 15 or 0
  local lower_value = state.cal_lower and 15 or 0
  local raise_channel = flap.raise or "positive"
  local lower_channel = flap.lower or "negative"

  if raise_value > 0 then
    local spec = flap[raise_channel]
    values.flaps[name][raise_channel] = io:write(spec, raise_value, name .. (raise_channel == "positive" and "+" or "-")) or 0
  elseif lower_value > 0 then
    local spec = flap[lower_channel]
    values.flaps[name][lower_channel] = io:write(spec, lower_value, name .. (lower_channel == "positive" and "+" or "-")) or 0
  end

  apply_clutch(io, config, state, values)
  apply_tail(io, config, state, values)
  return values
end

function apply_clutch(io, config, state, values)
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

function apply_tail(io, config, state, values)
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
  if state.calibration then
    return apply_calibration(io, config, state)
  end

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
  if state.calibration then
    local name = selected_flap_name(state)
    local flap = config.flaps[name]
    print("CALIBRATION MODE")
    print("Q/E select  1-4 select  R test raise  F test lower")
    print("C flip raise/lower  P save  M flight  X clear")
    print(string.format(
      "selected:%s raise:%s lower:%s",
      name,
      flap.raise or "positive",
      flap.lower or "negative"
    ))
  else
    print("R/F lift  W/S or I/K pitch  A/D or J/L roll")
    print("1 normal  2 reverse  3 stop    4 x2")
    print("C clutch  SPACE level  X zero  N reset  B panic  M cal")
  end
  print("")
  print(string.format(
    "collective:%2d/%2d pitch:%+3d/%+3d roll:%+3d/%+3d clutch:%s tail:%s",
    state.collective,
    state.target_collective or 0,
    state.pitch,
    state.target_pitch or 0,
    state.roll,
    state.target_roll or 0,
    state.lift_clutch and "on " or "off",
    values.tail_mode or active_tail_mode(state)
  ))
  print("")

  for _, name in ipairs(FLAP_ORDER) do
    local flap = values.flaps[name] or { target = 0, positive = 0, negative = 0 }
    print(string.format("%-5s cmd:%+3d  +%2d -%2d", name, flap.target, flap.positive, flap.negative))
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
  elseif state.status then
    print("")
    print(state.status)
  end

  if state.calibration and state.events and #state.events > 0 then
    print("")
    print("events:")
    local start = math.max(1, #state.events - 4)
    for index = start, #state.events do
      print(state.events[index])
    end
  end
end

local function is_hold_action(action)
  return action == "collective_up"
    or action == "collective_down"
    or action == "pitch_forward"
    or action == "pitch_back"
    or action == "roll_left"
    or action == "roll_right"
    or action == "yaw_reverse_hold"
    or action == "yaw_double_hold"
end

local function handle_action(config, state, action, released, repeated)
  if action == "cal_toggle" and not released and not repeated then
    state.calibration = not state.calibration
    state.cal_raise = false
    state.cal_lower = false
    zero_flaps(state)
    update_held_axes(config, state)
    state.status = state.calibration and "calibration on" or "flight mode"
    return true
  end

  if state.calibration then
    if action == "collective_up" then
      state.cal_raise = not released
      if state.cal_raise then
        state.cal_lower = false
      end
      state.status = "testing raise on " .. selected_flap_name(state)
      return true
    elseif action == "collective_down" then
      state.cal_lower = not released
      if state.cal_lower then
        state.cal_raise = false
      end
      state.status = "testing lower on " .. selected_flap_name(state)
      return true
    end

    if released or repeated then
      return false
    end

    if action == "yaw_reverse_hold" then
      state.cal_index = state.cal_index - 1
      if state.cal_index < 1 then
        state.cal_index = #FLAP_ORDER
      end
      state.status = "selected " .. selected_flap_name(state)
    elseif action == "yaw_double_hold" then
      state.cal_index = state.cal_index + 1
      if state.cal_index > #FLAP_ORDER then
        state.cal_index = 1
      end
      state.status = "selected " .. selected_flap_name(state)
    elseif action == "tail_normal" then
      state.cal_index = 1
      state.status = "selected " .. selected_flap_name(state)
    elseif action == "tail_reverse" then
      state.cal_index = 2
      state.status = "selected " .. selected_flap_name(state)
    elseif action == "tail_stop" then
      state.cal_index = 3
      state.status = "selected " .. selected_flap_name(state)
    elseif action == "tail_double" then
      state.cal_index = 4
      state.status = "selected " .. selected_flap_name(state)
    elseif action == "toggle_clutch" then
      local flap = config.flaps[selected_flap_name(state)]
      local old_raise = flap.raise or "positive"
      flap.raise = flap.lower or "negative"
      flap.lower = old_raise
      state.status = "flipped " .. selected_flap_name(state)
    elseif action == "zero_flaps" or action == "panic" then
      state.cal_raise = false
      state.cal_lower = false
      state.status = "outputs cleared"
    elseif action == "cal_save" then
      state.status = save_config(config) and "saved " .. CONFIG_PATH or "save failed"
    else
      return false
    end
    return true
  end

  if is_hold_action(action) then
    local next_value = not released
    if state.hold[action] == next_value then
      return false
    end
    state.hold[action] = next_value or nil
    update_held_axes(config, state)
    limit_state(config, state)
    return true
  end

  if released or repeated then
    return false
  end

  if action == "tail_normal" then
    state.tail_mode = "normal"
    state.hold.yaw_reverse_hold = nil
    state.hold.yaw_double_hold = nil
    update_held_axes(config, state)
  elseif action == "tail_reverse" then
    state.tail_mode = "reverse"
    state.hold.yaw_reverse_hold = nil
    state.hold.yaw_double_hold = nil
    update_held_axes(config, state)
  elseif action == "tail_stop" then
    state.tail_mode = "stop"
    state.hold.yaw_reverse_hold = nil
    state.hold.yaw_double_hold = nil
    update_held_axes(config, state)
  elseif action == "tail_double" then
    state.tail_mode = "double"
    state.hold.yaw_reverse_hold = nil
    state.hold.yaw_double_hold = nil
    update_held_axes(config, state)
  elseif action == "toggle_clutch" then
    state.lift_clutch = not state.lift_clutch
  elseif action == "neutral_cyclic" then
    neutral_cyclic(state)
    update_held_axes(config, state)
  elseif action == "neutral_all" then
    neutral_all(config, state)
  elseif action == "zero_flaps" then
    zero_flaps(state)
    update_held_axes(config, state)
  elseif action == "panic" then
    panic_state(state)
  end

  limit_state(config, state)
  return true
end

local function main()
  local config = load_config()
  local io = make_io(config)
  local keyboard_status = setup_keyboard(config)
  local cc_map, glfw_map = build_keymap()
  local state = startup_state(config)
  local values = apply_outputs(io, config, state)
  draw(config, state, values, keyboard_status)

  local timer = os.startTimer(config.refresh or 0.05)
  while true do
    local event, a, b, c = os.pullEventRaw()

    if event == "timer" and a == timer then
      local axes_changed = false
      if not state.calibration then
        axes_changed = slew_axes(config, state)
      end
      values = apply_outputs(io, config, state)
      if axes_changed then
        draw(config, state, values, keyboard_status)
      end
      timer = os.startTimer(config.refresh or 0.05)
    elseif event == "key" or event == "key_up" or event == "tm_keyboard_key" or event == "tm_keyboard_key_up" then
      local action, released, repeated = action_from_event(event, a, b, c, cc_map, glfw_map)
      log_key_event(state, event, a, b, c, action)
      if action then
        if handle_action(config, state, action, released, repeated) then
          if not state.calibration then
            slew_axes(config, state)
          end
          values = apply_outputs(io, config, state)
          draw(config, state, values, keyboard_status)
        end
      elseif state.calibration then
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
