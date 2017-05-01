# DEPRECATED

defmodule KryptoBrain.Trading.StateHolder do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    :ets.new(:trading_state_holder, [:set, :public, :named_table])
    {:ok, nil}
  end
end
