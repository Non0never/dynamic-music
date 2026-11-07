module DynamicMusic
  ENABLED = true
  DEBUG_MODE = false

  LOW_HP_ENABLED = true
  LOW_HP_THRESHOLD = 0.25
  LOW_HP_BGM = "Battle Elite"

  LAST_POKEMON_ENABLED = true
  LAST_POKEMON_BGM = "Battle Champion"

  BOSS_PHASES = {}
  DAY_NIGHT_ENABLED = true
  DAY_NIGHT_MAPS = {}
  NIGHT_START_HOUR = 20
  NIGHT_END_HOUR = 6
  WEATHER_MUSIC_ENABLED = true
  WEATHER_BGM = {}
  STORY_SWITCH_BGM = {}

  FADE_DURATION = 800
  VOLUME_NORMAL = 80

  def self.on?
    ENABLED && ($PokemonSystem.nil? || $PokemonSystem.dynamic_music == 0)
  end
end
