defmodule Granulix.Filter.Moog do
  @moduledoc """
  Emulates the Moog VCF.

  cutoff must be between 0 and 1

  resonance must be between 0 and 4

  This module is from the [Synthex](https://github.com/bitgamma/synthex) application
  but rewritten to use NIFs. (`c_src/granulix_moog.c`)
  """

  alias __MODULE__

  defstruct [:ref, cutoff: 1, resonance: 0]

  # -----------------------------------------------------------
  @on_load :load_nifs

  @doc false
  def load_nifs do
    case :erlang.load_nif(:code.priv_dir(:granulix) ++ '/granulix_moog', 0) do
      :ok -> :ok
      {:error, {:reload, _}} -> :ok
      {:error, reason} ->
        :logger.warning('Failed to load granulix_moog NIF: ~p',[reason])
    end
  end

  @doc false
  def moog_ctor() do
    raise "NIF moog_ctor/0 not loaded"
  end

  @doc false
  def moog_next(_ref, _frames, _cutoff, _resonance) do
    raise "NIF moog_next/4 not loaded"
  end

  # -----------------------------------------------------------
  @spec new(cutoff :: float(), resonance :: float()) :: %Granulix.Filter.Moog{}
  def new(cutoff, resonance) when
  cutoff >= 0.0 and cutoff <= 1.0 and
  resonance >= 0.0 and resonance <= 4.0
    do
    %Moog{ref: Moog.moog_ctor(), cutoff: cutoff, resonance: resonance}
  end

end

# -----------------------------------------------------------
defimpl Granulix.Transformer, for: Granulix.Filter.Moog do
@moduledoc "Transformer protocol implementation for Moog Filter"
  def next(%Granulix.Filter.Moog{ref: ref, cutoff: cf, resonance: r}, frames) do
    Granulix.Filter.Moog.moog_next(ref, frames, cf, r)
  end

  def stream(%Granulix.Filter.Moog{ref: ref, cutoff: cf, resonance: r}, enum) do
    Stream.map(
      enum,
      fn frames -> Granulix.Filter.Moog.moog_next(ref, frames, cf, r) end
    )
  end
end
