# Problems with current implementation:
# - Orders are not always filled in, especially when not a lot of people seem to be trading certain altcoin.
# - Recalculations of trade'able BTC balance after selling altcoin are very naive, possibly can cause problems.
# - Need a more recent information on the current datasample. Currently it might be delayed even by 5-10 mins.
# - Getting %{"error" => "Total must be at least 0.0001."} when attempting to make an order
# - When we own more altcoin than 0, Trader assumes that we want to sell it, add an option to bypass
# - Kinda high memory/CPU usage with multiple workers (probably due to multiple Python instances)
# - Nonce collisions with multiple workers
# - Need to manually kill Python instances after crash, or memory will run out

defmodule KryptoBrain.Trading.Trader do
  require KryptoBrain.Constants
  alias KryptoBrain.Constants, as: C
  require Logger
  use GenServer

  def start_link(alt_symbol, btc_balance, currency_owned \\ C._BTC) do
    GenServer.start_link(__MODULE__, [alt_symbol, btc_balance, currency_owned], name: String.to_atom(alt_symbol))
  end

  def init([alt_symbol, btc_balance, currency_owned]) do
    schedule_work()

    state = case :ets.lookup(:trading_state_holder, alt_symbol) do
      [{^alt_symbol, previous_state}] ->
        Logger.debug("Trader #{alt_symbol} started, restoring backed-up state: #{previous_state}")
        previous_state
      [] ->
        Logger.debug("Trader #{alt_symbol} started, starting with initial state")
        %{
          alt_symbol: alt_symbol,
          btc_balance: btc_balance,
          alt_balance: 0.0,
          currency_owned: currency_owned,
          most_recent_alt_price: nil
        }
    end

    {:ok, state}
  end

  defp schedule_work do
    Process.send_after(self(), :start_trading, Enum.random(1..5) * 1_000)
  end

  def handle_info(:start_trading, state) do
    refresh_balances(state) |> trade_loop
    {:noreply, state}
  end

  def terminate(reason, state) do
    :ets.insert(:trading_state_holder, {state[:alt_symbol], state})
    :ok
  end

  defp refresh_balances(state) do
    post_data = %{command: "returnBalances", nonce: :os.system_time(:microsecond)}
    encoded_post_data = post_data |> URI.encode_query
    sign = :crypto.hmac(
      :sha512, Application.get_env(:krypto_brain, __MODULE__)[:poloniex_api_secret], encoded_post_data
    ) |> Base.encode16

    %HTTPoison.Response{body: balances} = HTTPoison.post!(
      "https://poloniex.com/tradingApi",
      encoded_post_data,
      [
        {"Content-Type", "application/x-www-form-urlencoded"},
        {"Key", Application.get_env(:krypto_brain, __MODULE__)[:poloniex_api_key]},
        {"Sign", sign}
      ]
    )
    balances = Poison.decode!(balances)

    case balances do
      %{"error" => error} -> raise error
      _ -> nil
    end

    {alt_balance, ""} = balances[state[:alt_symbol]] |> Float.parse

    state
    |> Map.update!(:btc_balance, fn(_) -> if state[:currency_owned] == C._BTC, do: state[:btc_balance], else: 0.0 end)
    |> Map.update!(:alt_balance, fn(_) -> alt_balance end)
    # |> Map.update!(:currency_owned, fn(_) -> C._ALT end)
  end

  defp trade_loop(state) do
    {prediction, most_recent_alt_price} = KryptoBrain.Bridge.KryptoJanusz.most_recent_prediction(state[:alt_symbol])
    state = state |> Map.update!(:most_recent_alt_price, fn(_) -> most_recent_alt_price end)

    # if orders:
    # orders = [%{"amount" => "10000.00000000", "date" => "2017-04-21 22:04:39", "margin" => 0,
    #    "orderNumber" => "7043413544", "rate" => "0.00000001",
    #    "startingAmount" => "10000.00000000", "total" => "0.00010000",
    #    "type" => "buy"}]
    # else:
    # []
    #
    prediction_str = case prediction do
      1 ->
        case state[:currency_owned] do
          C._BTC -> "BUY"
          C._ALT -> "BUY but #{state[:alt_symbol]} is already bought"
        end
      0 ->
        "HOLD"
      -1 ->
        case state[:currency_owned] do
          C._BTC -> "SELL but #{state[:alt_symbol]} is already sold"
          C._ALT -> "SELL"
        end
    end

    Logger.info("Prediction for #{state[:alt_symbol]}: #{prediction_str}")

    state = case prediction do
      C._BUY ->
        orders = get_open_orders(state[:alt_symbol])
        buy_orders = Enum.filter(orders, fn(order) -> order["type"] == "buy" end)
        sell_orders = Enum.filter(orders, fn(order) -> order["type"] == "sell" end)

        if !Enum.empty?(sell_orders), do: true = cancel_orders(sell_orders)
        if Enum.empty?(buy_orders) && state[:currency_owned] == C._BTC, do: state = place_buy_order(state)

        state
      C._HOLD ->
        state
      C._SELL ->
        orders = get_open_orders(state[:alt_symbol])
        buy_orders = Enum.filter(orders, fn(order) -> order["type"] == "buy" end)
        sell_orders = Enum.filter(orders, fn(order) -> order["type"] == "sell" end)

        if !Enum.empty?(buy_orders), do: true = cancel_orders(buy_orders)
        if Enum.empty?(sell_orders) && state[:currency_owned] == C._ALT, do: state = place_sell_order(state)

        state
    end

    Logger.debug("Trade loop completed: #{inspect(state)}")

    :timer.sleep(5_000)
    trade_loop(state)
  end

  defp place_buy_order(state) do
    post_data = %{
      command: "buy",
      currencyPair: "BTC_#{state[:alt_symbol]}",
      rate: state[:most_recent_alt_price],
      amount: (state[:btc_balance] / state[:most_recent_alt_price]),
      fillOrKill: 1,
      nonce: :os.system_time(:microsecond)
    }
    encoded_post_data = post_data |> URI.encode_query
    sign = :crypto.hmac(
      :sha512, Application.get_env(:krypto_brain, __MODULE__)[:poloniex_api_secret], encoded_post_data
    ) |> Base.encode16

    %HTTPoison.Response{body: response_body} = HTTPoison.post!(
      "https://poloniex.com/tradingApi",
      encoded_post_data,
      [
        {"Content-Type", "application/x-www-form-urlencoded"},
        {"Key", Application.get_env(:krypto_brain, __MODULE__)[:poloniex_api_key]},
        {"Sign", sign}
      ]
    )
    response_body = Poison.decode!(response_body)
    Logger.info(inspect(response_body))

    case response_body do
      # if success:
      # %{"orderNumber" => "69077573330",
      #   "resultingTrades" => [%{"amount" => "0.02061855",
      #                           "date" => "2017-04-21 23:12:01", "rate" => "0.00969994",
      #                           "total" => "0.00019999", "tradeID" => "4165065", "type" => "buy"}]}
      # else:
        # %{"error" => "Unable to fill order completely."} ->

      %{"resultingTrades" => [trades]} ->
        Logger.info(inspect(trades))

        state = state
                |> Map.update!(:btc_balance, fn(_) -> 0.0 end)
                |> refresh_balances()
                |> Map.update!(:currency_owned, fn(_) -> C._ALT end)
      %{"error" => "Unable to fill order completely."} ->
        Logger.warn("Attempted to buy #{state[:alt_symbol]} but could not fill the order")

      state
    end

    state
  end

  defp place_sell_order(state) do
    post_data = %{
      command: "sell",
      currencyPair: "BTC_#{state[:alt_symbol]}",
      rate: state[:most_recent_alt_price],
      amount: state[:alt_balance],
      fillOrKill: 1,
      nonce: :os.system_time(:microsecond)
    }
    encoded_post_data = post_data |> URI.encode_query
    sign = :crypto.hmac(
      :sha512, Application.get_env(:krypto_brain, __MODULE__)[:poloniex_api_secret], encoded_post_data
    ) |> Base.encode16

    %HTTPoison.Response{body: response_body} = HTTPoison.post!(
      "https://poloniex.com/tradingApi",
      encoded_post_data,
      [
        {"Content-Type", "application/x-www-form-urlencoded"},
        {"Key", Application.get_env(:krypto_brain, __MODULE__)[:poloniex_api_key]},
        {"Sign", sign}
      ]
    )
    response_body = Poison.decode!(response_body)
    Logger.info(inspect(response_body))

    case response_body do
      # if success:
      # %{"orderNumber" => "69077573330",
      #   "resultingTrades" => [%{"amount" => "0.02061855",
      #                           "date" => "2017-04-21 23:12:01", "rate" => "0.00969994",
      #                           "total" => "0.00019999", "tradeID" => "4165065", "type" => "buy"}]}
      # else:
        # %{"error" => "Unable to fill order completely."} ->

      %{"resultingTrades" => [trades]} ->
        Logger.info(inspect(trades))

        btc_amount_after_trade = state[:alt_balance] * state[:most_recent_alt_price]
        trade_fee = btc_amount_after_trade * 0.0025 # taker fee
        btc_amount_after_trade = btc_amount_after_trade - trade_fee

        state = state
                |> Map.update!(:btc_balance, fn(_) -> btc_amount_after_trade end)
                |> Map.update!(:alt_balance, fn(_) -> 0.0 end)
                |> Map.update!(:currency_owned, fn(_) -> C._BTC end)

      %{"error" => "Unable to fill order completely."} ->
        Logger.warn("Attempted to sell #{state[:alt_symbol]} but could not fill the order")
    end

    state
  end

  defp get_open_orders(alt_symbol) do
    post_data = %{
      command: "returnOpenOrders",
      currencyPair: "BTC_#{alt_symbol}",
      nonce: :os.system_time(:microsecond)
    }
    encoded_post_data = post_data |> URI.encode_query
    sign = :crypto.hmac(
      :sha512, Application.get_env(:krypto_brain, __MODULE__)[:poloniex_api_secret], encoded_post_data
    ) |> Base.encode16

    %HTTPoison.Response{body: response_body} = HTTPoison.post!(
      "https://poloniex.com/tradingApi",
      encoded_post_data,
      [
        {"Content-Type", "application/x-www-form-urlencoded"},
        {"Key", Application.get_env(:krypto_brain, __MODULE__)[:poloniex_api_key]},
        {"Sign", sign}
      ]
    )

    Poison.decode!(response_body)
  end

  defp cancel_orders(orders) do
    Enum.each orders, fn(order) ->
      post_data = %{
        command: "cancelOrder",
        orderNumber: order["orderNumber"],
        nonce: :os.system_time(:microsecond)
      }
      encoded_post_data = post_data |> URI.encode_query
      sign = :crypto.hmac(
        :sha512, Application.get_env(:krypto_brain, __MODULE__)[:poloniex_api_secret], encoded_post_data
      ) |> Base.encode16

      %HTTPoison.Response{body: response_body} = HTTPoison.post!(
        "https://poloniex.com/tradingApi",
        encoded_post_data,
        [
          {"Content-Type", "application/x-www-form-urlencoded"},
          {"Key", Application.get_env(:krypto_brain, __MODULE__)[:poloniex_api_key]},
          {"Sign", sign}
        ]
      )

      %{"success" => 1} = Poison.decode!(response_body)
      Logger.info("Order #{order["orderNumber"]} cancelled.")
    end

    true
  end
end
