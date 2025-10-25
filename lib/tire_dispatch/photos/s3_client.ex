defmodule TireDispatch.Photos.S3Client do
  @moduledoc """
  Behaviour for AWS S3 client interactions.
  """

  @callback upload(String.t(), binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  @callback delete(String.t()) :: :ok | {:error, term()}
  @callback get_presigned_url(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
end
