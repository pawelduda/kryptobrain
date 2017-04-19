defmodule KryptoBrain.Api.Poloniex do
  @wsuri "wss://api.poloniex.com"
  @topic "ticker"

  def start_link do
    Task.start_link(fn -> subscribe_to_ticker() end)
    {:ok, self}
  end

  defp subscribe_to_ticker do
    # {:ok, _} = Crossbar.start()
    {:ok, connection} = Spell.connect(@wsuri, realm: "realm1", roles: [Spell.Role.Subscriber])
    {:ok, subscription} = Spell.call_subscribe(connection, @topic)

    receive_event(connection, subscription)
  end

  defp receive_event(connection, subscription) do
    case Spell.receive_event(connection, subscription) do
      {:ok, event} -> save_event(event)
      {:error, reason} -> {:error, reason}
    end

    receive_event(connection, subscription)
  end

  defp save_event(%{arguments: data}) do
    # Appropriate labels for these data are, in order:
    # currencyPair, last, lowestAsk, highestBid, percentChange, baseVolume,
    # quoteVolume, isFrozen, 24hrHigh, 24hrLow
    [currency_pair, last_price, lowest_ask, highest_bid, percent_change,
     base_volume, quote_volume, is_frozen, l24_hr_high, l24_hr_low] = data

    {last_price, _} = Float.parse(last_price)
    {lowest_ask, _} = Float.parse(lowest_ask)
    {highest_bid, _} = Float.parse(highest_bid)
    {percent_change, _} = Float.parse(percent_change)
    {base_volume, _} = Float.parse(base_volume)
    {quote_volume, _} = Float.parse(quote_volume)
    {l24_hr_high, _} = Float.parse(l24_hr_high)
    {l24_hr_low, _} = Float.parse(l24_hr_low)
    is_frozen = cond do
      0 -> false
      1 -> true
    end

    %PriceHistory{
      currency_pair: currency_pair,
      price: last_price,
      lowest_ask: lowest_ask,
      highest_bid: highest_bid,
      percent_change: percent_change,
      base_volume: base_volume,
      quote_volume: quote_volume,
      is_frozen: is_frozen,
      l24_hr_high: l24_hr_high,
      l24_hr_low: l24_hr_low
    } |> KryptoBrain.Repo.insert!
  end
end
