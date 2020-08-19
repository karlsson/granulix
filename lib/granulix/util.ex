defmodule Granulix.Util do
  alias Granulix.Math

  @doc """
  Make two channels muliplied with pos and 1.0 - pos respectively.
  pos shall be between 0.0 and 1.0.
  """
  @spec pan(x :: Granulix.frames(), pos :: float()) :: list(Granulix.frames)
  def pan(x, pos) when is_binary(x) do
    posn = 0.5 * pos + 0.5
    [Math.mul(x, posn), Math.mul(x, 1.0 - posn)]
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
    @spec pan(enum :: fs(), pos :: float() | Enumerable.t) :: list_of_frames_stream()
    def pan(enum, panning) when is_number(panning) do
      Elixir.Stream.map(enum, fn frames -> Granulix.Util.pan(frames, panning) end)
    end
    def pan(enum, panning) do
      Elixir.Stream.zip(enum, panning)
      |> Elixir.Stream.map(fn {frames, panf} -> Granulix.Util.pan(frames, panf) end)
    end

    @doc """
    This function is the one that will halt the stream. It shall be included
    in your pipeline unless you have some other means of stopping it.
    The time argument is in seconds.
    """
    @spec dur(enum :: lfs(),
      time :: float()) :: lfs()
    def dur(enum, time) do
      ctx = Granulix.Ctx.get()
      period_size = ctx.period_size
      no_of_frames = round(time * ctx.rate)

      Elixir.Stream.transform(
        enum,
        no_of_frames,
        fn frames, acc ->
          if acc > 0 do
            cond do
              is_list(frames)  ->
                {[frames], acc - byte_size(hd(frames)) / 4}
              is_binary(frames) ->
                {[frames], acc - byte_size(frames) / 4}
              is_float(frames) ->
                {[frames], acc - period_size}
              is_integer(frames) ->
                {[frames * 1.0], acc - period_size}
            end
          else
            {:halt, acc}
          end
        end)
    end

    def value(value) when is_number(value) do
      Elixir.Stream.unfold(
        value * 1.0,
        fn x -> {x,x} end
      )
    end

    def setter(key, start_value) when is_number(start_value) do
      Elixir.Stream.unfold(
        start_value * 1.0,
        fn x ->
          receive do
            {^key,nil} -> nil
            {^key,y} -> {y,y}
          after
            0 -> {x,x}
          end
        end
      )
    end

    def set(pid, key, :halt), do: send(pid, {key, nil})
    def set(pid, key, value), do: send(pid, {key, 1.0 * value})
  end
end
