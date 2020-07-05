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
  def lag_ctor(_rate, _period_size), do: raise "NIF lag_ctor/2 not loaded"
  @doc false
  def lag_next(_ref, _frames, _lag), do: raise "NIF lag_next/3 not loaded"

  @doc false
  def ramp_ctor(_rate, _level), do: raise "NIF ramp_ctor/2 not loaded"
  @doc false
  def ramp_next(_ref, _frames, _lagtime), do: raise "NIF ramp_next/3 not loaded"
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

  # Break a continuous signal into linearly interpolated segments
  # with specific durations.
  defmodule Ramp do
    @behaviour SC.Plugin
    defstruct [:ref, lagTime: 0.1]

    def new(rate, level) do
      %__MODULE__{ref: SC.Filter.ramp_ctor(rate, level)}
    end
    def next(%__MODULE__{ref: ref, lagTime: lagtime}, frames) do
      SC.Filter.ramp_next(ref, frames, lagtime)
    end
    def stream(m = %__MODULE__{}, enum) do
      Stream.map(enum, fn frames -> next(m, frames) end)
    end
  end
end
