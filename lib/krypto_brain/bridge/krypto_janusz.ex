defmodule KryptoBrain.Bridge.KryptoJanusz do
  require Logger
  use Export.Python
  use GenServer

  @predict_script_path "~/kryptojanusz/v2"
  @columns ["date", "high", "low", "open", "close", "volume", "quoteVolume", "weightedAverage"]

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    {:ok, _python} = Python.start(python_path: Path.expand(@predict_script_path))
  end

  def handle_call({:most_recent_prediction, alt_symbol}, _from, python) do
    ten_days_ago_gmt_timestamp =
      Calendar.DateTime.now!("GMT")
      |> Timex.shift(days: -2, minutes: -30)
      |> Calendar.DateTime.Format.unix

    poloniex_api_url = poloniex_prices_api_url(alt_symbol, ten_days_ago_gmt_timestamp)

    {prediction, newest_dataset_timestamp} =
      fn -> Python.call(python, predict_newest(poloniex_api_url, @columns, "BTC_#{alt_symbol}"), from_file: "predictor") end
      |> Task.async
      |> Task.await(15_000)

    Logger.warn(fn ->
      current_timestamp = Calendar.DateTime.now!("GMT") |> Calendar.DateTime.Format.unix
      timestamp_delta = current_timestamp - newest_dataset_timestamp
      "[#{alt_symbol}] Delay between now and the newest data sample: #{timestamp_delta}s"
    end)

    {:reply, prediction, python}
  end

  def terminate(_reason, python) do
    Python.stop(python)
  end

  defp poloniex_prices_api_url(alt_symbol, start_unix, end_unix \\ 9_999_999_999) do
    "https://poloniex.com/public?command=returnChartData&currencyPair=BTC_#{alt_symbol}&start=#{start_unix}&end=#{end_unix}&period=300"
  end
end
