# Problems with current implementation:
# - Kinda high memory/CPU usage with multiple workers (probably due to multiple Python instances)

# CURRENT FOCUS:
# - Need a more recent information on the current datasample. Currently it might be delayed even by 5-10 mins.
# Last time I checked, returnChartData endpoint is usually delayed by 2.5 mins

# PARTIALLY RESOLVED:
# - Orders are not always filled in, especially when not a lot of people seem to be trading certain altcoin.
# Fixed by relying on lowest ask or highest bid.

defmodule KryptoBrain.Trading.Trader do
  alias KryptoBrain.Constants, as: C
  alias KryptoBrain.Trading.PoloniexApi
  require KryptoBrain.Constants
  require Logger
  use GenServer

  def start_link(alt_symbol, currency_owned \\ C._BTC) do
    GenServer.start_link(__MODULE__, [alt_symbol], name: String.to_atom("#{alt_symbol}_trader"))
  end

  def init([alt_symbol]) do
    {:ok, python_bridge_pid} =
      GenServer.start_link(KryptoBrain.Bridge.KryptoJanusz, [], name: String.to_atom("#{alt_symbol}_python_bridge"))

    state = %{
      python_bridge_pid: python_bridge_pid,
      alt_symbol: alt_symbol,
      btc_balance: nil,
      alt_balance: nil,
      suggested_trade_price: nil,
      prediction: nil,
      buy_orders: [],
      sell_orders: []
      # currency_owned: currency_owned
    }

    Logger.info(fn -> "[#{alt_symbol}] Trader started with initial state." end)

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

  defp update_state(state) do
    state
    |> update_balances()
    |> update_suggested_trade_price()
    |> update_open_orders()
    |> update_prediction()
    |> print_status_message()
  end

  defp update_balances(%{alt_symbol: alt_symbol} = state) do
    refresh_balances_response = PoloniexApi.get_balances(alt_symbol)

    case refresh_balances_response do
      %{"error" => error} -> raise error
      _ -> nil
    end

    {btc_balance, ""} = refresh_balances_response[C._BTC] |> Float.parse
    {alt_balance, ""} = refresh_balances_response[alt_symbol] |> Float.parse

    state
    |> Map.update!(:btc_balance, fn(_) -> btc_balance end)
    |> Map.update!(:alt_balance, fn(_) -> alt_balance end)
  end

  defp update_suggested_trade_price(%{alt_symbol: alt_symbol} = state) do
    ticker_data_response =
      PoloniexApi.get_ticker_data
      |> Enum.find(fn(currency_data) -> elem(currency_data, 0) === "BTC_#{alt_symbol}" end)
      |> elem(1)

    {last, ""} = Map.fetch!(ticker_data_response, "last") |> Float.parse

    state |> Map.update!(:suggested_trade_price, fn(_) -> last end)
  end

  defp update_open_orders(%{alt_symbol: alt_symbol} = state) do
    orders = PoloniexApi.get_open_orders(alt_symbol)

    buy_orders = Enum.filter(orders, fn(order) -> order["type"] == "buy" end)
    sell_orders = Enum.filter(orders, fn(order) -> order["type"] == "sell" end)

    state
    |> Map.update!(:buy_orders, fn(_) -> buy_orders end)
    |> Map.update!(:sell_orders, fn(_) -> sell_orders end)
  end

  defp update_prediction(%{python_bridge_pid: python_bridge_pid, alt_symbol: alt_symbol} = state) do
    state |> Map.update!(:prediction, fn(_) -> get_prediction(python_bridge_pid, alt_symbol) end)
  end

  defp print_status_message(%{prediction: prediction, alt_symbol: alt_symbol} = state) do
    prediction_str = case prediction do
      C._BUY -> "#{IO.ANSI.green}⬆️ BUY"
      C._HOLD -> "#{IO.ANSI.blue}HOLD"
      C._SELL -> "#{IO.ANSI.red}⬇️ SELL"
    end

    # For now we do not print anything if the prediction is hold as it does not bring too much to the table
    # case state[:prediction] do
      # prediction when prediction in [C._BUY, C._SELL] ->
        Logger.debug(fn -> "[#{alt_symbol}] #{inspect(state)}" end)
        Logger.info(fn -> "[#{alt_symbol}] Predicted action: #{prediction_str}" end)
      # _ ->
        # nil
    # end

    state
  end

  defp trade_loop(state) do
    state = state
            |> update_state()
            |> act_upon_prediction()

    :timer.sleep(1_000)

    trade_loop(state)
  end

  defp act_upon_prediction(state) do
    %{
      alt_symbol: alt_symbol,
      btc_balance: btc_balance,
      alt_balance: alt_balance,
      suggested_trade_price: suggested_trade_price,
      prediction: prediction,
      buy_orders: buy_orders,
      sell_orders: sell_orders
    } = state

    case prediction do
      C._BUY ->
        if outdated_open_orders?(buy_orders, suggested_trade_price) do
          Logger.info(fn -> "[#{alt_symbol}] Got outdated open buy orders, cancelling..." end)
          cancel_orders(buy_orders, alt_symbol)
          # We are not doing anything else here so that loop repeats and we get updated balances
        end

        if !Enum.empty?(sell_orders) do
          Logger.info(fn -> "[#{alt_symbol}] Got open sell orders, cancelling..." end)
          cancel_orders(sell_orders, alt_symbol)
        end

        if btc_balance >= 0.0001 do
          Logger.info(fn -> "[#{alt_symbol}] Got some BTC balance, placing buy order..." end)
          place_buy_order(suggested_trade_price, btc_balance, alt_symbol)
        end
      C._HOLD ->
        if !Enum.empty?(buy_orders) || !Enum.empty?(sell_orders) do
          Logger.info(fn -> "[#{alt_symbol}] Got open buy/sell orders and the prediciton is to hold, cancelling..." end)
          cancel_orders(buy_orders ++ sell_orders, alt_symbol)
        end
      C._SELL ->
        if outdated_open_orders?(sell_orders, suggested_trade_price) do
          Logger.info(fn -> "[#{alt_symbol}] Found outdated open sell orders, cancelling..." end)
          cancel_orders(sell_orders, alt_symbol)
          # We are not doing anything else here so that loop repeats and we get updated balances
        end

        if !Enum.empty?(buy_orders) do
          Logger.info(fn -> "[#{alt_symbol}] Got open buy orders, cancelling..." end)
          cancel_orders(buy_orders, alt_symbol)
        end

        if alt_balance >= 0.0001 do
          Logger.info(fn -> "[#{alt_symbol}] Got some ALT balance, placing sell order..." end)
          place_sell_order(suggested_trade_price, alt_balance, alt_symbol)
        end
    end

    state
  end

  defp outdated_open_orders?(open_orders, suggested_trade_price) do
    Enum.any?(open_orders, fn(open_order) ->
      {rate, ""} = Float.parse(open_order["rate"])
      rate != suggested_trade_price
    end)
  end

  defp place_buy_order(suggested_trade_price, btc_balance, alt_symbol) do
    place_buy_order_response = PoloniexApi.place_buy_order(suggested_trade_price, btc_balance, alt_symbol)
    Logger.info(fn -> "[#{alt_symbol}] #{inspect(place_buy_order_response)}" end)

    case place_buy_order_response do
      %{"orderNumber" => _order_number, "resultingTrades" => _trades} ->
        Logger.info(fn -> "[#{alt_symbol}] Placed buy order." end)
      %{"error" => "Unable to fill order completely."} ->
        Logger.warn(fn -> "[#{alt_symbol}] Attempted to buy but could not fill the order." end)
    end
  end

  defp place_sell_order(suggested_trade_price, alt_balance, alt_symbol) do
    place_sell_order_response = PoloniexApi.place_sell_order(suggested_trade_price, alt_balance, alt_symbol)
    Logger.info(fn -> "[#{alt_symbol}] #{inspect(place_sell_order_response)}" end)

    case place_sell_order_response do
      %{"orderNumber" => _order_number, "resultingTrades" => _trades} ->
        Logger.info(fn -> "[#{alt_symbol}] Placed sell order." end)
      %{"error" => "Unable to fill order completely."} ->
        Logger.warn(fn -> "[#{alt_symbol}] Attempted to sell but could not fill the order" end)
      %{"error" => "Total must be at least 0.0001."} ->
        Logger.error(fn -> "[#{alt_symbol}] Total must be at least 0.0001." end)
    end
  end

  defp cancel_orders(orders, alt_symbol) do
    Enum.each orders, fn(order) ->
      %{"success" => 1} = PoloniexApi.cancel_order(order, alt_symbol)
      Logger.info(fn -> "[#{alt_symbol}] Order #{order["orderNumber"]} cancelled." end)
    end

    true
  end

  defp get_prediction(python_bridge_pid, alt_symbol) do
    {prediction, timestamp_delta} = GenServer.call(python_bridge_pid, {:most_recent_prediction, alt_symbol}, 15_000)

    # If the prediction comes from a dataset that is older than X seconds, discard it
    if timestamp_delta <= 120 do
      Logger.info(fn -> "[#{alt_symbol}] Prediction is fresh enough, keeping it." end)
      prediction
    else
      Logger.warn(fn -> "[#{alt_symbol}] Prediction outdated by #{timestamp_delta}s, discarding prediction!" end)
      C._HOLD
    end
  end
end
