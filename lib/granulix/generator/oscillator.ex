defmodule Granulix.Generator.Oscillator do
  alias __MODULE__
  @behaviour SC.Plugin

  defstruct [:frequency, :ref]

  @type frequency() :: number() | Enumerable.number()
  @type oscillator() :: %Oscillator{frequency: frequency(), ref: reference()}

  @typedoc false
  @type osc_type :: :sin | :saw | :triangle

  # -----------------------------------------------------------
  @on_load :load_nifs

  @doc false
  def load_nifs do
    case :erlang.load_nif(:code.priv_dir(:granulix) ++ '/granulix_osc', 0) do
      :ok -> :ok
      {:error, {:reload, _}} -> :ok
      {:error, reason} ->
        :logger.warning('Failed to load granulix_osc NIF: ~p',[reason])

    end
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

  @spec sin(frequency :: frequency()) :: oscillator()
  def sin(frequency \\ 440.0) do
    ctx = Granulix.Ctx.get()
    %Oscillator{ref: osc_ctor(ctx.rate, :sin), frequency: frequency}
  end

  @spec saw(frequency :: frequency()) :: oscillator()
  def saw(frequency \\ 440.0) do
    ctx = Granulix.Ctx.get()
    %Oscillator{ref: osc_ctor(ctx.rate, :saw), frequency: frequency}
  end

  @spec triangle(frequency :: frequency()) :: oscillator()
  def triangle(frequency \\ 440.0) do
    ctx = Granulix.Ctx.get()
    %Oscillator{ref: osc_ctor(ctx.rate, :triangle), frequency: frequency}
  end

  @doc "Get next no of frames"
  @spec next(oscillator(), no_of_frames :: integer()) :: binary()
  @impl SC.Plugin
  def next(%Oscillator{ref: ref, frequency: frequency}, no_of_frames) do
    osc_next(ref, 1.0 * frequency, no_of_frames)
  end

  @spec stream(oscillator(), no_of_frames :: integer()) :: Enumerable.binary()
  @impl SC.Plugin
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

  defmodule Stream do
    alias Granulix.Generator.Oscillator, as: Parent

    def sin(frequency \\ 440.0) do
      Parent.stream(Parent.sin(frequency), (Granulix.Ctx.get()).period_size)
    end

    def saw(frequency \\ 440.0) do
      Parent.stream(Parent.saw(frequency), (Granulix.Ctx.get()).period_size)
    end

    def triangle(frequency \\ 440.0) do
      Parent.stream(Parent.triangle(frequency), (Granulix.Ctx.get()).period_size)
    end

  end

end
