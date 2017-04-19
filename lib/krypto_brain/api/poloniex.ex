defmodule KryptoBrain.Api.Poloniex do
  @wsuri "wss://api.poloniex.com"
  @topic "ticker"

  def subscribe_to_ticker do
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
    [ currency_pair, last, lowest_ask, highest_bid, percent_change,
      base_volume, quote_volume, is_frozen, l24_hr_high, l24_hr_low ] = data
  end
end
