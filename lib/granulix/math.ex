defmodule Granulix.Math do
  @on_load :load_nifs

  @pi :math.pi()
  @doc "A useful number"
  @spec pi() :: float()
  def pi(), do: @pi

  @twopi @pi * 2
  @doc "A useful number times two"
  @spec twopi() :: float()
  def twopi(), do: @twopi

  @pi2 @pi * 0.5
  @doc "A useful number times 0.5"
  @spec pi2() :: float()
  def pi2(), do: @pi2

  @rtwopi 1.0 / @twopi
  @doc "1 / twopi()"
  @spec rtwopi() :: float()
  def rtwopi(), do: @rtwopi

  @doc """
  Multiply binary arrays of 32 bit floats with
  a scalar value or binary array
  """
  @spec mul(binary() | [binary()], binary() | float()) :: binary()
  def mul(l, y) when is_list(l), do: Enum.map(l, fn x -> mul(x, y) end)
  def mul(x, y) when is_binary(y), do: crossnif(x, y)
  def mul(x, y), do: mulnif(x, y)

  @doc "Add binary arrays of 32 bit floats with binary array"
  @spec add(binary() | [binary()], binary()) :: binary()
  def add(l, y) when is_list(l), do: Enum.map(l, fn x -> add(x, y) end)
  def add(x, y) when is_binary(x), do: addnif(x, y)

  @doc "Subtract binary arrays of 32 bit floats with binary array"
  @spec subtract(binary() | [binary()], binary()) :: binary()
  def subtract(l, y) when is_list(l), do: Enum.map(l, fn x -> subtract(x, y) end)
  def subtract(x, y) when is_binary(x), do: subtractnif(x, y)

  # -----------------------------------------------------------
  def load_nifs do
    :erlang.load_nif('./priv/granulix_math', 0)
  end

  @spec mulnif(binary(), binary() | float()) :: binary()
  defp mulnif(_x, _y) do
    raise "NIF mul/2 not loaded"
  end

  # @doc "Multiply 2 binary arrays of 32 bit floats"
  @spec crossnif(binary(), binary()) :: binary()
  defp crossnif(_x, _y) do
    raise "NIF cross/2 not loaded"
  end

  @doc "Multiply 2 binary arrays of 32 bit floats"
  @spec simdcross(binary(), binary()) :: binary()
  def simdcross(_x, _y) do
    raise "NIF simdcross/2 not loaded"
  end

  @spec addnif(binary(), binary()) :: binary()
  defp addnif(_x, _y) do
    raise "NIF add/2 not loaded"
  end

  @spec subtractnif(binary(), binary()) :: binary()
  defp subtractnif(_x, _y) do
    raise "NIF subtract/2 not loaded"
  end

  @doc "Convert a list of (Erlang) floats to a binary of 32 bit (C) floats"
  @spec float_list_to_binary([float()]) :: binary()
  def float_list_to_binary(_fl) do
    raise "NIF float_list_to_binary/1 not loaded"
  end

  @doc "Convert a binary of 32 bit (C) floats to a list of (Erlang) floats"
  @spec binary_to_float_list(binary) :: [float()]
  def binary_to_float_list(_bin) do
    raise "NIF binary_to_float_list/1 not loaded"
  end

  # -----------------------------------------------------------
end
