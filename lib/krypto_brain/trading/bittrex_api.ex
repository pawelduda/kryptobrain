defmodule KryptoBrain.Trading.BittrexApi do
  require Logger

  def get_balances do
    uri = "https://bittrex.com/api/v1.1/account/getbalances?apikey=#{api_key()}&nonce=#{nonce()}"

    %HTTPoison.Response{body: response_body} =
      HTTPoison.get!(uri, ["apisign": sign_uri_with_api_secret(api_secret(), uri)])

    case Poison.decode(response_body) do
      {:ok, response} -> (%{"success" => true} = response) && response["result"]
      {:error, reason} -> raise "Could not decode response from Bittrex. Reason: #{inspect(reason)}"
    end
  end

  def get_balance(alt_symbol) do
    uri =
      "https://bittrex.com/api/v1.1/account/getbalance?apikey=#{api_key()}&nonce=#{nonce()}&currency=#{alt_symbol}"

    %HTTPoison.Response{body: response_body} =
      HTTPoison.get!(uri, ["apisign": sign_uri_with_api_secret(api_secret(), uri)])

    %{"success" => true} = Poison.decode!(response_body)
  end

  def get_open_orders do
    uri =
      "https://bittrex.com/api/v1.1/market/getopenorders?apikey=#{api_key()}&nonce=#{nonce()}"

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
