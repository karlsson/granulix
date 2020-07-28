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
      fm = Lfo.triangle(ctx, 4) |> Lfo.nma(40, 420)

      # You can have a stream as modulating frequency input for osc
      sinosc = Granulix.Stream.new(Oscillator.sin(rate, fm))

  You can also use the Stream module zip function to insert LFOs,
  here moving sound between left and right channel every second:

      panmove = Lfo.triangle(ctx, 1.0) |> Lfo.nma(0.8, 0.1)

      sinosc
      |> Stream.zip(panmove)
      |> Stream.map(fn {x, y} -> Granulix.Util.pan(x, y) end)
  """


  @spec sin(frequency :: number()) :: Enumerable.float()
  def sin(freq) do
    ctx = Granulix.Ctx.get()
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

  @spec saw(frequency :: number()) :: Enumerable.float()
  def saw(freq) do
    ctx = Granulix.Ctx.get()
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

  @spec triangle(frequency :: number()) :: Enumerable.float()
  def triangle(freq) do
    ctx = Granulix.Ctx.get()
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

  @spec square(frequency :: number(), duty :: float()) :: Enumerable.float()
  def square(freq, duty \\ 0.5) do
    ctx = Granulix.Ctx.get()
    step = freq * ctx.period_size / ctx.rate

    Stream.unfold(
      0,
      fn acc ->
        val =
          cond do
            acc < duty -> 1.0
            true -> -1.0
          end

        next1 = acc + step

        next2 =
          cond do
            next1 > 1.0 -> next1 - 1.0
            true -> next1
          end

        {val, next2}
      end
    )
  end

  @doc """
  Normalize, Multiply, Add

  Move from -1, 1 range to 0, 1 and then multiply and add offset.
  """
  @spec nma(frames :: Enumerable.t, mul :: float, bottomlevel :: float) :: Enumerable.t
  def nma(frames, mul, bottomlevel) do
    x = 0.5 * mul
    Stream.map(frames,(&(&1 * x + bottomlevel + x)))
  end
end
