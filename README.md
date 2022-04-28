# Quick Start

```lua
local argparse = require "argparse"
local application = argparse.application
local command = argparse.command
local parameter = argparse.parameter

local cmd = command
    :new {
        name = "foo", help = "sample command"
    }:subcommand {
        command:new {
            name = "sub-1", help = "sample subcommand"
        }:parameter {
            parameter:new {
                name = "input", required = true, help = "input string data"
            },
            parameter:new {
                long = "repeat-count", short = "n", type = "number", default = 1,
                help = "print input this much times."
            }
        }:operation(function(args)
            for _ = 1, args.repeat_count do
                print(args.input)
            end
        end)
    }

local app = application:new("app-name", "0.1.0", cmd)
app:run()
```
