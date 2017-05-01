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
  alias KryptoBrain.Trading.Requests
  require KryptoBrain.Constants
  require Logger
  use GenServer

  def start_link(alt_symbol, currency_owned \\ C._BTC) do
    GenServer.start_link(__MODULE__, [alt_symbol], name: String.to_atom(alt_symbol))
  end

  def init([alt_symbol]) do
    schedule_work()

    Logger.info(fn -> "Trader #{alt_symbol} started, starting with initial state" end)
    state = %{
      alt_symbol: alt_symbol,
      btc_balance: nil,
      alt_balance: nil,
      suggested_trade_price: nil,
      prediction: nil,
      buy_orders: [],
      sell_orders: []
      # currency_owned: currency_owned
    }

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

  defp update_balances(state) do
    refresh_balances_response = Requests.get_balances(state[:alt_symbol])

    case refresh_balances_response do
      %{"error" => error} -> raise error
      _ -> nil
    end

    {btc_balance, ""} = refresh_balances_response[C._BTC] |> Float.parse
    {alt_balance, ""} = refresh_balances_response[state[:alt_symbol]] |> Float.parse

    state
    |> Map.update!(:btc_balance, fn(_) -> btc_balance end)
    |> Map.update!(:alt_balance, fn(_) -> alt_balance end)
  end

  defp update_suggested_trade_price(state) do
    ticker_data_response =
      Requests.get_ticker_data
      |> Enum.find(fn(currency_data) -> elem(currency_data, 0) === "BTC_#{state[:alt_symbol]}" end)
      |> elem(1)

    {last, ""} = Map.fetch!(ticker_data_response, "last") |> Float.parse

    state |> Map.update!(:suggested_trade_price, fn(_) -> last end)
  end

  defp update_open_orders(state) do
    orders = Requests.get_open_orders(state[:alt_symbol])

    buy_orders = Enum.filter(orders, fn(order) -> order["type"] == "buy" end)
    sell_orders = Enum.filter(orders, fn(order) -> order["type"] == "sell" end)

    state
    |> Map.update!(:buy_orders, fn(_) -> buy_orders end)
    |> Map.update!(:sell_orders, fn(_) -> sell_orders end)
  end

  defp update_prediction(state) do
    prediction = KryptoBrain.Bridge.KryptoJanusz.most_recent_prediction(state[:alt_symbol])
    state |> Map.update!(:prediction, fn(_) -> prediction end)
  end

  defp print_status_message(state) do
    prediction_str = case state[:prediction] do
      C._BUY -> "#{IO.ANSI.green}⬆️ BUY"
      C._HOLD -> "#{IO.ANSI.blue}HOLD"
      C._SELL -> "#{IO.ANSI.red}⬇️ SELL"
    end

    # For now we do not print anything if the prediction is hold as it does not bring too much to the table
    case state[:prediction] do
      prediction when prediction in [C._BUY, C._SELL] ->
        Logger.debug(inspect(state))
        Logger.info(fn -> "Predicted action for #{state[:alt_symbol]}: #{prediction_str}" end)
      _ ->
        nil
    end

    state
  end

  defp trade_loop(state) do
    state
    |> update_state()
    |> act_upon_prediction()
    |> trade_loop()
  end

  defp act_upon_prediction(state) do
    case state[:prediction] do
      C._BUY ->
        if outdated_open_orders?(state[:buy_orders], state[:suggested_trade_price]) do
          Logger.debug("Got outdated open buy orders, cancelling...")
          cancel_orders(state[:buy_orders], state[:alt_symbol])
          # We are not doing anything else here so that loop repeats and we get updated balances
        end

        if !Enum.empty?(state[:sell_orders]) do
          Logger.debug("Got open sell orders, cancelling...")
          cancel_orders(state[:sell_orders], state[:alt_symbol])
        end

        if state[:btc_balance] >= 0.0001 do
          Logger.debug("Got some BTC balance, placing buy order...")
          place_buy_order(state)
        end
      C._HOLD ->
        nil
      C._SELL ->
        if outdated_open_orders?(state[:sell_orders], state[:suggested_trade_price]) do
          Logger.debug("Found outdated open sell orders, cancelling...")
          cancel_orders(state[:sell_orders], state[:alt_symbol])
          # We are not doing anything else here so that loop repeats and we get updated balances
        end

        if !Enum.empty?(state[:buy_orders]) do
          Logger.debug("Got open buy orders, cancelling...")
          cancel_orders(state[:buy_orders], state[:alt_symbol])
        end

        if state[:alt_balance] >= 0.0001 do
          Logger.debug("Got some ALT balance, placing sell order...")
          place_sell_order(state)
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

  defp place_buy_order(state) do
    place_buy_order_response = Requests.place_buy_order(state[:suggested_trade_price], state[:btc_balance], state[:alt_symbol])
    Logger.info(inspect(place_buy_order_response))

    case place_buy_order_response do
      %{"orderNumber" => _order_number, "resultingTrades" => _trades} ->
        Logger.debug(fn -> "#{__ENV__.line}: #{inspect(state)}" end)
      %{"error" => "Unable to fill order completely."} ->
        Logger.warn(fn -> "Attempted to buy #{state[:alt_symbol]} but could not fill the order." end)
    end

    state
  end

  defp place_sell_order(state) do
    place_sell_order_response = Requests.place_sell_order(state[:suggested_trade_price], state[:alt_balance], state[:alt_symbol])
    Logger.info(inspect(place_sell_order_response))

    case place_sell_order_response do
      %{"orderNumber" => _order_number, "resultingTrades" => _trades} ->
        Logger.debug(fn -> "#{__ENV__.line}: #{inspect(state)}" end)
      %{"error" => "Unable to fill order completely."} ->
        Logger.warn(fn -> "Attempted to sell #{state[:alt_symbol]} but could not fill the order" end)
      %{"error" => "Total must be at least 0.0001."} ->
        Logger.error("Total must be at least 0.0001.")
        Logger.error(inspect(state))
    end

    state
  end

  defp cancel_orders(orders, alt_symbol) do
    Enum.each orders, fn(order) ->
      %{"success" => 1} = Requests.cancel_order(order, alt_symbol)
      Logger.info(fn -> "Order #{order["orderNumber"]} cancelled." end)
    end

    true
  end
end
