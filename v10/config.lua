return {
  config_version = 4,

  port_type = "tm_rsPort",
  keyboard_type = "tm_keyboard",

  ports = {
    flap_positive = "left",
    flap_negative = "right",
    aux = "back",
  },

  controls = {
    collective = 15,
    pitch = 15,
    roll = 15,
  },

  collective_map = {
    front = { up = "positive", down = "negative" },
    rear = { up = "positive", down = "negative" },
    left = { up = "positive", down = "negative" },
    right = { up = "positive", down = "negative" },
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
      pitch = 1,
      roll = 0,
      trim = 0,
      invert = false,
    },
    rear = {
      positive = { port = "flap_positive", side = "south" },
      negative = { port = "flap_negative", side = "south" },
      pitch = -1,
      roll = 0,
      trim = 0,
      invert = false,
    },
    left = {
      positive = { port = "flap_positive", side = "west" },
      negative = { port = "flap_negative", side = "west" },
      pitch = 0,
      roll = -1,
      trim = 0,
      invert = false,
    },
    right = {
      positive = { port = "flap_positive", side = "east" },
      negative = { port = "flap_negative", side = "east" },
      pitch = 0,
      roll = 1,
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
