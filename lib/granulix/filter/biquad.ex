defmodule Granulix.Filter.Biquad do
  # Code from - Synthex.Filter.Biquad:
  #  https://github.com/bitgamma/synthex/blob/master/lib/synthex/filter/biquad.ex
  #  transposed to use Erlang NIF library.

  alias __MODULE__

  @twopi :math.pi() * 2

  defstruct [:ref, coefficients: {1.0, 0.0, 0.0, 1.0, 0.0, 0.0}]

  # -----------------------------------------------------------
  @on_load :load_nifs

  @doc false
  def load_nifs do
    case :erlang.load_nif(:code.priv_dir(:granulix) ++ '/granulix_biquad', 0) do
      :ok -> :ok
      {:error, {:reload, _}} -> :ok
      {:error, reason} ->
        :logger.warning('Failed to load granulix_biquad NIF: ~p',[reason])
    end
  end

  @doc false
  def biquad_ctor() do
    raise "NIF biquad_ctor/0 not loaded"
  end

  @doc false
  def biquad_next(_ref, _frames, _coeff) do
    raise "NIF biquad_next/3 not loaded"
  end

  # -----------------------------------------------------------

  defp get_a(db_gain), do: :math.pow(10, db_gain / 40)

  defp get_w0(rate, freq) do
    w0 = @twopi * (freq / rate)
    cos_w0 = :math.cos(w0)
    sin_w0 = :math.sin(w0)

    {w0, cos_w0, sin_w0}
  end

  defp get_alpha(:q, _w0, sin_w0, q, _), do: sin_w0 / (2 * q)

  defp get_alpha(:bandwidth, w0, sin_w0, bw, _),
    do: sin_w0 * :math.sinh(:math.log(2) / 2 * bw * (w0 / sin_w0))

  defp get_alpha(:slope, _w0, sin_w0, s, a),
    do: sin_w0 / 2 * :math.sqrt((a + 1 / a) * (1 / s - 1) + 2)

  def lowpass(rate, freq, q \\ 1.0) do
    {w0, cos_w0, sin_w0} = get_w0(rate, freq)
    alpha = get_alpha(:q, w0, sin_w0, q, :none)

    a0 = 1 + alpha
    a1 = -2 * cos_w0
    a2 = 1 - alpha
    b1 = 1 - cos_w0
    b0 = b2 = b1 / 2

    %Biquad{ref: Biquad.biquad_ctor(), coefficients: {a0, a1, a2, b0, b1, b2}}
  end

  def highpass(rate, freq, q \\ 1.0) do
    {w0, cos_w0, sin_w0} = get_w0(rate, freq)
    alpha = get_alpha(:q, w0, sin_w0, q, :none)
    one_plus_cos_w0 = 1 + cos_w0

    a0 = 1 + alpha
    a1 = -2 * cos_w0
    a2 = 1 - alpha
    b0 = b2 = one_plus_cos_w0 / 2
    b1 = -one_plus_cos_w0

    %Biquad{ref: Biquad.biquad_ctor(), coefficients: {a0, a1, a2, b0, b1, b2}}
  end

  def bandpass_skirt(rate, freq, {type, q_or_bw} \\ {:q, 1.0}) do
    {w0, cos_w0, sin_w0} = get_w0(rate, freq)
    alpha = get_alpha(type, w0, sin_w0, q_or_bw, :none)
    half_sin_w0 = sin_w0 / 2

    a0 = 1 + alpha
    a1 = -2 * cos_w0
    a2 = 1 - alpha
    b0 = half_sin_w0
    b1 = 0.0
    b2 = -half_sin_w0

    %Biquad{ref: Biquad.biquad_ctor(), coefficients: {a0, a1, a2, b0, b1, b2}}
  end

  def bandpass_peak(rate, freq, {type, q_or_bw} \\ {:q, 1.0}) do
    {w0, cos_w0, sin_w0} = get_w0(rate, freq)
    alpha = get_alpha(type, w0, sin_w0, q_or_bw, :none)

    a0 = 1 + alpha
    a1 = -2 * cos_w0
    a2 = 1 - alpha
    b0 = alpha
    b1 = 0.0
    b2 = -alpha

    %Biquad{ref: Biquad.biquad_ctor(), coefficients: {a0, a1, a2, b0, b1, b2}}
  end

  def notch(rate, freq, {type, q_or_bw} \\ {:q, 1.0}) do
    {w0, cos_w0, sin_w0} = get_w0(rate, freq)
    alpha = get_alpha(type, w0, sin_w0, q_or_bw, :none)

    a0 = 1 + alpha
    a1 = b1 = -2 * cos_w0
    a2 = 1 - alpha
    b0 = b2 = 1.0

    %Biquad{ref: Biquad.biquad_ctor(), coefficients: {a0, a1, a2, b0, b1, b2}}
  end

  def allpass(rate, freq, q \\ 1.0) do
    {w0, cos_w0, sin_w0} = get_w0(rate, freq)
    alpha = get_alpha(:q, w0, sin_w0, q, :none)

    a0 = b2 = 1 + alpha
    a1 = b1 = -2 * cos_w0
    a2 = b0 = 1 - alpha

    %Biquad{ref: Biquad.biquad_ctor(), coefficients: {a0, a1, a2, b0, b1, b2}}
  end

  def peaking_eq(rate, freq, db_gain, {type, q_or_bw} \\ {:q, 1.0}) do
    a = get_a(db_gain)
    {w0, cos_w0, sin_w0} = get_w0(rate, freq)
    alpha = get_alpha(type, w0, sin_w0, q_or_bw, :none)
    alpha_on_a = alpha / a
    a_times_alpha = alpha * a

    a0 = 1 + alpha_on_a
    a1 = b1 = -2 * cos_w0
    a2 = 1 - alpha_on_a
    b0 = 1 + a_times_alpha
    b2 = 1 - a_times_alpha

    %Biquad{ref: Biquad.biquad_ctor(), coefficients: {a0, a1, a2, b0, b1, b2}}
  end

  def lowshelf(rate, freq, db_gain, {type, q_or_slope} \\ {:q, 1.0}) do
    a = get_a(db_gain)
    {w0, cos_w0, sin_w0} = get_w0(rate, freq)
    alpha = get_alpha(type, w0, sin_w0, q_or_slope, a)
    ap1 = a + 1
    am1 = a - 1
    ap1_cos_w0 = ap1 * cos_w0
    am1_cos_w0 = am1 * cos_w0
    beta = 2 * :math.sqrt(a) * alpha

    a0 = ap1 + am1_cos_w0 + beta
    a1 = -2 * (am1 + ap1_cos_w0)
    a2 = ap1 + am1_cos_w0 - beta
    b0 = a * (ap1 - am1_cos_w0 + beta)
    b1 = 2 * a * (am1 - ap1_cos_w0)
    b2 = a * (ap1 - am1_cos_w0 - beta)

    %Biquad{ref: Biquad.biquad_ctor(), coefficients: {a0, a1, a2, b0, b1, b2}}
  end

  def highshelf(rate, freq, db_gain, {type, q_or_slope} \\ {:q, 1.0}) do
    a = get_a(db_gain)
    {w0, cos_w0, sin_w0} = get_w0(rate, freq)
    alpha = get_alpha(type, w0, sin_w0, q_or_slope, a)
    ap1 = a + 1
    am1 = a - 1
    ap1_cos_w0 = ap1 * cos_w0
    am1_cos_w0 = am1 * cos_w0
    beta = 2 * :math.sqrt(a) * alpha

    a0 = ap1 - am1_cos_w0 + beta
    a1 = 2 * (am1 - ap1_cos_w0)
    a2 = ap1 - am1_cos_w0 - beta
    b0 = a * (ap1 + am1_cos_w0 + beta)
    b1 = -2 * a * (am1 + ap1_cos_w0)
    b2 = a * (ap1 + am1_cos_w0 - beta)

    %Biquad{ref: Biquad.biquad_ctor(), coefficients: {a0, a1, a2, b0, b1, b2}}
  end

  def stream(enum, %Biquad{ref: ref, coefficients: cf}) do
    Stream.map(
      enum,
      fn frames ->
        Biquad.biquad_next(ref, frames, cf)
      end
    )
  end
end

# -----------------------------------------------------------
defimpl Granulix.Transformer, for: Granulix.Filter.Biquad do
  def next(%Granulix.Filter.Biquad{ref: ref, coefficients: cf}, frames) do
    Granulix.Filter.Biquad.biquad_next(ref, frames, cf)
  end

  def stream(%Granulix.Filter.Biquad{ref: ref, coefficients: cf}, enum) do
    Stream.map(
      enum,
      fn frames -> Granulix.Filter.Biquad.biquad_next(ref, frames, cf) end
    )
  end
end
