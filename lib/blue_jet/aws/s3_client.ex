defmodule BlueJet.S3.Client do
  def get_presigned_url(key, method) do
    config = ExAws.Config.new(:s3)
    {:ok, url} = ExAws.S3.presigned_url(config, method, System.get_env("AWS_S3_BUCKET_NAME"), key)

    url
  end

  def delete_object(keys) when is_list(keys) do
    ExAws.S3.delete_all_objects(System.get_env("AWS_S3_BUCKET_NAME"), keys)
    |> ExAws.request()

    :ok
  end

  def delete_object(key) do
    ExAws.S3.delete_object(System.get_env("AWS_S3_BUCKET_NAME"), key)
    |> ExAws.request()

    :ok
  end
end