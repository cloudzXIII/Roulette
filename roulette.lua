RL = SMODS.current_mod

RL.description_loc_vars = function()
  return { background_colour = G.C.CLEAR, text_colour = G.C.WHITE, scale = 1.2, shadow = true }
end

-- talisman compat
to_number = to_number or function(x) return x end
to_big = to_big or function(x) return x end

function randomFloat(lower, greater)
  return lower + math.random() * (greater - lower);
end

G.BET_SIZE = 0
G.BET_COLOUR = "RED"
G.START_ROUL_SPIN = false
G.ROUL_SPIN = false
G.ROUL_VEL = randomFloat(6, 14)
G.WHEEL = { "GREEN", "RED", "BLACK", "RED", "BLACK", "RED", "BLACK", "RED", "BLACK", "RED", "BLACK", "RED" }
G.PAYOUTS = { GREEN = 11, BLACK = 2, RED = 1.8 }
--rads per section of the wheel
G.RADS_PER_SC = 6.283185 / #G.WHEEL
--Previous radian used for roulette sound
PREV_RADS = 0

SMODS.Atlas({
  key = "modicon",
  path = "mod_icon.png",
  px = 32,
  py = 32
})

SMODS.Atlas({
  key = "roulette",
  path = "roulette.png",
  px = 199,
  py = 199
})

SMODS.Atlas({
  key = "roul_marker",
  path = "roul_marker.png",
  px = 19,
  py = 7
})

-- Hook to modify the shop
local original_shop = G.UIDEF.shop

function G.UIDEF.shop()
  local ui = original_shop()
  if not (ui and ui.nodes) then return ui end

  local function find(node, condition)
    if condition(node) then return node end
    if node.nodes then
      for _, child in ipairs(node.nodes) do
        local result = find(child, condition)
        if result then
          return result
        end
      end
    end
  end

  local area = find(ui, function(n)
    if not n.nodes then return false end
    local has_reroll, has_next_round = false, false
    for _, c in ipairs(n.nodes) do
      if c.config and c.config.button == "reroll_shop" then
        has_reroll = true
      end
      if c.config and c.config.id == "next_round_button" then
        has_next_round = true
      end
    end
    return has_reroll and has_next_round
  end)

  if not area then
    return ui
  end

  local next_round_button = find(area, function(n)
    return n.config and n.config.id == "next_round_button"
  end)

  if next_round_button and next_round_button.config then
    next_round_button.config.minh = 1.0
    next_round_button.config.minw = 2.8
  end

  local roulette_button = {
    n = G.UIT.R,
    config = {
      align = "cm",
      minw = 2.8,
      minh = 1,
      r = 1,
      colour = G.C.PURPLE,
      hover = true,
      shadow = true,
      button = "roulette_button",
    },
    nodes = {
      {
        n = G.UIT.T,
        config = {
          text = localize("k_roulette_button"),
          scale = 0.5,
          colour = G.C.WHITE,
          shadow = true
        }
      }
    }
  }

  table.insert(area.nodes, 3, roulette_button)

  return ui
end

