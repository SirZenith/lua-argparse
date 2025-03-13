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

## `Parameter`

**Fields**

- `name`: Parameter's name, this will be used as key in parsed argument table.
- `long`: When provided, this parameter becomes a flag. A parameter name can be
  generated automatical from long flag, by replacing `-` with `_`.
- `short`: When provided, this parameter becomes a flag.
- `required`: A boolean value indicating if this parameter must be provided by
  caller.
- `type`: Parameter type string, possible values are `string`, `boolean`, `number`.
- `help`: Help description of this parameter.
- `default`: Default value of this parameter if you don't want it to be `nil` in
  parsed argument table when its missing.
- `max_cnt`: Maximum repeat count of assignment of this parameter. User can pass
  this parameter from command line, no matter it's a flag or positional one, this
  many times or less.

  By default this value is one. Otherwise, parsed value of this parameter will be
  a list instead of a plain value.

  When this value is set to non-positive, this parameter can be repeated infinite
  many times.

---

**Static methods**

- `Parameter:new(config: ParameterCfg): Parameter`

  constructor. Passed argument is a table, in which keys are field name of this
  class, and values are corresponding value of each field.

  This table must contains at least one of `name` or `long`.

## `Command`

**Fields**

- `name`: Command's name, used index in command tree, should be unique among its
  siblings.
- `help`: Help description for this command.

---

**Static Methods**

- `Command:new(config: CommandCfg): Command`

  constructor. Passed argument is a table, in which keys are field name of this
  class, and values are corresponding value of each field.

  This table must contains `name` field.

---

**Methods**

  Each method return `self`, so that chainning method calls is possible.

- `self:subcommand(commands: Command[]): Command`

  Adds a list of subcommands as children of current command.
- `self:parameter(params: (Parameter|ParameterCfg)[]): Command`

  Adds a list of parameters to current command. Each element in the list can either
  be an actual `Parameter` or a table you passed to `Parameter`'s constructor.

- `self:operation(op: fun(table<string, any>))`
  Set operation function of this command.

  When command gets executed, parsed argument table will be passed to this function
  as argument.

## `ArgParser`

**Static Mehtods**

- `ArgParser:new(): ArgParser`

  Constructor.

---

**Methods**

- `self:parse_arg(cmd: Command, arg_in: string[]?): Command?, table<string, any>?, string?`,
  - `cmd` is the target command tree that needs to be executed.
  - `arg_in` is string argument list, if its `nil`, global variable `arg` will be used.

  First returned value is target command taken from command tree, specified by
  given argument list.

  Second argument is parsed argument table, with parameters' name as its keys.

  Any error encountered during parsing argument list, will be propagated to caller
  as an error message by third return value.

## `Application`

Inheriting `Command`. Do all things `Command` does, `help` subcommand is added
on created.

When executed, if target command specified by argument list has no operation, its
help message will be printed.

**Fields**

- `version`: A string value indicating version of this application. Used in generated
  `help` command.

---

**Method**

- `self:info_str(): string`

  Returns meta info as string.
- `self:run_help()`

  Prints help info.
- `self:run_with_args(args_in: stirng[])`

  Takes a stirng argument list, parse it and run target command.
- `self:run()`

  Parse and run command with global variable `arg` as argument list.

