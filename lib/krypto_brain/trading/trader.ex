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
        Logger.info("Trader #{alt_symbol} started, restoring backed-up state: #{inspect(previous_state)}")
        previous_state
      [] ->
        Logger.info("Trader #{alt_symbol} started, starting with initial state")
        %{
          alt_symbol: alt_symbol,
          btc_balance: btc_balance,
          alt_balance: 0.0,
          currency_owned: currency_owned,
          most_recent_alt_price: nil
        }
    end

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

  def terminate(_reason, state) do
    :ets.insert(:trading_state_holder, {state[:alt_symbol], state})
    :ok
  end

  defp refresh_balances(state) do
    post_data = %{command: "returnBalances", nonce: get_nonce()}
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

    Logger.debug("#{__ENV__.line}: #{inspect(state)}")

    state = state
    |> Map.update!(:btc_balance, fn(_) -> if state[:currency_owned] == C._BTC, do: state[:btc_balance], else: 0.0 end)
    |> Map.update!(:alt_balance, fn(_) -> alt_balance end)
    # |> Map.update!(:currency_owned, fn(_) -> C._ALT end)

    Logger.debug("#{__ENV__.line}: #{inspect(state)}")
    state
  end

  defp trade_loop(state) do
    {prediction, most_recent_alt_price} = KryptoBrain.Bridge.KryptoJanusz.most_recent_prediction(state[:alt_symbol])
    state = state |> Map.update!(:most_recent_alt_price, fn(_) -> most_recent_alt_price end)
    Logger.debug("#{__ENV__.line}: #{inspect(state)}")

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
        # orders = get_open_orders(state[:alt_symbol])
        # buy_orders = Enum.filter(orders, fn(order) -> order["type"] == "buy" end)
        # sell_orders = Enum.filter(orders, fn(order) -> order["type"] == "sell" end)

        # if !Enum.empty?(sell_orders), do: true = cancel_orders(sell_orders)
        # if Enum.empty?(buy_orders) && state[:currency_owned] == C._BTC, do: state = place_buy_order(state)
        if state[:currency_owned] == C._BTC, do: state = place_buy_order(state)
        Logger.debug("#{__ENV__.line}: #{inspect(state)}")

        state
      C._HOLD ->
        state
      C._SELL ->
        # orders = get_open_orders(state[:alt_symbol])
        # buy_orders = Enum.filter(orders, fn(order) -> order["type"] == "buy" end)
        # sell_orders = Enum.filter(orders, fn(order) -> order["type"] == "sell" end)

        # if !Enum.empty?(buy_orders), do: true = cancel_orders(buy_orders)
        # if Enum.empty?(sell_orders) && state[:currency_owned] == C._ALT, do: state = place_sell_order(state)
        if state[:currency_owned] == C._ALT, do: state = place_sell_order(state)
        Logger.debug("#{__ENV__.line}: #{inspect(state)}")

        state
    end

    Logger.info("Trade loop completed: #{inspect(state)}")

    :timer.sleep(5_000)
    trade_loop(state)
  end

  defp place_buy_order(state) do
    place_buy_order_response = do_place_buy_order(state)
    Logger.info(inspect(place_buy_order_response))

    case place_buy_order_response do
      %{"orderNumber" => _order_number, "resultingTrades" => _trades} ->
        state = state
                |> refresh_balances()
                |> Map.update!(:btc_balance, fn(_) -> 0.0 end)
                |> Map.update!(:currency_owned, fn(_) -> C._ALT end)
        Logger.debug("#{__ENV__.line}: #{inspect(state)}")
      %{"error" => "Unable to fill order completely."} ->
        Logger.warn("Attempted to buy #{state[:alt_symbol]} but could not fill the order.")
      %{"error" => "Not enough BTC."} ->
        Logger.error("Attempted to buy #{state[:alt_symbol]} but failed due to low BTC balance, lowering BTC balance by 10%.")

        state = state |> Map.update!(:btc_balance, fn(btc_balance) -> btc_balance * 0.9 end)
        do_place_buy_order(state)
    end

    state
  end

  defp do_place_buy_order(state) do
    rate = state[:most_recent_alt_price]
    amount = state[:btc_balance] / state[:most_recent_alt_price]

    post_data = %{
      command: "buy",
      currencyPair: "BTC_#{state[:alt_symbol]}",
      rate: rate,
      amount: amount,
      fillOrKill: 1,
      nonce: get_nonce()
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

  defp place_sell_order(state) do
    place_sell_order_response = do_place_sell_order(state)
    Logger.info(inspect(place_sell_order_response))

    case place_sell_order_response do
      %{"orderNumber" => _order_number, "resultingTrades" => _trades} ->
        btc_amount_after_trade = state[:alt_balance] * state[:most_recent_alt_price]
        trade_fee = btc_amount_after_trade * 0.0025 # taker fee
        btc_amount_after_trade = btc_amount_after_trade - trade_fee

        state = state
                |> Map.update!(:btc_balance, fn(_) -> btc_amount_after_trade end)
                |> Map.update!(:alt_balance, fn(_) -> 0.0 end)
                |> Map.update!(:currency_owned, fn(_) -> C._BTC end)
        Logger.debug("#{__ENV__.line}: #{inspect(state)}")
      %{"error" => "Unable to fill order completely."} ->
        Logger.warn("Attempted to sell #{state[:alt_symbol]} but could not fill the order")
    end

    state
  end

  defp do_place_sell_order(state) do
    post_data = %{
      command: "sell",
      currencyPair: "BTC_#{state[:alt_symbol]}",
      rate: state[:most_recent_alt_price],
      amount: state[:alt_balance],
      fillOrKill: 1,
      nonce: get_nonce()
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

  defp get_open_orders(alt_symbol) do
    post_data = %{
      command: "returnOpenOrders",
      currencyPair: "BTC_#{alt_symbol}",
      nonce: get_nonce()
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
        nonce: get_nonce()
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

  defp get_nonce() do
    GenServer.call(KryptoBrain.Trading.NonceGenerator, :get_nonce)
  end
end
