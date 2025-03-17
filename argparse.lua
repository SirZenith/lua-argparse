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

-- try_append_list appends element to a table.
-- If passed table value is nil, then a new list will be created.
-- If passed element vlaue is nil, this function returns passed `list` value right away.
---@generic T
---@param list T[] | nil
---@param element T | nil
---@return T[] | nil
local function try_append_list(list, element)
    if not element then
        return nil
    end

    list = list or {}
    table.insert(list, element)

    return list
end

-- print_string_list prints each element in given list target file. If passed list
-- value is `nil`, `default_msg` will be printed instead.
---@param file file*
---@param list string[] | nil
---@param default_msg? string
local function print_string_list(file, list, default_msg)
    if list then
        for _, err in ipairs(list) do
            file:write(err, "\n")
        end
    elseif default_msg then
        file:write(default_msg, "\n")
    end
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
---@field is_hidden? boolean # If this parameter should be hidden in command's help message.
---@field is_internal? boolean # Indicating this parameter should not be shown to user in help message no matter what.
---@field topics? string[] # A list of topics this parameter belongs to.

---@class argparse.Parameter: argparse.ParameterCfg # Meta info about parameter of a command
---@field name string
---@field _converter fun(value: string): boolean, any # Function that convert command line string to target type
local Parameter = {}
Parameter.__index = Parameter

---@return string
function Parameter:__tostring()
    local buffer = {}

    self:_append_parameter_name(buffer)

    table.insert(buffer, ": ")
    self:_append_type_info_string(buffer)

    if self.default ~= nil then
        table.insert(buffer, " (default: ")
        self:_append_default_value_string(buffer)
        table.insert(buffer, ")")
    end

    local is_flag = self:is_flag()
    if (is_flag and self.required) or (not is_flag and not self.required) then
        table.insert(buffer, ", ")
        self:_append_required_flag_string(buffer)
    end

    if self.max_cnt ~= 1 then
        table.insert(buffer, ", ")
        self:_append_repeat_cnt_string(buffer)
    end

    return table.concat(buffer)
end

-- _append_parameter_name adds parameter display name string to buffer.
---@param buffer string[]
function Parameter:_append_parameter_name(buffer)
    if self:is_flag() then
        if self.short then
            table.insert(buffer, "-")
            table.insert(buffer, self.short)
        end

        if self.long then
            if self.short then
                table.insert(buffer, ", ")
            end
            table.insert(buffer, "--")
            table.insert(buffer, self.long)
        end
    else
        table.insert(buffer, self.name)
    end
end

-- _append_default_value_string adds string reresentation of parameter's default
-- value to buffer.
---@param buffer string[]
function Parameter:_append_default_value_string(buffer)
    table.insert(buffer, tostring(self.default))
end

-- _append_type_info_string adds type information of parameter to buffer.
---@param buffer string[]
function Parameter:_append_type_info_string(buffer)
    table.insert(buffer, self.type)
end

-- _append_required_flag_string adds required mark to buffer
---@param buffer string[]
function Parameter:_append_required_flag_string(buffer)
    if self:is_flag() then
        if self.required then
            table.insert(buffer, "required")
        end
    else
        if not self.required then
            table.insert(buffer, "optional")
        end
    end
end

-- _append_repeat_cnt_string appending max repeat cnt infomation to buffer.
---@param buffer string[]
function Parameter:_append_repeat_cnt_string(buffer)
    if self.max_cnt == 1 then
        -- pass
    elseif self.max_cnt > 1 then
        table.insert(buffer, "max_repeat(")
        table.insert(buffer, tostring(self.max_cnt))
        table.insert(buffer, ")")
    else
        table.insert(buffer, "max_repeat(Infinite)")
    end
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
    if this.short then
        assert(
            #this.short == 1,
            string.format("short flag for parameter '%s' has more than one letter (-%s)", this.name, this.short)
        )
    end

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
    this.is_hidden = config.is_hidden
    this.is_internal = config.is_internal

    if config.topics then
        local topics = {}
        for _, topic in ipairs(config.topics) do
            table.insert(topics, topic)
        end
        this.topics = topics
    end

    return this
end

