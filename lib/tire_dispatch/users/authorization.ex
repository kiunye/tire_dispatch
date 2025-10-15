defmodule TireDispatch.Users.Authorization do
  @moduledoc """
  Authorization helpers for role-based access control.
  """

  alias TireDispatch.Users.User

  @doc """
  Checks if the user has the driver role.

  ## Examples

      iex> driver?(%User{role: :driver})
      true

      iex> driver?(%User{role: :provider})
      false

  """
  def driver?(%User{role: :driver}), do: true
  def driver?(_), do: false

  @doc """
  Checks if the user has the provider role.

  ## Examples

      iex> provider?(%User{role: :provider})
      true

      iex> provider?(%User{role: :driver})
      false

  """
  def provider?(%User{role: :provider}), do: true
  def provider?(_), do: false

  @doc """
  Checks if the user has the admin role.

  ## Examples

      iex> admin?(%User{role: :admin})
      true

      iex> admin?(%User{role: :driver})
      false

  """
  def admin?(%User{role: :admin}), do: true
  def admin?(_), do: false

  @doc """
  Checks if the user has any of the specified roles.

  ## Examples

      iex> has_role?(%User{role: :driver}, [:driver, :admin])
      true

      iex> has_role?(%User{role: :provider}, [:driver, :admin])
      false

  """
  def has_role?(%User{role: role}, allowed_roles) when is_list(allowed_roles) do
    role in allowed_roles
  end

  def has_role?(_, _), do: false
end
