defmodule BlueJet.Repo.Migrations.CreateOrder do
  use Ecto.Migration

  def change do
    create table(:orders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all), null: false
      add :code, :string
      add :status, :string, null: false
      add :system_tag, :string
      add :label, :string

      add :email, :string
      add :first_name, :string
      add :last_name, :string
      add :phone_number, :string

      add :delivery_address_line_one, :string
      add :delivery_address_line_two, :string
      add :delivery_address_province, :string
      add :delivery_address_city, :string
      add :delivery_address_country_code, :string
      add :delivery_address_postal_code, :string

      add :sub_total_cents, :integer, null: false, default: 0
      add :tax_one_cents, :integer, null: false, default: 0
      add :tax_two_cents, :integer, null: false, default: 0
      add :tax_three_cents, :integer, null: false, default: 0
      add :grand_total_cents, :integer, null: false, default: 0

      add :is_estimate, :boolean, null: false, default: false

      add :fulfillment_method, :string

      add :placed_at, :utc_datetime
      add :confirmation_email_sent_at, :utc_datetime
      add :receipt_email_sent_at, :utc_datetime

      add :customer_id, references(:customers, type: :binary_id, on_delete: :delete_all)
      add :created_by_id, references(:users, type: :binary_id)

      add :custom_data, :map, null: false, default: "{}"
      add :translations, :map, null: false, default: "{}"

      timestamps()
    end

    create index(:orders, [:account_id])
    create index(:orders, [:customer_id])
    create index(:orders, [:created_by_id])
  end
end
