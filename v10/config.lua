return {
  port_type = "tm_rsPort",

  min_output = 0,
  max_output = 15,
  neutral_output = 7,

  startup = {
    collective = 7,
    pitch = 0,
    roll = 0,
  },

  limits = {
    collective_min = 0,
    collective_max = 15,
    pitch = 7,
    roll = 7,
  },

  key_step = 1,
  refresh = 0.05,

  channels = {
    front = { side = "north", collective = 1, pitch = 1, roll = 0, trim = 0, invert = false },
    rear = { side = "south", collective = 1, pitch = -1, roll = 0, trim = 0, invert = false },
    left = { side = "west", collective = 1, pitch = 0, roll = -1, trim = 0, invert = false },
    right = { side = "east", collective = 1, pitch = 0, roll = 1, trim = 0, invert = false },
  },
}
