%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      strict: true,
      color: true,
      checks: [
        {Credo.Check.Design.AliasUsage, priority: :low, exit_status: 0}
      ]
    }
  ]
}
