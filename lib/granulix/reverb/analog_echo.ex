defmodule Granulix.Reverb.AnalogEcho do
  alias __MODULE__
  
  @type analog_echo() :: %AnalogEcho{ref: reference(), maxdelay: float(), delay: float(),
  fb: float(), coeff: float()}
  defstruct [:ref, maxdelay: 0.3, delay: 0.3, fb: 0.9, coeff: 0.95]

  @on_load :load_nifs
  # -----------------------------------------------------------
  @doc false
  def load_nifs do
    :erlang.load_nif('./priv/granulix_analog_echo', 0)
  end

  @doc false
  defp analog_echo_ctor(_rate, _maxdelay) do
    raise "NIF analog_echo_ctor/2 not loaded"
  end

  @doc false
  defp analog_echo_next(_ref, _frames, _delay, _fb, _coeff) do
    raise "NIF analog_echo_next/5 not loaded"
  end

  # -----------------------------------------------------------
  @spec init(rate :: pos_integer(), delay :: float) :: analog_echo()
  def init(rate, delay \\ 0.3) do
    %AnalogEcho{ref: analog_echo_ctor(rate, delay), maxdelay: delay, delay: delay}
  end

  @spec next(frames :: binary(), analog_echo()) :: binary()
  def next(frames, %AnalogEcho{ref: ref, delay: delay, fb: fb, coeff: coeff}) do
    analog_echo_next(ref, frames, delay, fb, coeff)
  end

  @spec stream(enum :: Enumerable.t(), analog_echo()) :: binary()
  def stream(enum, analog_echo) do
    Stream.map(enum, fn frames -> next(frames, analog_echo) end)
  end
end

# -----------------------------------------------------------
defimpl Granulix.Transformer, for: Granulix.Reverb.AnalogEcho do
  def next(ae, frames) do
    Granulix.Reverb.AnalogEcho.next(frames, ae)
  end

  def stream(ae, enum) do
    Stream.map(enum, fn frames -> Granulix.Reverb.AnalogEcho.next(frames, ae) end)
  end
end
