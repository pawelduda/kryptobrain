defmodule KryptoBrain.Schemas.PriceHistory do
  use Ecto.Schema

  schema "price_history" do
    field :currency_pair, :string
    field :price, :decimal
    field :lowest_ask, :decimal
    field :highest_bid, :decimal
    field :percent_change, :float
    field :base_volume, :float
    field :quote_volume, :float
    field :is_frozen, :boolean
    field :l24_hr_high, :decimal
    field :l24_hr_low, :decimal

    timestamps()
  end
end
