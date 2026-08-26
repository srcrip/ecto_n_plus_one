defmodule EctoNPlusOneTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias EctoNPlusOne.Detection

  @event [:ecto_n_plus_one_test, :repo, :query]
  @other_event [:ecto_n_plus_one_test, :other_repo, :query]
  @application_stack [
    {MyApp.Loader, :load, 1, [file: ~c"lib/my_app/loader.ex", line: 1]}
  ]

  defmodule Repo do
    def config, do: [telemetry_prefix: [:ecto_n_plus_one_test, :repo]]
  end

  defmodule OtherRepo do
    def config, do: [telemetry_prefix: [:ecto_n_plus_one_test, :other_repo]]
  end

  setup do
    on_exit(fn ->
      EctoNPlusOne.detach(Repo)
      EctoNPlusOne.detach(OtherRepo)
    end)

    :ok
  end

  test "attaches to the Repo query event and reports an N+1 pattern" do
    attach()

    emit("SELECT * FROM profiles WHERE user_id = $1", [1], total_time: 7)
    emit("SELECT * FROM profiles WHERE user_id = $1", [2], total_time: 11)

    assert_receive {:detection,
                    %Detection{
                      count: 2,
                      parameter_variants: 2,
                      query: "SELECT * FROM profiles WHERE user_id = $1",
                      source: "users",
                      total_time: 18
                    }}
  end

  test "does not report ordinary queries that are not an N+1" do
    attach()

    emit("SELECT * FROM users", [])
    emit("SELECT * FROM profiles WHERE user_id = $1", [1])
    emit("SELECT * FROM records WHERE id = $1", [1], source: "users")
    emit("SELECT * FROM records WHERE id = $1", [2], source: "posts")
    emit("SELECT * FROM records WHERE id = $1", [3], repo: OtherRepo)

    refute_receive {:detection, _detection}, 0
  end

  test "reports repeated identical parameters by default" do
    attach()

    emit("SELECT * FROM capabilities WHERE viewer_id = $1", [1])
    emit("SELECT * FROM capabilities WHERE viewer_id = $1", [1])

    assert_receive {:detection, %Detection{count: 2, parameter_variants: 1, source: "users"}}
  end

  test "uses a five-query threshold by default" do
    owner = self()

    EctoNPlusOne.attach(Repo,
      application_modules: [MyApp],
      on_detect: fn detection -> send(owner, {:detection, detection}) end
    )

    Enum.each(1..4, fn _index ->
      emit("SELECT * FROM capabilities WHERE viewer_id = $1", [1])
    end)

    refute_receive {:detection, _detection}, 0
    emit("SELECT * FROM capabilities WHERE viewer_id = $1", [1])

    assert_receive {:detection, %Detection{count: 5, parameter_variants: 1, source: "users"}}
  end

  test "can require distinct parameter variants" do
    attach(min_parameter_variants: 2)

    emit("SELECT * FROM capabilities WHERE viewer_id = $1", [1])
    emit("SELECT * FROM capabilities WHERE viewer_id = $1", [1])

    refute_receive {:detection, _detection}, 0
  end

  test "ignores writes and transaction queries by default" do
    attach()

    emit("UPDATE users SET active = $1", [true])
    emit("UPDATE users SET active = $1", [false])
    emit("BEGIN", [])
    emit("BEGIN", [])

    refute_receive {:detection, _detection}, 0
  end

  test "separates identical SQL from different application callsites" do
    attach()

    first = [{MyApp.FirstLoader, :load, 1, [file: ~c"lib/first_loader.ex", line: 10]}]
    second = [{MyApp.SecondLoader, :load, 1, [file: ~c"lib/second_loader.ex", line: 20]}]

    emit("SELECT * FROM users WHERE id = $1", [1], stacktrace: first)
    emit("SELECT * FROM users WHERE id = $1", [2], stacktrace: second)

    refute_receive {:detection, _detection}, 0
  end

  test "separates the same query callsite reached through different application stacks" do
    attach(application_modules: [MyApp, MyAppWeb])

    query_frame =
      {MyApp.Accounts, :load_profile, 1, [file: ~c"lib/my_app/accounts.ex", line: 42]}

    first_caller =
      {MyAppWeb.ProfileCard, :update, 2, [file: ~c"lib/my_app_web/profile_card.ex", line: 18]}

    second_caller =
      {MyApp.Export, :render, 1, [file: ~c"lib/my_app/export.ex", line: 27]}

    emit("SELECT * FROM profiles WHERE user_id = $1", [1],
      stacktrace: [query_frame, first_caller]
    )

    emit("SELECT * FROM profiles WHERE user_id = $1", [2],
      stacktrace: [query_frame, second_caller]
    )

    refute_receive {:detection, _detection}, 0

    emit("SELECT * FROM profiles WHERE user_id = $1", [3],
      stacktrace: [query_frame, first_caller]
    )

    assert_receive {:detection,
                    %Detection{
                      callsite: ^query_frame,
                      stacktrace: [^query_frame, ^first_caller]
                    }}
  end

  test "requires a callsite under a configured application module" do
    attach(application_modules: [MyApp, MyAppWeb])

    dependency_stack = [
      {Oban.Repo, :dynamic_dispatch, 4, [file: ~c"lib/oban/repo.ex", line: 296]}
    ]

    emit("SELECT * FROM oban_producers WHERE queue = $1", ["default"],
      stacktrace: dependency_stack
    )

    emit("SELECT * FROM oban_producers WHERE queue = $1", ["default"],
      stacktrace: dependency_stack
    )

    refute_receive {:detection, _detection}, 0

    application_frame =
      {MyApp.Catalog.Loader, :load, 1, [file: ~c"lib/my_app/catalog/loader.ex", line: 12]}

    application_stack = dependency_stack ++ [application_frame]

    emit("SELECT * FROM posts WHERE author_id = $1", [1], stacktrace: application_stack)
    emit("SELECT * FROM posts WHERE author_id = $1", [2], stacktrace: application_stack)

    assert_receive {:detection, %Detection{callsite: ^application_frame, count: 2}}
  end

  test "reports only once while a matching query group remains active" do
    attach()

    emit("SELECT * FROM posts WHERE author_id = $1", [1])
    emit("SELECT * FROM posts WHERE author_id = $1", [2])
    assert_receive {:detection, %Detection{count: 2}}

    emit("SELECT * FROM posts WHERE author_id = $1", [3])
    refute_receive {:detection, _detection}, 0
  end

  test "honors thresholds and ignores" do
    attach(
      threshold: 3,
      ignore: fn query -> query.source == "ignored" end
    )

    Enum.each(1..3, &emit("SELECT * FROM ignored WHERE id = $1", [&1], source: "ignored"))
    Enum.each(1..2, &emit("SELECT * FROM users WHERE id = $1", [&1]))
    refute_receive {:detection, _detection}, 0

    emit("SELECT * FROM users WHERE id = $1", [3])
    assert_receive {:detection, %Detection{count: 3, source: "users"}}
  end

  test "ignores normalized query candidates with pattern-matched callback clauses" do
    ignored_callsite =
      {MyApp.Startup.Loader, :effective_config, 3,
       [file: ~c"lib/my_app/startup/loader.ex", line: 12]}

    attach(
      application_modules: [MyApp],
      ignore: fn
        %{
          source: "pipeline_settings",
          operation: :select,
          callsite: {MyApp.Startup.Loader, :effective_config, _, _}
        } ->
          true

        _query ->
          false
      end
    )

    emit("  SELECT * FROM pipeline_settings WHERE key = $1  ", ["one"],
      source: "pipeline_settings",
      stacktrace: [ignored_callsite]
    )

    emit("  SELECT * FROM pipeline_settings WHERE key = $1  ", ["two"],
      source: "pipeline_settings",
      stacktrace: [ignored_callsite]
    )

    refute_receive {:detection, _detection}, 0

    tracked_callsite =
      {MyApp.Catalog.Loader, :load, 1, [file: ~c"lib/my_app/catalog/loader.ex", line: 20]}

    emit(" SELECT * FROM posts WHERE author_id = $1 ", [1],
      source: "posts",
      stacktrace: [tracked_callsite]
    )

    emit(" SELECT * FROM posts WHERE author_id = $1 ", [2],
      source: "posts",
      stacktrace: [tracked_callsite]
    )

    assert_receive {:detection,
                    %Detection{
                      callsite: ^tracked_callsite,
                      operation: :select,
                      query: "SELECT * FROM posts WHERE author_id = $1",
                      source: "posts"
                    }}
  end

  test "can retain a capped number of parameter samples" do
    attach(include_params: true, max_samples: 2)

    emit("SELECT * FROM users WHERE id = $1", [1])
    emit("SELECT * FROM users WHERE id = $1", [2])

    assert_receive {:detection, %Detection{params: [[1], [2]]}}
  end

  test "attaches to multiple Repos" do
    owner = self()

    :ok =
      EctoNPlusOne.attach([Repo, OtherRepo],
        application_modules: [MyApp],
        threshold: 2,
        on_detect: fn detection -> send(owner, {:detection, detection}) end
      )

    emit_event(@other_event, "SELECT * FROM events WHERE account_id = $1", [1],
      repo: OtherRepo,
      source: "events"
    )

    emit_event(@other_event, "SELECT * FROM events WHERE account_id = $1", [2],
      repo: OtherRepo,
      source: "events"
    )

    assert_receive {:detection, %Detection{repo: OtherRepo, source: "events"}}
  end

  test "detach removes the Repo handler" do
    attach()
    assert automatic_handler_count(@event) == 1

    assert :ok = EctoNPlusOne.detach(Repo)
    assert automatic_handler_count(@event) == 0
  end

  test "validates Repos and options before attaching" do
    handler = fn _detection -> :ok end

    refute function_exported?(EctoNPlusOne, :event_name, 1)
    refute function_exported?(EctoNPlusOne, :attach, 1)

    assert_raise ArgumentError, fn ->
      EctoNPlusOne.attach([], application_modules: [MyApp], on_detect: handler)
    end

    assert_raise ArgumentError, fn ->
      EctoNPlusOne.attach([:not, :a, :repo],
        application_modules: [MyApp],
        on_detect: handler
      )
    end

    assert_raise NimbleOptions.ValidationError, fn ->
      EctoNPlusOne.attach(Repo,
        application_modules: [MyApp],
        threshold: 0,
        on_detect: handler
      )
    end

    assert_raise NimbleOptions.ValidationError, fn ->
      EctoNPlusOne.attach(Repo, application_modules: [], on_detect: handler)
    end

    assert_raise NimbleOptions.ValidationError, fn ->
      EctoNPlusOne.attach(Repo, application_modules: :all, on_detect: handler)
    end

    assert_raise NimbleOptions.ValidationError, fn ->
      EctoNPlusOne.attach(Repo,
        application_modules: [MyApp],
        ignore: :invalid,
        on_detect: handler
      )
    end

    assert_raise NimbleOptions.ValidationError, fn ->
      EctoNPlusOne.attach(Repo, application_modules: [MyApp], on_detect: :raise)
    end

    missing_handler_error =
      assert_raise NimbleOptions.ValidationError, fn ->
        EctoNPlusOne.attach(Repo, application_modules: [MyApp], threshold: 2)
      end

    assert Exception.message(missing_handler_error) =~ "required :on_detect option not found"

    unknown_option_error =
      assert_raise NimbleOptions.ValidationError, fn ->
        EctoNPlusOne.attach(Repo,
          application_modules: [MyApp],
          min_paramater_variants: 2,
          on_detect: handler
        )
      end

    assert Exception.message(unknown_option_error) =~ "unknown options [:min_paramater_variants]"

    missing_modules_error =
      assert_raise NimbleOptions.ValidationError, fn ->
        EctoNPlusOne.attach(Repo, on_detect: handler)
      end

    assert Exception.message(missing_modules_error) =~
             "required :application_modules option not found"
  end

  test "logs callback failures without removing the Telemetry handler" do
    EctoNPlusOne.attach(Repo,
      application_modules: [MyApp],
      threshold: 2,
      on_detect: fn _detection -> raise "handler unavailable" end
    )

    log =
      capture_log(fn ->
        emit("SELECT * FROM posts WHERE author_id = $1", [1])
        emit("SELECT * FROM posts WHERE author_id = $1", [2])
      end)

    assert log =~ "EctoNPlusOne Telemetry handler failed"
    assert log =~ "handler unavailable"
    assert automatic_handler_count(@event) == 1
  end

  defp attach(opts \\ []) do
    owner = self()

    opts =
      opts
      |> Keyword.put_new(:threshold, 2)
      |> Keyword.put_new(:application_modules, [MyApp])
      |> Keyword.put(:on_detect, fn detection -> send(owner, {:detection, detection}) end)

    EctoNPlusOne.attach(Repo, opts)
  end

  defp emit(query, params, opts \\ []), do: emit_event(@event, query, params, opts)

  defp emit_event(event, query, params, opts) do
    measurements = %{total_time: Keyword.get(opts, :total_time, 1)}

    metadata = %{
      query: query,
      params: params,
      repo: Keyword.get(opts, :repo, Repo),
      source: Keyword.get(opts, :source, "users"),
      stacktrace: Keyword.get(opts, :stacktrace, @application_stack)
    }

    :telemetry.execute(event, measurements, metadata)
  end

  defp automatic_handler_count(event) do
    Enum.count(:telemetry.list_handlers(event), &(&1.id == {EctoNPlusOne.Telemetry, event}))
  end
end
