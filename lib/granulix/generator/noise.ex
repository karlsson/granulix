defmodule Granulix.Generator.Noise do
  alias __MODULE__
  @behaviour SC.Plugin

  defstruct [:ref]

  # -----------------------------------------------------------
  @on_load :load_nifs

  def load_nifs do
    case :erlang.load_nif(:code.priv_dir(:granulix) ++ '/granulix_noise', 0) do
      :ok -> :ok
      {:error, {:reload, _}} -> :ok
      {:error, reason} ->
            :logger.warning('Failed to load granulix_noise NIF: ~p',[reason])
    end
  end

  def noise_ctor(_type) do
    raise "NIF noise_ctor/1 not loaded"
  end

  def noise_next(_ref, _no_of_frames) do
    raise "NIF noise_next/2 not loaded"
  end

  # -----------------------------------------------------------

  def white(), do: new(:white)
  def pink(), do: new(:pink)
  def brown(), do: new(:brown)
  defp new(type), do: %Noise{ref: Noise.noise_ctor(type)}

  @impl SC.Plugin
  def next(%Noise{ref: ref}, no_of_frames) do
    Noise.noise_next(ref, no_of_frames)
  end

  @impl SC.Plugin
  def stream(%Noise{ref: ref}, no_of_frames) do
    Stream.repeatedly(fn ->
      Noise.noise_next(ref, no_of_frames)
    end)
  end
end
