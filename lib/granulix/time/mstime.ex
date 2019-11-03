defmodule Granulix.Time.MsTime do
  defstruct oldtime: 0, newtime: 0
  def current_time(), do: :erlang.system_time(:millisecond)
end

defimpl Granulix.Time.PlayTime, for: Granulix.Time.MsTime do
  def wait(playtime, delay) do
    newtime1 =
      case playtime.newtime do
        0 -> Granulix.Time.MsTime.current_time()
        _ -> playtime.newtime
      end

    %{playtime | oldtime: playtime.newtime, newtime: newtime1 + round(delay * 1000)}
  end

  def timeout(playtime) do
    max(playtime.newtime - Granulix.Time.MsTime.current_time(), 0)
  end

  def step(playtime) do
    diff = playtime.newtime - playtime.oldtime
    %{playtime | oldtime: playtime.newtime, newtime: playtime.newtime + diff}
  end
end
