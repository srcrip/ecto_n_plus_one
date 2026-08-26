defmodule EctoNPlusOneDemoWeb.Router do
  use EctoNPlusOneDemoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {EctoNPlusOneDemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", EctoNPlusOneDemoWeb do
    pipe_through :browser

    get "/", PageController, :home
  end
end
