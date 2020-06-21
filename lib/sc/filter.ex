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
  def ramp_next(_ref, _frames, _period), do: raise "NIF ramp_next/3 not loaded"

  @doc false
  def lag_ctor(_rate, _y1), do: raise "NIF lag_ctor/2 not loaded"
  @doc false
  def lag_next(_ref, _frames, _lag), do: raise "NIF lag_next/3 not loaded"
  # -----------------------------------------------------------

  # Break a continuous signal into linearly interpolated segments
  # with specific durations.
  defmodule Ramp do
    @behaviour SC.Plugin
    defstruct [:ref, lagTime: 0.1]

    def new(rate, level) do
      %__MODULE__{ref: SC.Filter.ramp_ctor(rate, level)}
    end
    def next(%__MODULE__{ref: ref, lagTime: period}, frames) do
      SC.Filter.ramp_next(ref, frames, period)
    end
    def stream(m = %__MODULE__{}, enum) do
      Stream.map(enum, fn frames -> next(m, frames) end)
    end

  end
  
  defmodule Lag do
  end
end
