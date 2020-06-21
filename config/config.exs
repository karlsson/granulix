use Mix.Config

config :xalsa,
   rate: 48000,
   pcms: [{:"hw:PCH,0",
           [channels: 2, period_size: 256, period_buffer_size_ratio: 2]}]
# #   pcms: ["plughw:HDMI,3": 2]
