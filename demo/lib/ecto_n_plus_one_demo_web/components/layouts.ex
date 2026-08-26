defmodule EctoNPlusOneDemoWeb.Layouts do
  @moduledoc false

  use EctoNPlusOneDemoWeb, :html

  embed_templates "layouts/*"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <main>
      <div class="container">
        {render_slot(@inner_block)}
      </div>
    </main>
    """
  end
end
