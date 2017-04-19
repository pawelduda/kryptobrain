defmodule KryptoBrain.Api.Poloniex do
  @wsuri "wss://api.poloniex.com"
  @topic "ticker"

  def connect do
    # Appropriate labels for these data are, in order:
    # currencyPair, last, lowestAsk, highestBid, percentChange, baseVolume,
    # quoteVolume, isFrozen, 24hrHigh, 24hrLow

    # {:ok, _} = Crossbar.start()
    {:ok, subscriber} = Spell.connect(@wsuri, realm: "realm1", roles: [Spell.Role.Subscriber])
    {:ok, subscription} = Spell.call_subscribe(subscriber, @topic)
  end
end
