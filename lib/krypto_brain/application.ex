defmodule KryptoBrain.Application do
  @moduledoc false

  use Application
  require KryptoBrain.Constants
  alias KryptoBrain.Constants, as: C

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      supervisor(KryptoBrain.Repo, []),
      supervisor(KryptoBrain.Trading.StateHolder, []),

      worker(KryptoBrain.Trading.Trader, ["XEM", 0.0008, C._BTC], id: 1),
      worker(KryptoBrain.Trading.Trader, ["PINK", 0.0008, C._BTC], id: 2),
      worker(KryptoBrain.Trading.Trader, ["MAID", 0.0008, C._BTC], id: 3),
      worker(KryptoBrain.Trading.Trader, ["DGB", 0.0008, C._BTC], id: 4),
    ]

    opts = [strategy: :one_for_one, name: KryptoBrain.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
