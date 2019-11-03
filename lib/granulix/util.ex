defmodule Granulix.Util do
  alias Granulix.Math

  def pan(x, pos) when is_binary(x) do
    [Math.mul(x, pos), Math.mul(x, 1.0 - pos)]
  end

  def mix(l) when is_list(l) do
    Enum.reduce(l, <<>>, fn x, acc -> Math.add(x, acc) end)
  end

  defmodule Stream do
    def mix(enum) do
      Elixir.Stream.map(enum, &Granulix.Util.mix/1)
    end

    def pan(enum, panning) do
      Elixir.Stream.map(enum, fn frames -> Granulix.Util.pan(frames, panning) end)
    end

    def dur(enum, time, rate) do
      no_of_frames = round(time * rate)

      Elixir.Stream.transform(enum, no_of_frames, fn frames, acc ->
        if acc > 0 do
          {[frames], acc - byte_size(hd(frames)) / 4}
        else
          {:halt, acc}
        end
      end)
    end
  end
end
