defmodule KryptoBrain.Trading.BittrexTrader do
  alias KryptoBrain.Constants, as: C
  alias KryptoBrain.Trading.BittrexApi
  require Logger

  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    {:ok, python_bridge_pid} =
      GenServer.start_link(KryptoBrain.Bridge.KryptoJanusz, [], name: KryptoBrain.Bridge.KryptoJanusz)

    state = %{
      balances: [],
      open_orders: [],
      python_bridge_pid: python_bridge_pid
    }

    Logger.info(fn -> "[Bittrex] Trader started with initial state." end)

    schedule_work()

    {:ok, state}
  end

  defp schedule_work do
    Process.send_after(self(), :start_trading, Enum.random(1..5) * 1_000)
  end

  def handle_info(:start_trading, state) do
    update_state(state) |> trade_loop
    {:noreply, state}
  end

  def update_state(state) do
    state
    |> update_balances()
    |> update_open_orders()
  end

  defp update_balances(state) do
    balances =
      BittrexApi.get_balances()
      |> Enum.map(&Map.take(&1, ["Available", "Currency"]))
      |> Enum.reject(fn(balance) -> balance["Available"] == 0.0 end)

    state |> Map.update!(:balances, fn(_) -> balances end)
  end

  def update_open_orders(state) do
    open_orders = BittrexApi.get_open_orders()
    state |> Map.update!(:open_orders, fn(_) -> open_orders end)
  end

  defp trade_loop(state) do
    state
  end
end
