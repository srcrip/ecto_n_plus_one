defmodule EctoNPlusOne.TestTest do
  use ExUnit.Case, async: true

  alias EctoNPlusOne.Detection
  alias EctoNPlusOne.Test.NPlusOneDetectedError

  import EctoNPlusOne.Test

  @event [:ecto_n_plus_one_test_helper, :repo, :query]
  @application_stack [
    {MyApp.Loader, :load, 1, [file: ~c"lib/my_app/loader.ex", line: 1]}
  ]

  defmodule Repo do
    def config, do: [telemetry_prefix: [:ecto_n_plus_one_test_helper, :repo]]
  end

  defmodule DefaultsCase do
    use EctoNPlusOne.Test,
      repos: EctoNPlusOne.TestTest.Repo,
      application_modules: [MyApp]
  end

  test "flags a query repeated with distinct parameters from one callsite" do
    error =
      assert_raise NPlusOneDetectedError, fn ->
        assert_no_n_plus_one(
          fn ->
            Enum.each(1..3, &emit("SELECT * FROM posts WHERE author_id = $1", [&1]))
          end,
          repos: Repo,
          application_modules: [MyApp]
        )
      end

    assert [%Detection{count: 3, parameter_variants: 3, source: "users"}] = error.detections
    assert error.message =~ "SELECT * FROM posts WHERE author_id = $1"
    assert error.message =~ "lib/my_app/loader.ex:1"
    assert error.message =~ "3 executions with 3 distinct parameter sets"
    assert error.message =~ "sample parameters: [[1], [2], [3]]"
  end

  test "returns the block's result when no N+1 occurs" do
    result =
      assert_no_n_plus_one(
        fn ->
          emit("SELECT * FROM posts WHERE author_id = $1", [1])
          emit("SELECT * FROM comments WHERE post_id = $1", [2])
          :page_rendered
        end,
        repos: Repo,
        application_modules: [MyApp]
      )

    assert result == :page_rendered
  end

  # A LiveView test renders twice (disconnected and connected mount),
  # so every per-render query runs at least twice with the same parameters.
  test "allows the same query to repeat with identical parameters" do
    assert_no_n_plus_one(
      fn ->
        Enum.each(1..5, fn _ -> emit("SELECT * FROM users WHERE id = $1", [7]) end)
      end,
      repos: Repo,
      application_modules: [MyApp]
    )
  end

  test "ignores queries emitted before and after the block" do
    emit("SELECT * FROM posts WHERE author_id = $1", [1])
    emit("SELECT * FROM posts WHERE author_id = $1", [2])

    assert_no_n_plus_one(
      fn -> emit("SELECT * FROM posts WHERE author_id = $1", [3]) end,
      repos: Repo,
      application_modules: [MyApp]
    )

    emit("SELECT * FROM posts WHERE author_id = $1", [4])
    emit("SELECT * FROM posts WHERE author_id = $1", [5])
  end

  test "captures queries from processes started by the test" do
    error =
      assert_raise NPlusOneDetectedError, fn ->
        assert_no_n_plus_one(
          fn ->
            fn -> Enum.each(1..3, &emit("SELECT * FROM posts WHERE author_id = $1", [&1])) end
            |> Task.async()
            |> Task.await()
          end,
          repos: Repo,
          application_modules: [MyApp]
        )
      end

    assert [%Detection{count: 3, parameter_variants: 3}] = error.detections
  end

  test "captures queries from nested descendant processes" do
    assert_raise NPlusOneDetectedError, fn ->
      assert_no_n_plus_one(
        fn ->
          Task.async(fn ->
            fn -> Enum.each(1..3, &emit("SELECT * FROM posts WHERE author_id = $1", [&1])) end
            |> Task.async()
            |> Task.await()
          end)
          |> Task.await()
        end,
        repos: Repo,
        application_modules: [MyApp]
      )
    end
  end

  test "ignores queries from unrelated processes" do
    assert_no_n_plus_one(
      fn ->
        parent = self()

        # Raw spawned processes don't set `$callers` or `$ancestors`, so they're ignored.
        unrelated =
          spawn(fn ->
            receive do
              :execute_query ->
                Enum.each(1..5, &emit("SELECT * FROM posts WHERE author_id = $1", [&1]))
                send(parent, :done)
            end
          end)

        send(unrelated, :execute_query)
        assert_receive :done
      end,
      repos: Repo,
      application_modules: [MyApp]
    )
  end

  test "separates identical SQL from different callsites" do
    first = [{MyApp.FirstLoader, :load, 1, [file: ~c"lib/first_loader.ex", line: 10]}]
    second = [{MyApp.SecondLoader, :load, 1, [file: ~c"lib/second_loader.ex", line: 20]}]

    assert_no_n_plus_one(
      fn ->
        emit("SELECT * FROM users WHERE id = $1", [1], stacktrace: first)
        emit("SELECT * FROM users WHERE id = $1", [2], stacktrace: first)
        emit("SELECT * FROM users WHERE id = $1", [3], stacktrace: second)
        emit("SELECT * FROM users WHERE id = $1", [4], stacktrace: second)
      end,
      repos: Repo,
      application_modules: [MyApp]
    )
  end

  test "ignores callsites that aren't under a configured application module" do
    assert_no_n_plus_one(
      fn ->
        Enum.each(1..5, fn index ->
          emit("SELECT * FROM oban_producers WHERE queue = $1", ["queue-#{index}"],
            stacktrace: [
              {Oban.Repo, :dynamic_dispatch, 4, [file: ~c"lib/oban/repo.ex", line: 296]}
            ]
          )
        end)
      end,
      repos: Repo,
      application_modules: [MyApp]
    )
  end

  test "merges one callsite reached through different application stacks" do
    # Simulates a LiveView's disconnected and connected mounts. The same query callsite crosses the thresholds
    # once per mount path, but the failure should report the offending query only once.
    query_frame = {MyApp.Loader, :load, 1, [file: ~c"lib/my_app/loader.ex", line: 1]}
    static_caller = {MyApp.StaticMount, :mount, 3, [file: ~c"lib/static_mount.ex", line: 5]}
    live_caller = {MyApp.LiveMount, :mount, 3, [file: ~c"lib/live_mount.ex", line: 9]}

    error =
      assert_raise NPlusOneDetectedError, fn ->
        assert_no_n_plus_one(
          fn ->
            for caller <- [static_caller, live_caller],
                index <- 1..3 do
              emit("SELECT * FROM posts WHERE author_id = $1", [index],
                stacktrace: [query_frame, caller]
              )
            end
          end,
          repos: Repo,
          application_modules: [MyApp]
        )
      end

    assert [%Detection{callsite: ^query_frame, count: 6, parameter_variants: 3}] =
             error.detections
  end

  test "honors :threshold, :min_parameter_variants, and :ignore" do
    options = [repos: Repo, application_modules: [MyApp]]

    n_plus_one = fn ->
      Enum.each(1..3, &emit("SELECT * FROM posts WHERE author_id = $1", [&1]))
    end

    assert_no_n_plus_one(n_plus_one, options ++ [threshold: 4])
    assert_no_n_plus_one(n_plus_one, options ++ [min_parameter_variants: 4])
    assert_no_n_plus_one(n_plus_one, options ++ [ignore: &(&1.source == "users")])

    assert_raise NPlusOneDetectedError, fn -> assert_no_n_plus_one(n_plus_one, options) end
  end

  test "detect_n_plus_one_queries returns the result and the detections" do
    {result, detections} =
      detect_n_plus_one_queries(
        fn ->
          Enum.each(1..3, &emit("SELECT * FROM posts WHERE author_id = $1", [&1]))
          :rendered
        end,
        repos: Repo,
        application_modules: [MyApp]
      )

    assert result == :rendered
    assert [%Detection{count: 3, parameter_variants: 3}] = detections
  end

  test "raises when query events carry no stacktrace" do
    error =
      assert_raise ArgumentError, fn ->
        assert_no_n_plus_one(
          fn -> emit("SELECT * FROM posts WHERE author_id = $1", [1], stacktrace: nil) end,
          repos: Repo,
          application_modules: [MyApp]
        )
      end

    assert Exception.message(error) =~ "stacktrace: true"
  end

  test "detaches its handler after a successful block" do
    assert_no_n_plus_one(fn -> :ok end, repos: Repo, application_modules: [MyApp])
    assert scoped_handler_count() == 0
  end

  test "detaches its handler when the block raises" do
    assert_raise RuntimeError, "boom", fn ->
      assert_no_n_plus_one(
        fn -> raise "boom" end,
        repos: Repo,
        application_modules: [MyApp]
      )
    end

    assert scoped_handler_count() == 0
  end

  test "`use` injects wrappers with default options baked in" do
    assert_raise NPlusOneDetectedError, fn ->
      DefaultsCase.assert_no_n_plus_one(fn ->
        Enum.each(1..3, &emit("SELECT * FROM posts WHERE author_id = $1", [&1]))
      end)
    end

    assert {:ok, []} = DefaultsCase.detect_n_plus_one_queries(fn -> :ok end, threshold: 10)
  end

  test "validates options" do
    assert_raise NimbleOptions.ValidationError, fn ->
      assert_no_n_plus_one(fn -> :ok end, application_modules: [MyApp])
    end

    assert_raise NimbleOptions.ValidationError, fn ->
      assert_no_n_plus_one(fn -> :ok end, repos: Repo)
    end

    assert_raise NimbleOptions.ValidationError, fn ->
      assert_no_n_plus_one(fn -> :ok end,
        repos: Repo,
        application_modules: [MyApp],
        threshold: 0
      )
    end
  end

  defp emit(query, params, opts \\ []) do
    measurements = %{total_time: Keyword.get(opts, :total_time, 1)}

    metadata = %{
      query: query,
      params: params,
      repo: Keyword.get(opts, :repo, Repo),
      source: Keyword.get(opts, :source, "users"),
      stacktrace: Keyword.get(opts, :stacktrace, @application_stack)
    }

    :telemetry.execute(@event, measurements, metadata)
  end

  defp scoped_handler_count do
    Enum.count(:telemetry.list_handlers(@event), fn handler ->
      match?({EctoNPlusOne.Test, _ref, _event}, handler.id)
    end)
  end
end
