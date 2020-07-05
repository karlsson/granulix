defmodule GranulixStreamTest do
  use ExUnit.Case
  # doctest Granulix
  alias Granulix.Math, as: Ma
  alias Granulix.Util
  alias Granulix.Time.{MsTime, PlayTime}
  alias Granulix.Generator.Lfo
  alias Granulix.Generator.Oscillator, as: Osc
  alias Granulix.Generator.Noise
  alias Granulix.Filter.{Biquad,Bitcrusher}
  alias Granulix.Envelope
  alias Granulix.Envelope.ADSR
  alias SC.Plugin, as: ScP
  alias SC.Reverb.AnalogEcho
  alias SC.Filter.Lag

  @docp """
  Setting up realtime scheduling policy SCHED_RR with
  chrt needs setup of group audio and user added to this:
  groupadd audio
  usermod -a -G audio yourUserID

  and in /etc/security/limits.d/audio.conf:
  @audio   -  rtprio     95
  @audio   -  memlock    unlimited
  """
  setup do
    ctx = Granulix.Ctx.new()
    sc_ctx = %SC.Ctx{rate: ctx.rate, period_size: ctx.period_size}
    SC.Ctx.put(sc_ctx)
    [ctx: ctx]
  end

  # Some code translated from Bartetzki Supercollider grains example 3
  # https://www.bartetzki.de/docs/kita_sc08/examples_5_(grains+tasks).rtf
  test "example 3 again dense random texture with streams", context do
    :timer.sleep(200)
    rate = context[:ctx].rate
    dur = 0.2
    vol = 0.1
    time0 = PlayTime.wait(%MsTime{}, 0.5)

    for x <- 1..500 do
      freq = Enum.random(1000..7000)
      next = PlayTime.wait(time0, x * dur * Enum.random(10..40) / 800)
      # next = 0.005
      pos = Enum.random(0..100) / 100

      spawn(fn ->
        timeout = PlayTime.timeout(next)
        :timer.sleep(timeout)
        context[:ctx].period_size
        |> ScP.stream(Osc.sin(rate, freq))
        |> Envelope.saw_tuple(dur, rate)
        |> Stream.map(fn {frames, mul} -> Ma.mul(frames, mul * vol) end)
        |> Util.Stream.pan(pos)
        |> Granulix.Stream.play()
      end)
    end

    :timer.sleep(8000)
    log_max_gauges()
  end

  test "kickdrum with streams", context do
    rate = context[:ctx].rate
    period_size = context[:ctx].period_size
    pos = 0.5
    time0 = PlayTime.wait(%MsTime{}, 0.5)

    for x <- 1..12, y <- [0, 1, 3] do
      :timer.sleep(5)
      nexttime = PlayTime.wait(time0, x * 0.75 + y * 0.125)
      spawn(fn ->
        stream =
          sfullkickdrum(rate, period_size)
          |> Util.Stream.pan(pos)
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
    # fm = Lfo.triangle(context[:ctx], 4) |> Stream.map(&(&1 * 20 + 440))
    fm = Lfo.triangle(context[:ctx], 4) |> Lfo.nma(40, 420)
    # You can have a stream as modulating frequency input for osc
    context[:ctx].period_size
    |> ScP.stream(Osc.sin(rate, fm))
    |> Util.Stream.pan(0.5)
    |> Util.Stream.dur(5.0, rate)
    |> Granulix.Stream.play()

    log_max_gauges()
  end

  test "stream test saw", context do
    rate = context[:ctx].rate
    no_of_frames = context[:ctx].period_size

    Lfo.sin(context[:ctx], 4)
    |> Stream.map(&(&1 * 20 + 220))
    |> Stream.map(fn freq ->
      SC.Plugin.next(no_of_frames,
        %{Osc.saw(rate) | frequency: freq})
    end)
    |> Stream.map(fn frames -> Ma.mul(frames, 0.3) end)
    |> Util.Stream.pan(0.5)
    |> Util.Stream.dur(5, rate)
    |> Granulix.Stream.play()

    log_max_gauges()
  end

  test "stream test triangle", context do
    rate = context[:ctx].rate
    period_size = context[:ctx].period_size
    fm = Lfo.sin(context[:ctx], 4) |> Stream.map(&(&1 * 10 + 320))

    period_size
    |> ScP.stream(%{Osc.triangle(rate) | frequency: fm})
    |> Envelope.sin_tuple(rate, 2.0)
    |> Stream.map(fn {frames, mul} -> Ma.mul(frames, mul * 0.4) end)
    |> Util.Stream.dur(2.0, rate)
    |> ScP.stream(AnalogEcho.new(rate, period_size, 0.3))
    |> Stream.zip(Lfo.sin(context[:ctx], 1.5))
    |> Stream.map(fn {frames, panning} -> Granulix.Util.pan(frames, panning) end)
    |> Granulix.Stream.play()

    log_max_gauges()
  end

  test "stream test lowpass", context do
    fm = Lfo.triangle(context[:ctx], 0.25) |> Lfo.nma(400, 120)
    # You can have a stream as modulating frequency input for osc
    context[:ctx].period_size
    |> ScP.stream(%{Osc.sin(context[:ctx].rate) | frequency: fm})
    |> ScP.stream(Biquad.lowpass(context[:ctx].rate, 320, 10))
    |> Util.Stream.pan(0.5)
    |> Util.Stream.dur(5.0, context[:ctx].rate)
    |> Granulix.Stream.play()

    log_max_gauges()
  end

  test "stream test highpass", context do
    fm = Lfo.triangle(context[:ctx], 0.25) |> Stream.map(&(&1 * 200 + 320))
    # You can have a stream as modulating frequency input for osc
    context[:ctx].period_size
    |> ScP.stream(%{Osc.sin(context[:ctx].rate) | frequency: fm})
    |> Stream.map(fn frames -> Ma.mul(frames, 0.4) end)
    |> ScP.stream(Biquad.highpass(context[:ctx].rate, 320, 10))
    |> Util.Stream.pan(0.5)
    |> Util.Stream.dur(5.0, context[:ctx].rate)
    |> Granulix.Stream.play()

    log_max_gauges()
  end

  test "Hi Hat", context do
    rate = context[:ctx].rate
    period_size = context[:ctx].period_size
    spawn(fn ->
      openhat(rate, period_size)
      closehat(rate, period_size)
    end)
    :timer.sleep(2)
    log_max_gauges()
  end

  test "Moog test", context do
    rate = context[:ctx].rate
    streamf = fn(freq) ->
      fm = Lfo.triangle(context[:ctx], 5.0) |> Stream.map(&(&1 * 5 + freq))
      panmove = Lfo.triangle(context[:ctx], 1.0) |> Stream.map(&(&1*0.4 + 0.5 ))
      # You can have a stream as modulating frequency input for osc
      context[:ctx].period_size
      |> ScP.stream(%{Osc.sin(rate) | frequency: fm})
      |> ScP.stream(Granulix.Filter.Moog.new(0.1, 3.2))
      # |> Envelope.saw(rate, 1.0)
      # |> Stream.map(fn x -> Ma.mul(x, 0.3) end)
      # |> ScP.stream(%{AnalogEcho.init(rate, context[:ctx].period_size, 0.25) | fb: 0.7, coeff: 0.8})
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

  test "Bitcrusher", context do
    rate = context[:ctx].rate
    context[:ctx].period_size
    |> ScP.stream(Osc.sin(rate, 440))
    |> ScP.stream(Bitcrusher.new(4, 0.5))
    |> Util.Stream.dur(1.5, rate) |> Util.Stream.pan(0.5)
    |> Granulix.Stream.play()

    bc = Bitcrusher.new(4, 0.7)
    context[:ctx].period_size
    |> ScP.stream(Osc.sin(rate, 440))
    # Let the bitcrusher bits go from 8 to 1 during 6 seconds
    |> Envelope.saw_tuple(rate, 6.0)
    |> Stream.map(fn {enum, envelope} ->
      ScP.next(enum, %{bc | bits: (1 + envelope*7)})
      end)
    |> Util.Stream.dur(7.0, rate) |> Util.Stream.pan(0.5)
    |> Granulix.Stream.play()
  end

  test "Lag filter", context do
    rate = context[:ctx].rate
    fm0 = Lfo.square(context[:ctx], 1) |> Lfo.nma(50, 425)
    # Ramp lagtime from 0 to 1 during 5s
    lagtime = Lfo.saw(context[:ctx], 1/5) |> Lfo.nma(-1,1)
    fm = fm0 |> ScP.stream(Lag.new(lagtime))
    # You can have a stream as modulating frequency input for osc
    context[:ctx].period_size
    |> ScP.stream(%{Osc.sin(rate) | frequency: fm})
    |> Util.Stream.pan(0.5)
    |> Util.Stream.dur(5.0, rate)
    |> Granulix.Stream.play()

    log_max_gauges()
  end

  # test "Multicard", context do
  #   rate = context[:ctx].rate
  #   panning = fn(c1, c2, c3, c4) ->
  #     context[:ctx].period_size |> ScP.stream(Osc.sin(rate, 440))
  #     |> Util.Stream.dur(3.0, rate)
  #     |> Stream.map(fn x -> pan4(x, {c1, c2, c3, c4}) end)
  #     |> Granulix.Stream.out()
  #     |> Stream.run()
  #   end
  #   panning.(1.0, 0.0, 0.0, 0.0)
  #   panning.(0.0, 1.0, 0.0, 0.0)
  #   panning.(0.0, 0.0, 1.0, 0.0)
  #   panning.(0.0, 0.0, 0.0, 1.0)
  # end

  # defp pan4(bin, {c1, c2, c3, c4}) do
  #   [Ma.mul(bin, c1), Ma.mul(bin, c2), Ma.mul(bin, c3), Ma.mul(bin, c4)]
  # end

  # https://blog.rumblesan.com/post/53271713518/drum-sounds-in-supercollider-part-1
  # use streams
  defp sfullkickdrum(rate, period_size) do
    freq = :rand.uniform() * 4.0 + 98

    suboutput =
      period_size
      |> ScP.stream(Osc.sin(rate, freq))
      |> ADSR.new(rate, %ADSR{decay: 0.2, sustain: 1, sustain_level: 0.5, release: 1.0})

    clickoutput =
      period_size
      |> ScP.stream(Noise.white())
      |> ScP.stream(Biquad.lowpass(rate, 1500))
      |> (fn enum -> Stream.concat(Envelope.saw(enum, rate, 0.02), Envelope.empty_stream(enum)) end).()

    Stream.zip(suboutput, clickoutput)
    |> Stream.map(fn {s, c} -> Ma.mul(Ma.add(s, c), 0.4) end)
  end

  defp openhat(rate, period_size), do: hihat(rate, period_size, 0.3)
  defp closehat(rate, period_size), do: hihat(rate, period_size, 0.1)

  defp hihat(rate, period_size, dur) do
    period_size
    |> ScP.stream(Noise.white())
    |> ScP.stream(Biquad.lowpass(rate, 6000, 1.2))
    |> ScP.stream(Biquad.highpass(rate, 2000, 1.2))
    |> Envelope.saw(rate, dur)
    |> Util.Stream.pan(0.5)
    |> Util.Stream.dur(0.5, rate)
    |> Granulix.Stream.play()
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