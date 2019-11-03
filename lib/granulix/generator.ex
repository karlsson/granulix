defprotocol Granulix.Generator do
  def next(generator, no_of_frames)
  def stream(generator, no_of_frames)
end
