defmodule TireDispatchWeb.PageController do
  use TireDispatchWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
