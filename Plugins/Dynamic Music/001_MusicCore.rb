module DynamicMusicEngine
  @ow_target        = nil
  @map_default_bgm  = nil
  @map_default_audio = nil
  @pending_bgm      = nil
  @pending_play_at  = nil
  @pending_from     = nil
  @pending_from_audio = nil
  @last_check       = 0.0

  @battle_target    = nil
  @battle_base      = nil
  @battle_base_captured = false
  @battle_pending   = nil
  @battle_play_at   = nil
  @battle_from      = nil
  @battle_from_audio = nil

  RECHECK_INTERVAL = 1.0

  def self.debug_log(msg)
    return unless DynamicMusic::DEBUG_MODE
    echoln("[DynamicMusic] #{msg}") if defined?(echoln)
  end

  def self.night?
    time = UnrealTimeSystem.current_time if defined?(UnrealTimeSystem) && UnrealTimeSystem.respond_to?(:current_time)
    hour = (time || pbGetTimeNow).hour
    if DynamicMusic::NIGHT_START_HOUR > DynamicMusic::NIGHT_END_HOUR
      hour >= DynamicMusic::NIGHT_START_HOUR || hour < DynamicMusic::NIGHT_END_HOUR
    else
      hour >= DynamicMusic::NIGHT_START_HOUR && hour < DynamicMusic::NIGHT_END_HOUR
    end
  end

  def self.available_bgm?(name)
    !nil_or_empty?(name) && FileTest.audio_exist?("Audio/BGM/" + name)
  end

  def self.current_weather
    if defined?(WeatherEventEngine) && WeatherEventEngine.respond_to?(:current_weather)
      weather = WeatherEventEngine.current_weather
      return weather if weather && weather != :None
    end
    $game_screen&.weather_type || :None
  end

  def self.desired_overworld_bgm(map_id = ($game_map&.map_id))
    if $game_switches
      DynamicMusic::STORY_SWITCH_BGM.each do |switch_id, bgm|
        return bgm if $game_switches[switch_id] && available_bgm?(bgm)
      end
    end
    if DynamicMusic::WEATHER_MUSIC_ENABLED
      wbgm = DynamicMusic::WEATHER_BGM[current_weather]
      return wbgm if available_bgm?(wbgm)
    end
    if DynamicMusic::DAY_NIGHT_ENABLED && map_id
      config = DynamicMusic::DAY_NIGHT_MAPS[map_id]
      if config
        bgm = night? ? config[:night] : config[:day]
        return bgm if available_bgm?(bgm)
      end
    end
    nil
  end

  def self.refresh_map_default(map_data)
    @map_default_bgm = map_data&.autoplay_bgm ? $game_map.sc_dynmusic_bgm_name : nil
    @map_default_audio = map_data&.bgm && @map_default_bgm ?
      RPG::AudioFile.new(@map_default_bgm, map_data.bgm.volume, map_data.bgm.pitch) : nil
  end

  def self.note_map_default
    map_data = $game_map&.instance_variable_get(:@map)
    if !map_data&.autoplay_bgm && @pending_bgm && !$game_system.playing_bgm && available_bgm?(@pending_from)
      safe_bgm_play(@pending_from_audio || @pending_from)
    end
    refresh_map_default(map_data)
    @pending_bgm     = nil
    @pending_play_at = nil
    @pending_from    = nil
    @pending_from_audio = nil
  end

  def self.event_running?
    return false unless $game_system && $game_system.map_interpreter
    $game_system.map_interpreter.running?
  end

  def self.in_vehicle?
    return false unless $PokemonGlobal
    $PokemonGlobal.surfing || $PokemonGlobal.diving || $PokemonGlobal.bicycle
  end

  def self.owns_overworld_bgm?
    audio = ($game_system.playing_bgm rescue nil)
    return true if audio.nil?
    if audio.name == @ow_target || audio.name == desired_overworld_bgm
      return true if audio.volume == DynamicMusic::VOLUME_NORMAL && audio.pitch == 100
    end
    if audio.name == @map_default_bgm
      map_data = $game_map&.instance_variable_get(:@map)
      map_audio = map_data&.autoplay_bgm ? map_data.bgm : nil
      return false if audio.volume != (map_audio&.volume || 100) ||
                      audio.pitch != (map_audio&.pitch || 100)
      return true
    end
    false
  end

  def self.update_overworld
    play_pending
    now = System.uptime
    return if now - @last_check < RECHECK_INTERVAL
    @last_check = now
    recheck_overworld
  end

  def self.recheck_overworld
    return if event_running?
    return if in_vehicle?
    owns_bgm = owns_overworld_bgm?
    map_data = $game_map&.instance_variable_get(:@map)
    refresh_map_default(map_data)
    return unless owns_bgm
    desired = desired_overworld_bgm
    target  = desired || @map_default_bgm
    unless available_bgm?(target)
      playing = ($game_system.playing_bgm&.name rescue nil)
      pbBGMFade(DynamicMusic::FADE_DURATION / 1000.0) if @ow_target && playing == @ow_target
      @ow_target = nil
      @pending_bgm = @pending_play_at = @pending_from = nil
      @pending_from_audio = nil
      return
    end
    if @pending_bgm == target
      @ow_target = desired
      return
    end
    audio = ($game_system.playing_bgm rescue nil)
    target_audio = desired ? RPG::AudioFile.new(target, DynamicMusic::VOLUME_NORMAL, 100) : map_data&.bgm
    if audio&.name == target && target_audio &&
       audio.volume == target_audio.volume && audio.pitch == target_audio.pitch
      @ow_target = desired
      return
    end
    debug_log("overworld -> #{target.inspect}")
    @ow_target = desired
    fade_to(target)
  end

  def self.reset_overworld
    @ow_target       = nil
    @pending_bgm     = nil
    @pending_play_at = nil
    @pending_from    = nil
    @pending_from_audio = nil
    @last_check      = 0.0
  end

  def self.with_transfer_autoplay
    previous = @transfer_autoplay
    @transfer_autoplay = true
    yield
  ensure
    @transfer_autoplay = previous
  end

  def self.transfer_autoplay?
    !!@transfer_autoplay
  end

  def self.boss_trainer_type(battle)
    foe = battle.opponent
    return nil unless foe.is_a?(Array)
    foe.each_with_index do |t, trainer_index|
      next unless t
      tt = t.trainer_type rescue nil
      next unless tt && DynamicMusic::BOSS_PHASES.key?(tt)
      active = battle.battlers.any? do |b|
        b && b.opposes? && !b.fainted? &&
          battle.pbGetOwnerIndexFromBattlerIndex(b.index) == trainer_index
      end
      return tt if active
    end
    nil
  end

  def self.boss_battle?(battle)
    !boss_trainer_type(battle).nil?
  end

  def self.boss_phase_bgm(battle)
    return nil unless battle.opponent.is_a?(Array)
    selected = nil
    battle.opponent.each_with_index do |trainer, trainer_index|
      next unless trainer
      trainer_type = trainer.trainer_type rescue nil
      phases = DynamicMusic::BOSS_PHASES[trainer_type]
      next if phases.nil? || phases.empty?
      total_hp = 0
      current_hp = 0
      battle.battlers.each do |b|
        next unless b && b.opposes? && !b.fainted?
        next unless battle.pbGetOwnerIndexFromBattlerIndex(b.index) == trainer_index
        total_hp += b.totalhp
        current_hp += b.hp
      end
      next if total_hp <= 0
      ratio = current_hp.to_f / total_hp
      phase = phases.select { |p| ratio <= p[:threshold] && available_bgm?(p[:bgm]) }.min_by { |p| p[:threshold] }
      selected = phase if phase && (!selected || phase[:threshold] < selected[:threshold])
    end
    selected && selected[:bgm]
  end

  def self.player_low_hp?(battle)
    return false unless DynamicMusic::LOW_HP_ENABLED
    pb = battle.battlers.find { |b| b && !b.fainted? && battle.pbOwnedByPlayer?(b.index) }
    return false unless pb
    first, last = battle.pbTeamIndexRangeFromBattlerIndex(pb.index)
    return false unless battle.pbParty(pb.index)[first...last].count { |pkmn| pkmn&.able? } == 1
    ratio = pb.hp.to_f / pb.totalhp
    threshold = DynamicMusic::LOW_HP_THRESHOLD
    (@battle_target == DynamicMusic::LOW_HP_BGM) ? (ratio <= threshold + 0.05) : (ratio <= threshold)
  end

  def self.foe_last_pokemon?(battle)
    return false unless DynamicMusic::LAST_POKEMON_ENABLED
    return false unless battle.trainerBattle?
    battle.battlers.any? do |b|
      next false unless b && b.opposes? && !b.fainted?
      first, last = battle.pbTeamIndexRangeFromBattlerIndex(b.index)
      battle.pbParty(b.index)[first...last].count { |pkmn| pkmn&.able? } == 1
    end
  end

  def self.desired_battle_bgm(battle)
    boss = boss_battle?(battle)
    if boss
      phase = boss_phase_bgm(battle)
      return phase if phase
    end
    return DynamicMusic::LOW_HP_BGM if player_low_hp?(battle) && available_bgm?(DynamicMusic::LOW_HP_BGM)
    return DynamicMusic::LAST_POKEMON_BGM if !boss && foe_last_pokemon?(battle) && available_bgm?(DynamicMusic::LAST_POKEMON_BGM)
    nil
  end

  def self.apply_battle_music(battle)
    return unless battle
    return if battle.decision != 0
    @battle_context = battle
    desired = desired_battle_bgm(battle)
    audio = ($game_system.playing_bgm rescue nil)
    if desired == @battle_target
      return if !desired || @battle_pending || !same_audio?(audio, @battle_base) ||
                plugin_battle_audio?(audio, desired)
      @battle_target = nil
    end
    return if !@battle_target && @battle_base && !same_audio?(audio, @battle_base)
    return if !@battle_target && @battle_base_captured && @battle_base.nil? && audio
    return if @battle_target && audio.nil? && !@battle_pending
    if @battle_target && audio && !plugin_battle_audio?(audio, @battle_target) &&
       !same_audio?(audio, @battle_from_audio) && !same_audio?(audio, @battle_base)
      return
    end
    previous_target = @battle_target
    @battle_target = desired
    if desired
      unless @battle_base_captured
        @battle_base = (audio&.clone rescue nil)
        @battle_base_captured = true
      end
      debug_log("battle -> #{desired.inspect}")
      fade_battle_to(desired)
    elsif @battle_base
      debug_log("battle -> restore #{@battle_base.inspect}")
      fade_battle_to(@battle_base)
    elsif previous_target
      playing = ($game_system.playing_bgm&.name rescue nil)
      pbBGMFade(DynamicMusic::FADE_DURATION / 1000.0) if playing == previous_target
      @battle_pending = @battle_play_at = @battle_from = @battle_from_audio = nil
    end
  end

  def self.reset_battle
    @battle_context = nil
    @battle_target = nil
    @battle_base   = nil
    @battle_base_captured = false
    @battle_pending = nil
    @battle_play_at = nil
    @battle_from = nil
    @battle_from_audio = nil
  end

  def self.note_battle_base
    @battle_base = ($game_system.playing_bgm&.clone rescue nil)
    @battle_base_captured = true
  end

  def self.safe_bgm_play(bgm_name, map_default = false)
    return false unless available_bgm?(bgm_name.is_a?(RPG::AudioFile) ? bgm_name.name : bgm_name)
    if bgm_name.is_a?(RPG::AudioFile)
      pbBGMPlay(bgm_name)
    elsif map_default && $game_map&.bgm
      pbBGMPlay(bgm_name, $game_map.bgm.volume, $game_map.bgm.pitch)
    else
      pbBGMPlay(bgm_name, DynamicMusic::VOLUME_NORMAL)
    end
    true
  rescue StandardError => e
    debug_log("BGM #{bgm_name.inspect} failed to play: #{e.message}")
    false
  end

  def self.same_audio?(first, second)
    first && second && first.name == second.name &&
      first.volume == second.volume && first.pitch == second.pitch
  end

  def self.keep_shared_theme?(audio, map_audio, target)
    return false unless audio && audio.name == target
    return true if audio.volume == DynamicMusic::VOLUME_NORMAL && audio.pitch == 100
    return false if same_audio?(audio, @map_default_audio)
    return false if map_audio && audio.volume == map_audio.volume && audio.pitch == map_audio.pitch
    true
  end

  def self.plugin_battle_audio?(audio, target)
    return false unless audio && target
    return same_audio?(audio, target) if target.is_a?(RPG::AudioFile)
    return false unless audio.name == target
    audio.volume == DynamicMusic::VOLUME_NORMAL && audio.pitch == 100
  end

  def self.fade_to(bgm_name)
    return unless available_bgm?(bgm_name)
    fade = DynamicMusic::FADE_DURATION / 1000.0
    @pending_from = ($game_system.playing_bgm&.name rescue nil)
    @pending_from_audio = ($game_system.playing_bgm&.clone rescue nil)
    pbBGMFade(fade)
    @pending_bgm     = bgm_name
    @pending_play_at = System.uptime + fade
  end

  def self.play_pending
    return unless @pending_bgm
    return if System.uptime < @pending_play_at
    map_data = $game_map&.instance_variable_get(:@map)
    refresh_map_default(map_data)
    desired = desired_overworld_bgm
    latest = desired || @map_default_bgm
    if @pending_bgm != latest || @ow_target != desired
      @pending_bgm = available_bgm?(latest) ? latest : nil
      @ow_target = desired
    end
    playing_audio = ($game_system.playing_bgm rescue nil)
    if !event_running? && !in_vehicle? &&
       (playing_audio.nil? || same_audio?(playing_audio, @pending_from_audio))
      if @pending_bgm
        safe_bgm_play(@pending_from_audio || @pending_from) unless safe_bgm_play(@pending_bgm, @ow_target.nil?)
      else
        pbBGMStop
      end
    end
    @pending_bgm     = nil
    @pending_play_at = nil
    @pending_from    = nil
    @pending_from_audio = nil
  end

  def self.battle_clock
    System.respond_to?(:battle_speed_control_uptime) ? System.battle_speed_control_uptime : System.uptime
  end

  def self.fade_battle_to(bgm_name)
    name = bgm_name.is_a?(RPG::AudioFile) ? bgm_name.name : bgm_name
    return unless available_bgm?(name)
    fade = DynamicMusic::FADE_DURATION / 1000.0
    @battle_from = ($game_system.playing_bgm&.name rescue nil)
    @battle_from_audio = ($game_system.playing_bgm&.clone rescue nil)
    pbBGMFade(fade)
    @battle_pending = bgm_name
    @battle_play_at = battle_clock + fade
    @pending_bgm     = nil
    @pending_play_at = nil
    @pending_from    = nil
    @pending_from_audio = nil
    play_battle_pending if fade <= 0
  end

  def self.play_battle_pending
    return unless @battle_pending
    if @battle_context && @battle_context.decision != 0
      @battle_pending = @battle_play_at = @battle_from = @battle_from_audio = nil
      return
    end
    return if battle_clock < @battle_play_at
    if @battle_context
      desired = desired_battle_bgm(@battle_context)
      if desired != @battle_target
        @battle_target = desired
        @battle_pending = desired || @battle_base
      end
    end
    playing_audio = ($game_system.playing_bgm rescue nil)
    if playing_audio.nil? || same_audio?(playing_audio, @battle_from_audio)
      if @battle_pending
        safe_bgm_play(@battle_from_audio || @battle_base || @battle_from) unless safe_bgm_play(@battle_pending)
      else
        pbBGMStop
      end
    end
    @battle_pending = nil
    @battle_play_at = nil
    @battle_from = nil
    @battle_from_audio = nil
  end

  def self.deactivate
    if @battle_target || @battle_pending
      audio = ($game_system.playing_bgm rescue nil)
      if audio.nil? || plugin_battle_audio?(audio, @battle_target) ||
         plugin_battle_audio?(audio, @battle_pending) || same_audio?(audio, @battle_from_audio)
        @battle_base ? safe_bgm_play(@battle_base) : pbBGMStop
      end
    elsif (@ow_target || @pending_bgm) && owns_overworld_bgm?
      @map_default_bgm ? safe_bgm_play(@map_default_bgm, true) : pbBGMStop
    end
    reset_overworld
    reset_battle
  end
