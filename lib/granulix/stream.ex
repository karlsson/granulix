defmodule Granulix.Stream do
  @moduledoc """
  Granulix.Stream - functions for creating and handling streams of binaries.
  """

  @typedoc "A stream of 32-bit floats"
  @type frames_stream() :: Enumerable.t()
  @type t() :: Granulix.frames()

  @doc "Sends the stream to audio output. Returns the stream"
  @spec out(frames_stream()) :: frames_stream()
  def out(enum) do
    Elixir.Stream.transform(
      enum,
      fn -> :start end,
      fn frames, acc ->
        case acc do
          :cont ->
            Granulix.wait_ready4more()

          :start ->
            :dont_wait
        end

        case is_binary(frames) do
          true ->
            Granulix.out({frames, 1, true, self()})

          false ->
            Granulix.out({hd(frames), 1, true, self()})
            Granulix.out(Enum.with_index(tl(frames), 2))
        end

        {[frames], :cont}
      end,
      fn _acc -> :ok end
    )
  end

  @doc "Creates a generator stream with driver period buffer size."
  @spec new(Granulix.Generator.t()) :: Enumerable.t()
  def new(generator) do
    # (generator.__struct__).stream(generator, Granulix.period_size())
    Granulix.Generator.stream(generator, Granulix.period_size())
  end

  @doc "Creates a transformer stream (filter, reverb etc) with given input stream."
  @spec new(Enumerable.t(), Granulix.Transformer.t()) :: Enumerable.t()
  def new(enum, transformer) do
    # (transformer.__struct__).stream(enum, transformer)
    Granulix.Transformer.stream(transformer, enum)
  end
end
