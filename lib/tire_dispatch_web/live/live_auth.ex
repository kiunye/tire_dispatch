defmodule TireDispatchWeb.LiveAuth do
  @moduledoc """
  Authorization helpers for LiveView mount callbacks.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias TireDispatch.Users.Authorization

  @doc """
  Requires authentication in a LiveView mount callback.

  Returns `{:ok, socket}` if user is authenticated, otherwise redirects to login.

  ## Examples

      def mount(_params, session, socket) do
        socket = assign_current_user(socket, session)

        case require_authenticated_user(socket) do
          {:ok, socket} -> {:ok, socket}
          {:error, socket} -> {:ok, socket}
        end
      end

  """
  def require_authenticated_user(socket) do
    if socket.assigns[:current_user] do
      {:ok, socket}
    else
      socket =
        socket
        |> put_flash(:error, "You must log in to access this page.")
        |> redirect(to: "/users/log-in")

      {:error, socket}
    end
  end

  @doc """
  Requires the current user to have one of the specified roles.

  Returns `{:ok, socket}` if authorized, otherwise redirects to home with error.

  ## Examples

      def mount(_params, session, socket) do
        socket = assign_current_user(socket, session)

        with {:ok, socket} <- require_authenticated_user(socket),
             {:ok, socket} <- require_role(socket, [:admin]) do
          {:ok, socket}
        else
          {:error, socket} -> {:ok, socket}
        end
      end

  """
  def require_role(socket, required_roles) when is_list(required_roles) do
    current_user = socket.assigns[:current_user]

    if current_user && Authorization.has_role?(current_user, required_roles) do
      {:ok, socket}
    else
      socket =
        socket
        |> put_flash(:error, "You are not authorized to access this page.")
        |> redirect(to: "/")

      {:error, socket}
    end
  end

  @doc """
  Assigns the current user to the socket from the session.

  ## Examples

      def mount(_params, session, socket) do
        socket = assign_current_user(socket, session)
        {:ok, socket}
      end

  """
  def assign_current_user(socket, session) do
    case session do
      %{"user_token" => user_token} ->
        case TireDispatch.Users.get_user_by_session_token(user_token) do
          {user, _token_inserted_at} ->
            assign(socket, :current_user, user)

          nil ->
            assign(socket, :current_user, nil)
        end

      _ ->
        assign(socket, :current_user, nil)
    end
  end

  @doc """
  Convenience function to check if current user is a driver.
  """
  def driver?(socket) do
    case socket.assigns[:current_user] do
      nil -> false
      user -> Authorization.driver?(user)
    end
  end

  @doc """
  Convenience function to check if current user is a provider.
  """
  def provider?(socket) do
    case socket.assigns[:current_user] do
      nil -> false
      user -> Authorization.provider?(user)
    end
  end

  @doc """
  Convenience function to check if current user is an admin.
  """
  def admin?(socket) do
    case socket.assigns[:current_user] do
      nil -> false
      user -> Authorization.admin?(user)
    end
  end
end
