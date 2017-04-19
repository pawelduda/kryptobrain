defmodule KryptoBrain.Repo.Migrations.CreatePriceHistory do
  use Ecto.Migration

  def change do
    create table(:price_history) do
      add :currency_pair, :string
      add :price, :decimal
      add :lowest_ask, :decimal
      add :highest_bid, :decimal
      add :percent_change, :float
      add :base_volume, :float
      add :quote_volume, :float
      add :is_frozen, :boolean
      add :l24_hr_high, :decimal
      add :l24_hr_low, :decimal

      timestamps()
    end
  end
end
