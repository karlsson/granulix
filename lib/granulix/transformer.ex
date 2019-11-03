defprotocol Granulix.Transformer do
  def next(transformer, frames)
  def stream(transformer, enum)
end
