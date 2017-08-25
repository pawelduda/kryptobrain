defmodule KryptoBrain.Trading.BittrexSignalsFetcher do
  alias KryptoBrain.Constants, as: C
  alias KryptoBrain.Trading.BittrexApi
  require Logger
  require KryptoBrain.Constants

  def get_signals do
    currencies_data = BittrexApi.get_currencies()
    market_names = Enum.map(currencies_data, &(&1["MarketName"]))

    # IO.inspect market_names
    # data = market_names
    # |> Enum.map(&(Task.async(fn ->
      # %{market_name: &1, market_ticks: BittrexApi.get_market_ticks(&1, "hour", true)}
    # end)))
    # |> Task.yield_many(60_000)
    # |> Enum.map(fn(result) ->
      # {%Task{}, {:ok, market_data}} = result;
      # market_data
    # end)
    # File.write!("charts_sample_data.txt", :erlang.term_to_binary(data))
    File.read!("charts_sample_data.txt")
    |> :erlang.binary_to_term
    |> Enum.map(fn(market_data) ->
      signal = case get_signal(market_data[:market_ticks]) do
        {:ok, signal} -> signal
        {:error, :outdated, _signal} -> C._HOLD
      end

      %{market_name: market_data[:market_name], signal: signal}
    end)

  end

  defp get_signal(chart_data) do
    {signal, retrieval_date_gmt} =
      GenServer.call(KryptoBrain.Bridge.KryptoJanusz, {:most_recent_prediction_bittrex, chart_data}, 15_000)

    # TODO: ensure we are good here with timezones
    retrieval_date_timestamp = # TODO |> Calendar.DateTime.Format.unix
    current_timestamp = Calendar.DateTime.now!("GMT") |> Calendar.DateTime.Format.unix
    timestamp_delta = current_timestamp - retrieval_date_timestamp

    if timestamp_delta <= 300 do
      Logger.info(fn ->
        """
        Delay between now and the newest data sample: #{timestamp_delta}s
        Signal is new enough, keeping it.
        """
      end)
      {:ok, signal}
    else
      Logger.warn(fn -> "Signal outdated by #{timestamp_delta}s." end)
      {:error, :outdated, signal}
    end
  end
end
