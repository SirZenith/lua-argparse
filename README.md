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

If you are to write some completion script for you shell, check out `--shell-completion-flags`
and `--shell-completion-subcommands` flags. When provided, all positional arguments
and other flags are ignored, instead of running command action, command prints
completion information of itself to stdout.

```shell
lua example.lua what ever value --shell-completion-subcommands
```

Output:

```
help:show help message for command
say:sample subcommand
```

# Overview

This script provide type `Parameter`, `Command`, `ArgParser`, `Application`.

`Parameter` is a struct where you put all you specification of arguments. Like
parameter name, value type, etc..

`Command` is used for structuring your operation function. A `Command` has help
info, parameters, operation that bind with it, and subcommands if you want.
And every `Command` will got a `help` subcommand when they gets created.

`ArgParser`, with a given `Command` and a list of string arguments, it can locate
target specified by arguments in you command tree, and return a `table<string, any>`
containing parsed parameters. That table uses parameter's name as key.

`Application` is a extended `Command` that sotres more meta infomation, and serves
as entrance of your command tree.

# API

Following documentation describes master branch of this repo. If you want to read
the doc for specific version, please switch to corresponding git tag.

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
- `is_hidden`: If set to true, this parameter will be hidden when `help` command
  is ran without `--show-all` flag.
- `is_internal`: If set to true, this parameter won't be printed in `help` command
  event with `--show-all` flag.
- `topics`: A list of topic this parameter belongs to, useful for filtering help
  message output.

---

**Static methods**

- `Parameter:new(config: ParameterCfg): Parameter`

  constructor. Passed argument is a table, in which keys are field name of this
  class, and values are corresponding value of each field.

  This table must contains at least one of `name` or `long`.

---

**Methods**

- `self:is_flag(): boolean`

  Check if current parameter is a flag.
- `self:is_match_topic(topic?: string): boolean`

  Check if current parameter belongs to given topic.

## `Command`

`help` subcommand is added on its creation.

Help command do takes positional argument and flags.

`--show-all` is a bool flag, indication print out all hidden subcommands and
parameters too.

`--list-topic` is a bool flag that tells help command to list all available topics
of current command.

One topic can be specified by positional argument. If given, only parameters and
subcommands that belongs to given topic will be printed in help mesasge.

And all commands has following two flags: `--shell-completion-flags`,
`--shell-completion-subcommands`. These flags can be useful when generating or
defining shell completion. They can list all available non-internal flags and
subcommands respectively.

**Fields**

- `name`: Command's name, used index in command tree, should be unique among its
  siblings.
- `help`: Help description for this command.
- `is_hidden`: If this command should be hidden when `help` command is run without
  `--show-all` flag.
- `is_internal`: If set to true, this command won't be printed in `help` command
  event with `--show-all` flag.
- `topics`: A list of topic this command belongs to. Userful for filtering help
  message output.
- `no_help_cmd`: Only used during construction, when set to true, no help subcommand
  will be created for this command.,

---

**Static Methods**

- `Command:new(config: CommandCfg): Command`

  constructor. Passed argument is a table, in which keys are field name of this
  class, and values are corresponding value of each field.

  This table must contains `name` field.

---

**Methods**

  Each method return `self`, so that chainning method calls is possible.

- `self:run_help()`

  Run `help` subcommand of current if it exists.

- `self:subcommand(commands: Command[]): Command`

  Adds a list of subcommands as children of current command.
- `self:parameter(params: (Parameter|ParameterCfg)[]): Command`

  Adds a list of parameters to current command. Each element in the list can either
  be an actual `Parameter` or a table you passed to `Parameter`'s constructor.

- `self:operation(op: fun(table<string, any>))`
  Set operation function of this command.

  When command gets executed, parsed argument table will be passed to this function
  as argument.
- `self:is_match_topic(topic?: string): boolean`

  Check if current command belongs given topic.
- `self:get_topic_list(): stirng[]`

  Returns a list of all available topics under this command.
- `self:gen_completion_for_subcommands(): string[]`

  Returns a unsorted list of all non-internal subcommands.
- `self:gen_completion_for_flags(): stirng[]`

  Returns a unsorted list of all non-internal flags.

## `ArgParser`

**Static Mehtods**

- `ArgParser:new(): ArgParser`

  Constructor.

---

**Methods**

- `self:parse_arg(cmd: Command, arg_in: string[]?): Command, table<string, any>, string[]?`,
  - `cmd` is the target command tree that needs to be executed.
  - `arg_in` is string argument list, if its `nil`, global variable `arg` will be used.

  First returned value is target command taken from command tree, specified by
  given argument list.

  Second argument is parsed argument table, with parameters' name as its keys.

  Any error encountered during parsing argument list, will be propagated to caller
  as an error message by third return value.

## `Application`

Inheriting `Command`. Do all things `Command` does.

When executed, if target command specified by argument list has no operation, its
help message will be printed.

**Fields**

- `version`: A string value indicating version of this application. Used in generated
  `help` command.

---

**Method**

- `self:info_str(): string`

  Returns meta info as string.
- `self:run_with_args(args_in: stirng[])`

  Takes a stirng argument list, parse it and run target command.
- `self:run()`

  Parse and run command with global variable `arg` as argument list.

