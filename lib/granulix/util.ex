defmodule Granulix.Util do
  alias Granulix.Math

  @doc """
  Make two channels muliplied with pos and 1.0 - pos respectively.
  pos shall be between 0.0 and 1.0.
  """
  @spec pan(x :: Granulix.frames(), pos :: float()) :: list(Granulix.frames)
  def pan(x, pos) when is_binary(x) do
    [Math.mul(x, pos), Math.mul(x, 1.0 - pos)]
  end

  @doc "Sum a list of frames into one"
  @spec mix(l :: list(Granulix.frames())) :: Granulix.frames()
  def mix(l) when is_list(l) do
    Enum.reduce(l, <<>>, fn x, acc -> Math.add(x, acc) end)
  end

  defmodule Stream do
    @type fs() :: Granulix.Stream.frames_stream()
    @type list_of_frames_stream() :: Enumerable.list(Granulix.frames())
    @type lfs() :: fs() | list_of_frames_stream()

    @doc "Sum a stream of list of frames into one"
    @spec mix(enum :: list_of_frames_stream()) :: fs()
    def mix(enum) do
      Elixir.Stream.map(enum, &Granulix.Util.mix/1)
    end

    @doc """
    Make two channels muliplied with pos and 1.0 - pos respectively.
    pos shall be between 0.0 and 1.0. The returned stream holds a list
    of two frame arrays.
    """
    @spec pan(enum :: fs(), pos :: float()) :: list_of_frames_stream()
    def pan(enum, panning) do
      Elixir.Stream.map(enum, fn frames -> Granulix.Util.pan(frames, panning) end)
    end

    @doc """
    This function is the one that will halt the stream. It shall be included
    in your pipeline unless you have some other means of stopping it.
    The time argument is in seconds.
    """
    @spec dur(enum :: lfs(),
      time :: float(),
      rate :: pos_integer()) :: lfs()
    def dur(enum, time, rate) do
      no_of_frames = round(time * rate)

      Elixir.Stream.transform(
        enum,
        no_of_frames,
        fn frames, acc ->
          if acc > 0 do
            case is_list(frames) do
              true ->
                {[frames], acc - byte_size(hd(frames)) / 4}
              false ->
                {[frames], acc - byte_size(frames) / 4}
            end
          else
            {:halt, acc}
          end
        end)
    end
  end
end
