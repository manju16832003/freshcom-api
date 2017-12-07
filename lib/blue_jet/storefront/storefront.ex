defmodule BlueJet.Storefront do
  use BlueJet, :context

  alias Ecto.Changeset
  alias Ecto.Multi

  alias BlueJet.Identity
  alias BlueJet.Billing

  alias BlueJet.Storefront.Customer
  alias BlueJet.Storefront.Order
  alias BlueJet.Storefront.OrderLineItem
  alias BlueJet.Storefront.Payment
  alias BlueJet.Storefront.StripePaymentError
  alias BlueJet.Storefront.Unlock
  alias BlueJet.Storefront.Refund
  alias BlueJet.Storefront.Card

  def handle_event("billing.payment.before_create", %{ fields: fields, owner: %{ type: "Customer", id: customer_id } }) do
    customer = Repo.get!(Customer, customer_id)
    customer = Customer.preprocess(customer, payment_processor: "stripe")
    fields = Map.put(fields, "stripe_customer_id", customer.stripe_customer_id)
    {:ok, fields}
  end
  def handle_event("billing.payment.before_create", %{ fields: fields }), do: {:ok, fields}

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

  ####
  # Customer
  ####
  def list_customer(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "storefront.list_customer") do
      do_list_customer(request)
    else
      {:error, reason} -> {:error, :access_denied}
    end
  end
  def do_list_customer(request = %AccessRequest{ vas: %{ account_id: account_id }, filter: filter, pagination: pagination }) do
    query =
      Customer.Query.default()
      |> search([:first_name, :last_name, :other_name, :code, :email, :phone_number, :id], request.search, request.locale, account_id)
      |> filter_by(status: request.filter[:status], label: request.filter[:label], delivery_address_country_code: request.filter[:delivery_address_country_code])
      |> Customer.Query.for_account(account_id)
    result_count = Repo.aggregate(query, :count, :id)

    total_query = Customer |> Customer.Query.for_account(account_id)
    total_count = Repo.aggregate(total_query, :count, :id)

    query = paginate(query, size: pagination[:size], number: pagination[:number])

    customers =
      Repo.all(query)
      |> Repo.preload(Customer.Query.preloads(request.preloads))
      |> Translation.translate(request.locale)

    response = %AccessResponse{
      meta: %{
        total_count: total_count,
        result_count: result_count,
      },
      data: customers
    }

    {:ok, response}
  end

  def create_customer(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "storefront.create_customer") do
      do_create_customer(request)
    else
      {:error, reason} -> {:error, :access_denied}
    end
  end
  def do_create_customer(request = %{ vas: vas }) do
    fields = Map.merge(request.fields, %{ "account_id" => vas[:account_id], "role" => "customer" })

    statements =
      Multi.new()
      |> Multi.run(:user, fn(_) ->
          if fields["status"] == "registered" do
            case Identity.create_user(%AccessRequest{ vas: vas, fields: fields}) do
              {:ok, %{ data: user }} -> {:ok, user}
              other -> other
            end
          else
            {:ok, nil}
          end
         end)
      |> Multi.run(:changeset, fn(%{ user: user }) ->
          fields = if user do
            Map.merge(fields, %{ "user_id" => user.id })
          else
            fields
          end

          changeset = Customer.changeset(%Customer{}, fields)
          {:ok, changeset}
         end)
      |> Multi.run(:customer, fn(%{ changeset: changeset }) ->
          Repo.insert(changeset)
         end)

    case Repo.transaction(statements) do
      {:ok, %{ customer: customer }} ->
        customer = Repo.preload(customer, Customer.Query.preloads(request.preloads))
        {:ok, %AccessResponse{ data: customer }}
      {:error, :user, response, _} ->
        {:error, response}
      {:error, :customer, changeset, _} ->
        {:error, %AccessResponse{ errors: changeset.errors }}
    end
  end

  def get_customer(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "storefront.get_customer") do
      do_get_customer(%{ request | role: role })
    else
      {:error, reason} -> {:error, :access_denied}
    end
  end
  def do_get_customer(request = %AccessRequest{ vas: vas, params: %{ "id" => id } }) do
    customer = Customer |> Customer.Query.for_account(vas[:account_id]) |> Repo.get(id)
    do_get_customer_response(customer, request)
  end
  def do_get_customer(request = %AccessRequest{ role: "guest", vas: vas, params: params = %{ "code" => code } }) when map_size(params) >= 2 do
    customer = Customer |> Customer.Query.for_account(vas[:account_id]) |> Repo.get_by(code: code, status: "guest")

    params = Map.drop(params, ["code"])
    if Customer.match?(customer, params) do
      do_get_customer_response(customer, request)
    else
      {:error, :not_found}
    end
  end
  def do_get_customer(%AccessRequest{ role: "guest" }), do: {:error, :not_found}
  def do_get_customer(request = %AccessRequest{ vas: vas, params: %{ code: code } }) do
    customer = Customer |> Customer.Query.for_account(vas[:account_id]) |> Repo.get_by(code: code)
    do_get_customer_response(customer, request)
  end
  def do_get_customer(_), do: {:error, :not_found}

  defp do_get_customer_response(nil, _) do
    {:error, :not_found}
  end
  defp do_get_customer_response(customer, request) do
    customer =
      customer
      |> Repo.preload(Customer.Query.preloads(request.preloads))
      |> Customer.put_external_resources(request.preloads)
      |> Translation.translate(request.locale)

    {:ok, %AccessResponse{ data: customer }}
  end

  def update_customer(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "storefront.update_customer") do
      do_update_customer(%{ request | role: role })
    else
      {:error, reason} -> {:error, :access_denied}
    end
  end
  def do_update_customer(request = %AccessRequest{ role: role, vas: vas, params: %{ "id" => id } }) do
    customer_query = Customer |> Customer.Query.for_account(vas[:account_id])

    customer = case role do
      "guest" -> Repo.get_by(customer_query, id: id, status: "guest")
      "customer" -> Repo.get(customer_query, id) # TODO: only find the customer of the user
      other -> Repo.get(customer_query, id)
    end

    statements =
      Multi.new()
      |> Multi.run(:user, fn(_) ->
          cond do
            customer.status == "guest" && request.fields["status"] == "registered" ->
              case Identity.create_user(%AccessRequest{ vas: vas, fields: request.fields}) do
                {:ok, %{ data: user }} -> {:ok, user}
                other -> other
              end
            true -> {:ok, nil}
          end
         end)
      |> Multi.run(:changeset, fn(%{ user: user }) ->
          fields = if user do
            Map.merge(request.fields, %{ "user_id" => user.id, "account_id" => vas[:account_id] })
          else
            request.fields
          end

          changeset = Customer.changeset(customer, fields)
          {:ok, changeset}
         end)
      |> Multi.run(:customer, fn(%{ changeset: changeset}) ->
          Repo.update(changeset)
         end)

    with %Customer{} <- customer,
         {:ok, %{ customer: customer }} <- Repo.transaction(statements)
    do
      customer =
        customer
        |> Repo.preload(Customer.Query.preloads(request.preloads))
        |> Customer.put_external_resources(request.preloads)
        |> Translation.translate(request.locale)

      {:ok, %AccessResponse{ data: customer }}
    else
      nil ->
        {:error, :not_found}
      {:error, :user, response, _} ->
        {:error, response}
      {:error, :customer, changeset, _} ->
        {:error, %AccessResponse{ errors: changeset.errors }}
    end
  end

  def delete_customer(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "storefront.delete_customer") do
      do_delete_customer(request)
    else
      {:error, reason} -> {:error, :access_denied}
    end
  end
  def do_delete_customer(request = %AccessRequest{ vas: vas, params: %{ customer_id: customer_id } }) do
    customer = Customer |> Customer.Query.for_account(vas[:account_id]) |> Repo.get(customer_id)

    statements =
      Multi.new()
      |> Multi.run(:delete_user, fn(_) ->
          if customer.user_id do
            Identity.delete_user(%AccessRequest{ vas: vas, params: %{ user_id: customer.user_id } })
          else
            {:ok, nil}
          end
         end)
      |> Multi.delete(:deleted_customer, customer)

    if customer do
      {:ok, _} = Repo.transaction(statements)
      {:ok, %AccessResponse{}}
    else
      {:error, :not_found}
    end
  end
end
