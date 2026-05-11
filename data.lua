-- Registers custom input prototype for left-click companion interaction.
-- Runs in data stage (before game start).

data:extend({
  {
    type         = "custom-input",
    name         = "companion-open-inventory",
    key_sequence = "mouse-button-1",
    consuming    = "none",
  }
})
