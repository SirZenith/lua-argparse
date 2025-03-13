# 0.2.0

## Feature

- Add support for repeatable arguments. Now both flags and positional arguments
  can appear more than once in argument list, if they are defined to allow so in
  you paramerter list.

## Breaking

- Underscore field `_argParser` of `Application` class is renamed to `_arg_parser`.

## Others

- Format of help message is changed.
- LuaCATS of types are now prefixed with module namespace.
