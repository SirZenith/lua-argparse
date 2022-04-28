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
---@field converter fun(value: string): boolean, any Function that convert command line string to target type
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
function Parameter:New(config)
    local this = setmetatable({}, self)

    this.long = config["long"]
    this.short = config["short"] or nil
    this.name = config["name"] or (this.long and this.long:gsub("-", "_") or nil)
    assert(
        this.name or this.long or this.short,
        "parameter config must contain a name or one of long/short flag"
    )
    assert(
        this.short == nil or #this.short == 1,
        string.format("short flag for parameter '%s' has more than one letter (-%s)", this.name, this.short)
    )

    this.required = config["required"] or false
    this.type = config["type"] or "string"
    this.converter = TypeConverter[this.type]
    assert(this.converter, string.format("invalide type for parameter %s: %s", this.name, this.type))
    this.default = config["default"]
    this.help = config["help"] or nil

    return this
end

-----------------------------------------------------------------------------

---@class Command
---@field name string
---@field help? string
---@field currentSubCommand? string Name of current subcommand that command line arguments directed to.
---@field _subCommands table<string, Command> A table that map subcommand name to Command object.
---@field _parameters Parameter[] List for all Parameters
---@field _flags table<string, Parameter> A table that map flags to Parameter object.
---@field _positionals Parameter[] A list for positional arguments
---@field args table<string, any> Table that map parameter names to command line input flag value.
---@field _operation fun(args: table<string, any>) Operation bind to the command, take target command object as input.
local Command = {}
Command.__index = Command
Command.indent = "    "

---@param config table<string, string>
---@return Command
function Command:New(config)
    local this = setmetatable({}, self)

    this.name = config["name"]
    this.help = config["help"]
    assert(this.name, "name must be provided for a command")
    this.currentSubCommand = nil
    this._subCommands = {}
    this._parameters = {}
    this._flags = {}
    this._positionals = {}
    this.args = {}
    this._operation = nil

    return this
end

---@return string
function Command:__tostring()
    local strList = self:_ToString()
    return table.concat(strList, "\n")
end

---@param strList? string[]
---@param indent? string
---@return string[]
function Command:_ToString(strList, indent)
    strList = strList or {}
    indent = indent or ""
    local list
    local nameSorter = function(a, b) return a.name < b.name end

    local title = indent .. self.name
    if self.help then
        title = title .. ": " .. self.help
    end
    table.insert(strList, title)

    -- parameter serialize
    list = { table.unpack(self._parameters) }
    table.sort(list, nameSorter)
    for _, param in ipairs(list) do
        local msg = indent .. Command.indent .. "- " .. tostring(param)
        if param.help and #param.help ~= 0 then
            msg = msg .. ", " .. param.help
        end
        table.insert(strList, msg)
    end

    -- subcommand serialize
    list = {}
    for name, _ in pairs(self._subCommands) do
        table.insert(list, name)
    end
    table.sort(list)
    if #list ~= 0 then
        table.insert(strList, "")
        table.insert(strList, indent .. Command.indent .. "** Subcommands **")
        table.insert(strList, "")
    end
    for _, name in ipairs(list) do
        local cmd = self._subCommands[name]
        cmd:_ToString(strList, indent .. Command.indent)
    end
    table.insert(strList, "")

    return strList
end

do
    ---@param map table<string, any>
    ---@param mapName string
    ---@param key string
    ---@param value any
    local function TryAddToMap(map, mapName, key, value)
        local check = map[key]
        assert(check == nil, string.format("duplicated %s key: %s", mapName, key))
        map[key] = value
    end

    -- Adding subcommands to command
    ---@param commands Command[]
    ---@return Command
    function Command:SubCommand(commands)
        for _, cmd in ipairs(commands) do
            TryAddToMap(self._subCommands, "Command", cmd.name, cmd)
        end
        return self
    end

    -- Adding parameters to command
    ---@param parameters Parameter[]
    ---@return Command
    function Command:Parameter(parameters)
        for _, param in ipairs(parameters) do
            table.insert(self._parameters, param)
            if param.long then
                TryAddToMap(self._flags, "Long Flag", "--" .. param.long, param)
            end
            if param.short then
                TryAddToMap(self._flags, "Short Flag", "-" .. param.short, param)
            end
            if not param.long and not param.short then
                table.insert(self._positionals, param)
            end
        end
        return self
    end
end

---@param op fun(args: table<string, any>)
function Command:Operation(op)
    self._operation = op
    return self
end

-----------------------------------------------------------------------------

---@class ArgParser
---@field _cmd Command
---@field _posIndex integer Index of next positional parameter to be used
local ArgParser = {}
ArgParser.__index = ArgParser

---@return ArgParser
function ArgParser:New(cmd)
    local this = setmetatable({}, self)
    this._cmd = cmd
    this._posIndex = 1
    return this
end

-- Try to parse arguments and put results in to Command object bind to this parser.
-- Return Command specified by arguments and an error message, message is nil when
-- no error occured.
---@param argList? string[]
---@return Command cmd
---@return string? errmsg
function ArgParser:ParseArg(argList)
    argList = argList or arg
    local ok, result = pcall(function ()
        self:_SetupDefaultValue()

        local cmd, leftArgs = self:_DirectToCmd(argList)
        self:_SettleArguments(cmd, leftArgs)
        self:_CheckAllRequired(cmd)
        return cmd
    end)
    if not ok then
        return nil, result
    end
    return result, nil
