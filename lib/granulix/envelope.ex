defmodule Granulix.Envelope do
  alias Granulix.Math, as: Ma

  @moduledoc """
  Granulix envelopes - functions for creating envelopes and multiplying streams with them.

  Here is a simple example of use with own multiplier (envelope value * 0.4):
  ```elixir

  fm = Lfo.sin(4) |> Stream.map(&(&1 * 10 + 320))

  Granulix.Stream.new(Oscillator.triangle(fm))
  |> Envelope.sin_tuple(2.0)
  |> Stream.map(fn {frames, mul} -> Ma.mul(frames, mul * 0.4) end)
  ```
  Using the sin/3 instead and excluding the Stream.map/2 function is the
  same as just using mul * 1.0.
  """

  @type fs() :: Granulix.Stream.frames_stream()
  @type envelope_tuple() :: Enumerable.t()
  @type t() :: {Granulix.frames(), float}

  @doc """
  Uses a sine shaped mirrored S-form envelope to limit the frame array.
  The duration argument is in seconds.
  """
  @spec sin(enum :: fs(),
    duration :: float()) :: fs()
  def sin(enum,duration) do
    sin_tuple(enum, duration)
    |> Stream.map(fn {frames, mul} -> Ma.mul(frames, mul) end)
  end

  @doc """
  Same as sin/3 function but do not touch the frames. Instead it returns
  the frames and the envelope value in a tuple.
  """
  @spec sin_tuple(enum :: fs(),
    duration :: float()) :: envelope_tuple()
  def sin_tuple(enum, duration) do
    ctx = Granulix.Ctx.get()
    no_of_frames = round(duration * ctx.rate)
    twopi_by_nof = :math.pi() * 2 / no_of_frames

    Stream.transform(enum, 0, fn frames, progress ->
      if progress < no_of_frames do
        x = :math.cos(progress * twopi_by_nof) * -0.5 + 0.5
        {[{frames, x}], progress + byte_size(frames) / 4}
      else
        # {[{frames, 0.0}], progress}
        {:halt, progress}
      end
    end)
  end

  @doc """
  Uses a line shaped envelope starting from 1 end ending with 0 to
  limit the frame array. The duration argument is in seconds.
  """
  @spec saw(enum :: fs(),
    duration :: float()) :: fs()
  def saw(enum, duration) do
    saw_tuple(enum, duration)
    |> Stream.map(fn {frames, mul} -> Ma.mul(frames, mul) end)
  end
  @doc """
  Same as saw/3 function but do not touch the frames. Instead it returns
  the frames and the envelope value in a tuple.
  """
  @spec saw_tuple(enum :: fs(),
    duration :: float()) :: envelope_tuple()
  def saw_tuple(enum, duration) do
    line_tuple(enum, duration, 1.0, 0.0)
  end

  @spec line(enum :: fs(),
    duration :: float(),
    startv :: float(),
    endv:: float()) :: fs()
  def line(enum, duration, startv, endv) do
    line_tuple(enum, duration, startv, endv)
    |> Stream.map(fn {frames, mul} -> Ma.mul(frames, mul) end)
  end

  @spec line_tuple(enum :: fs(),
    duration :: float(),
    startv :: float(),
    endv:: float()) :: envelope_tuple()
  def line_tuple(enum, duration, startv, endv) do
    ctx = Granulix.Ctx.get()
    no_of_frames = round(duration * ctx.rate)

    Stream.transform(enum, 0, fn frames, progress ->
      if progress < no_of_frames do
        x = linev(startv, endv, progress, 0, no_of_frames)
        {[{frames, x}], progress + byte_size(frames) / 4}
      else
        # {[{frames, 0.0}], progress}
        {:halt, progress}
      end
    end)
  end

  defmodule ADSR do
    alias __MODULE__
    alias Granulix.Envelope, as: GE
    defstruct [
      attack: 0.0, attack_level: 1.0,
      decay: 0.0, decay_level: nil,
      sustain: 0.0, sustain_level: 1.0,
      release: 1.0]

    def new(enum, adsr = %ADSR{}) do
      tuple(enum, adsr)
      |> Stream.map(fn {frames, mul} -> Ma.mul(frames, mul) end)
    end

    def tuple(enum, adsr0 = %ADSR{decay_level: dl, sustain_level: sl}) do
      %Granulix.Ctx{rate: rate} = Granulix.Ctx.get()
      a = cond do
        dl == nil -> %{adsr0 | decay_level: sl}
        true -> adsr0
      end

      d_start = round(a.attack * rate)
      s_start = round(a.decay * rate) + d_start
      r_start = round(a.sustain * rate) + s_start
      r_end = round(a.release * rate) + r_start

      Stream.transform(enum, {0, sl}, fn frames, {progress0, level} ->
        {progress, rl} = cond do
          progress0 < r_start ->
            # If one receives :note_off, move to release phase and start
            # from current level
            receive do
              :note_off -> {r_start, level}
            after
              0 -> {progress0, a.sustain_level}
            end
          true ->
            {progress0, level}
        end

        y0 = cond do
          progress < d_start ->
            GE.linev(0.0, a.attack_level, progress, 0, d_start)
          progress < s_start ->
            GE.linev(a.attack_level, a.decay_level, progress, d_start, s_start)
          progress < r_start ->
            GE.linev(a.decay_level, a.sustain_level, progress, s_start, r_start)
          progress < r_end ->
            GE.linev(rl, 0.0, progress, r_start, r_end)
          true ->
            0.0
        end
        y = min(y0, 1.0)

        newlevel = cond do
          progress < r_start -> y
          true -> level
        end

        cond do
          progress < r_end -> {[{frames, y}], {round(progress + byte_size(frames) / 4), newlevel}}
          true -> {:halt, {progress, newlevel}}
        end
      end)
    end

  end

  def empty_stream(enum) do
    Stream.map(enum, fn frames -> Ma.mul(frames, 0.0) end)
  end

  def linev(_,endv,_,endx, endx) do
    endv
  end
  def linev(startv, endv, x, startx, endx) do
    startv + (endv - startv) * (x - startx) / (endx - startx)
  end

end
