defmodule SC.Plugin do
  @callback next(plugin :: term, frames :: binary | integer) :: binary()
  @callback stream(plugin :: term, Enumerable.binary() | integer) :: Enumerable.binary()

  def next(frames, plugin) when is_struct(plugin) do
    (plugin.__struct__).next(plugin, frames)
  end

  def next(frames, impl, plugin) do
    impl.next(plugin, frames)
  end

  def stream(plugin) when is_struct(plugin) do
    (plugin.__struct__).stream(plugin, Granulix.period_size())
  end

  def stream(enum, plugin) when is_struct(plugin) do
    (plugin.__struct__).stream(plugin, enum)
  end

  def stream(enum, impl, plugin) do
    impl.stream(plugin, enum)
  end
end
