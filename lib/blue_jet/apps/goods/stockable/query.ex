defmodule BlueJet.Goods.Stockable.Query do
  use BlueJet, :query

  alias BlueJet.Goods.Stockable

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
    from s in Stockable
  end

  def for_account(query, account_id) do
    from s in query, where: s.account_id == ^account_id
  end

  def search(query, keyword, locale, default_locale) do
    search(query, @searchable_fields, keyword, locale, default_locale, Stockable.translatable_fields())
  end

  def filter_by(query, filter) do
    filter_by(query, filter, @filterable_fields)
  end

  def preloads(_, _) do
    []
  end
end