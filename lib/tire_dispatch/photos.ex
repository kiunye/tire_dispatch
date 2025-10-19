defmodule TireDispatch.Photos do
  @moduledoc """
  Context for handling photo uploads to AWS S3.
  """

  require Logger

  @allowed_extensions [".jpg", ".jpeg", ".png"]
  # 5MB
  @max_file_size_bytes 5 * 1024 * 1024

  @doc """
  Uploads a photo to AWS S3 with thumbnail generation.

  ## Arguments

    * `file_path` - Local path to the file to upload
    * `job_id` - UUID of the job this photo belongs to
    * `photo_type` - Type of photo (:before, :after, or :issue)

  ## Returns

    * `{:ok, %{original: original_url, thumbnail: thumbnail_url}}` on success
    * `{:error, reason}` if validation or upload fails

  ## Examples

      iex> upload_photo_to_s3("/tmp/photo.jpg", "job-uuid", :before)
      {:ok, %{
        original: "https://s3.amazonaws.com/bucket/jobs/job-uuid/before-1234567890.jpg",
        thumbnail: "https://s3.amazonaws.com/bucket/jobs/job-uuid/before-1234567890-thumb.jpg"
      }}

  """
  def upload_photo_to_s3(file_path, job_id, photo_type) do
    with :ok <- validate_file(file_path),
         {:ok, s3_key} <- generate_s3_key(job_id, photo_type, file_path),
         {:ok, file_binary} <- File.read(file_path),
         {:ok, _response} <- upload_to_s3(s3_key, file_binary),
         {:ok, thumbnail_url} <- generate_and_upload_thumbnail(file_path, job_id, photo_type) do
      original_url = build_public_url(s3_key)

      Logger.info("Photo and thumbnail uploaded successfully", %{
        job_id: job_id,
        photo_type: photo_type,
        s3_key: s3_key,
        original_url: original_url,
        thumbnail_url: thumbnail_url
      })

      {:ok, %{original: original_url, thumbnail: thumbnail_url}}
    else
      {:error, reason} = error ->
        Logger.error("Photo upload failed", %{
          job_id: job_id,
          photo_type: photo_type,
          file_path: file_path,
          reason: inspect(reason)
        })

        error
    end
  end

  @doc """
  Validates a file for upload.

  Checks:
  - File exists
  - File extension is allowed (JPEG, PNG)
  - File size is within limit (max 5MB)

  ## Arguments

    * `file_path` - Path to the file to validate

  ## Returns

    * `:ok` if validation passes
    * `{:error, reason}` if validation fails
  """
  def validate_file(file_path) do
    cond do
      !File.exists?(file_path) ->
        {:error, "File does not exist"}

      !valid_extension?(file_path) ->
        {:error, "Invalid file type. Only JPEG and PNG are allowed"}

      !valid_size?(file_path) ->
        {:error, "File size exceeds 5MB limit"}

      true ->
        :ok
    end
  end

  # Private functions

  defp valid_extension?(file_path) do
    extension = Path.extname(file_path) |> String.downcase()
    extension in @allowed_extensions
  end

  defp valid_size?(file_path) do
    case File.stat(file_path) do
      {:ok, %{size: size}} -> size <= @max_file_size_bytes
      {:error, _} -> false
    end
  end

  defp generate_s3_key(job_id, photo_type, file_path) do
    extension = Path.extname(file_path)
    timestamp = System.system_time(:second)
    s3_key = "jobs/#{job_id}/#{photo_type}-#{timestamp}#{extension}"
    {:ok, s3_key}
  end

  defp upload_to_s3(s3_key, file_binary) do
    bucket = Application.get_env(:tire_dispatch, :s3_bucket)

    ExAws.S3.put_object(bucket, s3_key, file_binary, acl: :public_read)
    |> ExAws.request()
    |> case do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, "S3 upload failed: #{inspect(reason)}"}
    end
  end

  defp build_public_url(s3_key) do
    bucket = Application.get_env(:tire_dispatch, :s3_bucket)
    region = Application.get_env(:ex_aws, :region, "us-east-1")

    "https://#{bucket}.s3.#{region}.amazonaws.com/#{s3_key}"
  end

  defp generate_and_upload_thumbnail(file_path, job_id, photo_type) do
    thumbnail_path = generate_thumbnail(file_path)

    with {:ok, thumbnail_s3_key} <- generate_thumbnail_s3_key(job_id, photo_type, file_path),
         {:ok, thumbnail_binary} <- File.read(thumbnail_path),
         {:ok, _response} <- upload_to_s3(thumbnail_s3_key, thumbnail_binary) do
      # Clean up temporary thumbnail file
      File.rm(thumbnail_path)
      {:ok, build_public_url(thumbnail_s3_key)}
    else
      {:error, _reason} = error ->
        # Clean up temporary thumbnail file on error
        if File.exists?(thumbnail_path), do: File.rm(thumbnail_path)
        error
    end
  end

  defp generate_thumbnail(file_path) do
    thumbnail_path = file_path <> ".thumb"

    file_path
    |> Mogrify.open()
    |> Mogrify.resize_to_limit("300x300")
    |> Mogrify.save(path: thumbnail_path)

    thumbnail_path
  end

  defp generate_thumbnail_s3_key(job_id, photo_type, file_path) do
    extension = Path.extname(file_path)
    timestamp = System.system_time(:second)
    s3_key = "jobs/#{job_id}/#{photo_type}-#{timestamp}-thumb#{extension}"
    {:ok, s3_key}
  end
end
