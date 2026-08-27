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

  @spec validate_repos(term()) :: {:ok, module() | [module()]} | {:error, String.t()}
  def validate_repos(repo) when is_atom(repo) and not is_nil(repo), do: {:ok, repo}

  def validate_repos([repo | _rest] = repos) when is_atom(repo) do
    if Enum.all?(repos, &is_atom/1) do
      {:ok, repos}
    else
      {:error, "expected an Ecto Repo module or a non-empty list of Repo modules"}
    end
  end

  def validate_repos(_repos),
    do: {:error, "expected an Ecto Repo module or a non-empty list of Repo modules"}
end
