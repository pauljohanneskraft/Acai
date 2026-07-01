class Player
  attr_accessor :current_item

  def play(item)
    @current_item = item
    item.play
  end

  def stop
    @current_item.stop if @current_item
  end
end
