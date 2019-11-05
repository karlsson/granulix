defmodule Granulix.Generator.Lfo do
  alias Granulix.Math, as: GM
  @moduledoc """
  **Low Frequency Oscillator**

  The Lfo module returns a stream of floats() between -1.0 and 1.0.
  To be used as amplitude/frequency modulating input into audio rate streams.

  Example, create a 4 Hz frequency modulator between 420 and 460 Hz and use
  it as input for a sinus oscillator:

      alias Granulix.Generator.Lfo
      alias Granulix.Generator.Oscillator

      ctx = Granulix.Ctx.new()
      fm = Lfo.triangle(ctx, 4) |> Stream.map(&(&1 * 20 + 440))

      # You can have a stream as modulating frequency input for osc
      sinosc = Granulix.Stream.new(Oscillator.sin(rate, fm))

  You can also use the Stream module zip function to insert LFOs,
  here moving sound between left and right channel every second:

      panmove = Lfo.triangle(ctx, 1.0) |> Stream.map(&(&1*0.4 + 0.5 ))

      sinosc
      |> Stream.zip(panmove)
      |> Stream.map(fn {x, y} -> Granulix.Util.pan(x, y) end)
  """


  @spec sin(ctx :: Granulix.Ctx.ctx(), frequency :: number()) :: Enumerable.float()
  def sin(ctx, freq) do
    step = GM.twopi() * freq * ctx.period_size / ctx.rate

    Stream.unfold(
      0,
      fn acc ->
        next = acc + step
        next =
          cond do
            next > GM.twopi() -> next - GM.twopi()
            true -> next
          end
        {:math.sin(acc), next}
      end
    )
  end

  @spec saw(ctx :: Granulix.Ctx.ctx(), frequency :: number()) :: Enumerable.float()
  def saw(ctx, freq) do
    step = 2 * freq * ctx.period_size / ctx.rate

    Stream.unfold(
      0,
      fn acc ->
        val = 1.0 - acc

        next1 = acc + step

        next2 =
          cond do
            next1 > 2.0 -> next1 - 2.0
            true -> next1
          end

        {val, next2}
      end
    )
  end

  @spec triangle(ctx :: Granulix.Ctx.ctx(), frequency :: number()) :: Enumerable.float()
  def triangle(ctx, freq) do
    step = 4 * freq * ctx.period_size / ctx.rate

    Stream.unfold(
      0,
      fn acc ->
        val =
          cond do
            acc < 2.0 -> acc - 1.0
            true -> 3.0 - acc
          end

        next1 = acc + step

        next2 =
          cond do
            next1 > 4.0 -> next1 - 4.0
            true -> next1
          end

        {val, next2}
      end
    )
  end
end
