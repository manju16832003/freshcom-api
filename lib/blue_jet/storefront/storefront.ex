defmodule BlueJet.Storefront do
  use BlueJet, :context

  alias Ecto.Changeset
  alias Ecto.Multi

  alias BlueJet.Identity
  alias BlueJet.Billing

  alias BlueJet.Storefront.Order
  alias BlueJet.Storefront.OrderLineItem
  alias BlueJet.Storefront.Unlock

  def handle_event("billing.payment.created", %{ payment: %{ target_type: "Order", target_id: order_id } }) do
    order = Repo.get!(Order, order_id)

    case order.status do
      "cart" ->
        changeset =
          order
          |> Order.refresh_payment_status()
          |> Changeset.change(status: "opened", opened_at: Ecto.DateTime.utc())

        changeset
        |> Repo.update!()
        |> Order.process(changeset)
      other ->
        {:ok, Order.refresh_payment_status(order)}
    end
  end
  def handle_event("billing.payment.updated", %{ payment: %{ target_type: "Order", target_id: order_id } }) do
    order = Repo.get!(Order, order_id) |> Order.refresh_payment_status()
    {:ok, order}
  end
  def handle_event("billing.refund.created", %{ refund: %{ target_type: "Order", target_id: order_id } }) do
    order = Repo.get!(Order, order_id) |> Order.refresh_payment_status()
    {:ok, order}
  end
  def handle_event(_, data) do
    {:ok, nil}
  end

  ####
  # Order
  ####
  def list_order(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "storefront.list_order") do
      do_list_order(request)
    else
      {:error, reason} -> {:error, :access_denied}
    end
  end
  def do_list_order(request = %AccessRequest{ vas: %{ account_id: account_id }, filter: filter, pagination: pagination }) do
    filter = if !filter[:status] do
      Map.put(filter, :status, "opened")
    else
      filter
    end

    query =
      Order.Query.default()
      |> search([:first_name, :last_name, :code, :email, :phone_number, :id], request.search, request.locale, account_id)
      |> Order.Query.not_cart()
      |> filter_by(
        customer_id: filter[:customer_id],
        status: filter[:status],
        label: filter[:label],
        delivery_address_province: filter[:delivery_address_province],
        delivery_address_city: filter[:delivery_address_city],
        fulfillment_method: filter[:fulfillment_method]
      )
      |> Order.Query.for_account(account_id)
    result_count = Repo.aggregate(query, :count, :id)

    total_query = Order.Query.default() |> Order.Query.for_account(account_id)
    total_count = Repo.aggregate(total_query, :count, :id)

    query = paginate(query, size: pagination[:size], number: pagination[:number])

    orders =
      Repo.all(query)
      |> Repo.preload(Order.Query.preloads(request.preloads))
      |> Translation.translate(request.locale)

    response = %AccessResponse{
      meta: %{
        total_count: total_count,
        result_count: result_count,
      },
      data: orders
    }

    {:ok, response}
  end

  def create_order(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "storefront.create_order") do
      do_create_order(request)
    else
      {:error, reason} -> {:error, :access_denied}
    end
  end
  def do_create_order(request = %{ vas: vas }) do
    fields = Map.merge(request.fields, %{ "account_id" => vas[:account_id], "customer_id" => vas[:customer_id] || request.fields["customer_id"] })
    changeset = Order.changeset(%Order{}, fields)

    with {:ok, order} <- Repo.insert(changeset) do
      order = Repo.preload(order, Order.Query.preloads(request.preloads))
      {:ok, %AccessResponse{ data: order }}
    else
      {:error, changeset} ->
        {:error, %AccessResponse{ errors: changeset.errors }}
    end
  end

  def get_order(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "storefront.get_order") do
      do_get_order(request)
    else
      {:error, reason} -> {:error, :access_denied}
    end
  end
  def do_get_order(request = %AccessRequest{ vas: vas, params: %{ order_id: order_id } }) do
    order = Order |> Order.Query.for_account(vas[:account_id]) |> Repo.get(order_id)

    if order do
      order =
        order
        |> Repo.preload(Order.Query.preloads(request.preloads))
        |> Translation.translate(request.locale)
      {:ok, %AccessResponse{ data: order }}
    else
      {:error, :not_found}
    end
  end

  # TODO: Check if customer already have unlock
  def update_order(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "storefront.update_order") do
      do_update_order(request)
    else
      {:error, reason} -> {:error, :access_denied}
    end
  end
  def do_update_order(request = %AccessRequest{ vas: vas, params: %{ order_id: order_id }}) do
    order = Order |> Order.Query.for_account(vas[:account_id]) |> Repo.get(order_id)
    changeset = Order.changeset(order, request.fields, request.locale)

    with %Order{} <- order,
         changeset <- Order.changeset(order, request.fields, request.locale),
          {:ok, order} <- Repo.update(changeset)
    do
      order =
        order
        |> Repo.preload(Order.Query.preloads(request.preloads))
        |> Translation.translate(request.locale)

      {:ok, %AccessResponse{ data: order }}
    else
      {:error, changeset} ->
        {:error, %AccessResponse{ errors: changeset.errors }}
    end
  end

  def delete_order(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "storefront.delete_order") do
      do_delete_order(request)
    else
      {:error, reason} -> {:error, :access_denied}
    end
  end
  def do_delete_order(%AccessRequest{ vas: vas, params: %{ order_id: order_id } }) do
    order = Order |> Order.Query.for_account(vas[:account_id]) |> Repo.get(order_id)

    if order do
      payments = Billing.list_payment_for_target("Order", order_id)
      case length(payments) do
        0 ->
          Repo.delete!(order)
          {:ok, %AccessResponse{}}
        other ->
          errors = %{ id: {"Order with existing payment can not be deleted", [code: :order_with_payment_cannot_be_deleted, full_error_message: true]} }
          {:error, %AccessResponse{ errors: errors }}
      end
    else
      {:error, :not_found}
    end
  end

  ####
  # Order Line Item
  ####
  def create_order_line_item(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "storefront.create_order_line_item") do
      do_create_order_line_item(request)
    else
      {:error, reason} -> {:error, :access_denied}
    end
  end
  def do_create_order_line_item(request = %AccessRequest{ vas: vas }) do
    fields = Map.merge(request.fields, %{ "account_id" => vas[:account_id] })
    changeset = OrderLineItem.changeset(%OrderLineItem{}, fields)

    statements =
      Multi.new()
      |> Multi.insert(:oli, changeset)
      |> Multi.run(:balanced_oli, fn(%{ oli: oli }) ->
          {:ok, OrderLineItem.balance!(oli)}
         end)
      |> Multi.run(:balanced_order, fn(%{ balanced_oli: balanced_oli }) ->
          order = Repo.get!(Order, balanced_oli.order_id)
          {:ok, Order.balance(order)}
         end)
      |> Multi.run(:processed_order, fn(%{ balanced_order: balanced_order }) ->
          Order.process(balanced_order)
         end)
      |> Multi.run(:updated_order, fn(%{ processed_order: order }) ->
          {:ok, Order.refresh_payment_status(order)}
         end)

    case Repo.transaction(statements) do
      {:ok, %{ oli: oli }} ->
        oli = Repo.preload(oli, OrderLineItem.Query.preloads(request.preloads))
        {:ok, %AccessResponse{ data: oli }}
      {:error, _, errors, _} ->
        {:error, %AccessResponse{ errors: errors }}
    end
  end

  def update_order_line_item(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "storefront.update_order_line_item") do
      do_update_order_line_item(request)
    else
      {:error, reason} -> {:error, :access_denied}
    end
  end
  def do_update_order_line_item(request = %AccessRequest{ vas: vas, params: %{ order_line_item_id: oli_id } }) do
    oli = OrderLineItem |> OrderLineItem.Query.for_account(vas[:account_id]) |> Repo.get(oli_id)

    with %OrderLineItem{} <- oli,
         changeset = %{valid?: true} <- OrderLineItem.changeset(oli, request.fields)
    do
      statements =
        Multi.new()
        |> Multi.update(:oli, changeset)
        |> Multi.run(:balanced_oli, fn(%{ oli: oli }) ->
            {:ok, OrderLineItem.balance!(oli)}
           end)
        |> Multi.run(:balanced_order, fn(%{ balanced_oli: oli }) ->
            order = Repo.get!(Order, oli.order_id)
            {:ok, Order.balance(order)}
           end)
        |> Multi.run(:updated_order, fn(%{ balanced_order: order }) ->
            {:ok, Order.refresh_payment_status(order)}
           end)

      {:ok, %{ balanced_oli: oli }} = Repo.transaction(statements)
      {:ok, %AccessResponse{ data: oli }}
    else
      nil -> {:error, :not_found}
      %{ errors: errors } ->
        {:error, %AccessResponse{ errors: errors }}
    end
  end

  def delete_order_line_item(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "storefront.delete_order_line_item") do
      do_delete_order_line_item(request)
    else
      {:error, reason} -> {:error, :access_denied}
    end
  end
  def do_delete_order_line_item(request = %AccessRequest{ vas: vas, params: %{ order_line_item_id: oli_id } }) do
    oli = OrderLineItem |> OrderLineItem.Query.for_account(vas[:account_id]) |> Repo.get(oli_id)

    statements =
      Multi.new()
      |> Multi.run(:processed_oli, fn(_) ->
          oli = oli |> Repo.preload(:order)
          OrderLineItem.process(oli, :delete)
         end)
      |> Multi.delete(:oli, oli)
      |> Multi.run(:balanced_order, fn(%{ processed_oli: oli }) ->
          {:ok, Order.balance(oli.order)}
         end)
      |> Multi.run(:updated_order, fn(%{ balanced_order: order }) ->
          {:ok, Order.refresh_payment_status(order)}
         end)

    if oli do
      {:ok, _} = Repo.transaction(statements)
      {:ok, %AccessResponse{}}
    else
      {:error, :not_found}
    end
  end

  #
  # Unlock
  #
  def list_unlock(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "storefront.list_unlock") do
      do_list_unlock(request)
    else
      {:error, reason} -> {:error, :access_denied}
    end
  end
  def do_list_unlock(request = %AccessRequest{ vas: %{ account_id: account_id }, filter: filter, pagination: pagination }) do
    query =
      Unlock.Query.default()
      |> filter_by(customer_id: filter[:customer_id])
      |> Unlock.Query.for_account(account_id)
    result_count = Repo.aggregate(query, :count, :id)

    total_query = Unlock |> Unlock.Query.for_account(account_id)
    total_count = Repo.aggregate(total_query, :count, :id)

    query = paginate(query, size: pagination[:size], number: pagination[:number])

    unlocks =
      Repo.all(query)
      |> Repo.preload(Unlock.Query.preloads(request.preloads))
      |> Unlock.put_external_resources(request.preloads)
      |> Translation.translate(request.locale)

    response = %AccessResponse{
      meta: %{
        total_count: total_count,
        result_count: result_count,
      },
      data: unlocks
    }

    {:ok, response}
  end
end
