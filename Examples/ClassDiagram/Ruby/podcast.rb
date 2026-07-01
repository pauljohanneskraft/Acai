require_relative 'media_item'
require_relative 'playable'

class Podcast < MediaItem
  include Playable

  attr_accessor :host, :episode_number

  def initialize(title, duration, host, episode_number)
    super(title, duration)
    @host = host
    @episode_number = episode_number
  end
end
