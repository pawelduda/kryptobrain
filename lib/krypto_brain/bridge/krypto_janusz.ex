defmodule KryptoBrain.Bridge.KryptoJanusz do
  use Export.Python

  @predict_script_path "~/kryptojanusz/v2"
  @columns ["date", "high", "low", "open", "close", "volume", "quoteVolume", "weightedAverage"]

  def most_recent_prediction(currency_pair \\ "BTC_ETH") do
    ten_days_ago_gmt_timestamp =
      Calendar.DateTime.now!("GMT")
      |> Timex.shift(days: -10, minutes: -30)
      |> Calendar.DateTime.Format.unix

    %HTTPoison.Response{body: poloniex_response} =
      poloniex_prices_api_url(currency_pair, ten_days_ago_gmt_timestamp) |> HTTPoison.get!

    {:ok, python} = Python.start(python_path: Path.expand(@predict_script_path))
    Python.call(python, "predictor", "predict_newest", [poloniex_response, @columns])
  end

  defp poloniex_prices_api_url(currency_pair, start_unix, end_unix \\ 9_999_999_999) do
    "https://poloniex.com/public?command=returnChartData&currencyPair=#{currency_pair}&start=#{start_unix}&end=#{end_unix}&period=300"
  end
end
