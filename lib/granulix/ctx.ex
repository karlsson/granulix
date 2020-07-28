defmodule Granulix.Ctx do
  alias __MODULE__
  
  defstruct [:api, :rate, :period_size]
  @type ctx() :: %Ctx{api: atom(), rate: Xalsa.rates(), period_size: pos_integer()} 

  @spec new() :: ctx()
  def new() do
    ctx = %Granulix.Ctx{api: Granulix.api(), rate: Granulix.rate(), period_size: Granulix.period_size()}
    put(ctx)
    ctx
  end

  def put(ctx = %__MODULE__{}) do
    :persistent_term.put(__MODULE__, ctx)
  end

  def get() do
    :persistent_term.get(__MODULE__)
  end
end
