# 0.2.1

## Feature

- Add display of parameter default value to help message.
- Now parameters and subcommand can have topics binded, topics can be used for
  filtering help message.
- Parameters and subcommand can be marked as `hidden`. Those parameters and subcommands
  will only get printed in help message when `help` command is ran with `--show-all`
  flag.

## Fix

- When subcommand located by arguments has no binded operation, print its help
  message, instead of root command's.

## Breaking

- `help` commands created when constructing `Command` no longer takes subcommands
  path as argument, instead, it takes topic name now.

## Others

- Reformat help message to make different types of element can be distingushed
  easier.

# 0.2.0

## Feature

- Add support for repeatable arguments. Now both flags and positional arguments
  can appear more than once in argument list, if they are defined to allow so in
  you parameter list.
- `help` command will be added for all command. And `help` command can not take
  a child path list as argument.

## Breaking

- Underscore field `_argParser` of `Application` class is renamed to `_arg_parser`.
- `run_help` method is moved from `Application` class to `Command` class.

## Others

- Format of help message is changed.
- LuaCATS of types are now prefixed with module namespace.
