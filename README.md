# Quick Start

```lua
local argparse = require "argparse"
local Application = argparse.Application
local Command = argparse.Command

local app = Application
    :new {
        name = "foo", version = "0.1.0", help = "sample command"
    }:subcommand {
        Command:new {
            name = "say", help = "sample subcommand"
        }:parameter {
            {
                name = "input",
                type = "string",
                required = true,
                max_cnt = 0,
                help = "input string data"
            },
            {
                long = "repeat-count",
                short = "n",
                type = "number",
                default = 1,
                help = "print input this much times"
            }
        }:operation(function(args)
            local input = table.concat(args.input, ", ")
            for _ = 1, args.repeat_count do
                print(input)
            end
        end)
    }

app:run()
```

Save this code snippet into `example.lua`, then you can print help message with
command:

```
lua example.lua help
```

Try running it with some arguments:

```
lua example.lua say hello world -n 5
```

This command generates following output:

```
hello, world
hello, world
hello, world
hello, world
hello, world
```

# Overview

This script provide type `Parameter`, `Command`, `ArgParser`, `Application`.

`Parameter` is a struct where you put all you specification of arguments. Like
parameter name, value type, etc..

`Command` is used for structuring your operation function. A `Command` has help
info, parameters, operation that bind with it, and subcommands if you want.

`ArgParser`, with a given `Command` and a list of string arguments, it can locate
target specified by arguments in you command tree, and return a `table<string, any>`
containing parsed parameters. That table uses parameter's name as key.

`Application` is a extended `Command` that sotres more meta infomation, and serves
as entrance of your command tree. And every `Application` will got a `help` subcommand
when they're created.

# API

- `Parameter`
  - fields
    - name
    - long
    - short
    - required
    - type
    - default
    - help
  - static methods
    - `Parameter:new(config: table<string, any>): Parameter`, constructor each
      field of object can be set by config table passed in, if they appears in
      the table. Config must contains one of `name` or `long`.
- `Command`
  - fields
    - name
    - help
  - static methods
    - `Command:new(config: table<string, any>): Command`, each field of object
      can be set by config table passed in, if they appears in the table. Config
      must have a `name` field.
  - methods. Each method return `self`, so that chainning method calls are possible.
    - `self:subcommand(commands: Command[]): Command`, adding commands in list
      as subcommand.
    - `self:parameter(params: (Parameter|table<string, any>)[]): Command`,
      adding parameters in lsit to command. List item can either be `Parameter`
      or parameter config table.
    - `self:operation(op: fun(table<string, any>))`, bind operation to command.
      Operation should be function which takes parameter value map as argument.
- `ArgParser`
  - static methods
    - `ArgParser:new(): ArgParser`, constructor.
  - methods
    - `self:parse_arg(cmd: Command, arg_in: string[]?): Command, table<string, any>, string?`,
    `cmd` is the target command group for parsing. `arg_in` is string argument
    list, if `nil`, will use `arg` as its value.
- `Application`, inheriting `Command`. Do all things `Command` does, adding a help
  command to itself when instantiated.
  - fields
    - version
  - methods
    - `self:info_str(): string`, return meta info by string.
    - `self:run_help()`, print help info. `Application` will print its help info
      if command arguments points to a command without operation.
    - `self:run()`, parse command line argument and run target operation.