---@return boolean # If this parameter is a flag.
function Parameter:is_flag()
    return self.short ~= nil or self.long ~= nil
end

-- is_match_topic check wheather current command belongs given topic.
---@param topic? string
---@return boolean
function Parameter:is_match_topic(topic)
    if topic == nil then
        return true
    end

    if not self.topics then
        return false
    end

    local is_match = false
    for _, value in ipairs(self.topics) do
        is_match = value == topic
        if is_match then
            break
        end
    end

    return is_match
end

-----------------------------------------------------------------------------

local FLAG_SHELL_COMPLETION_FLAGS = "shell-completion-flags"
local FLAG_SHELL_COMPLETION_SUBCOMMANDS = "shell-completion-subcommands"

local PARAM_NAME_SHELL_COMPLETION_FLAGS = FLAG_SHELL_COMPLETION_FLAGS:gsub("-", "_")
local PARAM_NAME_SHELL_COMPLETION_SUBCOMMANDS = FLAG_SHELL_COMPLETION_SUBCOMMANDS:gsub("-", "_")

---@class argparse.CommandCfg # A table of data used to create a new command.
---@field name string
---@field help? string
---@field is_hidden? boolean # If this command should be hidden in help message.
---@field is_internal? boolean # Indicating this command should no be shown to user in help message no matter what.
---@field topics? string[] # A list of topics this command belongs to.
---@field no_help_cmd? boolean # Do not create help command when construct new command.

---@class argparse.Command: argparse.CommandCfg
---@field _subcommands table<string, argparse.Command> # A table that map subcommand name to Command object.
---@field _parameters argparse.Parameter[] # List for all Parameters
---@field _flags table<string, argparse.Parameter> # A table that map flags to Parameter object.
---@field _positionals argparse.Parameter[] # A list for positional arguments
---@field _operation fun(args: table<string, any>) # Operation bind to the command, take target command object as input.
local Command = {}
Command.__index = Command
Command._indent = "  "

