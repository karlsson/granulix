defmodule SC.Plugin do

  @moduledoc """
  # SuperCollider Plugins

  ### SC.Plugin behaviour

  SC plugins uses NIFs for generating and transforming the frames in a similar way as Supercollider (SC) uses UGens.
  SC "plugins" should implement the SC.Plugin behavior.

  ## Installation

  **Include from github.**
  - In your applications mix.exs, in deps part, include
  {:sc_plugin_nif, git: "https://github.com/karlsson/sc_plugin_nif.git"}}
  - mix deps.get
  - mix compile.

  ## License

  The code is modified from SuperCollider and hence uses the same license:

  "SuperCollider is free software; you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free Software
  Foundation; either version 2 of the License, or (at your option) any later
  version. See COPYING file for the license text."

  """
  @type frames() :: binary | integer

  @callback next(plugin :: struct(), frames :: frames()) :: binary
  @callback stream(plugin :: struct(), frames :: Enumerable.t() | integer) :: Enumerable.t()

  def next(frames, plugin) when is_struct(plugin) do
    (plugin.__struct__).next(plugin, frames)
  end

  def stream(enum, plugin) when is_struct(plugin) do
    (plugin.__struct__).stream(plugin, enum)
  end
end
