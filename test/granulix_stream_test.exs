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
  alias SC.Reverb.{AnalogEcho, FreeVerb}
  alias SC.Filter.{Lag, LPF, HPF, LagUD}

  @docp """
  Setting up realtime scheduling policy SCHED_RR with
  chrt needs setup of group audio and user added to this:
  groupadd audio
  usermod -a -G audio yourUserID

  and in /etc/security/limits.d/audio.conf:
  @audio   -  rtprio     95
  @audio   -  memlock    unlimited
  """

  def ma(enum, m, a) do
    Stream.map(enum, fn
      frames when is_list(frames) -> Ma.add(Ma.mul(frames, m), a)
      frames when is_binary(frames) -> Ma.add(Ma.mul(frames, m), a)
      val -> val * m + a
    end)
  end

  def m(enum, m) do
    Stream.map(enum, fn
      frames when is_list(frames) -> Ma.mul(frames, m)
      frames when is_binary(frames) -> Ma.mul(frames, m)
      val -> val * m
    end)
  end

  setup do
    ctx = Granulix.Ctx.new()
    sc_ctx = %SC.Ctx{rate: ctx.rate, period_size: ctx.period_size}
    SC.Ctx.put(sc_ctx)
    [ctx: ctx]
  end

  # Some code translated from Bartetzki Supercollider grains example 3
  # https://www.bartetzki.de/docs/kita_sc08/examples_5_(grains+tasks).rtf
  test "example 3 again dense random texture with streams", _context do
    :timer.sleep(200)
    dur = 0.2
    vol = 0.1
    time0 = PlayTime.wait(%MsTime{}, 0.5)

    for x <- 1..500 do
      freq = Enum.random(1000..7000)
      next = PlayTime.wait(time0, x * dur * Enum.random(10..40) / 800)
      # next = 0.005
      pos = Enum.random(-100..100) / 100

      spawn(fn ->
        timeout = PlayTime.timeout(next)
        :timer.sleep(timeout)
        Osc.Stream.sin(freq)
        |> Envelope.saw_tuple(dur)
        |> Stream.map(fn {frames, mul} -> Ma.mul(frames, mul * vol) end)
        |> Util.Stream.pan(pos)
        |> Granulix.Stream.play()
      end)
    end

    :timer.sleep(8000)
    log_max_gauges()
  end

  test "kickdrum with streams", _context do
    pos = 0.0
    time0 = PlayTime.wait(%MsTime{}, 0.5)

    for x <- 1..12, y <- [0, 1, 3] do
      :timer.sleep(5)
      nexttime = PlayTime.wait(time0, x * 0.75 + y * 0.125)
      spawn(fn ->
        stream =
          sfullkickdrum()
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

  test "stream test sinus", _context do
    fm = Lfo.triangle(4) |> Lfo.nma(40, 420)
    # You can have a stream as modulating frequency input for osc
    Osc.Stream.sin(fm)
    |> Util.Stream.pan(0.0)
    |> Util.Stream.dur(5.0)
    |> Granulix.Stream.play()

    log_max_gauges()
  end

  test "stream test saw", context do
    gctx = context[:ctx]
    no_of_frames = gctx.period_size

    Lfo.sin(4) |> Lfo.nma(40,200) # 200 <-> 240, 4 Hz
    |> Stream.map(fn freq ->
      SC.Plugin.next(no_of_frames,
        Osc.saw(freq))
    end)
    |> m(0.3)
    |> Util.Stream.pan(0.0)
    |> Util.Stream.dur(5)
    |> Granulix.Stream.play()

    log_max_gauges()
  end

  test "stream test triangle", _context do
    Lfo.sin(4) |> Lfo.nma(20,300) # Between 300 and 320 at 4 Hz
    |> Osc.Stream.triangle()
    |> Envelope.sin_tuple(2.0)
    |> Stream.map(fn {frames, mul} -> Ma.mul(frames, mul * 0.4) end)
    |> Util.Stream.dur(2.0)
    |> AnalogEcho.ns(0.3)
    # |> Stream.zip(Lfo.sin(1.5))
    # |> Stream.map(fn {frames, panning} -> Granulix.Util.pan(frames, panning) end)
    |> Util.Stream.pan(Lfo.sin(1.5))
    |> Granulix.Stream.play()

    log_max_gauges()
  end

  test "stream test lowpass", _context do
    fm = Lfo.triangle(0.25) |> Lfo.nma(400, 120)
    # You can have a stream as modulating frequency input for osc
    Osc.Stream.sin(fm)
    # |> ScP.stream(Biquad.lowpass(320, 2.0))
    |> LPF.ns(420.0)
    |> Util.Stream.pan(0.0)
    |> Util.Stream.dur(5.0)
    |> Granulix.Stream.play()

    log_max_gauges()
  end

  test "stream test highpass", _context do
    fm = Lfo.triangle(0.25) |> Lfo.nma(400,120)
    # You can have a stream as modulating frequency input for osc
    Osc.Stream.sin(fm)
    # |> Stream.map(fn frames -> Ma.mul(frames, 0.4) end)
    # |> ScP.stream(Biquad.highpass(320, 10))
    |> HPF.ns(320.0)
    |> Util.Stream.pan(0.0)
    |> Util.Stream.dur(5.0)
    |> Granulix.Stream.play()

    log_max_gauges()
  end

  test "Hi Hat", _context do
    spawn(fn ->
      openhat()
      closehat()
    end)
    :timer.sleep(1000)
    log_max_gauges()
  end

  test "Moog test", _context do
    streamf = fn(freq) ->
      Lfo.triangle(5.0) |> ma(5, freq)
      # You can have a stream as modulating frequency input for osc
      |> Osc.Stream.sin()
      |> Granulix.Filter.Moog.ns(0.1, 3.2)
      |> Util.Stream.pan(Lfo.triangle(1.0) |> ma(0.8, 0))
      |> Granulix.Stream.out()
     end
    a = streamf.(freq(:A))
    c = streamf.(freq(:C))
    a |> Util.Stream.dur(1.4) |> Stream.run()
    c |> Util.Stream.dur(2.4) |> Stream.run()
    a |> Util.Stream.dur(1.4) |> Stream.run()
    log_max_gauges()
  end

  test "Bitcrusher", _context do
    Osc.Stream.sin(440)
    |> ScP.stream(Bitcrusher.new(4, 0.5))
    |> Util.Stream.dur(1.5) |> Util.Stream.pan(0.0)
    |> Granulix.Stream.play()

    bc = Bitcrusher.new(4, 0.7)
    Osc.Stream.sin(440)
    # Let the bitcrusher bits go from 8 to 1 during 6 seconds
    |> Envelope.saw_tuple(6.0)
    |> Stream.map(fn {enum, envelope} ->
      ScP.next(enum, %{bc | bits: (1 + envelope*7)})
      end)
    |> Util.Stream.dur(7.0) |> Util.Stream.pan(0.0)
    |> Granulix.Stream.play()
  end

  test "Lag filter", _context do
    # Ramp lagtime from 0 to 1 during 5s
    lagtime = Lfo.saw(1/5) |> Lfo.nma(-1,1)
    Lfo.square(1) |> Lfo.nma(50, 425)
    |> Lag.ns(lagtime)
    # You can have a stream as modulating frequency input for osc
    |> Osc.Stream.sin()
    |> Util.Stream.pan(0.0)
    |> Util.Stream.dur(5.0)
    |> Granulix.Stream.play()

    log_max_gauges()
  end

  test "Lag filter 2", _context do
    stream = fn freq, pan->
      Util.Stream.setter(:freq, freq)
      |> Lag.ns(2.0)
      |> Osc.Stream.sin()
      |> m(0.4)
      |> Util.Stream.pan(pan)
      |> FreeVerb.ns2(0.6, 0.8, 0.2)
      |> Granulix.Stream.play()
    end
    pid1 = spawn(fn -> stream.(320, 0.5) end)
    pid2 = spawn(fn -> stream.(400, Lfo.sin(1.5)) end)
    :timer.sleep(2000)
    Util.Stream.set(pid1, :freq, 475)
    :timer.sleep(1000)
    Util.Stream.set(pid2, :freq, 220)
    :timer.sleep(3000)
    Util.Stream.set(pid1, :freq, :halt)
    :timer.sleep(1000)
    Util.Stream.set(pid2, :freq, :halt)
    log_max_gauges()
  end

  test "LagUD filter", _context do
    # value,duration stream
    vd = fn freq, dur -> Util.Stream.value(freq) |> Util.Stream.dur(dur) end
    Stream.concat([vd.(300,2), vd.(500,4), vd.(100,5)])
    |> LagUD.ns(1.0, 5.0) # 1s lag for rising values and 5s lag for decreasing
    |> Osc.Stream.sin()
    |> Util.Stream.pan(Lfo.sin(1/3))
    |> Granulix.Stream.play()

    log_max_gauges()
  end

  # test "Multicard", _context do
  #   panning = fn(c1, c2, c3, c4) ->
  #     Osc.Stream.sin(440))
  #     |> Util.Stream.dur(3.0)
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
  defp sfullkickdrum() do
    freq = :rand.uniform() * 4.0 + 98

    suboutput =
      Osc.Stream.sin(freq)
      |> ADSR.new(%ADSR{decay: 0.2, sustain: 1, sustain_level: 0.5, release: 1.0})

    clickoutput =
      ScP.stream(Noise.white())
      |> ScP.stream(Biquad.lowpass(1500))
      # |> LPF.ns(1500)
      |> (fn enum -> Stream.concat(Envelope.saw(enum, 0.02), Envelope.empty_stream(enum)) end).()

    Stream.zip(suboutput, clickoutput)
    |> Stream.map(fn {s, c} -> Ma.mul(Ma.add(s, c), 0.4) end)
  end

  defp openhat(), do: hihat(0.3)
  defp closehat(), do: hihat(0.1)

  defp hihat(dur) do
    ScP.stream(Noise.white())
    # |> ScP.stream(Biquad.lowpass(6000, 1.2))
    # |> ScP.stream(Biquad.highpass(2000, 1.2))
    |> LPF.ns(6000)
    |> HPF.ns(2000)
    |> Envelope.saw(dur)
    |> Util.Stream.pan(0.0)
    |> Util.Stream.dur(0.5)
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
