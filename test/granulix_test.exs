defmodule GranulixTest do
  use ExUnit.Case
  # doctest Granulix
  alias Granulix.Math, as: Ma
  alias Granulix.Util
  alias Granulix.Time.{MsTime, PlayTime}
  alias Granulix.Generator
  alias Granulix.Generator.Oscillator, as: Osc
  alias Granulix.Generator.Noise
  alias Granulix.Plugin.AnalogEcho
  alias Granulix.Filter.Biquad

  setup do
    ctx = Granulix.Ctx.new()
    [ctx: ctx]
  end

  test "float list to binary" do
    assert Ma.float_list_to_binary([2.0, 4.0]) == <<0, 0, 0, 64, 0, 0, 128, 64>>
  end

  test "twinkle", context do
    rate = context[:ctx].rate
    dur = 0.3
    no_frames = tot_frames(dur)
    # This means overlap of 2 grains
    next = dur * 0.5
    # gives 2 S sinusoidal envelope
    env = envelope(no_frames)

    notes = [:C, :D, :E, :F, :G, :A, :B]

    [c, d, e, f, g, a, _b] =
      notes
      |> Enum.map(fn x ->
        freq(x)
        |> generate_sinus(rate, no_frames)
        |> Ma.mul(0.2)
        |> Ma.mul(env)
        # |> Granulix.Math.simdcross(env)
      end)

    # zero grain
    z = (c <> c) |> Ma.mul(0.0)

    twinkle = [
      c,
      z,
      c,
      z,
      g,
      z,
      g,
      z,
      a,
      z,
      a,
      z,
      g,
      g,
      g,
      z,
      f,
      z,
      f,
      z,
      e,
      z,
      e,
      z,
      d,
      z,
      d,
      z,
      c,
      c,
      c
    ]

    send_notes(twinkle ++ twinkle, next)
    :timer.sleep(12000)
    log_max_gauges()
  end

  # Some code translated from Bartetzki Supercollider grains example 3
  # https://www.bartetzki.de/docs/kita_sc08/examples_5_(grains+tasks).rtf
  test "example 3 dense random texture", context do
    rate = context[:ctx].rate
    dur = 0.2
    no_frames = tot_frames(dur)
    env = line_envelope(no_frames)
    vol = 0.2
    # Start one second from now
    next0 = PlayTime.wait(%MsTime{}, 1)
    white = generate_white(no_frames)

    for x <- 1..100 do
      freq = Enum.random(100..700)
      next = PlayTime.wait(next0, x * dur *  Enum.random(10..40) / 100)

      spawn(fn ->
        pos = Enum.random(0..100) / 100

        generate_sinus(freq, rate, no_frames)
        |> Ma.add(white)
        |> Ma.mul(env)
        |> Ma.mul(vol)
        |> echo(next, 0.25)
        |> pan(pos)
        |> send_frames(next)
      end)
    end

    :timer.sleep(10000)
    log_max_gauges()
  end

  test "example 3 again dense random texture" do
    :timer.sleep(200)
    dur = 0.2
    vol = 0.1
    time0 = PlayTime.wait(%MsTime{}, 0.5)

    for x <- 1..500 do
      freq = Enum.random(1000..7000)
      next = PlayTime.wait(time0, x * dur * Enum.random(10..40) / 800)
      # next = 0.005
      pos = Enum.random(0..100) / 100

      spawn(fn ->
        synth(dur, freq, pos, vol)
        |> send_frames(next)
      end)
    end

    :timer.sleep(8000)
    log_max_gauges()
  end

  test "kickdrum" do
    time0 = PlayTime.wait(%MsTime{}, 0.5)

    for x <- 1..12 do
      nexttime = PlayTime.wait(time0, x * 0.5)
      pos = 0.5

      spawn(fn ->
        fullkickdrum()
        |> pan(pos)
        |> send_frames(nexttime)
      end)
    end

    :timer.sleep(8000)
    log_max_gauges()
  end

  test "kickdrum with streams", context do
    time0 = PlayTime.wait(%MsTime{}, 0.5)
    rate = context[:ctx].rate
    period_size = context[:ctx].period_size
    pos = 0.5

    for x <- 1..12, y <- [0, 1, 3] do
      nexttime = PlayTime.wait(time0, x * 0.75 + y * 0.125)

      spawn(fn ->
        stream =
          sfullkickdrum(rate, period_size)
          |> Util.Stream.pan(pos)
          |> Util.Stream.dur(1.0, rate)
          |> Granulix.Stream.out()

        timeout = PlayTime.timeout(nexttime)
        :timer.sleep(timeout)
        Stream.run(stream)
      end)
    end

    :timer.sleep(12000)
    log_max_gauges()
  end

  test "stream test sinus", context do
    rate = context[:ctx].rate
    fm = ktriangle(4) |> Stream.map(&(&1 * 20 + 440))
    # You can have a stream as modulating frequency input for osc
    Granulix.Stream.new(%{Osc.sin(rate) | frequency: fm})
    |> Util.Stream.pan(0.5)
    |> Util.Stream.dur(5.0, rate)
    |> Granulix.Stream.out()
    |> Stream.run()

    log_max_gauges()
  end

  test "stream test saw", context do
    rate = context[:ctx].rate
    osc = Osc.saw(rate)
    no_of_frames = context[:ctx].period_size

    ksin(4, context[:ctx])
    |> Stream.map(&(&1 * 20 + 220))
    |> Stream.map(fn freq -> Generator.next(%{osc | frequency: freq}, no_of_frames) end)
    |> Stream.map(fn frames -> Ma.mul(frames, 0.3) end)
    |> Util.Stream.pan(0.5)
    |> Util.Stream.dur(5, rate)
    |> Granulix.Stream.out()
    |> Stream.run()

    log_max_gauges()
  end

  test "stream test triangle", context do
    rate = context[:ctx].rate
    fm = ksin(4, context[:ctx]) |> Stream.map(&(&1 * 10 + 320))

    Granulix.Stream.new(%{Osc.triangle(rate) | frequency: fm})
    |> senvelope(2.0)
    |> Stream.map(fn {frames, mul} -> Ma.mul(frames, mul * 0.4) end)
    |> Granulix.Stream.new(AnalogEcho.init(rate, 0.3))
    |> Stream.zip(ksin(1.5, context[:ctx]))
    |> Stream.map(fn {frames, panning} -> Granulix.Util.pan(frames, panning) end)
    |> Util.Stream.dur(5.0, rate)
    |> Granulix.Stream.out()
    |> Stream.run()

    log_max_gauges()
  end

  test "stream test lowpass", context do
    fm = ktriangle(0.25) |> Stream.map(&(&1 * 200 + 320))
    # You can have a stream as modulating frequency input for osc
    Granulix.Stream.new(%{Osc.sin(context[:ctx].rate) | frequency: fm})
    |> Granulix.Stream.new(Biquad.lowpass(context[:ctx].rate, 320, 10))
    |> Util.Stream.pan(0.5)
    |> Util.Stream.dur(5.0, context[:ctx].rate)
    |> Granulix.Stream.out()
    |> Stream.run()

    log_max_gauges()
  end

  test "stream test highpass", context do
    fm = ktriangle(0.25) |> Stream.map(&(&1 * 200 + 320))
    # You can have a stream as modulating frequency input for osc
    Granulix.Stream.new(%{Osc.sin(context[:ctx].rate) | frequency: fm})
    |> Stream.map(fn frames -> Ma.mul(frames, 0.4) end)
    |> Granulix.Stream.new(Biquad.highpass(context[:ctx].rate, 320, 10))
    |> Util.Stream.pan(0.5)
    |> Util.Stream.dur(5.0, context[:ctx].rate)
    |> Granulix.Stream.out()
    |> Stream.run()

    log_max_gauges()
  end

  test "Hi Hat", context do
    rate = context[:ctx].rate
    openhat(rate)
    closehat(rate)
    log_max_gauges()
  end

  test "Moog test", context do
    rate = context[:ctx].rate
    streamf = fn(freq) ->
      fm = ktriangle(5.0) |> Stream.map(&(&1 * 5 + freq))
      panmove = ktriangle(1.0) |> Stream.map(&(&1*0.4 + 0.5 ))
      # You can have a stream as modulating frequency input for osc
      Granulix.Stream.new(%{Osc.sin(rate) | frequency: fm})
      |> Granulix.Stream.new(Granulix.Filter.Moog.new(0.1, 3.2))
      # |> slmenvelope(1.0)
      # |> Stream.map(fn x -> Ma.mul(x, 0.3) end)
      # |> Granulix.Stream.new(%{AnalogEcho.init(rate, 0.25) | fb: 0.7, coeff: 0.8})
      |> Stream.zip(panmove) |> Stream.map(fn {x, y} -> Util.pan(x, y) end)
      |> Granulix.Stream.out()
    end
    a = streamf.(freq(:A))
    c = streamf.(freq(:C))
    a |> Util.Stream.dur(1.4, rate) |> Stream.run()
    c |> Util.Stream.dur(2.4, rate) |> Stream.run()
    a |> Util.Stream.dur(1.4, rate) |> Stream.run()
    log_max_gauges()
  end

  defp synth(dur, freq, pos, vol) do
    no_frames = tot_frames(dur)
    env = line_envelope(no_frames)

    generate_sinus(freq, Granulix.rate(), no_frames)
    |> pan(pos)
    |> Ma.mul(env)
    |> Ma.mul(vol)
  end

  # https://blog.rumblesan.com/post/53271713518/drum-sounds-in-supercollider-part-1
  defp fullkickdrum do
    nof_sub = tot_frames(1.0)
    nof_click = tot_frames(0.02)

    suboutput =
      generate_sinus(100, Granulix.rate(), nof_sub)
      |> Ma.mul(line_envelope(nof_sub))

    clickoutput =
      generate_white(nof_click)
      |> Ma.mul(line_envelope(nof_click))

    Ma.add(suboutput, clickoutput)
  end

  # use streams
  defp sfullkickdrum(rate, _period_size) do
    freq = :rand.uniform() * 4.0 + 98

    suboutput =
      Granulix.Stream.new(Osc.sin(rate, freq))
      |> slmenvelope(1.0)

    clickoutput =
      Granulix.Stream.new(Noise.white())
      |> Granulix.Stream.new(Biquad.lowpass(rate, 1500))
      |> slmenvelope(0.02)

    Stream.zip(suboutput, clickoutput)
    |> Stream.map(fn {s, c} -> Ma.mul(Ma.add(s, c), 0.4) end)
  end

  defp openhat(rate), do: hihat(rate, 0.3)
  defp closehat(rate), do: hihat(rate, 0.1)

  defp hihat(rate, dur) do
    Granulix.Stream.new(Noise.white())
    |> Granulix.Stream.new(Biquad.lowpass(rate, 6000, 1.2))
    |> Granulix.Stream.new(Biquad.highpass(rate, 2000, 1.2))
    |> slmenvelope(dur)
    |> Util.Stream.pan(0.5)
    |> Util.Stream.dur(0.5, rate)
    |> Granulix.Stream.out()
    |> Stream.run()
  end

  defp send_notes(frames, next) do
    time = %MsTime{}
    send_notes(frames, time, next)
  end

  defp send_notes([], _time, _next), do: :ok

  defp send_notes([h | t], time, next) do
    spawn(fn -> send_frames([h, h], time) end)
    send_notes(t, PlayTime.wait(time, next), next)
  end

  defp send_frames(frames, wait) do
    timeout = PlayTime.timeout(wait)
    :timer.sleep(timeout)
    Granulix.out(frames)
  end

  defp generate_white(no_of_frames) do
    Noise.next(Noise.white(), no_of_frames)
  end

  defp generate_sinus(freq, rate, no_of_frames) do
    Osc.next(%{Osc.sin(rate) | frequency: freq}, no_of_frames)
  end

  defp cososc(stop, stop, _step, acc) do
    Enum.reverse(acc)
  end

  defp cososc(n, stop, step, acc) do
    cososc(n + 1, stop, step, [:math.cos(n * step) | acc])
  end

  defp pan(bin, pos) do
    Granulix.Util.pan(bin, pos)
  end

  defp envelope(no_of_frames) do
    step = :math.pi() * 2 / no_of_frames
    cososc(0, no_of_frames, step, []) |> Ma.float_list_to_binary() |> Ma.mul(-0.5) |> Ma.add(0.5)
  end

  defp line_envelope(no_of_frames) do
    step = 1 / no_of_frames

    no_of_frames..1
    |> Enum.map(fn x -> x * step end)
    |> Ma.float_list_to_binary()
  end

  defp tot_frames(dur) do
    tot_frames = round(dur * Granulix.rate())
    div(tot_frames, 8) * 8
  end

  defp echo(frames, wait, delay) do
    echo1(frames, wait, delay, 5)
  end

  defp echo1(frames, _, _, 0), do: frames

  defp echo1(frames, wait, delay, n) do
    spawn(fn ->
      frames
      |> Ma.mul(0.4)
      |> echo1(wait, delay, n - 1)
      # Bounce between left and right
      |> pan(rem(n, 2))
      |> send_frames(PlayTime.wait(wait, delay * (6 - n)))
    end)

    frames
  end

  defp ksin(freq, ctx) do
    step = 2 * :math.pi() * freq * ctx.period_size / ctx.rate

    Stream.unfold(
      0,
      fn acc ->
        next = acc + step
        {:math.sin(acc), next}
      end
    )
  end

  defp ktriangle(freq) do
    step = 4 * freq * Granulix.period_size() / Granulix.rate()

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

  defp senvelope(enum, duration) do
    no_of_frames = round(duration * Granulix.rate())
    twopi_by_nof = :math.pi() * 2 / no_of_frames

    Stream.transform(enum, 0, fn frames, progress ->
      if progress < no_of_frames do
        x = :math.cos(progress * twopi_by_nof) * -0.5 + 0.5
        {[{frames, x}], progress + byte_size(frames) / 4}
      else
        {[{frames, 0.0}], progress}
      end
    end)
  end

  defp slenvelope(enum, duration) do
    no_of_frames = round(duration * Granulix.rate())

    Stream.transform(enum, 0, fn frames, progress ->
      if progress < no_of_frames do
        x = 1.0 - progress / no_of_frames
        {[{frames, x}], progress + byte_size(frames) / 4}
      else
        {[{frames, 0.0}], progress}
      end
    end)
  end

  defp smenvelope(enum, duration) do
    senvelope(enum, duration)
    |> Stream.map(fn {frames, mul} -> Ma.mul(frames, mul) end)
  end

  defp slmenvelope(enum, duration) do
    slenvelope(enum, duration)
    |> Stream.map(fn {frames, mul} -> Ma.mul(frames, mul) end)
  end

  defp freq(tone), do: freq(tone, 4)

  defp freq(:A, 3), do: 220.0
  defp freq(:Asharp, 3), do: 233.08
  defp freq(:B, 3), do: 246.94
  defp freq(:C, 4), do: 261.63
  defp freq(:Csharp, 4), do: 277.18
  defp freq(:D, 4), do: 293.66
  defp freq(:Dsharp, 4), do: 311.13
  defp freq(:E, 4), do: 329.63
  defp freq(:F, 4), do: 349.23
  defp freq(:Fsharp, 4), do: 369.99
  defp freq(:G, 4), do: 392.00
  defp freq(:Gsharp, 4), do: 415.30
  defp freq(:A, 4), do: 440.00
  defp freq(:Asharp, 4), do: 466.16
  defp freq(:B, 4), do: 493.88
  defp freq(:C, 5), do: 523.25
  defp freq(:Csharp, 5), do: 554.37
  defp freq(:D, 5), do: 587.33

  defp log_max_gauges() do
    [max1] = Granulix.api().max_mix_time()
    [max2] = Granulix.api().max_map_size()
    :logger.info('Max mix time ~p µs, max map size ~p', [max1, max2])
    Granulix.api().clear_max_mix_time()
    Granulix.api().clear_max_map_size()
  end
end