Game.updateShopRef = Game.update_shop
function Game:update_shop(dt)
  self:updateShopRef(dt)

  --When spin is pressed
  if G.START_ROUL_SPIN then
    G.ROUL_SPIN = true
    G.START_ROUL_SPIN = false

    G.ROUL_VEL = randomFloat(6, 14)


    --Retire money
    ease_dollars(-G.BET_SIZE)
  end

  --Roulette is spinning
  if G.ROUL_SPIN then
    local roulette = G.OVERLAY_MENU:get_UIE_by_ID("roulette_object")
    local current_rads = roulette.config.object.T.r

    --Rotate and decelerate
    roulette:rotate(G.ROUL_VEL * dt)
    G.ROUL_VEL = G.ROUL_VEL - (1 * dt)

    --Play sound when passes from one section of the wheel to another
    if (math.floor(((PREV_RADS % 6.283185) % G.RADS_PER_SC) * 10) > 0) and (math.floor(((current_rads % 6.283185) % G.RADS_PER_SC) * 10) == 0) then
      play_sound('button', 0.9 + math.random() * 0.1, 0.8)
    end

    PREV_RADS = current_rads
  end

  --Roulette stops
  if G.ROUL_VEL <= 0.01 and G.ROUL_SPIN then
    local roulette = G.OVERLAY_MENU:get_UIE_by_ID("roulette_object")

    local colour_landed = roulette_landing(roulette.config.object.T.r, G.WHEEL)

    --If colourLanded is the same as the colour the bet was placed on, its a win
    if colour_landed == G.BET_COLOUR then
      play_sound('chips2', 1, 0.4)
      ease_dollars(roulette_payout(G.PAYOUTS, colour_landed, G.BET_SIZE))
    else
      play_sound('tarot2', 1, 0.4)
      G.FUNCS.validate_bet_size()
      G.FUNCS.update_bet_size_bump_rate()
    end

    --STOPS THE ROULETTE
    G.ROUL_SPIN = false
  end
end

-- Hook so you can't press escape key while wheel is spinning
local key_press_update_ref = Controller.key_press_update
function Controller:key_press_update(key, dt)
  if key == "escape" and G.OVERLAY_MENU and not G.OVERLAY_MENU.config.no_esc and G.ROUL_SPIN then
    return
  end

  key_press_update_ref(self, key, dt)
end

function G.FUNCS.roulette_button()
  G.FUNCS.validate_bet_size()

  G.FUNCS.overlay_menu({
    definition = create_roulette_menu(),
    config = {}
  })
end

function G.FUNCS.ease_bet_size(e)
  local num = e.config.amount
  G.BET_SIZE = G.BET_SIZE + num
  G.FUNCS.validate_bet_size()
  G.FUNCS.update_bet_size_bump_rate()
end

function G.FUNCS.validate_bet_size()
  local max_bet = to_number(G.GAME.dollars)
  G.BET_SIZE = math.min(math.max(G.BET_SIZE, 0), max_bet)
end

function G.FUNCS.update_bet_size_bump_rate()
  local bet_size = G.OVERLAY_MENU:get_UIE_by_ID("bet_size")
  if to_number(G.GAME.dollars) > 5 then
    bet_size.config.object.bump_rate = (G.BET_SIZE / to_number(G.GAME.dollars)) * 6 + 2
    bet_size.config.object.bump_amount = (G.BET_SIZE / to_number(G.GAME.dollars)) * 3 + 0.5
  else
    bet_size.config.object.bump_rate = 2
    bet_size.config.object.bump_amount = 0.5
  end
end

function G.FUNCS.update_spin_colour(element)
  local indicator = G.OVERLAY_MENU:get_UIE_by_ID("colour_indicator")
  indicator.config.colour = element.config.colour
  G.BET_COLOUR = element.children[1].children[1].config.text
end

function G.FUNCS.start_roul_spin()
  if not G.ROUL_SPIN then
    G.START_ROUL_SPIN = true
  end
end

G.FUNCS.can_use_button = function(e)
  local c1 = e.config.ref_table
  if not G.ROUL_SPIN then
    e.config.colour = e.config.original_colour
    e.config.button = e.config.original_button
  else
    e.config.colour = G.C.UI.BACKGROUND_INACTIVE
    e.config.button = nil
  end
end

