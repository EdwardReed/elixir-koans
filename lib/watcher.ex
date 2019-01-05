defmodule Watcher do
  use GenServer

  @default_arguments %{
    folder_to_watch: "lib/koans",
    handler: &Watcher.reload/1,
    name: __MODULE__
  }

  def start_link(args \\ %{}) do
    state = Map.merge(@default_arguments, args)
    GenServer.start_link(__MODULE__, state, name: state[:name])
  end

  def init(%{folder_to_watch: dirs} = args) do
    {:ok, watcher_pid} = FileSystem.start_link(dirs: [dirs], latency: 0)
    :ok = FileSystem.subscribe(watcher_pid)
    {:ok, args}
  end

  def handle_info({:file_event, _, {path, events}}, %{handler: file_handler} = state) do
    # respond to renamed as well due to that some editors use temporary files for atomic writes (ex: TextMate)
    if :modified in events or :renamed in events do
      path
      |> normalize
      |> file_handler.()
    end

    {:noreply, state}
  end

  def reload(file) do
    if Path.extname(file) == ".ex" do
      try do
        file
        |> portable_load_file
        |> Enum.map(&elem(&1, 0))
        |> Enum.find(&Runner.koan?/1)
        |> Runner.modules_to_run()
        |> Runner.run()
      rescue
        e -> Display.show_compile_error(e)
      end
    end
  end

  # Elixir 1.7 deprecates Code.load_file in favor of Code.compile_file. In
  # order to avoid the depecation warnings while maintaining backwards
  # compatibility, we check the sytem version and execute conditionally.
  defp portable_load_file(file) do
    if Version.match?(System.version(), "~> 1.7") do
      Code.compile_file(file)
    else
      Code.load_file(file)
    end
  end

  defp normalize(file) do
    String.replace_suffix(file, "___jb_tmp___", "")
  end
end
