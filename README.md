# Granulix

### Sound synthesis in Elixir

This is an experimental application and a proof of concept attempt to make sound synthesis in Elixir using processes as central part in the architecture and to make it fast enough for real-time play.

Granulix makes use of the [Xalsa](https://hexdocs.pm/xalsa/readme.html) application which expects frames to be in a binary array of 32 bit floats for the C api.
The Granulix.Math module holds a helper function to convert from an Elixir list of floats.
Normally one do not need to create the binary arrays oneself, but instead use some of the Granulix.Generator.* modules.

Granulix uses NIFs for generating and transforming ẗhe frames in a similar way as Supercollider (SC) uses UGens. The Granulix.Reverb.AnalogEcho module and granulix_analog_echo.c file combined are translated from the SC [AnalogEcho](https://github.com/supercollider/example-plugins/blob/master/03-AnalogEcho/AnalogEcho.cpp) example as a comparison.

NIF resources are created to keep state in the C-code between subsequent calls for frames generation or transformation (filtering etc.). A reference to the resource is passed to the Elixir side for this.

**NOTE:** Since the reference points to a NIF resource that is mutable and holds state, it is not meant to be shared between processes. If doing so it will probably give some interesting sound effects but not the expected ones.

Also, the maximum absolute value that the sound driver accepts before clipping is 1.0 (-1.0 to 1.0).

## Installation

**Checkout from github.**
- git clone https://github.com/karlsson/granulix.git
- mix deps.get
- mix compile. In order to compile the dependency application xalsa's c code you will need some alsa development libraries to be installed (libasound2-dev).

## Configuration

If Xalsa's default card configuration does not work for your sound card(s) you
can add xalsa configuration to the config/config.exs in the granulix application. Par example:
```elixir
config :xalsa,
  rate: 44100,
  pcms: ["plughw:HDMI,3": 2]
```

## Running

- mix test. Check the test/granulix_test.exs script for examples on how to generate sound.

## Acknowledgements

Many thanks to Magnus Johansson at [VEMS](https://vems.nu/vems/) for a gentle
introducton to Electroacoustic music and SuperCollider.
