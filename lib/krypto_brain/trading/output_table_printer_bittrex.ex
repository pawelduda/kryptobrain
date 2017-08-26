defmodule KryptoBrain.Trading.OutputTablePrinterBittrex do
  alias KryptoBrain.Constants, as: C
  require KryptoBrain.Constants
  use GenServer

  @headers [
    "Market name",
    "Signal",
    "Retrieval date GMT",
    "Daily volume (BTC)",
    "Last upper BBAND",
    "Last price",
    "Last lower BBAND",
    "Last STOCH RSI K"
  ]

  def start_link do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(%{}) do
    {:ok, %{}}
  end

  def update_state_of_trader(buy_signals, sell_signals) do
    GenServer.cast(__MODULE__, {:update_state_of_trader, buy_signals, sell_signals})
  end

  def handle_cast({:update_state_of_trader, buy_signals, sell_signals}, state) do
    # TODO: refactor code smell
    buy_signals = Enum.map(buy_signals, &(
      [
        market_name: &1[:market_name],
        signal: signal_int_to_str(&1[:signal_data].signal),
        retrieval_date_gmt: &1[:signal_data].retrieval_date_gmt,
        daily_volume: &1[:daily_volume],
        last_upper_bband: format_price_as_satoshis(&1[:signal_data].last_upper_bband),
        last_price: format_price_as_satoshis(&1[:signal_data].last_price),
        last_lower_bband: format_price_as_satoshis(&1[:signal_data].last_lower_bband),
        last_stoch_rsi_k: &1[:signal_data].last_stoch_rsi_k
      ]
    ))
    sell_signals = Enum.map(sell_signals, &(
      [
        market_name: &1[:market_name],
        signal: signal_int_to_str(&1[:signal_data].signal),
        retrieval_date_gmt: &1[:signal_data].retrieval_date_gmt,
        daily_volume: &1[:daily_volume],
        last_upper_bband: format_price_as_satoshis(&1[:signal_data].last_upper_bband),
        last_price: format_price_as_satoshis(&1[:signal_data].last_price),
        last_lower_bband: format_price_as_satoshis(&1[:signal_data].last_lower_bband),
        last_stoch_rsi_k: &1[:signal_data].last_stoch_rsi_k
      ]
    ))

    print_status_table(buy_signals, sell_signals)

    {:noreply, state}
  end

  defp print_status_table(buy_signals, sell_signals) do
    buy_signals_values = Enum.map(buy_signals, &Keyword.values/1)
    sell_signals_values = Enum.map(sell_signals, &Keyword.values/1)
    rows = Enum.concat(buy_signals_values, sell_signals_values)

    IO.puts("\n")
    TableRex.Table.new(rows, @headers)
    |> TableRex.Table.put_column_meta(1, color: fn(text, value) ->
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

  defp signal_int_to_str(signal_int) do
    case signal_int do
      C._BUY -> "⬆️ BUY"
      C._HOLD -> "HOLD"
      C._SELL -> "⬇️ SELL"
    end
  end

  defp format_price_as_satoshis(float_price) do
    :erlang.float_to_binary(float_price, [decimals: 8])
  end
end