end

EventHandlers.add(:on_frame_update, :sc_dynamic_music_tick,
  proc {
    next unless DynamicMusic.on?
    DynamicMusicEngine.update_overworld if $scene.is_a?(Scene_Map)
  }
)

EventHandlers.add(:on_enter_map, :sc_dynamic_music_map,
  proc { |_old_map_id|
    next unless DynamicMusic.on?
    DynamicMusicEngine.note_map_default
    DynamicMusicEngine.recheck_overworld
  }
)

class Game_Map
  unless method_defined?(:sc_dynmusic_bgm_name)
    alias_method :sc_dynmusic_bgm_name, :bgm_name
  end

  unless method_defined?(:sc_dynmusic_autoplayAsCue)
    alias_method :sc_dynmusic_autoplayAsCue, :autoplayAsCue
  end

  unless method_defined?(:sc_dynmusic_autoplay)
    alias_method :sc_dynmusic_autoplay, :autoplay
  end

  def bgm_name
    raw = sc_dynmusic_bgm_name
    return raw unless DynamicMusic.on?
    DynamicMusicEngine.desired_overworld_bgm(map_id) || raw
  end

  def autoplayAsCue
    if DynamicMusic.on? && @map.autoplay_bgm
      target = DynamicMusicEngine.desired_overworld_bgm(map_id)
      if target
        audio = $game_system&.playing_bgm
        unless DynamicMusicEngine.keep_shared_theme?(audio, @map.bgm, target)
          pbCueBGM(target, 1.0, DynamicMusic::VOLUME_NORMAL, 100)
        end
        pbBGSPlay(@map.bgs) if @map.autoplay_bgs
        return
      end
    end
    sc_dynmusic_autoplayAsCue
  end

  def autoplay
    if DynamicMusic.on? && @map.autoplay_bgm
      target = DynamicMusicEngine.desired_overworld_bgm(map_id)
      if target
        unless DynamicMusicEngine.transfer_autoplay? &&
               DynamicMusicEngine.keep_shared_theme?($game_system&.playing_bgm, @map.bgm, target)
          pbBGMPlay(target, DynamicMusic::VOLUME_NORMAL, 100)
        end
        pbBGSPlay(@map.bgs) if @map.autoplay_bgs
        return
      end
    end
    sc_dynmusic_autoplay
  end
