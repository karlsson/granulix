defprotocol Granulix.Time.PlayTime do
  def wait(time, delay)
  def timeout(time)
  def step(time)
end
