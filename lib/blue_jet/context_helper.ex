defmodule BlueJet.ContextHelpers do
  import Ecto.Query

  alias BlueJet.Translation

  def paginate(query, size: size, number: number) do
    limit = size
    offset = size * (number - 1)

    query
    |> limit(^limit)
    |> offset(^offset)
  end

  def search(model, _, nil, _, _), do: model
  def search(model, _, "", _, _), do: model
  def search(model, columns, keyword, locale, account_id) do
    default_locale = Translation.default_locale(%{ account_id: account_id })
    if locale == default_locale do
      search_default_locale(model, columns, keyword)
    else
      search_translations(model, columns, keyword, locale)
    end
  end
  def search_default_locale(model, columns, keyword) do
    keyword = "%#{keyword}%"

    Enum.reduce(columns, model, fn(column, query) ->
      from q in query, or_where: ilike(fragment("?::varchar", field(q, ^column)), ^keyword)
    end)
  end
  def search_translations(model, columns, keyword, locale) do
    keyword = "%#{keyword}%"

    Enum.reduce(columns, model, fn(column, query) ->
      if Enum.member?(model.translatable_fields(), column) do
        column = Atom.to_string(column)
        from q in query, or_where: ilike(fragment("?->?->>?", q.translations, ^locale, ^column), ^keyword)
      else
        from q in query, or_where: ilike(fragment("?::varchar", field(q, ^column)), ^keyword)
      end
    end)
  end

  def filter_by(query, filter) do
    filter = Enum.filter(filter, fn({_, value}) -> value end)

    Enum.reduce(filter, query, fn({k, v}, acc_query) ->
      if is_list(v) do
        from q in acc_query, where: field(q, ^k) in ^v
      else
        from q in acc_query, where: field(q, ^k) == ^v
      end
    end)
  end

  def ids_only(query) do
    from q in query, select: q.id
  end
end