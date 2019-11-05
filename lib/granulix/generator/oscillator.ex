defmodule Granulix.Generator.Oscillator do
  alias __MODULE__

  defstruct [:frequency, :ref]

  @type frequency() :: number() | Enumerable.number()
  @type oscillator() :: %Oscillator{frequency: frequency(), ref: reference()}

  @typedoc false
  @type osc_type :: :sin | :saw | :triangle

  # -----------------------------------------------------------
  @on_load :load_nifs

  @doc false
  def load_nifs do
    :erlang.load_nif('./priv/granulix_osc', 0)
  end

  @doc false
  @spec osc_ctor(_rate :: integer(), _type :: osc_type()) :: reference()
  defp osc_ctor(_rate, _type) do
    raise "NIF osc_ctor/2 not loaded"
  end

  @doc false
  defp osc_next(_ref, _freq, _no_of_frames) do
    raise "NIF osc_next/3 not loaded"
  end

  # -----------------------------------------------------------

  @spec sin(rate :: integer(), frequency :: frequency()) :: oscillator()
  def sin(rate, frequency \\ 440.0) do
    %Oscillator{ref: osc_ctor(rate, :sin), frequency: frequency}
  end

  @spec saw(rate :: integer(), frequency :: frequency()) :: oscillator()
  def saw(rate, frequency \\ 440.0) do
    %Oscillator{ref: osc_ctor(rate, :saw), frequency: frequency}
  end

  @spec triangle(rate :: integer(), frequency :: frequency()) :: oscillator()
  def triangle(rate, frequency \\ 440.0) do
    %Oscillator{ref: osc_ctor(rate, :triangle), frequency: frequency}
  end

  @doc "Get next no of frames"
  @spec next(oscillator(), no_of_frames :: integer()) :: binary()
  def next(%Oscillator{ref: ref, frequency: frequency}, no_of_frames) do
    osc_next(ref, 1.0 * frequency, no_of_frames)
  end

  @spec stream(oscillator(), no_of_frames :: integer()) :: Enumerable.binary()
  def stream(osc = %Oscillator{frequency: freqin}, no_of_frames) do
    cond do
      is_number(freqin) ->
        Stream.repeatedly(fn ->
          next(osc, no_of_frames)
        end)

      true ->
        Stream.map(
          freqin,
          fn freq ->
            next(%{osc | frequency: freq}, no_of_frames)
          end
        )
    end
  end
end

# -----------------------------------------------------------
defimpl Granulix.Generator, for: Granulix.Generator.Oscillator do
  def next(osc, no_of_frames) do
    Granulix.Generator.Oscillator.next(osc, no_of_frames)
  end

  def stream(osc, no_of_frames) do
    Granulix.Generator.Oscillator.stream(osc, no_of_frames)
  end
end
