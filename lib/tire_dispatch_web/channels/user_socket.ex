defmodule TireDispatchWeb.UserSocket do
  @moduledoc """
  Socket for handling real-time Phoenix Channel connections.

  This socket authenticates users via session tokens and provides
  access to job-specific channels for real-time communication.
  """

  use Phoenix.Socket

  require Logger

  # Channels
  channel "jobs:*", TireDispatchWeb.JobChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    # Verify the token and extract user_id
    case verify_token(token) do
      {:ok, user_id} ->
        Logger.info("User connected to socket", %{user_id: user_id})
        {:ok, assign(socket, :user_id, user_id)}

      {:error, reason} ->
        Logger.warning("Socket connection failed", %{reason: reason})
        :error
    end
  end

  def connect(_params, _socket, _connect_info) do
    Logger.warning("Socket connection failed - missing token")
    :error
  end

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"

  # Private helper to verify authentication token
  defp verify_token(token) do
    # In a real implementation, this would verify a JWT or session token
    # For now, we'll accept the token as the user_id directly
    # In production, use Phoenix.Token.verify/4 or similar
    case Phoenix.Token.verify(
           TireDispatchWeb.Endpoint,
           "user socket",
           token,
           max_age: 86_400
         ) do
      {:ok, user_id} -> {:ok, user_id}
      {:error, _reason} -> {:error, :invalid_token}
    end
  rescue
    _ -> {:error, :invalid_token}
  end
end
