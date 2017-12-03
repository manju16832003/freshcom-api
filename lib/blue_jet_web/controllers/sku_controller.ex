defmodule BlueJetWeb.StockableController do
  use BlueJetWeb, :controller

  alias JaSerializer.Params
  alias BlueJet.Goods

  action_fallback BlueJetWeb.FallbackController

  plug :scrub_params, "data" when action in [:create, :update]

  def index(conn = %{ assigns: assigns }, params) do
    request = %AccessRequest{
      vas: assigns[:vas],
      search: params["search"],
      filter: assigns[:filter],
      pagination: %{ size: assigns[:page_size], number: assigns[:page_number] },
      preloads: assigns[:preloads],
      locale: assigns[:locale]
    }

    {:ok, %AccessResponse{ data: stockables, meta: meta }} = Goods.list_stockable(request)

    render(conn, "index.json-api", data: stockables, opts: [meta: camelize_map(meta), include: conn.query_params["include"]])
  end

  def create(conn = %{ assigns: assigns = %{ vas: vas } }, %{ "data" => data = %{ "type" => "Stockable" } }) do
    request = %AccessRequest{
      vas: assigns[:vas],
      fields: Params.to_attributes(data),
      preloads: assigns[:preloads]
    }

    case Goods.create_stockable(request) do
      {:ok, %AccessResponse{ data: stockable }} ->
        conn
        |> put_status(:created)
        |> render("show.json-api", data: stockable, opts: [include: conn.query_params["include"]])
      {:error, %AccessResponse{ errors: errors }} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:errors, data: extract_errors(errors))
    end
  end

  def show(conn = %{ assigns: assigns = %{ vas: vas } }, %{ "id" => stockable_id }) do
    request = %AccessRequest{
      vas: assigns[:vas],
      params: %{ stockable_id: stockable_id },
      preloads: assigns[:preloads],
      locale: assigns[:locale]
    }

    {:ok, %AccessResponse{ data: stockable }} = Goods.get_stockable(request)

    render(conn, "show.json-api", data: stockable, opts: [include: conn.query_params["include"]])
  end

  def update(conn = %{ assigns: assigns = %{ vas: vas } }, %{ "id" => stockable_id, "data" => data = %{ "type" => "Stockable" } }) do
    request = %AccessRequest{
      vas: assigns[:vas],
      params: %{ stockable_id: stockable_id },
      fields: Params.to_attributes(data),
      preloads: assigns[:preloads],
      locale: assigns[:locale]
    }

    case Goods.update_stockable(request) do
      {:ok, %AccessResponse{ data: stockable }} ->
        render(conn, "show.json-api", data: stockable, opts: [include: conn.query_params["include"]])
      {:error, %AccessResponse{ errors: errors }} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:errors, data: extract_errors(errors))
    end
  end

  def delete(conn = %{ assigns: assigns = %{ vas: vas } }, %{ "id" => stockable_id }) do
    request = %AccessRequest{
      vas: assigns[:vas],
      params: %{ stockable_id: stockable_id }
    }

    Goods.delete_stockable(request)

    send_resp(conn, :no_content, "")
  end
end
