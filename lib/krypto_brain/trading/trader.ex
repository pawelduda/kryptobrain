defmodule KryptoBrain.Trading.Trader do
  import Logger

  use GenServer

  @buy   1
  @hold  0
  @sell -1

  @btc "BTC"
  @alt "ALT"

  def start_link(alt_symbol, btc_balance) do
    GenServer.start_link(__MODULE__, [alt_symbol, btc_balance], name: String.to_atom(alt_symbol))
  end

  def init([alt_symbol, btc_balance]) do
    schedule_work()
    {:ok, %{
      alt_symbol: alt_symbol,
      btc_balance: btc_balance,
      alt_balance: 0.0,
      currency_owned: @btc,
      most_recent_alt_price: nil
    }}
  end

  defp schedule_work do
    Process.send_after(self(), :trade_loop, 1_000)
  end

  def handle_info(:trade_loop, state) do
    refresh_balances(state) |> trade_loop
    {:noreply, state}
  end

  defp refresh_balances(state) do
    post_data = %{command: "returnBalances", nonce: :os.system_time(:millisecond) * 1_000}
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

    {alt_balance, ""} = balances[state[:alt_symbol]] |> Float.parse

    state = cond do
      alt_balance > 0.0 ->
        state
        |> Map.update!(:btc_balance, fn(_) -> 0.0 end)
        |> Map.update!(:alt_balance, fn(_) -> alt_balance end)
        |> Map.update!(:currency_owned, fn(_) -> @alt end)
      alt_balance === 0.0 ->
        state
    end

    state
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

    Logger.info("Prediction for #{state[:alt_symbol]}: #{prediction}")

    state = case prediction do
      @buy ->
        orders = get_open_orders(state[:alt_symbol])
        buy_orders = Enum.filter(orders, fn(order) -> order["type"] == "buy" end)
        sell_orders = Enum.filter(orders, fn(order) -> order["type"] == "sell" end)

        if !Enum.empty?(sell_orders), do: true = cancel_orders(sell_orders)
        if Enum.empty?(buy_orders), do: state = place_buy_order(state)

        state
      @hold ->
        state
      @sell ->
        orders = get_open_orders(state[:alt_symbol])
        buy_orders = Enum.filter(orders, fn(order) -> order["type"] == "buy" end)
        sell_orders = Enum.filter(orders, fn(order) -> order["type"] == "sell" end)

        if !Enum.empty?(buy_orders), do: true = cancel_orders(buy_orders)
        if Enum.empty?(sell_orders), do: state = place_sell_order(state)

        state
    end

    Logger.debug("Trader with state: #{inspect(state)} completed trade loop...")

    :timer.sleep(10_000)
    trade_loop(state)
  end

  defp place_buy_order(state) do
    post_data = %{
      command: "buy",
      currencyPair: "BTC_#{state[:alt_symbol]}",
      rate: state[:most_recent_alt_price],
      amount: (state[:btc_balance] / state[:most_recent_alt_price]),
      fillOrKill: 1,
      nonce: :os.system_time(:millisecond) * 1_000
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
    response_body |> IO.inspect

    case response_body do
      # if success:
      # %{"orderNumber" => "69077573330",
      #   "resultingTrades" => [%{"amount" => "0.02061855",
      #                           "date" => "2017-04-21 23:12:01", "rate" => "0.00969994",
      #                           "total" => "0.00019999", "tradeID" => "4165065", "type" => "buy"}]}
      # else:
        # %{"error" => "Unable to fill order completely."} ->

        %{"resultingTrades" => [_]} ->
          # TODO: need to refresh balances here
          state = state |> Map.update!(:currency_owned, fn(_) -> @alt end)
        %{"error" => "Unable to fill order completely."} ->
          Logger.warn("Attempted to sell #{state[:alt_symbol]} but could not fill the order")
    end

    state
  end

  defp place_sell_order(state) do
    post_data = %{
      command: "sell",
      currencyPair: "BTC_#{state[:alt_symbol]}",
      rate: state[:most_recent_alt_price],
      amount: (state[:alt_balance] * state[:most_recent_alt_price]),
      fillOrKill: 1,
      nonce: :os.system_time(:millisecond) * 1_000
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
    response_body |> IO.inspect

    case response_body do
      # if success:
      # %{"orderNumber" => "69077573330",
      #   "resultingTrades" => [%{"amount" => "0.02061855",
      #                           "date" => "2017-04-21 23:12:01", "rate" => "0.00969994",
      #                           "total" => "0.00019999", "tradeID" => "4165065", "type" => "buy"}]}
      # else:
        # %{"error" => "Unable to fill order completely."} ->

        %{"resultingTrades" => [_]} ->
          # TODO: need to refresh balances here
          state = state |> Map.update!(:currency_owned, fn(_) -> @btc end)
        %{"error" => "Unable to fill order completely."} ->
          Logger.warn("Attempted to buy #{state[:alt_symbol]} but could not fill the order")
    end

    state
  end

  defp get_open_orders(alt_symbol) do
    post_data = %{
      command: "returnOpenOrders",
      currencyPair: "BTC_#{alt_symbol}",
      nonce: :os.system_time(:millisecond) * 1_000
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
        nonce: :os.system_time(:millisecond) * 1_000
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
