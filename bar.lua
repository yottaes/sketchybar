local colors = require("colors")

-- Equivalent to the --bar domain
sbar.bar({
  height = 32,
  topmost = "window",
  -- Visual effects (blur + translucency)
  color = colors.bar.bg,
  blur_radius = 20,
  padding_right = 2,
  padding_left = 2,
})
