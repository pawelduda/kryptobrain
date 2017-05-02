defmodule KryptoBrain.Trading.Requests do
  def get_balances(alt_symbol) do
    post_data = %{command: "returnBalances", nonce: nonce()}
    trading_api_post_response(alt_symbol, post_data)
  end

  def place_buy_order(most_recent_alt_price, btc_balance, alt_symbol) do
    amount = btc_balance / most_recent_alt_price

    post_data = %{
      command: "buy",
      currencyPair: "BTC_#{alt_symbol}",
      rate: most_recent_alt_price,
      amount: amount,
      nonce: nonce()
    }
    trading_api_post_response(alt_symbol, post_data)
  end

  def place_sell_order(most_recent_alt_price, alt_balance, alt_symbol) do
    post_data = %{
      command: "sell",
      currencyPair: "BTC_#{alt_symbol}",
      rate: most_recent_alt_price,
      amount: alt_balance,
      nonce: nonce()
    }
    trading_api_post_response(alt_symbol, post_data)
  end

  def get_open_orders(alt_symbol) do
    post_data = %{
      command: "returnOpenOrders",
      currencyPair: "BTC_#{alt_symbol}",
      nonce: nonce()
    }
    trading_api_post_response(alt_symbol, post_data)
  end

  def cancel_order(order, alt_symbol) do
    post_data = %{
      command: "cancelOrder",
      orderNumber: order["orderNumber"],
      nonce: nonce()
    }
    trading_api_post_response(alt_symbol, post_data)
  end

  def get_ticker_data do
    %HTTPoison.Response{body: response_body} = HTTPoison.get!("https://poloniex.com/public?command=returnTicker")
    Poison.decode!(response_body)
  end

  defp trading_api_post_response(alt_symbol, post_data) do
    encoded_post_data = encode_post_data(post_data)

    %HTTPoison.Response{body: response_body} = HTTPoison.post!(
      "https://poloniex.com/tradingApi",
      encoded_post_data,
      trading_api_headers(alt_symbol, encoded_post_data)
    )
    Poison.decode!(response_body)
  end

  defp trading_api_headers(alt_symbol, encoded_post_data) do
    [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Key", map_altcoin_symbol_to_api_key(alt_symbol)},
      {"Sign", sign_post_data_with_api_secret(map_altcoin_symbol_to_api_secret(alt_symbol), encoded_post_data)}
    ]
  end

  defp map_altcoin_symbol_to_api_key(alt_symbol) do
    api_key_id = Application.get_env(:krypto_brain, __MODULE__)[String.to_atom(alt_symbol)]
    Application.get_env(:krypto_brain, __MODULE__)[:"poloniex_api_key#{api_key_id}"]
  end

  defp map_altcoin_symbol_to_api_secret(alt_symbol) do
    api_key_id = Application.get_env(:krypto_brain, __MODULE__)[String.to_atom(alt_symbol)]
    Application.get_env(:krypto_brain, __MODULE__)[:"poloniex_api_secret#{api_key_id}"]
  end

  defp encode_post_data(post_data) do
    URI.encode_query(post_data)
  end

  defp sign_post_data_with_api_secret(api_secret, encoded_post_data) do
    :crypto.hmac(:sha512, api_secret, encoded_post_data) |> Base.encode16
  end

  defp nonce do
    :os.system_time(:nanosecond)
  end
end
