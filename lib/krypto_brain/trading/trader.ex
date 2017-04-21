defmodule KryptoBrain.Trading.Trader do
  use GenServer

  def start_link(currency_pair, btc_balance) do
    GenServer.start_link(__MODULE__, [currency_pair, btc_balance], name: String.to_atom(currency_pair))
  end

  def init([currency_pair, btc_balance]) do
    schedule_work()
    {:ok, %{currency_pair: currency_pair, btc_balance: btc_balance}}
  end

  def schedule_work do
    Process.send_after(self(), :trade_loop, 1_000)
  end

  def handle_info(:trade_loop, state) do
    trade_loop()
    {:noreply, state}
  end

  def trade_loop do
    post_data = %{command: "returnBalances", nonce: :os.system_time(:seconds) * 1_000}
    encoded_post_data = post_data |> URI.encode_query
    sign = :crypto.hmac(:sha512, Application.get_env(:krypto_brain, __MODULE__)[:poloniex_api_secret], encoded_post_data)
           |> Base.encode16

    encoded_post_data |> IO.inspect
    post_data |> Poison.encode! |> IO.inspect

    HTTPoison.post!(
      "https://poloniex.com/tradingApi",
      encoded_post_data,
      [
        {"Content-Type", "application/x-www-form-urlencoded"},
        {"Key", Application.get_env(:krypto_brain, __MODULE__)[:poloniex_api_key]},
        {"Sign", sign}
      ]
    ) |> IO.inspect
  end
end
