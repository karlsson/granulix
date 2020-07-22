defmodule SC.Filter do


  # -----------------------------------------------------------
  @on_load :load_nifs

  @doc false
  def load_nifs do
    case :erlang.load_nif(:code.priv_dir(:granulix) ++ '/sc_filter', 0) do
      :ok -> :ok
      {:error, {:reload, _}} -> :ok
      {:error, reason} ->
        :logger.warning('Failed to load sc_filter NIF: ~p',[reason])
    end
  end

  @doc false
  def ramp_ctor(_rate, _level), do: raise "NIF ramp_ctor/2 not loaded"
  @doc false
  def ramp_next(_ref, _frames, _lagtime), do: raise "NIF ramp_next/3 not loaded"
  @doc false

  def lag_ctor(_rate, _period_size), do: raise "NIF lag_ctor/2 not loaded"
  @doc false
  def lag_next(_ref, _frames, _lag), do: raise "NIF lag_next/3 not loaded"

  def lpf_ctor(_rate, _period_size), do: raise "NIF lpf_ctor/2 not loaded"
  @doc false
  def lpf_next(_ref, _frames, _freq), do: raise "NIF lpf_next/3 not loaded"

  # -----------------------------------------------------------
  # Break a continuous signal into linearly interpolated segments
  # with specific durations.
  defmodule Ramp do
    @behaviour SC.Plugin
    defstruct [:ref, lagTime: 0.1]

    def new(lagtime \\ 0.1) do
      %SC.Ctx{rate: rate, period_size: period_size} = SC.Ctx.get()
      %__MODULE__{ref: SC.Filter.ramp_ctor(rate, period_size), lagTime: lagtime}
    end

    def next(%__MODULE__{ref: ref, lagTime: lagtime}, frames) when is_float(lagtime) do
      SC.Filter.ramp_next(ref, frames, lagtime)
    end

    def stream(m = %__MODULE__{lagTime: lagtime}, enum) when is_float(lagtime) do
      Stream.map(enum, fn frames -> next(m, frames) end)
    end
    def stream(%__MODULE__{ref: ref, lagTime: lagtime}, enum) when is_struct(lagtime) do
      Stream.zip(enum, lagtime)
      |> Stream.map(fn {frames, lagtimef} -> SC.Filter.ramp_next(ref, frames, lagtimef) end)
    end
  end

  # -----------------------------------------------------------

  defmodule Lag do
    @behaviour SC.Plugin
    defstruct [:ref, lagTime: 0.1]

    def new(lagtime \\ 0.1) do
      %SC.Ctx{rate: rate, period_size: period_size} = SC.Ctx.get()
      %__MODULE__{ref: SC.Filter.lag_ctor(rate, period_size), lagTime: lagtime}
    end

    def next(%__MODULE__{ref: ref, lagTime: lagtime}, frames) when is_float(lagtime) do
      SC.Filter.lag_next(ref, frames, lagtime)
    end

    def stream(m = %__MODULE__{lagTime: lagtime}, enum) when is_float(lagtime) do
      Stream.map(enum, fn frames -> next(m, frames) end)
    end
    def stream(%__MODULE__{ref: ref, lagTime: lagtime}, enum) when is_struct(lagtime) do
      Stream.zip(enum, lagtime)
      |> Stream.map(fn {frames, lagtimef} -> SC.Filter.lag_next(ref, frames, lagtimef) end)
    end
  end

  # -----------------------------------------------------------

  defmodule LPF do
    @behaviour SC.Plugin
    defstruct [:ref, frequency: 440.0]

    def new(frequency \\ 440.0) do
      %SC.Ctx{rate: rate, period_size: period_size} = SC.Ctx.get()
      %__MODULE__{ref: SC.Filter.lpf_ctor(rate, period_size), frequency: frequency}
    end

    def next(%__MODULE__{ref: ref, frequency: frequency}, frames) when is_float(frequency) do
      SC.Filter.lpf_next(ref, frames, frequency)
    end

    def stream(m = %__MODULE__{frequency: frequency}, enum) when is_float(frequency) do
      Stream.map(enum, fn frames -> next(m, frames) end)
    end
    def stream(%__MODULE__{ref: ref, frequency: frequency}, enum) when is_struct(frequency) do
      Stream.zip(enum, frequency)
      |> Stream.map(fn {frames, frequencyf} -> SC.Filter.lpf_next(ref, frames, frequencyf) end)
    end
  end

end
