defmodule SC.Ctx do
  defstruct [:rate, :period_size]

  def put(ctx = %__MODULE__{}) do
    :persistent_term.put(__MODULE__, ctx)
  end

  def get() do
    :persistent_term.get(__MODULE__)
  end
end
