class PokemonSystem
  attr_writer :dynamic_music

  alias scdm_initialize initialize unless method_defined?(:scdm_initialize)
  def initialize
    scdm_initialize
    @dynamic_music = 0
  end

  def dynamic_music
    @dynamic_music = 0 if @dynamic_music.nil?
    @dynamic_music
  end
end

MenuHandlers.add(:options_menu, :dynamic_music, {
  "name"        => _INTL("Dynamic Music"),
  "order"       => 25,
  "type"        => (defined?(EnumOption) ? EnumOption : :array),
  "parameters"  => [_INTL("On"), _INTL("Off")],
  "description" => _INTL("Context-aware music: low-HP tension, boss phases, day/night and weather themes."),
  "condition"   => proc { next DynamicMusic::ENABLED },
  "get_proc"    => proc { next $PokemonSystem.dynamic_music },
  "set_proc"    => proc { |value, _scene|
    $PokemonSystem.dynamic_music = value
    DynamicMusicEngine.deactivate if value != 0
  }
})
