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
    GenServer.start_link(__MODULE__, [alt_symbol, currency_owned], name: String.to_atom(alt_symbol))
  end

  def init([alt_symbol, currency_owned]) do
    schedule_work()

    # state = case :ets.lookup(:trading_state_holder, alt_symbol) do
      # [{^alt_symbol, previous_state}] ->
        # Logger.info("Trader #{alt_symbol} started, restoring backed-up state: #{inspect(previous_state)}")
        # previous_state
      # [] ->
        Logger.info("Trader #{alt_symbol} started, starting with initial state")
        state = %{
          alt_symbol: alt_symbol,
          btc_balance: nil,
          alt_balance: nil,
          currency_owned: currency_owned
          # most_recent_alt_price: nil
        }
    # end

    Logger.debug("#{__ENV__.line}: #{inspect(state)}")
    {:ok, state}
  end

  defp schedule_work do
    Process.send_after(self(), :start_trading, Enum.random(1..5) * 1_000)
  end

  def handle_info(:start_trading, state) do
    refresh_balances(state) |> trade_loop
    {:noreply, state}
  end

  # def terminate(_reason, state) do
    # :ets.insert(:trading_state_holder, {state[:alt_symbol], state})
    # :ok
  # end

  defp refresh_balances(state) do
    refresh_balances_response = Requests.refresh_balances(state[:alt_symbol])

    case refresh_balances_response do
      %{"error" => error} -> raise error
      _ -> nil
    end

    {btc_balance, ""} = refresh_balances_response[C._BTC] |> Float.parse
    {alt_balance, ""} = refresh_balances_response[state[:alt_symbol]] |> Float.parse

    orders = Requests.get_open_orders(state[:alt_symbol])
    buy_orders = Enum.filter(orders, fn(order) -> order["type"] == "buy" end)
    sell_orders = Enum.filter(orders, fn(order) -> order["type"] == "sell" end)

    Logger.debug("#{__ENV__.line}: #{inspect(state)}")

    state = state
            |> Map.update!(:btc_balance, fn(_) -> btc_balance end)
            |> Map.update!(:alt_balance, fn(_) -> alt_balance end)
            |> Map.update!(:currency_owned, fn(_) ->
                 cond do
                   btc_balance >= alt_balance || !Enum.empty?(buy_orders)  -> C._BTC
                   btc_balance  < alt_balance || !Enum.empty?(sell_orders) -> C._ALT
                 end
               end)

    Logger.debug("#{__ENV__.line}: #{inspect(state)}")
    state
  end

  defp trade_loop(state) do
    # {prediction, _most_recent_alt_price} = KryptoBrain.Bridge.KryptoJanusz.most_recent_prediction(state[:alt_symbol])
    prediction = KryptoBrain.Bridge.KryptoJanusz.most_recent_prediction(state[:alt_symbol])
    # state = state |> Map.update!(:most_recent_alt_price, fn(_) -> most_recent_alt_price end)
    Logger.debug("#{__ENV__.line}: #{inspect(state)}")

    prediction_str = case prediction do
      C._BUY ->
        case state[:currency_owned] do
          C._BTC -> "#{IO.ANSI.green}⬆️ BUY"
          C._ALT -> "#{IO.ANSI.blue}⬆️ BUY (already bought)"
        end
      C._HOLD ->
        "#{IO.ANSI.blue}HOLD"
      C._SELL ->
        case state[:currency_owned] do
          C._BTC -> "#{IO.ANSI.blue}⬇️ SELL (already sold)"
          C._ALT -> "#{IO.ANSI.red}⬇️ SELL"
        end
    end
    Logger.info("Predicted action for #{state[:alt_symbol]}: #{prediction_str}")

    state = case prediction do
      C._BUY ->
        orders = Requests.get_open_orders(state[:alt_symbol])
        buy_orders = Enum.filter(orders, fn(order) -> order["type"] == "buy" end)
        sell_orders = Enum.filter(orders, fn(order) -> order["type"] == "sell" end)

        if state[:currency_owned] == C._BTC do
          if !Enum.empty?(sell_orders) do
            true = cancel_orders(sell_orders, state[:alt_symbol])
            state = refresh_balances(state)
          end
          if Enum.empty?(buy_orders) do
            suggested_trade_price = suggested_trade_price(state[:alt_symbol])
            state = place_buy_order(state, suggested_trade_price)
          end

          state
        end

        Logger.debug("#{__ENV__.line}: #{inspect(state)}")
        state

      C._HOLD ->
        state

      C._SELL ->
        orders = Requests.get_open_orders(state[:alt_symbol])
        buy_orders = Enum.filter(orders, fn(order) -> order["type"] == "buy" end)
        sell_orders = Enum.filter(orders, fn(order) -> order["type"] == "sell" end)

        if state[:currency_owned] == C._ALT do
          if !Enum.empty?(buy_orders) do
            true = cancel_orders(buy_orders, state[:alt_symbol])
            state = refresh_balances(state)
          end
          if Enum.empty?(sell_orders) do
            suggested_trade_price = suggested_trade_price(state[:alt_symbol])
            state = place_sell_order(state, suggested_trade_price)
          end

          state
        end

        Logger.debug("#{__ENV__.line}: #{inspect(state)}")
        state
    end

    Logger.info("Trade loop completed: #{inspect(state)}")

    :timer.sleep(5_000)
    trade_loop(state)
  end

  defp place_buy_order(state, price) do
    place_buy_order_response = Requests.place_buy_order(price, state[:btc_balance], state[:alt_symbol])
    Logger.info(inspect(place_buy_order_response))

    case place_buy_order_response do
      %{"orderNumber" => _order_number, "resultingTrades" => _trades} ->
        state = state
                # |> refresh_balances()
                # |> Map.update!(:btc_balance, fn(_) -> 0.0 end)
                |> Map.update!(:currency_owned, fn(_) -> C._ALT end)
        Logger.debug("#{__ENV__.line}: #{inspect(state)}")
      %{"error" => "Unable to fill order completely."} ->
        Logger.warn("Attempted to buy #{state[:alt_symbol]} but could not fill the order.")
      # %{"error" => "Not enough BTC."} ->
        # Logger.error("Attempted to buy #{state[:alt_symbol]} but failed due to low BTC balance, lowering BTC balance by 10%.")

        # state = state |> Map.update!(:btc_balance, fn(btc_balance) -> btc_balance * 0.9 end)
        # state = place_buy_order(state, price)
    end

    state
  end

  defp place_sell_order(state, price) do
    place_sell_order_response = Requests.place_sell_order(price, state[:alt_balance], state[:alt_symbol])
    Logger.info(inspect(place_sell_order_response))

    case place_sell_order_response do
      %{"orderNumber" => _order_number, "resultingTrades" => _trades} ->
        # btc_amount_after_trade = state[:alt_balance] * state[:most_recent_alt_price]
        # trade_fee = btc_amount_after_trade * 0.0025 # taker fee
        # btc_amount_after_trade = btc_amount_after_trade - trade_fee

        state = state
                # |> refresh_balances()
                # |> Map.update!(:btc_balance, fn(_) -> btc_amount_after_trade end)
                # |> Map.update!(:alt_balance, fn(_) -> 0.0 end)
                |> Map.update!(:currency_owned, fn(_) -> C._BTC end)
        Logger.debug("#{__ENV__.line}: #{inspect(state)}")
      %{"error" => "Unable to fill order completely."} ->
        Logger.warn("Attempted to sell #{state[:alt_symbol]} but could not fill the order")
      %{"error" => "Total must be at least 0.0001."} ->
        Logger.error("Total must be at least 0.0001.")
        Logger.error(inspect(state))
    end

    state
  end

  defp cancel_orders(orders, alt_symbol) do
    Enum.each orders, fn(order) ->
      %{"success" => 1} = Requests.cancel_order(order, alt_symbol)
      Logger.info("Order #{order["orderNumber"]} cancelled.")
    end

    true
  end

  # defp suggested_trade_price(alt_symbol, buy_or_sell) do
  defp suggested_trade_price(alt_symbol) do
    ticker_data_response = Requests.get_ticker_data
                           |> Enum.find(fn(currency_data) -> elem(currency_data, 0) === "BTC_#{alt_symbol}" end)
                           |> elem(1)

    # case buy_or_sell do
      # :buy  ->
        # {lowest_ask, ""} = Map.fetch!(ticker_data_response, "lowestAsk") |> Float.parse
        # lowest_ask
      # :sell ->
        # {highest_bid, ""} = Map.fetch!(ticker_data_response, "highestBid") |> Float.parse
        # highest_bid
    # end

    {last, ""} = Map.fetch!(ticker_data_response, "last") |> Float.parse
    last
  end
end
