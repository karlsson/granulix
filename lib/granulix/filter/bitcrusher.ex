defmodule Granulix.Filter.Bitcrusher do
  alias __MODULE__
  @behaviour SC.Plugin

  @moduledoc """
  Quantizer / Decimator with smooth control.

  bits must be between 1.0 and 16.0
  normalized_frequency (frequency / rate) must be between 0 and 1

  This module is from the [Synthex](https://github.com/bitgamma/synthex) application
  but rewritten to use NIFs. (`c_src/granulix_bitcrusher.c`)
  """


  defstruct [:ref, bits: 16.0, normalized_frequency: 1.0]

  # -----------------------------------------------------------
  @on_load :load_nifs

  @doc false
  def load_nifs do
    case :erlang.load_nif(:code.priv_dir(:granulix) ++ '/granulix_bitcrusher', 0) do
      :ok -> :ok
      {:error, {:reload, _}} -> :ok
      {:error, reason} ->
        :logger.warning('Failed to load granulix_bitcrusher NIF: ~p',[reason])
    end
  end

  @doc false
  def bitcrusher_ctor() do
    raise "NIF bitcrusher_ctor/0 not loaded"
  end

  @doc false
  def bitcrusher_next(_ref, _frames, _bits, _normalized_frequency) do
    raise "NIF bitcrusher_next/4 not loaded"
  end

  # -----------------------------------------------------------
  @spec new(bits :: integer(), normalized_frequency :: float()) :: %Bitcrusher{}
  def new(bits, normalized_frequency) when is_integer(bits) do
    new(bits * 1.0, normalized_frequency)
  end
  def new(bits, normalized_frequency) when
  normalized_frequency >= 0.0 and normalized_frequency <= 1.0 and
  bits >= 1.0 and bits <= 16.0 do
    %Bitcrusher{ref: Bitcrusher.bitcrusher_ctor(),
                bits: bits,
                normalized_frequency: normalized_frequency}
  end

  @impl SC.Plugin
  def next(%Bitcrusher{ref: ref, bits: bits, normalized_frequency: nf}, frames) do
    Bitcrusher.bitcrusher_next(ref, frames, bits, nf)
  end

  @impl SC.Plugin
  def stream(bitcrusher = %Bitcrusher{}, enum) do
    Stream.map(
      enum,
      fn frames -> next(bitcrusher, frames) end
    )
  end
end
