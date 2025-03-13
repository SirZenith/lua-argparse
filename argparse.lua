local unpack = unpack or table.unpack

local FLAG_START = "-"

-----------------------------------------------------------------------------

---@type table<string, fun(string): boolean, any>
local TypeConverter = {
    string = function(value)
        return true, value
    end,
    boolean = function(value)
        if value == nil then
            return true, true
        elseif value:lower() == "false" or value:lower() == "f" then
            return true, false
        else
            return true, true
        end
    end,
    number = function(value)
        local result = tonumber(value)
        return result ~= nil, result
    end
}

-- Return true if tab is a empty table
---@param tab table
---@return boolean
local function is_empty(tab)
    if not tab then return true end

    local check = true
    for _, _ in pairs(tab) do
        check = false
        break
    end
    return check
end

-----------------------------------------------------------------------------
-- Parameter for command

---@class argparse.ParameterCfg # A table of data indicating how to create a parameter.
---@field name? string # Name for parameter, if not provided, this will try to be set to long flag name.
---@field long? string # Long flag name of parameter.
---@field short? string # Short flag name of parameter, default to nil.
---@field required? boolean # Set whether the parameter must be provided.
---@field type string # Type of the parameter.
---@field help? string # Help info for the parameter.
---@field default? any # Default value for the parameter.
---@field max_cnt? integer # Max repeat number of this parameter. Default to 1, non-positive value means infinite.

---@class argparse.Parameter: argparse.ParameterCfg # Meta info about parameter of a command
---@field name string
---@field _converter fun(value: string): boolean, any # Function that convert command line string to target type
local Parameter = {}
Parameter.__index = Parameter

---@return string
function Parameter:__tostring()
    local buffer = { self.name }

    if not self.required then
        table.insert(buffer, "?")
    end

    if self.short then
        table.insert(buffer, " (-")
        table.insert(buffer, self.short)
    end
    if self.long and not self.short then
        table.insert(buffer, " (--")
        table.insert(buffer, self.long)
        table.insert(buffer, ")")
    elseif self.long then
        table.insert(buffer, ", --")
        table.insert(buffer, self.long)
        table.insert(buffer, ")")
    elseif self.short then
        table.insert(buffer, ")")
    end

    table.insert(buffer, ": ")
    table.insert(buffer, self.type)

    if self.max_cnt == 1 then
        -- pass
    elseif self.max_cnt > 1 then
        table.insert(buffer, ", ")
        table.insert(buffer, "max_repeat(")
        table.insert(buffer, tostring(self.max_cnt))
        table.insert(buffer, ")")
    else
        table.insert(buffer, ", ")
        table.insert(buffer, "max_repeat(Inf)")
    end

    return table.concat(buffer)
end

-- new creates a new parameter with given config meta.
---@param config argparse.ParameterCfg
---@return argparse.Parameter
function Parameter:new(config)
    local this = setmetatable({}, self)

    this.long = config["long"]
    this.short = config["short"] or nil
    this.name = config["name"] or (this.long and this.long:gsub("-", "_") or "")
    assert(this.name, "parameter must have a name or long flag name.")
    assert(
        this.short == nil or #this.short == 1,
        string.format("short flag for parameter '%s' has more than one letter (-%s)", this.name, this.short)
    )

    this.required = config["required"] or false
    this.type = config["type"] or "string"
    this._converter = TypeConverter[this.type]
    assert(this._converter, string.format("invalid type for parameter %s: %s", this.name, this.type))
    this.default = config["default"]
    assert(
        this.default == nil or type(this.default) == this.type,
        string.format(
            "'%s': type of default value(%s) doesn't match parameter type(%s)",
            this.name, type(this.default), type(this.type)
        )
    )
    this.help = config["help"] or nil

    this.max_cnt = type(config.max_cnt) == "number" and config.max_cnt or 1

    return this
end

-----------------------------------------------------------------------------

---@class argparse.CommandCfg # A table of data used to create a new command.
---@field name string
---@field help? string

---@class argparse.Command: argparse.CommandCfg
---@field _subcommand_list argparse.Command[] # Array storing subcommands. To preserve adding order of subcommands.
---@field _subcommands table<string, argparse.Command> # A table that map subcommand name to Command object.
---@field _parameters argparse.Parameter[] # List for all Parameters
---@field _flags table<string, argparse.Parameter> # A table that map flags to Parameter object.
---@field _positionals argparse.Parameter[] # A list for positional arguments
---@field _operation fun(args: table<string, any>) # Operation bind to the command, take target command object as input.
local Command = {}
Command.__index = Command
Command._indent = "    "
Command._indent_secondary = "  "

