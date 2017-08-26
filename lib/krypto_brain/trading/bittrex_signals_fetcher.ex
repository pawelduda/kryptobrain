defmodule KryptoBrain.Trading.BittrexSignalsFetcher do
  alias KryptoBrain.Constants, as: C
  alias KryptoBrain.Trading.{BittrexApi, SignalData}
  require Logger
  require KryptoBrain.Constants

  # This is a manual list of markets to avoid due to reasons such as being delisted, etc.
  # TODO: possibly switch to a more dynamic source of this data, i.e. file or database
  @blacklisted_markets ~w(BTC-HKG BTC-XBB)

  def get_signals do
    market_summaries =
      BittrexApi.get_market_summaries()
      Enum.map(market_summaries, &(Map.take(&1, ["MarketName", "BaseVolume"])))
      |> filter_btc_markets()
      |> reject_blacklisted_markets()

    data = market_summaries
    |> Enum.map(&(Task.async(fn ->
      market_ticks = BittrexApi.get_market_ticks(&1["MarketName"], "hour", true)
      # TODO: refactor code smell
      case market_ticks do
        nil -> nil
        _ -> %{market_name: &1["MarketName"], daily_volume: &1["BaseVolume"], market_ticks: market_ticks}
      end
    end)))
    |> Task.yield_many(60_000)
    |> Enum.map(fn(result) ->
      {%Task{}, {:ok, market_data}} = result;
      market_data
    end)
    |> Enum.filter(&(&1)) # Remove any falsey values
    File.write!("charts_sample_data.txt", :erlang.term_to_binary(data))

    File.read!("charts_sample_data.txt")
    |> :erlang.binary_to_term
    |> Enum.map(fn(market_data) ->
      signal_data = case get_signal(market_data[:market_ticks]) do
        {:ok, signal_data} -> signal_data
        {:error, :outdated, signal_data} -> signal_data # TODO: improve error handling when signal is outdated
      end

      %{market_name: market_data[:market_name], daily_volume: market_data[:daily_volume], signal_data: signal_data}
    end)
  end

  defp get_signal(chart_data) do
    signal_data = %SignalData{} =
      GenServer.call(KryptoBrain.Bridge.KryptoJanusz, {:most_recent_prediction_bittrex, chart_data}, 15_000)

    {:ok, retrieval_date} = (signal_data.retrieval_date_utc <> "Z") |> Calendar.DateTime.Parse.rfc3339_utc
    retrieval_date_timestamp = Calendar.DateTime.Format.unix(retrieval_date)
    current_timestamp = Calendar.DateTime.now_utc |> Calendar.DateTime.Format.unix
    timestamp_delta = current_timestamp - retrieval_date_timestamp

    if timestamp_delta <= 600 do
      Logger.info(fn ->
        """
        Delay between now and the newest data sample: #{timestamp_delta}s
        Signal is new enough, keeping it.
        """
      end)
      {:ok, signal_data}
    else
      Logger.warn(fn -> "Signal outdated by #{timestamp_delta}s." end)
      {:error, :outdated, signal_data}
    end
  end

  defp filter_btc_markets(market_summaries) do
    Enum.filter(market_summaries, fn(market_summary) ->
      [left_market_name_part | _rest] = String.split(market_summary["MarketName"], "-")
      left_market_name_part == "BTC"
    end)
  end

  defp reject_blacklisted_markets(market_summaries) do
    Enum.reject(market_summaries, &(Enum.member?(@blacklisted_markets, &1["MarketName"])))
  end
end
