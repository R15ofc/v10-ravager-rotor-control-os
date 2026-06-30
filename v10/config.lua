return {
  config_version = 5,

  port_type = "tm_rsPort",
  keyboard_type = "tm_keyboard",

  ports = {
    flap_positive = "left",
    flap_negative = "right",
    aux = "back",
  },

  controls = {
    collective = 12,
    pitch = 6,
    roll = 6,
  },

  cyclic = {
    rotation = "clockwise",
    phase_lag_quarters = 1,
  },

  startup = {
    lift_clutch = true,
    tail_mode = "normal",
  },

  refresh = 0.20,

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
      raise = "negative",
      lower = "positive",
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
