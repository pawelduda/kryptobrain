defmodule KryptoBrain.Bridge.KryptoJanusz do
  use Export.Python

  @predict_script_path "~/kryptojanusz/v2"
  @columns ["date", "high", "low", "open", "close", "volume", "quoteVolume", "weightedAverage"]

  def most_recent_prediction(alt_symbol) do
    ten_days_ago_gmt_timestamp =
      Calendar.DateTime.now!("GMT")
      |> Timex.shift(days: -2, minutes: -30)
      |> Calendar.DateTime.Format.unix

    poloniex_api_url = poloniex_prices_api_url(alt_symbol, ten_days_ago_gmt_timestamp)
    {:ok, python} = Python.start(python_path: Path.expand(@predict_script_path))
    prediction_data = Python.call(python, "predictor", "predict_newest", [poloniex_api_url, @columns, "BTC_#{alt_symbol}"])
    Python.stop(python)
    prediction_data
  end

  defp poloniex_prices_api_url(alt_symbol, start_unix, end_unix \\ 9_999_999_999) do
    "https://poloniex.com/public?command=returnChartData&currencyPair=BTC_#{alt_symbol}&start=#{start_unix}&end=#{end_unix}&period=300"
  end
end