--Roulette Menu
function create_roulette_menu()
  local rouletteasset = Sprite(0, 0, 8.5, 8.5, G.ASSET_ATLAS["spin_roulette"], { x = 0, y = 0 })
  local markerasset = Sprite(0, 0, 0.5, 0.5, G.ASSET_ATLAS["spin_roul_marker"], { x = 0, y = 0 })

  local t = {
    n = G.UIT.ROOT,
    config = { align = 'cm', minw = 20, minh = 11, padding = 0.15, r = 0.5, colour = G.C.CLEAR },
    nodes = {
      {
        n = G.UIT.R,
        config = { minw = 20, minh = 11, padding = 0.15, colour = G.C.BLACK, r = 0.5 },
        nodes = {
          {
            n = G.UIT.R,
            config = { minw = 20, minh = 9, padding = 0.15, r = 0.3, colour = G.C.GREY },
            nodes = { --Row containing roulette and functionality
              {
                n = G.UIT.C,
                config = { align = "cm", maxw = 9, minh = 9 },
                nodes = {
                  {
                    n = G.UIT.R,
                    nodes = {
                      { n = G.UIT.O, config = { id = "roulette_object", object = rouletteasset } },
                    }
                  },
                  {
                    n = G.UIT.R,
                    config = { align = "m" },
                    nodes = {
                      { n = G.UIT.O, config = { object = markerasset } }
                    }
                  }
                }
              },
              {
                n = G.UIT.C,
                config = { align = "m", minw = 11, minh = 9, r = 0.3 },
                nodes = { --Column for functionality
                  {
                    n = G.UIT.R,
                    config = { minw = 8, minh = 3, padding = 0.16 },
                    nodes = { --Bet size managing 1st row
                      {
                        n = G.UIT.C,
                        config = { align = "cm", minw = 2.5, minh = 2.84, padding = 0.11, r = 0.3 },
                        nodes = { --Left column containing minus buttons
                          {
                            n = G.UIT.R,
                            config = { align = "cm", minw = 2.5, minh = 0.83, r = 0.3, hover = true, emboss = 0.1, colour = G.C.PURPLE, original_colour = G.C.PURPLE, button = "ease_bet_size", original_button = "ease_bet_size", amount = -1, func = "can_use_button" },
                            nodes = {
                              { n = G.UIT.T, config = { text = "-1", scale = 0.7 } }
                            }
                          },
                          {
                            n = G.UIT.R,
                            config = { align = "cm", minw = 2.5, minh = 0.83, r = 0.3, hover = true, emboss = 0.1, colour = G.C.PURPLE, original_colour = G.C.PURPLE, button = "ease_bet_size", original_button = "ease_bet_size", amount = -10, func = "can_use_button" },
                            nodes = {
                              { n = G.UIT.T, config = { text = "-10", scale = 0.7 } }
                            }
                          },
                          {
                            n = G.UIT.R,
                            config = { align = "cm", minw = 2.5, minh = 0.83, r = 0.3, hover = true, emboss = 0.1, colour = G.C.PURPLE, original_colour = G.C.PURPLE, button = "ease_bet_size", original_button = "ease_bet_size", amount = -100, func = "can_use_button" },
                            nodes = {
                              { n = G.UIT.T, config = { text = "-100", scale = 0.7 } }
                            }
                          }
                        }
                      },
                      {
                        n = G.UIT.C,
                        config = { align = "cm", minw = 2.5, minh = 2.84, r = 0.3, colour = G.C.DYN_UI.BOSS_MAIN },
                        nodes = { --Bordes are made using 2 components, one smaller inside a larger one with different colors
                          {
                            n = G.UIT.C,
                            config = { align = "cm", minw = 2.4, minh = 2.64, r = 0.3, colour = G.C.DYN_UI.BOSS_DARK },
                            nodes = {
                              { n = G.UIT.O, config = { id = "bet_size", object = DynaText({ string = { { ref_table = G, ref_value = "BET_SIZE", prefix = localize('$') } }, colours = { G.C.UI.TEXT_LIGHT }, bump = true, bump_rate = 2, config = { minh = 2.84, maxw = 2.5, scale = 2 } }) } }
                            }
                          }
                        }
                      },
                      {
                        n = G.UIT.C,
                        config = { align = "cm", minw = 2.5, minh = 2.84, padding = 0.11, r = 0.3 },
                        nodes = { --Right column containing plus buttons
                          {
                            n = G.UIT.R,
                            config = { align = "cm", minw = 2.5, minh = 0.83, r = 0.3, hover = true, emboss = 0.1, colour = G.C.GREEN, original_colour = G.C.GREEN, button = "ease_bet_size", original_button = "ease_bet_size", amount = 1, func = "can_use_button" },
                            nodes = {
                              { n = G.UIT.T, config = { text = "+1", scale = 0.7 } }
                            }
                          },
                          {
                            n = G.UIT.R,
                            config = { align = "cm", minw = 2.5, minh = 0.83, r = 0.3, hover = true, emboss = 0.1, colour = G.C.GREEN, original_colour = G.C.GREEN, button = "ease_bet_size", original_button = "ease_bet_size", amount = 10, func = "can_use_button" },
                            nodes = {
                              { n = G.UIT.T, config = { text = "+10", scale = 0.7 } }
                            }
                          },
                          {
                            n = G.UIT.R,
                            config = { align = "cm", minw = 2.5, minh = 0.83, r = 0.3, hover = true, emboss = 0.1, colour = G.C.GREEN, original_colour = G.C.GREEN, button = "ease_bet_size", original_button = "ease_bet_size", amount = 100, func = "can_use_button" },
                            nodes = {
                              { n = G.UIT.T, config = { text = "+100", scale = 0.7 } }
                            }
                          }
                        }
                      }
                    }
                  },
                  {
                    n = G.UIT.R,
                    config = { align = "cm", padding = 0.1, minw = 8, minh = 3, colour = G.C.CLEAR },
                    nodes = { --2nd row
                      {
                        n = G.UIT.C,
                        config = { align = "cm", minw = 2.5, minh = 2.8, colour = G.C.RED, original_colour = G.C.RED, hover = true, emboss = 0.1, r = 0.3, button = "update_spin_colour", original_button = "update_spin_colour", func = "can_use_button", },
                        nodes = {
                          {
                            n = G.UIT.R,
                            nodes = {
                              { n = G.UIT.T, config = { text = localize('k_roulette_red'), scale = 0.8, colour = G.C.UI.TEXT_LIGHT } }
                            }
                          },
                          {
                            n = G.UIT.R,
                            config = { align = "m" },
                            nodes = {
                              { n = G.UIT.T, config = { text = "x1.8", scale = 0.4, colour = G.C.UI.TEXT_LIGHT } }
                            }
                          }
                        }
                      },
                      {
                        n = G.UIT.C,
                        config = { align = "cm", minw = 2.5, minh = 2.8, colour = G.C.GREEN, original_colour = G.C.GREEN, hover = true, emboss = 0.1, r = 0.3, button = "update_spin_colour", original_button = "update_spin_colour", func = "can_use_button", },
                        nodes = {
                          {
                            n = G.UIT.R,
                            nodes = {
                              { n = G.UIT.T, config = { text = localize('k_roulette_green'), scale = 0.8, colour = G.C.UI.TEXT_LIGHT } }
                            }
                          },
                          {
                            n = G.UIT.R,
                            config = { align = "m" },
                            nodes = {
                              { n = G.UIT.T, config = { text = "x11", scale = 0.4, colour = G.C.UI.TEXT_LIGHT } }
                            }
                          }
                        }
                      },
                      {
                        n = G.UIT.C,
                        config = { align = "cm", minw = 2.5, minh = 2.8, colour = G.C.BLACK, original_colour = G.C.BLACK, hover = true, emboss = 0.1, r = 0.3, button = "update_spin_colour", original_button = "update_spin_colour", func = "can_use_button", },
                        nodes = {
                          {
                            n = G.UIT.R,
                            nodes = {
                              { n = G.UIT.T, config = { text = localize('k_roulette_black'), scale = 0.8, colour = G.C.UI.TEXT_LIGHT } }
                            }
                          },
                          {
                            n = G.UIT.R,
                            config = { align = "m" },
                            nodes = {
                              { n = G.UIT.T, config = { text = "x2", scale = 0.4, colour = G.C.UI.TEXT_LIGHT } }
                            }
                          }
                        }
                      }
                    }
                  },
                  {
                    n = G.UIT.R,
                    config = { align = "cm", minw = 8, minh = 3, padding = 0.2, colour = G.C.CLEAR },
                    nodes = {        --3rd row
                      {
                        n = G.UIT.C, -- Colour indicator
                        config = { id = "colour_indicator", align = "cm", minw = 1, minh = 1.5, colour = G.C.RED, r = 0.1 },
                        nodes = {}
                      },
                      {
                        n = G.UIT.C,
                        config = { id = "spin_button", align = "cm", minw = 3, minh = 1.5, colour = G.C.MULT, original_colour = G.C.MULT, r = 0.1, hover = true, emboss = 0.1, button = "start_roul_spin", original_button = "start_roul_spin", func = "can_use_button" },
                        nodes = { --Spin button
                          { n = G.UIT.T, config = { text = localize('k_roulette_spin'), scale = 0.8, colour = G.C.TEXT_LIGHT } }
                        }
                      },
                      {
                        n = G.UIT.C,
                        config = { align = "cm", minw = 3, minh = 1.5, padding = 0.15, colour = G.C.DYN_UI.BOSS_MAIN, r = 0.1 },
                        nodes = { --Money count
                          {
                            n = G.UIT.C,
                            config = { align = "cm", minw = 2.65, minh = 1.35, colour = G.C.DYN_UI.BOSS_DARK, r = 0.1 },
                            nodes = {
                              { n = G.UIT.O, config = { object = DynaText({ string = { { ref_table = G.GAME, ref_value = 'dollars', prefix = localize('$') } }, colours = { G.C.MONEY }, font = G.LANGUAGES['en-us'].font, shadow = true, bump = true, scale = 0.8 }), id = 'dollar_text_UI' } }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          },
          {
            n = G.UIT.R,
            config = { align = "cm", padding = 0.1 },
            nodes = {
              {
                n = G.UIT.R,
                config = {
                  id = 'roulette_back_button',
                  align = "cm",
                  minw = 6,
                  minh = 0.6,
                  padding = 0.08,
                  r = 0.1,
                  hover = true,
                  colour = G.C.ORANGE,
                  original_colour = G.C.ORANGE,
                  button = "exit_roulette_menu",
                  original_button = "exit_roulette_menu",
                  func = "can_use_button",
                  shadow = true,
                  focus_args = { nav = 'wide', button = 'b' }
                },
                nodes = {
                  {
                    n = G.UIT.R,
                    config = { align = "cm", padding = 0, no_fill = true },
                    nodes = {
                      { n = G.UIT.T, config = { text = localize('k_roulette_back'), minw = 2, scale = 0.5, minh = 0.9, shadow = true, colour = G.C.UI.TEXT_LIGHT } }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  return t
end

--Only for UIT.O aka Objects
function Moveable:rotate(rad)
  self.VT.r = self.VT.r + rad
  self.config.object.VT.r = self.VT.r + rad
  self.T.r = self.T.r + rad
  self.config.object.T.r = self.T.r + rad
end

--sections = {"GREEN","RED","BLACK","RED","BLACK","RED","BLACK","RED","BLACK"... etc}
function roulette_landing(rads, wheel)
  local sections = #wheel
  local real_rads = rads % 6.283185
  local rads_per_section = 6.283185 / sections
  local section_landed = math.floor(real_rads / rads_per_section) + 1

  return wheel[section_landed]
end

function roulette_payout(payouts, landed_on, dollars_bet)
  return dollars_bet * payouts[landed_on]
end

--Almost identical function as "exit_menu_overlay", just adapted to exit correctly roulette menu
G.FUNCS.exit_roulette_menu = function()
  if not G.OVERLAY_MENU then return end
  G.CONTROLLER.locks.frame_set = true
  G.CONTROLLER.locks.frame = true
  G.CONTROLLER:mod_cursor_context_layer(-1000)
  G.OVERLAY_MENU:remove()
  G.OVERLAY_MENU = nil
  G.VIEWING_DECK = nil
  G.SETTINGS.paused = false

  G.ROUL_SPIN = false

  --Save settings to file
  G:save_settings()
end
