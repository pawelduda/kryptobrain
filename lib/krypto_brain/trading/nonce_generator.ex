# DEPRECATED

defmodule KryptoBrain.Trading.NonceGenerator do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    {:ok, :os.system_time(:nanosecond)}
  end

  def get_nonce do
    GenServer.call(__MODULE__, :get_nonce)
  end

  def handle_call(:get_nonce, _from, current_nonce) do
    new_nonce = current_nonce + 1
    {:reply, new_nonce, new_nonce}
  end
end
