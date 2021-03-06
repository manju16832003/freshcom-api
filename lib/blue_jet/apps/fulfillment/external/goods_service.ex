defmodule BlueJet.Fulfillment.GoodsService do
  alias BlueJet.Goods.{Stockable, Unlockable, Depositable}

  @goods_service Application.get_env(:blue_jet, :fulfillment)[:goods_service]

  @callback get_stockable(map, map) :: Stockable.t | nil
  @callback get_unlockable(map, map) :: Unlockable.t | nil
  @callback get_depositable(map, map) :: Depositable.t | nil

  defdelegate get_stockable(fields, opts), to: @goods_service
  defdelegate get_unlockable(fields, opts), to: @goods_service
  defdelegate get_depositable(fields, opts), to: @goods_service
end