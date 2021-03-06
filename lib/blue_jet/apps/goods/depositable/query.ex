defmodule BlueJet.Goods.Depositable.Query do
  use BlueJet, :query

  alias BlueJet.Goods.Depositable

  @searchable_fields [
    :code,
    :name
  ]

  @filterable_fields [
    :id,
    :status,
    :label
  ]

  def default() do
    from d in Depositable
  end

  def for_account(query, account_id) do
    from d in query, where: d.account_id == ^account_id
  end

  def search(query, keyword, locale, default_locale) do
    search(query, @searchable_fields, keyword, locale, default_locale, Depositable.translatable_fields())
  end

  def filter_by(query, filter) do
    filter_by(query, filter, @filterable_fields)
  end

  def preloads(_, _) do
    []
  end
end