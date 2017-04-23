defmodule KryptoBrain.Trading.Requests do
  alias KryptoBrain.Trading.NonceGenerator

  def refresh_balances do
    post_data = %{command: "returnBalances", nonce: NonceGenerator.get_nonce}
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

  def place_buy_order(most_recent_alt_price, btc_balance, alt_symbol) do
    amount = btc_balance / most_recent_alt_price

    post_data = %{
      command: "buy",
      currencyPair: "BTC_#{alt_symbol}",
      rate: most_recent_alt_price,
      amount: amount,
      fillOrKill: 1,
      nonce: NonceGenerator.get_nonce
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

  def place_sell_order(most_recent_alt_price, alt_balance, alt_symbol) do
    post_data = %{
      command: "sell",
      currencyPair: "BTC_#{alt_symbol}",
      rate: most_recent_alt_price,
      amount: alt_balance,
      fillOrKill: 1,
      nonce: NonceGenerator.get_nonce
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

  def get_open_orders(alt_symbol) do
    post_data = %{
      command: "returnOpenOrders",
      currencyPair: "BTC_#{alt_symbol}",
      nonce: NonceGenerator.get_nonce
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

  def cancel_order(order) do
    post_data = %{
      command: "cancelOrder",
      orderNumber: order["orderNumber"],
      nonce: NonceGenerator.get_nonce
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
end