end

class Scene_Map
  alias sc_dynmusic_transfer_player transfer_player unless method_defined?(:sc_dynmusic_transfer_player)

  def transfer_player(*args)
    DynamicMusicEngine.with_transfer_autoplay { sc_dynmusic_transfer_player(*args) }
  end
end

class Battle
  unless method_defined?(:sc_dynmusic_pbStartBattle)
    alias_method :sc_dynmusic_pbStartBattle, :pbStartBattle
  end

  def pbStartBattle
    DynamicMusicEngine.note_battle_base if DynamicMusic.on?
    sc_dynmusic_pbStartBattle
  end

  unless method_defined?(:sc_dynmusic_pbEndOfRoundPhase)
    alias_method :sc_dynmusic_pbEndOfRoundPhase, :pbEndOfRoundPhase
  end

  def pbEndOfRoundPhase
    sc_dynmusic_pbEndOfRoundPhase
    DynamicMusicEngine.apply_battle_music(self) if DynamicMusic.on?
  end
end

class Battle::Scene
  unless method_defined?(:sc_dynmusic_pbUpdate)
    alias_method :sc_dynmusic_pbUpdate, :pbUpdate
  end

  def pbUpdate(cw = nil)
    sc_dynmusic_pbUpdate(cw)
    DynamicMusicEngine.play_battle_pending if DynamicMusic.on?
  end
end

EventHandlers.add(:on_start_battle, :sc_dynamic_music_battle_start,
  proc {
    DynamicMusicEngine.reset_overworld
    DynamicMusicEngine.reset_battle
  }
)

EventHandlers.add(:on_end_battle, :sc_dynamic_music_cleanup,
  proc { |_result, _can_lose|
    DynamicMusicEngine.reset_battle
    DynamicMusicEngine.reset_overworld
  }
)
