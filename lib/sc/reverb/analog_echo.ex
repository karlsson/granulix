defmodule SC.Reverb.AnalogEcho do
  @behaviour SC.Plugin

  @moduledoc """
  # Analog Echo

  ### Analog Echo plugin

  The SC.AnalogEcho module and sc_analog_echo.c file combined are translated from the SC [AnalogEcho](https://github.com/supercollider/example-plugins/blob/master/03-AnalogEcho/AnalogEcho.cpp) example as a comparison.

  """

  defstruct ref: nil,
    maxdelay: 0.3,
    delay: 0.3,
    fb: 0.9,
    coeff: 0.95

  @typedoc """
  Properties that can be set for AnalogEcho.

  Available options are:
    * `:maxdelay` - max size of delay buffer in seconds. Default 0.3.
    * `:delay` - delay for echo in seconds. Default 0.3.
    * `:fb` - feedback coefficient. Default 0.9.
    * `:coeff` - filter coefficient. Default 0.95.
  """
  @type t() :: %__MODULE__{
    ref: reference(),
    maxdelay: float(),
    delay: float(),
    fb: float(),
    coeff: float()
  }


  @on_load :load_nifs
  @doc false
  def load_nifs do
    case :erlang.load_nif(:code.priv_dir(:granulix) ++
          '/sc_analog_echo', 0) do
      :ok -> :ok
      {:error, {:reload, _}} -> :ok
      {:error, reason} ->
        :logger.warning('Failed to load sc_analog_echo nif: ~p', [reason])
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


  @spec new(rate :: pos_integer(), period_size :: pos_integer(), maxdelay :: float) :: t
  def new(rate, period_size, maxdelay \\ 0.3) do
    %__MODULE__{ref: analog_echo_ctor(rate, period_size, maxdelay), maxdelay: maxdelay, delay: maxdelay}
  end

  @spec next(t(), frames :: binary()) :: binary()
  def next(%__MODULE__{ref: ref, delay: delay, fb: fb, coeff: coeff}, frames) do
    analog_echo_next(ref, frames, delay, fb, coeff)
  end

  @spec stream(t(), enum :: Enumerable.t()) :: binary()
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
