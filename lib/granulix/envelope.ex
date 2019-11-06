defmodule Granulix.Envelope do
  alias Granulix.Math, as: Ma

  @moduledoc """
  Granulix envelopes - functions for creating envelopes and multiplying streams with them.

  Here is a simple example of use with own multiplier (envelope value * 0.4):
  ```elixir
     ctx = Granulix.Ctx.new()
     rate = ctx.rate
     fm = Lfo.sin(ctx, 4) |> Stream.map(&(&1 * 10 + 320))

     Granulix.Stream.new(%{Oscillator.triangle(rate) | frequency: fm})
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
    rate :: pos_integer(),
    duration :: float()) :: fs()
  def sin(enum, rate, duration) do
    sin_tuple(enum, rate, duration)
    |> Stream.map(fn {frames, mul} -> Ma.mul(frames, mul) end)
  end

  @doc """
  Same as sin/3 function but do not touch the frames. Instead it returns
  the frames and the envelope value in a tuple.
  """
  @spec sin_tuple(enum :: fs(),
    rate :: pos_integer(),
    duration :: float()) :: envelope_tuple()
  def sin_tuple(enum, rate, duration) do
    no_of_frames = round(duration * rate)
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

  @doc """
  Uses a line shaped envelope starting from 1 end ending with 0 to
  limit the frame array. The duration argument is in seconds.
  """
  @spec saw(enum :: fs(),
    rate :: pos_integer(),
    duration :: float()) :: fs()
  def saw(enum, rate, duration) do
    saw_tuple(enum, rate, duration)
    |> Stream.map(fn {frames, mul} -> Ma.mul(frames, mul) end)
  end

  @doc """
  Same as saw/3 function but do not touch the frames. Instead it returns
  the frames and the envelope value in a tuple.
  """
  @spec saw_tuple(enum :: fs(),
    rate :: pos_integer(),
    duration :: float()) :: envelope_tuple()
  def saw_tuple(enum, rate, duration) do
    no_of_frames = round(duration * rate)

    Stream.transform(enum, 0, fn frames, progress ->
      if progress < no_of_frames do
        x = 1.0 - progress / no_of_frames
        {[{frames, x}], progress + byte_size(frames) / 4}
      else
        {[{frames, 0.0}], progress}
      end
    end)
  end

end
