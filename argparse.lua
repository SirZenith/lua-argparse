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

-----------------------------------------------------------------------------
-- Parameter for command

---@class Parameter Meta info about parameter of a command
---@field long? string Long flag name of parameter.
---@field short? string Short flag name of parameter, default to nil.
---@field name string Name for parameter, if not provided, this will try to be set to long flag name.
---@field required boolean Set whether the parameter must be provided.
---@field type string Type of the parameter.
---@field _converter fun(value: string): boolean, any Function that convert command line string to target type
---@field help string Help info for the parameter.
---@field default any Default value for the parameter.
local Parameter = {}
Parameter.__index = Parameter

---@return string
function Parameter:__tostring()
    local str = string.format("%s: %s", self.name, self.type)

    if self.short then
        str = str .. " (-" .. self.long
    end
    if self.long and not self.short then
        str = str .. " (--" .. self.long .. ")"
    elseif self.long then
        str = str .. ", --" .. self.long .. ")"
    elseif self.short then
        str = str .. ")"
    end

    return str
end

---@param config table<string, any>
---@return Parameter
function Parameter:new(config)
    local this = setmetatable({}, self)

    this.long = config["long"]
    this.short = config["short"] or nil
    this.name = config["name"] or (this.long and this.long:gsub("-", "_") or nil)
    assert(this.name, "parameter must have a name or long flag name.")
    assert(
        this.short == nil or #this.short == 1,
        string.format("short flag for parameter '%s' has more than one letter (-%s)", this.name, this.short)
    )

    this.required = config["required"] or false
    this.type = config["type"] or "string"
    this._converter = TypeConverter[this.type]
    assert(this._converter, string.format("invalide type for parameter %s: %s", this.name, this.type))
    this.default = config["default"]
    assert(
        this.default == nil or type(this.default) == this.type,
        string.format(
            "'%s': type of default value(%s) doesn't match parameter type(%s)",
            this.name, type(this.default), type(this.type)
        )
    )
    this.help = config["help"] or nil

    return this
end

-----------------------------------------------------------------------------

---@class Command
---@field name string
---@field help? string
---@field _subcommands table<string, Command> A table that map subcommand name to Command object.
---@field _parameters Parameter[] List for all Parameters
---@field _flags table<string, Parameter> A table that map flags to Parameter object.
---@field _positionals Parameter[] A list for positional arguments
---@field _operation fun(args: table<string, any>) Operation bind to the command, take target command object as input.
local Command = {}
Command.__index = Command
Command.indent = "    "

---@param config table<string, string>
---@return Command
function Command:new(config)
    local this = setmetatable({}, self)

    this.name = config["name"]
    this.help = config["help"]
    assert(this.name, "name must be provided for a command")
    this._subcommands = {}
    this._parameters = {}
    this._flags = {}
    this._positionals = {}
    this._operation = nil

    return this
end

---@return string
function Command:__tostring()
    local strList = self:_to_string()
    return table.concat(strList, "\n")
end

---@param strlist? string[]
---@param indent? string
---@return string[]
function Command:_to_string(strlist, indent)
    strlist = strlist or {}
    indent = indent or ""
    local list
    local name_sorter = function(a, b) return a.name < b.name end

    local title = indent .. self.name
    if self.help then
        title = title .. ": " .. self.help
    end
    table.insert(strlist, title)

    -- parameter serialize
    list = { table.unpack(self._parameters) }
    table.sort(list, name_sorter)
    for _, param in ipairs(list) do
        local msg = indent .. Command.indent .. "- " .. tostring(param)
        if param.help and #param.help ~= 0 then
            msg = msg .. ", " .. param.help
        end
        table.insert(strlist, msg)
    end

    -- subcommand serialize
    list = {}
    for name, _ in pairs(self._subcommands) do
        table.insert(list, name)
    end
    table.sort(list)
    if #list ~= 0 then
        table.insert(strlist, "")
        table.insert(strlist, indent .. Command.indent .. "** Subcommands **")
        table.insert(strlist, "")
    end
    for _, name in ipairs(list) do
        local cmd = self._subcommands[name]
        cmd:_to_string(strlist, indent .. Command.indent)
    end
    table.insert(strlist, "")

    return strlist
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
    ---@param commands Command[]
    ---@return Command
    function Command:subcommand(commands)
        for _, cmd in ipairs(commands) do
            try_add_to_map(self._subcommands, "Command", cmd.name, cmd)
        end
        return self
    end

    -- Adding parameters to command
    ---@param parameters Parameter[]|table<string, any>[]
    ---@return Command
    function Command:parameter(parameters)
        for _, param in ipairs(parameters) do
            if getmetatable(param) ~= Parameter then
                param = Parameter:new(param)
            end

            table.insert(self._parameters, param)
            if param.long then
                try_add_to_map(self._flags, "Long Flag", "--" .. param.long, param)
            end
            if param.short then
                try_add_to_map(self._flags, "Short Flag", "-" .. param.short, param)
            end
            if not param.long and not param.short then
                table.insert(self._positionals, param)
            end
        end
        return self
    end
