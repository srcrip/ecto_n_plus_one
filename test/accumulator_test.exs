defmodule EctoNPlusOne.AccumulatorTest do
  use ExUnit.Case, async: true

  alias EctoNPlusOne.Accumulator

  @query "SELECT * FROM posts WHERE author_id = $1"

  test "starts a fresh group when that query has been inactive past the window" do
    options = options()

    {groups, _key} = Accumulator.capture(%{}, measurements(), metadata([1]), options, 1_000)

    {groups, key} =
      Accumulator.capture(groups, measurements(), metadata([2]), options, 3_001)

    {_groups, detection} = Accumulator.new_detection(groups, key, options)

    assert detection == nil
    assert [%{count: 1}] = Map.values(groups)
  end

  test "keeps counting a query at the inactivity-window boundary" do
    options = options()

    {groups, _key} = Accumulator.capture(%{}, measurements(), metadata([1]), options, 1_000)

    {groups, key} =
      Accumulator.capture(groups, measurements(), metadata([2]), options, 3_000)

    {_groups, detection} = Accumulator.new_detection(groups, key, options)

    assert detection.count == 2
    assert detection.parameter_variants == 2
  end

  test "bounds distinct groups until inactivity pruning frees capacity" do
    options = options(max_queries: 1)

    {groups, _key} = Accumulator.capture(%{}, measurements(), metadata([1]), options, 1_000)

    other_metadata = %{metadata([2]) | query: "SELECT * FROM comments WHERE post_id = $1"}
    {groups, _key} = Accumulator.capture(groups, measurements(), other_metadata, options, 1_001)

    assert [%{query: @query}] = Map.values(groups)

    groups = Accumulator.prune(groups, 3_001, options[:window_ms])
    {groups, _key} = Accumulator.capture(groups, measurements(), other_metadata, options, 3_001)

    assert [%{query: "SELECT * FROM comments WHERE post_id = $1"}] = Map.values(groups)
  end

  defp options(overrides \\ []) do
    Keyword.merge(
      [
        application_modules: [MyApp],
        exclude: fn _metadata -> false end,
        group_by_callsite: true,
        ignore: fn _candidate -> false end,
        include_params: false,
        max_queries: 1_000,
        max_samples: 3,
        min_parameter_variants: 1,
        operations: [:select],
        threshold: 2,
        window_ms: 2_000
      ],
      overrides
    )
  end

  defp measurements, do: %{total_time: 1}

  defp metadata(params) do
    %{
      params: params,
      query: @query,
      repo: MyApp.Repo,
      source: "posts",
      stacktrace: [{MyApp.Loader, :load, 1, [file: ~c"lib/my_app/loader.ex", line: 1]}]
    }
  end
end
