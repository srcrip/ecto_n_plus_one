defmodule EctoNPlusOne.Options do
  @moduledoc false

  @spec validate_application_modules(term()) :: {:ok, [module()]} | {:error, String.t()}
  def validate_application_modules([module | _rest] = modules) when is_atom(module) do
    if Enum.all?(modules, &is_atom/1) do
      {:ok, modules}
    else
      {:error, "expected a non-empty list of modules"}
    end
  end

  def validate_application_modules(_modules), do: {:error, "expected a non-empty list of modules"}
end
