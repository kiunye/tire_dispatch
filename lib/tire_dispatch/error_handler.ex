defmodule TireDispatch.ErrorHandler do
  @moduledoc """
  Custom error handler for enhanced error tracking and reporting.

  This module provides utilities for capturing errors with additional context
  and sending them to Sentry for monitoring and alerting.
  """

  require Logger

  @doc """
  Captures an exception with additional context and sends it to Sentry.

  ## Arguments

    * `exception` - The exception struct
    * `stacktrace` - The stacktrace from the exception
    * `context` - Map of additional context (job_id, transaction_id, user_id, etc.)

  ## Examples

      try do
        # Some operation
      rescue
        exception ->
          ErrorHandler.capture_exception(exception, __STACKTRACE__, %{
            job_id: job.id,
            user_id: user.id
          })
      end
  """
  def capture_exception(exception, stacktrace, context \\ %{}) do
    # Log the error with context
    Logger.error("Exception captured",
      exception: Exception.message(exception),
      stacktrace: Exception.format_stacktrace(stacktrace),
      context: inspect(context)
    )

    # Send to Sentry if configured
    if sentry_configured?() do
      Sentry.capture_exception(exception,
        stacktrace: stacktrace,
        extra: context,
        tags: extract_tags(context)
      )
    end

    :ok
  end

  @doc """
  Captures a message with additional context and sends it to Sentry.

  Useful for logging important events or errors that aren't exceptions.

  ## Arguments

    * `message` - The message string
    * `level` - Severity level (:error, :warning, :info)
    * `context` - Map of additional context

  ## Examples

      ErrorHandler.capture_message("Payment processing timeout", :error, %{
        transaction_id: transaction.id,
        payment_method: :stripe
      })
  """
  def capture_message(message, level \\ :error, context \\ %{}) do
    # Log the message with context
    log_level =
      case level do
        :error -> :error
        :warning -> :warning
        :info -> :info
        _ -> :error
      end

    Logger.log(log_level, message, context: inspect(context))

    # Send to Sentry if configured
    if sentry_configured?() do
      Sentry.capture_message(message,
        level: level,
        extra: context,
        tags: extract_tags(context)
      )
    end

    :ok
  end

  @doc """
  Wraps a function call with error handling and automatic Sentry reporting.

  ## Arguments

    * `fun` - Function to execute
    * `context` - Map of context to include if an error occurs

  ## Returns

    * `{:ok, result}` if function succeeds
    * `{:error, reason}` if function fails

  ## Examples

      ErrorHandler.with_error_handling(fn ->
        process_payment(transaction)
      end, %{transaction_id: transaction.id})
  """
  def with_error_handling(fun, context \\ %{}) when is_function(fun, 0) do
    result = fun.()
    {:ok, result}
  rescue
    exception ->
      capture_exception(exception, __STACKTRACE__, context)
      {:error, Exception.message(exception)}
  end

  @doc """
  Sets user context for Sentry error tracking.

  This associates errors with specific users for better debugging.

  ## Arguments

    * `user_id` - UUID of the user
    * `user_attrs` - Additional user attributes (email, role, etc.)

  ## Examples

      ErrorHandler.set_user_context(user.id, %{
        email: user.email,
        role: user.role
      })
  """
  def set_user_context(user_id, user_attrs \\ %{}) do
    if sentry_configured?() do
      Sentry.Context.set_user_context(%{
        id: user_id,
        email: Map.get(user_attrs, :email),
        username: Map.get(user_attrs, :username),
        role: Map.get(user_attrs, :role)
      })
    end

    :ok
  end

  @doc """
  Sets request context for Sentry error tracking.

  This associates errors with specific HTTP requests.

  ## Arguments

    * `conn` - Plug.Conn struct

  ## Examples

      ErrorHandler.set_request_context(conn)
  """
  def set_request_context(conn) do
    if sentry_configured?() do
      Sentry.Context.set_request_context(%{
        url: "#{conn.scheme}://#{conn.host}#{conn.request_path}",
        method: conn.method,
        headers: sanitize_headers(conn.req_headers),
        query_string: conn.query_string
      })
    end

    :ok
  end

  @doc """
  Adds breadcrumb for tracking user actions leading to an error.

  ## Arguments

    * `message` - Breadcrumb message
    * `category` - Category (e.g., "navigation", "api", "user_action")
    * `metadata` - Additional metadata

  ## Examples

      ErrorHandler.add_breadcrumb("User clicked payment button", "user_action", %{
        job_id: job.id
      })
  """
  def add_breadcrumb(message, category \\ "default", metadata \\ %{}) do
    if sentry_configured?() do
      Sentry.Context.add_breadcrumb(%{
        message: message,
        category: category,
        data: metadata,
        timestamp: DateTime.utc_now() |> DateTime.to_unix()
      })
    end

    :ok
  end

  # Private helper functions

  defp sentry_configured? do
    case Application.get_env(:sentry, :dsn) do
      nil -> false
      "" -> false
      _dsn -> true
    end
  end

  defp extract_tags(context) do
    context
    |> Map.take([:job_id, :transaction_id, :user_id, :provider_id, :driver_id, :payment_method])
    |> Enum.map(fn {k, v} -> {k, to_string(v)} end)
    |> Map.new()
  end

  defp sanitize_headers(headers) do
    # Remove sensitive headers
    sensitive_headers = ["authorization", "cookie", "x-api-key"]

    headers
    |> Enum.reject(fn {key, _value} ->
      String.downcase(key) in sensitive_headers
    end)
    |> Map.new()
  end
end
