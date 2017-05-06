defmodule KryptoBrain.Trading.OutputTablePrinter do
  alias KryptoBrain.Constants, as: C
  require KryptoBrain.Constants
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(%{}) do
    {:ok, %{}}
  end

  def update_state_of_trader(state_of_trader) do
    GenServer.cast(__MODULE__, {:update_state_of_trader, state_of_trader})
    state_of_trader
  end

  def handle_cast({:update_state_of_trader, state_of_trader}, state) do
    prediction_int_to_str = fn(prediction_int) ->
      case prediction_int do
        C._BUY -> "⬆️ BUY"
        C._HOLD -> "HOLD"
        C._SELL -> "⬇️ SELL"
      end
    end

    state_of_trader = Map.delete(state_of_trader, :python_bridge_pid)
                      |> Map.delete(:buy_orders)
                      |> Map.delete(:sell_orders)
                      |> Map.update!(:prediction, fn(prediction) -> prediction_int_to_str.(prediction) end)

    state = Map.put(state, state_of_trader[:alt_symbol], state_of_trader)

    print_status_table(state)

    {:noreply, state}
  end

  defp print_status_table(state) do
    headers = ["ALT balance", "ALT symbol", "BTC balance", "Prediction", "Last price"]
    rows = Enum.map(Map.values(state), &(Map.values(&1)))

    IO.puts("\n")
    TableRex.Table.new(rows, headers)
    |> TableRex.Table.put_column_meta(3, color: fn(text, value) ->
      case value do
        "⬆️ BUY" -> [:green, text]
        "HOLD" -> [:blue, text]
        "⬇️ SELL" -> [:red, text]
        _ -> text
      end
    end)
    |> TableRex.Table.render!
    |> IO.puts
  end
end
