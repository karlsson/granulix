defmodule GranulixTest do
  use ExUnit.Case
  # doctest Granulix
  alias Granulix.Math, as: Ma
  alias Granulix.Time.{MsTime, PlayTime}
  alias Granulix.Generator.Oscillator, as: Osc
  alias Granulix.Generator.Noise
  alias SC.Plugin, as: ScP
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
        :timer.sleep(x*2)
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
      :timer.sleep(10)
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
    ScP.next(no_of_frames, Noise.white())
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
