defmodule TireDispatchWeb.Plugs.RequireRole do
  @moduledoc """
  Plug for requiring specific user roles to access routes.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias TireDispatch.Users.Authorization

  @doc """
  Initializes the plug with the required roles.

  ## Examples

      plug TireDispatchWeb.Plugs.RequireRole, [:admin]
      plug TireDispatchWeb.Plugs.RequireRole, [:driver, :provider]

  """
  def init(roles) when is_list(roles), do: roles

  @doc """
  Checks if the current user has one of the required roles.
  Redirects to home page with error flash if unauthorized.
  """
  def call(conn, required_roles) do
    current_user = conn.assigns[:current_user]

    if current_user && Authorization.has_role?(current_user, required_roles) do
      conn
    else
      conn
      |> put_flash(:error, "You are not authorized to access this page.")
      |> redirect(to: "/")
      |> halt()
    end
  end
end
