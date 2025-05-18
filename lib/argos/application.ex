defmodule Argos.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Add your supervisors/workers here if needed
    ]
    opts = [strategy: :one_for_one, name: Argos.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
