defmodule TireDispatchWeb.Plugs.SentryContextPlug do
  @moduledoc """
  Plug for setting Sentry context on each request.

  This plug automatically captures request information and user context
  for better error tracking in Sentry.
  """

  import Plug.Conn

  alias TireDispatch.ErrorHandler

  def init(opts), do: opts

  def call(conn, _opts) do
    # Set request context
    ErrorHandler.set_request_context(conn)

    # Set user context if user is authenticated
    if user_id = get_session(conn, :user_id) do
      ErrorHandler.set_user_context(user_id)
    end

    # Add breadcrumb for the request
    ErrorHandler.add_breadcrumb(
      "#{conn.method} #{conn.request_path}",
      "navigation",
      %{
        method: conn.method,
        path: conn.request_path,
        query_string: conn.query_string
      }
    )

    conn
  end
end