end

---@param op fun(args: table<string, any>)
function Command:operation(op)
    self._operation = op
    return self
end

-----------------------------------------------------------------------------

---@class ArgParser
---@field _pos_index integer Index of next positional parameter to be used
local ArgParser = {}
ArgParser.__index = ArgParser

---@return ArgParser
function ArgParser:new()
    local this = setmetatable({}, self)
    this._pos_index = 1
    return this
end

---@param _ Parameter
function ArgParser:_increment_pos_index(_)
    self._pos_index = self._pos_index + 1
end

do
    -- Fill all default values into command args map
    ---@param cmd Command
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
                arg_out[flag.name] = flag.default
            end

            for _, pos in ipairs(cmd._positionals) do
                arg_out[pos.name] = pos.default
            end
        end
        return arg_out
    end

    -- Find target command using argument list, returning command found and arguments
    -- left in the list. panic if not command is current binding to ArgParser.
    ---@param arg_in string[]
    ---@return Command cmd
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

        return cmd, { table.unpack(arg_in, index, #arg_in) }
    end

    -- Store a flag value to arg map, panic when failed
    ---@param args table<string, any>
    ---@param cmd Command
    ---@param flag string
    ---@param value any
    local function store_flag(args, cmd, flag, value)
        local param = cmd._flags[flag]
        if not param then
            error("unexpected flag: " .. flag, 0)
        end

        local ok, converted = param._converter(value)
        if ok then
            args[param.name] = converted
        else
            local msg = string.format("failed to convert '%s' to type %s for flag '%s'", value, param.name, flag)
            error(msg, 0)
        end

        return nil
    end

    -- Store a positional argument to arg map, panic when failed
    ---@param parser ArgParser
    ---@param args table<string, any>
    ---@param cmd Command
    ---@param value any
    local function store_positional(parser, args, cmd, value)
        local param = cmd._positionals[parser._pos_index]
        if not param then
            error("unexpected positional parameter: " .. value, 0)
        end

        local ok, converted = param._converter(value)
        if ok then
            args[param.name] = converted
            parser:_increment_pos_index(param)
        else
            local msg = string.format(
                "failed to convert '%s' to type '%s' for positional parameter '%s'",
                value, param.type, param.name
            )
            error(msg, 0)
        end
    end

    -- Read all command argument into arg map panic when failed
    ---@param parser ArgParser
    ---@param arg_out table<string, any>
    ---@param cmd Command
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
    ---@param param_list Parameter[] Parameter list to check.
    ---@param value_map table<string, any> Table that stores value of each parameter.
    ---@param msg_maker fun(param: Parameter): string Function that makes error messgae based on a Parameter
    local function check_required_paramlist(missing_list, param_list, value_map, msg_maker)
        for _, param in pairs(param_list) do
            if param.required and value_map[param.name] == nil then
                table.insert(missing_list, msg_maker(param))
            end
        end
    end

    -- Check whether all required parameters are given, panic if have missing
    ---@param args table<string, any>
    ---@param cmd Command
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

    -- Try to parse arguments and put results in to Command object bind to this parser.
    -- Return Command specified by arguments and an error message, message is nil when
    -- no error occured.
    ---@return Command cmd
    ---@param arg_in? string[]
    ---@return Command cmd
    ---@return table<string, any> args
    ---@return string? errmsg
    function ArgParser:parse_arg(cmd, arg_in)
        arg_in = arg_in or arg
        self._pos_index = 1
        local ok, result, args = pcall(function()
            local arg_out = setup_default_value(cmd)

            local left_args
            cmd, left_args = direct_to_cmd(cmd, arg_in)
            settle_arguments(self, arg_out, cmd, left_args)
            check_all_required(arg_out, cmd)
            return cmd, arg_out
        end)
        if not ok then
            return nil, nil, result
        end
        return result, args, nil
    end


end

-----------------------------------------------------------------------------

---@class Application : Command
---@field name string
---@field version string
---@field cmd Command
---@field _argParser ArgParser
local Application = setmetatable({}, Command)
Application.__index = Application

do
    local Super = Command
    ---@param config table<string, any>
    ---@return Application
    function Application:new(config)
        ---@type Application
        local this = Super.new(self, config)

        this.version = config["version"] or "0.1.0"
        this._argParser = ArgParser:new()

        this:subcommand {
            Command:new {
                name = "help", help = "show help message for command"
            }:operation(function() print(this) end)
        }

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

    -- Parse argument and run target command operation
    function Application:run()
        local cmd, args, errmsg = self._argParser:parse_arg(self)
        if errmsg then
            io.stderr:write(errmsg .. "\n")
            os.exit(1)
        end
        if not cmd or not cmd._operation then return end
        cmd._operation(args)
    end
end

return {
    Parameter = Parameter,
    Command = Command,
    ArgParser = ArgParser,
    Application = Application,
}
