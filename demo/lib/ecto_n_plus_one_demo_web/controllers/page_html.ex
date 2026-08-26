defmodule EctoNPlusOneDemoWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use EctoNPlusOneDemoWeb, :html

  embed_templates "page_html/*"

  def format_callsite(callsite) do
    callsite
    |> Exception.format_stacktrace_entry()
    |> String.trim()
  end
end
