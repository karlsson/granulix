defmodule Granulix.Plugin.AnalogEcho do
  alias __MODULE__
  @behaviour SC.Plugin

  @moduledoc """
  Analog Echo plugin.

  """

  @type analog_echo() :: %AnalogEcho{ref: reference(), maxdelay: float(), delay: float(),
  fb: float(), coeff: float()}
  defstruct [:ref, maxdelay: 0.3, delay: 0.3, fb: 0.9, coeff: 0.95]

  # -----------------------------------------------------------
  @on_load :load_nifs
  @doc false
  def load_nifs do
    case :erlang.load_nif(:code.priv_dir(:granulix) ++
          '/granulix_analog_echo', 0) do
      :ok -> :ok
      {:error, {:reload, _}} -> :ok
      {:error, reason} ->
        :logger.warning('Failed to load granulix_analog_echo nif: ~p', [reason])
    end
  end

  @doc false
  defp analog_echo_ctor(_rate, _period_size, _maxdelay) do
    raise "NIF analog_echo_ctor/3 not loaded"
  end

  @doc false
  defp analog_echo_next(_ref, _frames, _delay, _fb, _coeff) do
    raise "NIF analog_echo_next/5 not loaded"
  end

  # -----------------------------------------------------------
  @spec init(rate :: pos_integer(), period_size :: pos_integer(), delay :: float) :: analog_echo()
  def init(rate, period_size, delay \\ 0.3) do
    %AnalogEcho{ref: analog_echo_ctor(rate, period_size, delay), maxdelay: delay, delay: delay}
  end

  # -----------------------------------------------------------
  @spec next(analog_echo(), frames :: binary()) :: binary()
  @impl SC.Plugin
  def next(%AnalogEcho{ref: ref, delay: delay, fb: fb, coeff: coeff}, frames) do
    analog_echo_next(ref, frames, delay, fb, coeff)
  end

  @spec stream(analog_echo(), enum :: Enumerable.t()) :: binary()
  @impl SC.Plugin
  def stream(analog_echo, enum) do
    # When upstream halted - emit echo for 500 * 6 ms ~ 3 s
    enum2 =
      Stream.unfold(500, fn
        0 -> nil
        x -> {<<>>, x - 1}
      end)
    Stream.concat(enum, enum2) |>
      Stream.map(fn frames -> next(analog_echo, frames) end)
  end

end