-- Find target command using argument list, returning command found and arguments
-- left in the list. panic if not command is current binding to ArgParser.
---@param cmd argparse.Command
---@param arg_in string[]
---@return argparse.Command cmd
---@return string[] argListSlice
local function direct_to_cmd(cmd, arg_in)
    local index = 1

    while arg_in[index] do
        local name = arg_in[index]
        if not cmd._subcommands[name] then break end
        cmd = cmd._subcommands[name]
        index = index + 1
    end

    return cmd, { unpack(arg_in, index, #arg_in) }
end

-- new creates a new command with given meta config.
---@param config argparse.CommandCfg
---@return argparse.Command
function Command:new(config)
    local this = setmetatable({}, self)

    this.name = config.name
    assert(this.name, "name must be provided for a command")

    this.help = config.help
    this.is_hidden = config.is_hidden

    if config.topics then
        local topics = {}
        for _, topic in ipairs(config.topics) do
            table.insert(topics, topic)
        end
        this.topics = topics
    end

    this._subcommands = {}
    this._parameters = {}
    this._flags = {}
    this._positionals = {}
    this._operation = nil

    if not config.no_help_cmd then
        this:subcommand {
            this:_make_help_cmd()
        }
    end

    this:parameter {
        { long = FLAG_SHELL_COMPLETION_FLAGS,       type = "boolean", is_internal = true, help = "generate completion for flags" },
        { long = FLAG_SHELL_COMPLETION_SUBCOMMANDS, type = "boolean", is_internal = true, help = "generate completion for subcommands" }
    }

    return this
end

---@return string
function Command:__tostring()
    local buffer = self:_generate_help_message_buffer()
    return table.concat(buffer)
end

---@class argparse.CommandHelpArgs
---@field show_all? boolean # When set to `true`, all hidden parameters and subcommands will be shown.
---@field topic? string # topic value used to filter out some of parameters and subcommands

-- _generate_help_message_buffer makes a table of strings containing help message
-- of current command.
---@param buffer? string[]
---@param args? argparse.CommandHelpArgs
---@return string[]
function Command:_generate_help_message_buffer(buffer, args)
    buffer = buffer or {}

    self:_append_usage_string(buffer)
    self:_append_parameter_string(buffer, args)
    self:_append_subcommand_string(buffer, args)

    return buffer
end

-- _append_usage_string adds command usage and description text to buffer.
---@param buffer string[]
function Command:_append_usage_string(buffer)
    table.insert(buffer, "Usage:\n")
    table.insert(buffer, Command._indent)
    table.insert(buffer, self.name)

    -- title line
    if not is_empty(self._flags) then
        table.insert(buffer, " {flags}")
    end
    if not is_empty(self._positionals) then
        table.insert(buffer, " ")

        for i, param in ipairs(self._positionals) do
            if i > 1 then
                table.insert(buffer, " ")
            end

            local max_cnt = param.max_cnt
            if max_cnt >= 1 then
                for _ = 1, max_cnt do
                    table.insert(buffer, "<")
                    table.insert(buffer, param.name)
                    table.insert(buffer, ">")
                end
            else
                table.insert(buffer, "...(")
                table.insert(buffer, param.name)
                table.insert(buffer, ")")
            end
        end
    end

    -- help info
    if self.help then
        table.insert(buffer, "\n")
        table.insert(buffer, "\n")

        table.insert(buffer, "Description:\n")
        table.insert(buffer, Command._indent)
        table.insert(buffer, self.help)
    end
end

-- _append_parameter_string adds help message of command's parameter to string
-- buffer.
---@param buffer string[]
---@param args? argparse.CommandHelpArgs
function Command:_append_parameter_string(buffer, args)
    local show_all = args and args.show_all or false
    local topic = args and args.topic or nil

    local positionals = {} ---@type argparse.Parameter[]
    local flags = {} ---@type argparse.Parameter[]

    for _, param in ipairs(self._parameters) do
        local is_visible = not param.is_internal and (show_all or not param.is_hidden)
        if is_visible and param:is_match_topic(topic) then
            if param:is_flag() then
                table.insert(flags, param)
            else
                table.insert(positionals, param)
            end
        end
    end

    if #positionals > 0 then
        table.insert(buffer, "\n")
        table.insert(buffer, "\n")
        table.insert(buffer, "Positional:")

        for _, param in ipairs(positionals) do
            table.insert(buffer, "\n")
            self:_append_single_parameter_string(buffer, param)
        end
    end

    if #flags > 0 then
        table.sort(flags, function(param_a, param_b)
            local a_name = param_a.short or param_a.long
            local b_name = param_b.short or param_b.long
            return a_name < b_name
        end)

        table.insert(buffer, "\n")
        table.insert(buffer, "\n")
        table.insert(buffer, "Flag:")

        for _, param in ipairs(flags) do
            table.insert(buffer, "\n")
            self:_append_single_parameter_string(buffer, param)
        end
    end
end

-- _append_single_parameter_string adds description text of given parameter to
-- buffer.
---@param buffer string[]
---@param param argparse.Parameter
function Command:_append_single_parameter_string(buffer, param)
    table.insert(buffer, Command._indent)
    param:_append_parameter_name(buffer)
    table.insert(buffer, "\n")

    table.insert(buffer, Command._indent)
    table.insert(buffer, "  * ")
    param:_append_type_info_string(buffer)
    if param.default ~= nil then
        table.insert(buffer, " (default: ")
        param:_append_default_value_string(buffer)
        table.insert(buffer, ")")
    end
    table.insert(buffer, ", ")
    param:_append_required_flag_string(buffer)
    if param.max_cnt ~= 1 then
        table.insert(buffer, ", ")
        param:_append_repeat_cnt_string(buffer)
    end

    if param.help and #param.help ~= 0 then
        table.insert(buffer, "\n")
        table.insert(buffer, Command._indent)
        table.insert(buffer, "  * ")
        table.insert(buffer, param.help)
    end
end

-- _append_subcommand_string adds help message of subcommands to string buffer.
---@param buffer string[]
---@param args? argparse.CommandHelpArgs
function Command:_append_subcommand_string(buffer, args)
    local show_all = args and args.show_all or false
    local topic = args and args.topic or nil

    local commands = {} ---@type argparse.Command[]

    for _, cmd in pairs(self._subcommands) do
        local is_visible = not cmd.is_internal and (show_all or not cmd.is_hidden)
        if is_visible and cmd:is_match_topic(topic) then
            table.insert(commands, cmd)
        end
    end

    if #commands > 0 then
        table.sort(commands, function(cmd_a, cmd_b)
            return cmd_a.name < cmd_b.name
        end)

        table.insert(buffer, "\n")
        table.insert(buffer, "\n")
        table.insert(buffer, "Subcommands:")

        for _, cmd in ipairs(commands) do
            table.insert(buffer, "\n")
            table.insert(buffer, Command._indent)
            table.insert(buffer, "* ")
            table.insert(buffer, cmd.name)
            if cmd.help then
                table.insert(buffer, ": ")
                table.insert(buffer, cmd.help)
            end
        end
    end
end

-- _make_help_cmd makes a help subcommand for itself.
---@return argparse.Command
function Command:_make_help_cmd()
    return Command:new {
        name = "help",
        help = "show help message for command",
        no_help_cmd = true,
    }:parameter {
        { name = "topic",      type = "string",  help = "subtopic used to filter parameters, subcommands" },
        { long = "show-all",   type = "boolean", help = "includes hidden subcommands and parameters in help message" },
        { long = "list-topic", type = "boolean", help = "list all available help topics" },
    }:operation(function(args)
        if args.list_topic then
            local list = self:get_topic_list()
            if #list <= 0 then
                print("no topic available")
            else
                for _, topic in ipairs(list) do
                    print(topic)
                end
            end
        else
            local buffer = self:_generate_help_message_buffer(nil, args)
            print(table.concat(buffer))
        end
    end)
end

-- run_help runs `help` subcommand of current command if it exists.
function Command:run_help()
    local cmd = self._subcommands.help
    if cmd then
        cmd._operation {}
    end
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

-- is_match_topic check wheather current command belongs given topic.
---@param topic? string
---@return boolean
function Command:is_match_topic(topic)
    if topic == nil then
        return true
    end

    if not self.topics then
        return false
    end

    local is_match = false
    for _, value in ipairs(self.topics) do
        is_match = value == topic
        if is_match then
            break
        end
    end

    return is_match
end

-- get_topic_list returns a list of topics containing all possible topic of current
-- command.
---@return string[]
function Command:get_topic_list()
    local topic_set = {} ---@type table<string, boolean>

    for _, param in ipairs(self._parameters) do
        if param.topics then
            for _, topic in ipairs(param.topics) do
                topic_set[topic] = true
            end
        end
    end

    for _, cmd in ipairs(self._subcommands) do
        if cmd.topics then
            for _, topic in ipairs(cmd.topics) do
                topic_set[topic] = true
            end
        end
    end

    local topics = {} ---@type string[]
    for topic in pairs(topic_set) do
        table.insert(topics, topic)
    end

    table.sort(topics)

    return topics
end

-- subcommand_completion returns a list of all non-internal subcommands, including hidden
-- ones. Useful for generating shell completion.
-- Note that returned list is not sorted in any way.
---@return string[]
function Command:gen_completion_for_subcommands()
    local result = {}

    for _, cmd in pairs(self._subcommands) do
        if not cmd.is_internal then
            table.insert(result, ("%s:%s"):format(cmd.name, cmd.help or ""))
        end
    end

    return result
end

-- flag_completion returns a list of all non-internal flags, including hidden ones.
-- Useful for generating shell completion.
-- Note that returned list is not sorted in any way.
---@return string[]
function Command:gen_completion_for_flags()
    local result = {}

    for _, param in pairs(self._parameters) do
        if not param.is_internal then
            local help = param.help or ""

            if param.short then
                table.insert(result, ("%s:%s"):format("-" .. param.short, help))
            end

            if param.long then
                table.insert(result, ("%s:%s"):format("--" .. param.long, help))
            end
        end
    end

    return result
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
    ---@return table<string, any>
    local function setup_default_value(cmd)
        local arg_out = {}

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

        return arg_out
    end

    -- store_flag adds a flag value to arg map.
    ---@param args table<string, any>
    ---@param cmd argparse.Command
    ---@param flag string
    ---@param value any
    ---@return string? err
    local function store_flag(args, cmd, flag, value)
        local param = cmd._flags[flag]
        if not param then
            return "unexpected flag: " .. flag
        end

        local ok, converted = param._converter(value)
        if not ok then
            return ("failed to convert '%s' to type %s for flag '%s'"):format(value, param.name, flag)
        end

        if param.max_cnt == 1 then
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
                return ("flag %s is passed more times than allowed"):format(flag)
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
    ---@return string? err
    local function store_positional(parser, args, cmd, value)
        local param = cmd._positionals[parser._pos_index]
        if not param then
            return "unexpected positional parameter: " .. value
        end

        local ok, converted = param._converter(value)
        if not ok then
            return string.format(
                "failed to convert '%s' to type '%s' for positional parameter '%s'",
                value, param.type, param.name
            )
        end

        if param.max_cnt == 1 then
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

        return nil
    end

    -- Read all command argument into arg map panic when failed
    ---@param parser argparse.ArgParser
    ---@param arg_out table<string, any>
    ---@param cmd argparse.Command
    ---@param arg_in string[]
    ---@return string[]? err_list # collected errors happened during reading arguments.
    local function settle_arguments(parser, arg_out, cmd, arg_in)
        local flag = nil
        local err_list = nil

        for _, a in ipairs(arg_in) do
            if a:sub(1, 1) == FLAG_START then
                -- if encountering a new flag
                if flag ~= nil then
                    local err = store_flag(arg_out, cmd, flag, nil)
                    err_list = try_append_list(err_list, err)
                end

                flag = a
            elseif flag ~= nil then
                -- if encounter value paired with previous flag
                local err = store_flag(arg_out, cmd, flag, a)
                err_list = try_append_list(err_list, err)

                flag = nil
            else
                -- positional argument
                local err = store_positional(parser, arg_out, cmd, a)
                err_list = try_append_list(err_list, err)
            end
        end

        if flag ~= nil then
            local err = store_flag(arg_out, cmd, flag, nil)
            err_list = try_append_list(err_list, err)
        end

        return err_list
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
    ---@return string? err
    local function check_all_required(args, cmd)
        local missing = {}
        check_required_paramlist(missing, cmd._flags, args, tostring)
        check_required_paramlist(missing, cmd._positionals, args, tostring)

        local missing_cnt = #missing
        if missing_cnt > 0 then
            local indent = "\n    "
            local msg = ("following %s is required, but missing:%s%s"):format(
                missing_cnt > 1 and "parameters" or "parameter",
                indent,
                table.concat(missing, indent)
            )

            return msg
        end

        return nil
    end

    -- parse_arg tries to parse arguments and put results in to Command object
    -- binded to this parser.
    -- Returns target command specified by arguments and a possible error message.
    ---@param cmd argparse.Command
    ---@param arg_in? string[]
    ---@return argparse.Command cmd
    ---@return table<string, any> args
    ---@return string[]? err_list
    function ArgParser:parse_arg(cmd, arg_in)
        arg_in = arg_in or arg
        self._pos_index = 1

        local target, left_args = direct_to_cmd(cmd, arg_in)

        local arg_out = setup_default_value(target)
        local arg_err = settle_arguments(self, arg_out, target, left_args)
        if arg_err then
            return target, arg_out, arg_err
        end

        local requirement_err = check_all_required(arg_out, target)
        if requirement_err then
            return target, arg_out, { requirement_err }
        end

        return target, arg_out, nil
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

    -- run_with_args parses given arguments and run target command's operation.
    ---@param args_in string[] # command arguments
    function Application:run_with_args(args_in)
        local cmd, args, err_list = self._arg_parser:parse_arg(self, args_in)

        if args[PARAM_NAME_SHELL_COMPLETION_FLAGS] then
            local list = cmd:gen_completion_for_flags()
            table.sort(list)
            print_string_list(io.stdout, list)
            return
        elseif args[PARAM_NAME_SHELL_COMPLETION_SUBCOMMANDS] then
            local list = cmd:gen_completion_for_subcommands()
            table.sort(list)
            print_string_list(io.stdout, list)
            return
        elseif err_list then
            print_string_list(io.stderr, err_list, "Unknown parsing error")
            os.exit(1)
        end

        if not cmd._operation then
            cmd:run_help()
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
