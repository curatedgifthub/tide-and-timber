-- Temporary resolutions for underspecified cases. Read DECISIONS.md.
return {
  starting_hand = 5,
  min_deck_size = 20,
  max_deck_size = 30,
  -- Explicit fixed-size scenarios from the original terminal simulator.
  classic = {starting_hand=10, max_hand=12},
  max_activations_per_action = 200,
  max_steps_per_match = 2000,
  -- Players choose simultaneous friendly chain triggers; opposing triggers resolve afterward.
  -- No valid target: optional or mandatory ability safely fizzles, card is still played.
  -- Continuous immunities do not reverse already resolved one-time modifications.
  -- Round-specific bonuses last until cleanup, including buffs granted by units that leave.
  -- Search bottom-of-deck order is chosen by the current controller; default preserves order.
  -- The tabletop hand can grow through abilities.
  -- Cards returning to hand from an enemy battlefield return to owner's hand.
  -- A player's own hand includes stolen cards; stolen cards discarded go to owner's pile.
  -- A card's owner and controller are distinct at all times.
}
