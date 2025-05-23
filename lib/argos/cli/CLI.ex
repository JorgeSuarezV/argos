defmodule Argos.CLI do
  def main(argv) do
    {_opts, args, _} = OptionParser.parse(argv, switches: [], aliases: [])

    case args do
      ["start", config_path] -> run(:start, load_config(config_path))
      ["reload", config_path] -> run(:reload, load_config(config_path))
      ["stop"] -> run(:stop, nil)
      _ -> usage()
    end
  end

  # En el código:
  defp run(command, config) do
    IO.puts("#{String.capitalize(to_string(command))}ing...")
    IO.puts("-------------------------")

    # pretty_print devuelve un string con saltos de línea e indentación
    pretty = Jason.Formatter.pretty_print(Jason.encode!(config))
    IO.puts(pretty)
  end

  defp load_config(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  defp usage do
    IO.puts("Usage: argos <start|reload|stop> /path/to/config.json")
    :error
  end
end
