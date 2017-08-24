defmodule KryptoBrain.Trading.BittrexApi do
  require Logger

  def get_currencies do
    public_api_get_response("https://bittrex.com/api/v1.1/public/getmarketsummaries")
  end

  def get_market_ticks(market_name, tick_interval \\ "hour", raw_response? \\ false) do
    public_api_get_response(
      "https://bittrex.com/Api/v2.0/pub/market/GetTicks?marketName=#{market_name}&tickInterval=#{tick_interval}",
      raw_response?
    )
  end

  def get_balances do
    trading_api_get_response("https://bittrex.com/api/v1.1/account/getbalances")
  end

  def get_balance(alt_symbol) do
    trading_api_get_response("https://bittrex.com/api/v1.1/account/getbalance", "currency=#{alt_symbol}")
  end

  def get_open_orders do
    trading_api_get_response("https://bittrex.com/api/v1.1/market/getopenorders")
  end

  defp public_api_get_response(uri, raw_response? \\ false)

  defp public_api_get_response(uri, raw_response?) when raw_response? do
    %HTTPoison.Response{body: response_body} =
      HTTPoison.get!(uri, ["apisign": sign_uri_with_api_secret(api_secret(), uri)])

    case Poison.decode(response_body) do
      {:ok, response} -> (%{"success" => true} = response) && (response["result"] |> Poison.encode!)
      {:error, reason} ->
        raise ~s"""
          Could not decode response from Bittrex.
          Reason: #{inspect(reason)}.
          Raw response body: #{response_body}
        """
    end
  end

  defp public_api_get_response(uri, raw_response?) when not raw_response? do
    %HTTPoison.Response{body: response_body} =
      HTTPoison.get!(uri, ["apisign": sign_uri_with_api_secret(api_secret(), uri)])

    case Poison.decode(response_body) do
      {:ok, response} -> (%{"success" => true} = response) && response["result"]
      {:error, reason} ->
        raise ~s"""
          Could not decode response from Bittrex.
          Reason: #{inspect(reason)}.
          Raw response body: #{response_body}
        """
    end
  end

  defp trading_api_get_response(uri_base, query_params \\ nil) do
    uri = case query_params do
      nil -> "#{uri_base}?apikey=#{api_key()}&nonce=#{nonce()}"
      _ -> "#{uri_base}?apikey=#{api_key()}&nonce=#{nonce()}&#{query_params}"
    end

    %HTTPoison.Response{body: response_body} =
      HTTPoison.get!(uri, ["apisign": sign_uri_with_api_secret(api_secret(), uri)])

    case Poison.decode(response_body) do
      {:ok, response} -> (%{"success" => true} = response) && response["result"]
      {:error, reason} ->
        raise ~s"""
          Could not decode response from Bittrex.
          Reason: #{inspect(reason)}.
          Raw response body: #{response_body}
        """
    end
  end

  defp sign_uri_with_api_secret(api_secret, uri) do
    :crypto.hmac(:sha512, api_secret, uri) |> Base.encode16
  end

  defp api_key do
    Application.get_env(:krypto_brain, __MODULE__)[:bittrex_api_key0]
  end

  defp api_secret do
    Application.get_env(:krypto_brain, __MODULE__)[:bittrex_api_secret0]
  end

  defp nonce do
    :os.system_time(:nanosecond)
  end
end
