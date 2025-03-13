# 0.2.0

## Feature

- Add support for repeatable arguments. Now both flags and positional arguments
  can appear more than once in argument list, if they are defined to allow so in
  you paramerter list.
- `help` command will be added for all command. And `help` command can not take
  a child path list as argument.

## Breaking

- Underscore field `_argParser` of `Application` class is renamed to `_arg_parser`.
- `run_help` method is moved from `Application` class to `Command` class.

## Others

- Format of help message is changed.
- LuaCATS of types are now prefixed with module namespace.