-- Find target command using argument list, returning command found and arguments
-- left in the list. panic if not command is current binding to ArgParser.
---@param cmd argparse.Command
---@param arg_in string[]
---@return argparse.Command cmd
---@return string[] argListSlice
local function direct_to_cmd(cmd, arg_in)
    local index = 1
    if not cmd then
        error("no valid command is passed to ArgParser", 1)
    end

    while arg_in[index] do
        local name = arg_in[index]
        if not cmd._subcommands[name] then break end
        cmd = cmd._subcommands[name]
        index = index + 1
    end

    return cmd, { unpack(arg_in, index, #arg_in) }
end

-- new creates a new command with given meta config.
---@param config table<string, string>
---@return argparse.Command
function Command:new(config)
    local this = setmetatable({}, self)

    this.name = config["name"]
    this.help = config["help"]
    assert(this.name, "name must be provided for a command")
    this._subcommand_list = {}
    this._subcommands = {}
    this._parameters = {}
    this._flags = {}
    this._positionals = {}
    this._operation = nil

    if this.name ~= "help" then
        this:subcommand {
            Command:new {
                name = "help", help = "show help message for command"
            }:parameter {
                { name = "path", type = "string", max_cnt = 0 }
            }:operation(function(args)
                local path = args.path
                local target, left_args = this, nil

                if path then
                    target, left_args = direct_to_cmd(this, path)
                end

                if not left_args or #left_args == 0 then
                    print(target)
                else
                    print("command not found")
                end
            end)
        }
    end

    return this
end

---@return string
function Command:__tostring()
    local buffer = self:_to_string()
    local cnt = 0
    for _, s in ipairs(buffer) do
        if s == "\n" then
            cnt = cnt + 1
        end
    end
    return table.concat(buffer)
end

---@param buffer? string[]
---@param indent? string
---@return string[]
function Command:_to_string(buffer, indent)
    buffer = buffer or {}
    indent = indent or ""

    table.insert(buffer, indent)
    -- if indent ~= "" then
    table.insert(buffer, "* ")
    -- end
    table.insert(buffer, self.name)

    -- title line
    if not is_empty(self._subcommands) then
        table.insert(buffer, " [Subcommand]")
    end
    if not is_empty(self._flags) then
        table.insert(buffer, " [Options]")
    end
    if not is_empty(self._positionals) then
        table.insert(buffer, " ")

        for i, param in ipairs(self._positionals) do
            if i > 1 then
                table.insert(buffer, " ")
            end

            table.insert(buffer, string.format("<%s>", param.name))
        end
    end

    -- help info
    if self.help then
        table.insert(buffer, "\n")

        table.insert(buffer, indent)
        table.insert(buffer, Command._indent_secondary)
        table.insert(buffer, "|=> ")
        table.insert(buffer, self.help)
    end

    -- parameters
    if #self._parameters > 0 then
        table.insert(buffer, "\n")
        table.insert(buffer, "\n")
        table.insert(buffer, indent .. Command._indent_secondary .. "|-- Parameters")

        for _, param in ipairs(self._parameters) do
            table.insert(buffer, "\n")

            table.insert(buffer, indent)
            table.insert(buffer, Command._indent)
            table.insert(buffer, "- ")
            table.insert(buffer, tostring(param))

            if param.help and #param.help ~= 0 then
                table.insert(buffer, "\n")
                table.insert(buffer, indent)
                table.insert(buffer, Command._indent)
                table.insert(buffer, Command._indent_secondary)
                table.insert(buffer, "|> ")
                table.insert(buffer, param.help)
            end
        end
    end

    -- subcommands
    if not is_empty(self._subcommands) then
        table.insert(buffer, "\n")
        table.insert(buffer, "\n")
        table.insert(buffer, indent .. Command._indent_secondary .. "|-- Subcommands")

        for _, cmd in ipairs(self._subcommand_list) do
            table.insert(buffer, "\n")
            -- cmd:_to_string(buffer, indent .. Command._indent)
            table.insert(buffer, indent)
            table.insert(buffer, Command._indent)
            table.insert(buffer, "* ")
            table.insert(buffer, cmd.name)
        end
    end

    return buffer
end

do
    ---@param map table<string, any>
    ---@param mapName string
    ---@param key string
    ---@param value any
    local function try_add_to_map(map, mapName, key, value)
        local check = map[key]
        assert(check == nil, string.format("duplicated %s key: %s", mapName, key))
        map[key] = value
    end

    -- Adding subcommands to command
    ---@param commands argparse.Command[]
    ---@return argparse.Command
    function Command:subcommand(commands)
        for _, cmd in ipairs(commands) do
            try_add_to_map(self._subcommands, "Command", cmd.name, cmd)
            table.insert(self._subcommand_list, cmd)
        end
        return self
    end

    -- parameter adds a list of parameters to current command.
    ---@param parameters (argparse.ParameterCfg | argparse.Parameter)[]
    ---@return argparse.Command
    function Command:parameter(parameters)
        for _, param in ipairs(parameters) do
            if getmetatable(param) ~= Parameter then
                param = Parameter:new(param)
            end

            if param.long then
                try_add_to_map(self._flags, "Long Flag", "--" .. param.long, param)
            end
            if param.short then
                try_add_to_map(self._flags, "Short Flag", "-" .. param.short, param)
            end
            if not param.long and not param.short then
                table.insert(self._positionals, param)
            end
            table.insert(self._parameters, param)
        end
        return self
    end
end

-- operation sets action function to call when command gets ran. `args` is a table
-- of parsed command arguments.
---@param op fun(args: table<string, any>)
function Command:operation(op)
    self._operation = op
    return self
end

-----------------------------------------------------------------------------

---@class argparse.ArgParser
---@field _pos_index integer # Index of next positional parameter to be used
local ArgParser = {}
ArgParser.__index = ArgParser

-- new creates a new argument parser.
---@return argparse.ArgParser
function ArgParser:new()
    local this = setmetatable({}, self)
    this._pos_index = 1
    return this
end

---@param _ argparse.Parameter
function ArgParser:_increment_pos_index(_)
    self._pos_index = self._pos_index + 1
end

do
    -- Fill all default values into command args map
    ---@param cmd argparse.Command
    local function setup_default_value(cmd)
        local arg_out = {}
        local stack = { cmd }
        while #stack ~= 0 do
            local size = #stack
            cmd = stack[size]
            stack[size] = nil

            for _, subcmd in pairs(cmd._subcommands) do
                table.insert(stack, subcmd)
            end

            for _, flag in pairs(cmd._flags) do
                local name = flag.name

                if flag.max_cnt and flag.max_cnt ~= 1 then
                    arg_out[name] = {}
                else
                    arg_out[name] = flag.default
                end
            end

            for _, pos in ipairs(cmd._positionals) do
                local name = pos.name

                if pos.max_cnt and pos.max_cnt ~= 1 then
                    arg_out[name] = {}
                else
                    arg_out[name] = pos.default
                end
            end
        end
        return arg_out
    end

    -- Store a flag value to arg map, panic when failed
    ---@param args table<string, any>
    ---@param cmd argparse.Command
    ---@param flag string
    ---@param value any
    local function store_flag(args, cmd, flag, value)
        local param = cmd._flags[flag]
        if not param then
            error("unexpected flag: " .. flag, 0)
        end

        local ok, converted = param._converter(value)
        if not ok then
            local msg = ("failed to convert '%s' to type %s for flag '%s'"):format(value, param.name, flag)
            error(msg, 0)
        elseif param.max_cnt == 1 then
            -- single time value
            args[param.name] = converted
        else
            -- store repeatable value
            local name = param.name
            local list = args[name]
            if not list then
                list = {}
                args[name] = list
            end

            if param.max_cnt > 0 and #list >= param.max_cnt then
                local msg = ("flag %s is passed more times than allowed"):format(flag)
                error(msg, 0)
            end

            table.insert(list, converted)
        end

        return nil
    end

    -- Store a positional argument to arg map, panic when failed
    ---@param parser argparse.ArgParser
    ---@param args table<string, any>
    ---@param cmd argparse.Command
    ---@param value any
    local function store_positional(parser, args, cmd, value)
        local param = cmd._positionals[parser._pos_index]
        if not param then
            error("unexpected positional parameter: " .. value, 0)
        end

        local ok, converted = param._converter(value)
        if not ok then
            local msg = string.format(
                "failed to convert '%s' to type '%s' for positional parameter '%s'",
                value, param.type, param.name
            )
            error(msg, 0)
        elseif param.max_cnt == 1 then
            -- single value argument
            args[param.name] = converted
            parser:_increment_pos_index(param)
        else
            -- repeatable argument
            local name = param.name
            local list = args[name]
            if not list then
                list = {}
                args[name] = list
            end

            table.insert(list, converted)

            if param.max_cnt > 0 and #list >= param.max_cnt then
                parser:_increment_pos_index(param)
            end
        end
    end

    -- Read all command argument into arg map panic when failed
    ---@param parser argparse.ArgParser
    ---@param arg_out table<string, any>
    ---@param cmd argparse.Command
    ---@param arg_in string[]
    local function settle_arguments(parser, arg_out, cmd, arg_in)
        local flag = nil
        for _, a in ipairs(arg_in) do
            if a:sub(1, 1) == FLAG_START then
                -- if encountering a new flag
                if flag ~= nil then
                    store_flag(arg_out, cmd, flag, nil)
                end
                flag = a
            elseif flag ~= nil then
                -- if encounter value paired with previous flag
                store_flag(arg_out, cmd, flag, a)
                flag = nil
            else
                -- positional argument
                store_positional(parser, arg_out, cmd, a)
            end
        end

        if flag ~= nil then
            store_flag(arg_out, cmd, flag, nil)
        end
    end

    -- helper function for required parameter checking
    ---@param missing_list string[] Message list for missing parameters.
    ---@param param_list argparse.Parameter[] Parameter list to check.
    ---@param value_map table<string, any> Table that stores value of each parameter.
    ---@param msg_maker fun(param: argparse.Parameter): string Function that makes error messgae based on a Parameter
    local function check_required_paramlist(missing_list, param_list, value_map, msg_maker)
        for _, param in pairs(param_list) do
            if param.required then
                local is_missing = false

                if param.max_cnt == 1 then
                    is_missing = value_map[param.name] == nil
                else
                    local list = value_map[param.name]
                    is_missing = not list or #list < 1
                end

                if is_missing then
                    table.insert(missing_list, msg_maker(param))
                end
            end
        end
    end

    -- Check whether all required parameters are given, panic if have missing
    ---@param args table<string, any>
    ---@param cmd argparse.Command
    local function check_all_required(args, cmd)
        local missing = {}
        check_required_paramlist(missing, cmd._flags, args, tostring)
        check_required_paramlist(missing, cmd._positionals, args, tostring)
        if #missing ~= 0 then
            local indent = "\n    "
            local msg = "following parameter(s) is required, but missing:"
                .. indent .. table.concat(missing, indent)
            error(msg, 0)
        end
    end

    -- parse_arg tries to parse arguments and put results in to Command object
    -- binded to this parser.
    -- Returns target command specified by arguments and a possible error message.
    ---@param cmd argparse.Command
    ---@param arg_in? string[]
    ---@return argparse.Command? cmd
    ---@return table<string, any>? args
    ---@return string? err
    function ArgParser:parse_arg(cmd, arg_in)
        arg_in = arg_in or arg
        self._pos_index = 1

        local ok, result, args = pcall(function()
            local left_args
            cmd, left_args = direct_to_cmd(cmd, arg_in)

            local arg_out = setup_default_value(cmd)
            settle_arguments(self, arg_out, cmd, left_args)

            check_all_required(arg_out, cmd)

            return cmd, arg_out
        end)

        if not ok then
            return nil, nil, result --[[@as string]]
        end

        return result, args, nil
    end
end

-----------------------------------------------------------------------------

---@class argparse.ApplicationCfg : argparse.CommandCfg
---@field version string

---@class argparse.Application : argparse.Command, argparse.ApplicationCfg # A command that has version infomation and help subcommand.
---@field _arg_parser argparse.ArgParser
local Application = setmetatable({}, Command)
Application.__index = Application

do
    local Super = Command

    -- new creates a new application with
    ---@param config argparse.ApplicationCfg
    ---@return argparse.Application
    function Application:new(config)
        local this = Super.new(self, config) --[[@as argparse.Application]]

        this.version = config["version"] or "0.1.0"
        this._arg_parser = ArgParser:new()

        return this
    end

    function Application:__tostring()
        local metainfo = self:info_str()
        local help = Super.__tostring(self)
        return metainfo .. "\n\n" .. help
    end

    function Application:info_str()
        return string.format("%s (%s)", self.name, self.version)
    end

    function Application:run_help()
        self._subcommands.help._operation {}
    end

    -- run_with_args parses given arguments and run target command's operation.
    ---@param args_in string[] # command arguments
    function Application:run_with_args(args_in)
        local cmd, args, errmsg = self._arg_parser:parse_arg(self, args_in)
        if not cmd or not args or errmsg then
            io.stderr:write(errmsg or "unknown error")
            io.stderr:write("\n")
            os.exit(1)
        end

        if not cmd._operation then
            self:run_help()
        else
            cmd._operation(args)
        end
    end

    -- run parses arguments provided by command and run target command's operation.
    function Application:run()
        self:run_with_args(arg)
    end
end

return {
    Parameter = Parameter,
    Command = Command,
    ArgParser = ArgParser,
    Application = Application,
}
