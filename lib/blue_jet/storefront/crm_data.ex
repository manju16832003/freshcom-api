defmodule BlueJet.Storefront.CrmData do
  alias BlueJet.Crm.{Customer, PointAccount, PointTransaction}

  @crm_data Application.get_env(:blue_jet, :storefront)[:crm_data]

  @callback get_customer(String.t) :: Customer.t
  @callback get_point_account(String.t) :: PointAccount.t
  @callback create_point_transaction(map) :: PointTransaction.t
  @callback update_point_transaction(String.t, map) :: PointTransaction.t
  @callback get_point_transaction(String.t) :: PointTransaction.t

  defdelegate get_customer(id), to: @crm_data
  defdelegate get_point_account(id), to: @crm_data
  defdelegate create_point_transaction(fields), to: @crm_data
  defdelegate update_point_transaction(id, fields), to: @crm_data
  defdelegate get_point_transaction(id), to: @crm_data
end