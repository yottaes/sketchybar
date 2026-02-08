-- Catppuccin Mocha color palette
return {
  -- Base colors
  base = 0xff1e1e2e,
  mantle = 0xff181825,
  crust = 0xff11111b,
  surface0 = 0xff313244,
  surface1 = 0xff45475a,
  overlay0 = 0xff6c7086,

  -- Text
  text = 0xffcdd6f4,
  subtext0 = 0xffa6adc8,

  -- Accent colors
  red = 0xfff38ba8,
  green = 0xffa6e3a1,
  blue = 0xff89b4fa,
  yellow = 0xfff9e2af,
  peach = 0xfffab387,
  mauve = 0xffcba6f7,
  teal = 0xff94e2d5,
  sky = 0xff89dceb,
  lavender = 0xffb4befe,

  -- Legacy aliases (used by binbinsh items)
  white = 0xffcdd6f4,
  black = 0xff1e1e2e,
  grey = 0xff6c7086,
  orange = 0xfffab387,
  magenta = 0xffcba6f7,
  transparent = 0x00000000,

  bar = {
    bg = 0xe61e1e2e,
    border = 0xff313244,
  },
  popup = {
    bg = 0xc0181825,
    border = 0xff45475a,
  },
  bg1 = 0xb3313244,
  bg2 = 0xb345475a,

  with_alpha = function(color, alpha)
    if alpha > 1.0 or alpha < 0.0 then return color end
    return (color & 0x00ffffff) | (math.floor(alpha * 255.0) << 24)
  end,
}
