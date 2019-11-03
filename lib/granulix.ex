defmodule Granulix do
  @moduledoc """
  Granulix - sound synthesis in Elixir.

  *Note:* The application currently uses the Linux adapter Xalsa and so it can
  only be run under Linux.
  """

  @type frames() :: binary()
  @type channel_no() :: pos_integer()
  @type notify_flag() :: boolean()
  @type frames_tuple2() :: {frames(), channel_no()}
  @type frames_tuple3() :: {frames(), channel_no(), notify_flag()}
  @type frames_tuple4() :: {frames(), channel_no(), notify_flag(), from :: pid()}
  @type out_type() :: frames() | frames_tuple2() | frames_tuple3() | frames_tuple4()
  
  @doc """
  Send frames to output

  """
  @spec out(out_type() | [out_type()]) :: :ok

  def out({x, chan, notify, from}) when is_binary(x) do
    api().send_frames(x, chan, notify, from)
  end

  def out({x, chan, notify}), do: out({x, chan, notify, self()})
  def out({x, chan}),         do: out({x, chan, false, self()})

  def out([x | _] = l) when is_binary(x) do
    Enum.with_index(l, 1) |> out()
  end
  
  def out([x | t]) do
    out(x)
    out(t)
  end
  
  def out([]), do: :ok

  @spec rate() :: pos_integer()
  def rate(), do: api().rate()

  @spec period_size() :: pos_integer()
  def period_size(), do: api().period_size()

  @spec wait_ready4more() :: :ok
  def wait_ready4more(), do: api().wait_ready4more

  @doc "Return backend module. Defined in env variable backend_api"
  @spec api() :: atom()
  def api() do
    Application.get_env(:granulix, :backend_api)
  end
end