end

-- Fill all default values into command args map
function ArgParser:_SetupDefaultValue()
    local stack = { self._cmd }
    while #stack ~= 0 do
        local size = #stack
        local cmd = stack[size]
        stack[size] = nil

        for _, subcmd in pairs(cmd._subCommands) do
            table.insert(stack, subcmd)
        end

        for _, flag in pairs(cmd._flags) do
            cmd.args[flag.name] = flag.default
        end

        for _, pos in ipairs(cmd._positionals) do
            cmd.args[pos.name] = pos.default
        end
    end
end

-- Find target command using argument list, returning command found and arguments
-- left in the list. panic if not command is current binding to ArgParser.
---@param argList string[]
---@return Command cmd
---@return string[] argListSlice
function ArgParser:_DirectToCmd(argList)
    local cmd, index = self._cmd, 1
    if not cmd then
        error("no command is currently bind with ArgParser", 1)
    end

    while argList[index] do
        local name = argList[index]
        if not cmd._subCommands[name] then break end
        cmd = cmd._subCommands[name]
        index = index + 1
    end

    return cmd, { table.unpack(argList, index, #argList) }
end

-- Read all command argument into arg map panic when failed
---@param cmd Command
---@param argList string[]
function ArgParser:_SettleArguments(cmd, argList)
    local flag = nil
    for _, a in ipairs(argList) do
        if a:sub(1, 1) == FLAG_START then
            -- if encountering a new flag
            if flag ~= nil then
                self:_StoreFlag(cmd, flag, nil)
            end
            flag = a
        elseif flag ~= nil then
            -- if encounter value paired with previous flag
            self:_StoreFlag(cmd, flag, a)
            flag = nil
        else
            -- positional argument
            self:_StorePositional(cmd, a)
        end
    end

    if flag ~= nil then
        self:_StoreFlag(cmd, flag, nil)
    end
end

-- Store a flag value to arg map, panic when failed
---@param cmd Command
---@param flag string
---@param value any
function ArgParser:_StoreFlag(cmd, flag, value)
    local param = cmd._flags[flag]
    if not param then
        error("unexpected flag: " .. flag, 0)
    end

    local ok, converted = param.converter(value)
    if ok then
        cmd.args[param.name] = converted
    else
        local msg = string.format("failed to convert '%s' to type %s for flag '%s'", value, param.name, flag)
        error(msg, 0)
    end

    return nil
end

-- Store a positional argument to arg map, panic when failed
---@param cmd Command
---@param value any
function ArgParser:_StorePositional(cmd, value)
    local param = cmd._positionals[self._posIndex]
    if not param then
        error("unexpected positional parameter: " .. value, 0)
    end

    local ok, converted = param.converter(value)
    if ok then
        cmd.args[param.name] = converted
        self:_IncrementPosIndex(param)
    else
        local msg = string.format(
            "failed to convert '%s' to type '%s' for positional parameter '%s'",
            value, param.type, param.name
        )
        error(msg, 0)
    end
end

---@param param Parameter
function ArgParser:_IncrementPosIndex(param)
    self._posIndex = self._posIndex + 1
end

-- Check whether all required parameters are given, panic if have missing
---@param cmd Command
function ArgParser:_CheckAllRequired(cmd)
    local missingList = {}
    self:_CheckRequiredParamList(missingList, cmd._flags, cmd.args, tostring)
    self:_CheckRequiredParamList(missingList, cmd._positionals, cmd.args, tostring)
    if #missingList ~= 0 then
        local indent = "\n    "
        local msg = "following parameter(s) is required, but missing:"
            .. indent .. table.concat(missingList, indent)
        error(msg, 0)
    end
end

-- helper function for required parameter checking
---@param missingList string[] Message list for missing parameters.
---@param paramList Parameter[] Parameter list to check.
---@param valueMap table<string, any> Table that stores value of each parameter.
---@param msgMaker fun(param: Parameter): string Function that makes error messgae based on a Parameter
function ArgParser:_CheckRequiredParamList(missingList, paramList, valueMap, msgMaker)
    for _, param in pairs(paramList) do
        if param.required and valueMap[param.name] == nil then
            table.insert(missingList, msgMaker(param))
        end
    end
end

-----------------------------------------------------------------------------

---@class Application
---@field name string
---@field version string
---@field cmd Command
---@field argParser ArgParser
local Application = {}
Application.__index = Application

---@param name string
---@param version string
---@return Application
function Application:New(name, version, cmd)
    local this = setmetatable({}, self)

    this.name = name
    this.version = version or "0.1.0"
    this.cmd = cmd
    this.argParser = ArgParser:New(this.cmd)

    this.cmd:SubCommand {
        Command:New {
            name = "help", help = "show help message for command"
        }:Operation(function ()
            this:ShowInfo()
            print(this.cmd)
        end)
    }

    return this
end

function Application:ShowInfo()
    print(string.format("%s (%s)", self.name, self.version))
end

-- Parse argument and run target command operation
function Application:Run()
    local cmd, errmsg = self.argParser:ParseArg()
    if errmsg then
        io.stderr:write(errmsg .. "\n")
        os.exit(1)
    end
    if not cmd or not cmd._operation then return end
    cmd._operation(cmd.args)
end

return {
    Parameter = Parameter,
    Command = Command,
    ArgParser = ArgParser,
    Application = Application,
}
