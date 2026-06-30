return {
  config_version = 13,

  port_type = "tm_rsPort",
  keyboard_type = "tm_keyboard",

  ports = {
    flap_positive = "left",
    flap_negative = "right",
    aux = "back",
  },

  controls = {
    collective = 6,
    pitch = 4,
    roll = 4,
  },

  ramp = {
    collective = 1,
    pitch = 1,
    roll = 1,
    release = 2,
  },

  cyclic = {
    mode = "timed",
    rpm = 60,
    direction = 1,
    phase_degrees = 0,
    rpm_step = 5,
    phase_step_degrees = 15,
  },

  mix = {
    front = { collective = 1, pitch = 0, roll = -1 },
    right = { collective = 1, pitch = 1, roll = 0 },
    rear = { collective = 1, pitch = 0, roll = 1 },
    left = { collective = 1, pitch = -1, roll = 0 },
  },

  startup = {
    lift_clutch = true,
    tail_mode = "normal",
  },

  refresh = 0.05,

  flaps = {
    front = {
      positive = { port = "flap_positive", side = "north" },
      negative = { port = "flap_negative", side = "north" },
      raise = "positive",
      lower = "negative",
      trim = 0,
      invert = false,
    },
    rear = {
      positive = { port = "flap_positive", side = "south" },
      negative = { port = "flap_negative", side = "south" },
      raise = "positive",
      lower = "negative",
      trim = 0,
      invert = false,
    },
    left = {
      positive = { port = "flap_positive", side = "west" },
      negative = { port = "flap_negative", side = "west" },
      raise = "positive",
      lower = "negative",
      trim = 0,
      invert = false,
    },
    right = {
      positive = { port = "flap_positive", side = "east" },
      negative = { port = "flap_negative", side = "east" },
      raise = "positive",
      lower = "negative",
      trim = 0,
      invert = false,
    },
  },

  lift_clutch = {
    output = { port = "aux", side = "north" },
    powered_stops = true,
  },

  tail_prop = {
    reverse = { port = "aux", side = "east" },
    stop = { port = "aux", side = "south" },
    double = { port = "aux", side = "west" },
  },
}
