defmodule KryptoBrain.Api.Poloniex do
  @wsuri "wss://api.poloniex.com"

  def connect do
    # {:ok, _} = Crossbar.start()
    {:ok, subscriber} = Spell.connect(@wsuri, realm: "realm1", roles: [Spell.Role.Subscriber])
    {:ok, subscription} = Spell.call_subscribe(subscriber, "ticker")
  end
end
