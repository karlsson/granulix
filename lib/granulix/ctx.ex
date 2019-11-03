defmodule Granulix.Ctx do
  alias __MODULE__
  
  defstruct [:api, :rate, :period_size]
  @type ctx() :: %Ctx{api: atom(), rate: Xalsa.rates(), period_size: pos_integer()} 

  @spec new() :: ctx()
  def new() do
    %Granulix.Ctx{api: Granulix.api(), rate: Granulix.rate(), period_size: Granulix.period_size()}
  end
end
