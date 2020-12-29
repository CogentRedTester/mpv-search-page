--[[
    For the full documentation see: https://github.com/CogentRedTester/mpv-search-page

    This script allows you to search for keybinds, properties, options and commands and have matching entries display on the OSD.
    The search is case insensitive, and the script sends the filter directly to a lua string match function,
    so you can use patterns to get more complex filtering.

    The keybind page searches and displays the key, command, section, and any comments.
    The command page searches just the command name, but also shows information about arguments.
    The properties page will search just the property name, but will also show contents of the property
    The options page will search the name and option choices, it shows default values, choices, and ranges

    The search page will remain open until told to close. This key is esc.

    The default commands are:
        f12 script-binding search-keybinds
        Ctrl+f12 script-binding search-commands
        Shift+f12 script-binding search-properties
        Alt+f12 script-binding search-options
        Ctrl+Shift+Alt script-binding search-all

    Once the command is sent the console will open with a pre-entered search command, simply add a query string as the first argument.
    Using the above keybinds will pre-enter the raw query command into the console, but you can modify it to search multiple criteria at once.

    The raw command is:
        script-message search_page/input [query types] [query string] {flags}

    The valid query types are as follows:
        key$    searches keybindings
        cmd$    searches commands
        prop$   searches properties
        opt$    searches options
        all$    searches all
    These queries can be combined, i.e. key$cmd$ to search multiple categories at once

    Sending a query message without any arguments (or with only the type argument) will reopen the last search.

    Flags are strings you can add to the end to customise the query, currently there are 3:
        wrap        search for a whole word only
        pattern     don't convert the query to lowercase, required for some Lua patterns
        exact       don't convert anything to lowercase

    These flags can be combined, so for example a query `t wrap` would normally result in both lower and upper case t binds, however,
    `t wrap+exact` will return only lowercase t. The pattern flag is only useful when doing some funky pattern stuff, for example:
    `f%A wrap+pattern` will return all complete words containing f followed by a non-letter. Often exact will work just fine for this,
    but in this example we might still want to find upper-case keys, like function keys, so using just pattern can be more useful.

    These may be subject to change
]]--

local mp = require 'mp'
local msg = require 'mp.msg'
local opt = require 'mp.options'
local utils = require 'mp.utils'

local o = {
    --there seems to be a significant performance hit from having lots of text off the screen
    max_list = 22,

    --number of pixels to pan on each click
    --this refers to the horizontal panning
    pan_speed = 100,

    --enables custom keybindings specified in `~~/script-opts/search-page-keybinds.json`
    custom_keybinds = false,

    --all colour options
    ass_header = "{\\c&H00ccff&\\fs40\\b500\\q2\\fnMonospace}",
    ass_underline = "{\\c&00ccff&\\fs30\\b100\\q2}",
    ass_footer = "{\\c&00ccff&\\b500\\fs20}",
    ass_selector = "{\\c&H00ccff&}",
    ass_allselectorspaces = "{\\fs20}",

    --colours for keybind page
    ass_allkeybindresults = "{\\fs20\\q2}",
    ass_key = "{\\c&Hffccff&}",
    ass_section = "{\\c&H00cccc&}",
    ass_cmdkey = "{\\c&Hffff00&}",
    ass_comment = "{\\c&H33ff66&}",

    --colours for commands page
    ass_cmd = "{\\c&Hffccff&\\fs20\\q2}",
    ass_args = "{\\fs20\\c&H33ff66&}",
    ass_optargs = "{\\fs20\\c&Hffff00&}",
    ass_argtype = "{\\c&H00cccc&\\fs12}",

    --colours for property list
    ass_properties = "{\\c&Hffccff&\\fs20\\q2}",
    ass_propertycurrent = "{\\c&Hffff00&}",

    --colours for options list
    ass_options = "{\\c&Hffccff&>\\fs20\\q2}",
    ass_optvalue = "{\\fs20\\c&Hffff00&}",
    ass_optionstype = "{\\c&H00cccc&}{\\fs20}",
    ass_optionsdefault = "{\\c&H00cccc&}",
    --list of choices for choice options, ranges for numeric options
    ass_optionsspec = "{\\c&H33ff66&\\fs20}",
}

opt.read_options(o, "search_page")

package.path = mp.command_native({'expand-path', '~~/scripts'}) .. '/?.lua;' .. package.path
local _list = require 'scroll-list'
local list_meta = getmetatable( _list ).__scroll_list

local osd_display = mp.get_property_number('osd-duration', 0) / 1000

list_meta.header_style = o.ass_header
list_meta.wrapper_style = o.ass_footer
list_meta.indent = [[\h\h\h]]
list_meta.num_entries = o.max_list
list_meta.empty_text = "no results"

list_meta.current_page = nil
list_meta.latest_search = {
    keyword = "",
    flags = ""
}

--creates a new page object
local function create_page(type, t)
    local temp = t or _list:new()

    temp.id = temp.ass.id
    temp.posX = 15
    temp.type = type
    temp.keyword = ""
    temp.flags = ""
    temp.keybinds = {
        {"DOWN", "down_page", function() temp:scroll_down() end, {repeatable = true}},
        {"UP", "up_page", function() temp:scroll_up() end, {repeatable = true}},
        {"ESC", "close_overlay", function() temp:close() end, {}},
        {"LEFT", "pan_left", function() temp:pan_left() end, {repeatable = true}},
        {"RIGHT", "pan_right", function() temp:pan_right() end, {repeatable = true}},
        {"Shift+LEFT", "page_left", function() temp:page_left() end, {}},
        {"Shift+RIGHT", "page_right", function() temp:page_right() end, {}},
        {"Ctrl+LEFT", "page_left_search", function() temp:page_left(true) end, {}},
        {"Ctrl+RIGHT", "page_right_search", function() temp:page_right(true) end, {}},
        {"Ctrl+ENTER", "run_latest", function() temp:run_search(temp.latest_search.keyword, temp.latest_search.flags) end, {}}
    }
    return temp
end

local KEYBINDS = create_page("key", _list)
local COMMANDS = create_page("command")
local OPTIONS = create_page("option")
local PROPERTIES = create_page("property")

local PAGES = {
    ["key$"] = KEYBINDS,
    ["cmd$"] = COMMANDS,
    ["opt$"] = OPTIONS,
    ["prop$"] = PROPERTIES
}
local PAGE_IDS = {"key$", "cmd$", "opt$", "prop$"}

--loads the header
function list_meta:format_header()
    self:append("{\\pos("..self.posX..",10)\\an7}")
    local flags = self.flags
    if not flags then
        flags = ""
    else
        flags = " ("..flags..")"
    end
    self:append(o.ass_header.."Search results for "..self.type ..' "'..self.ass_escape(self.keyword)..'"'..flags)
    self:newline()
    self:append(o.ass_underline.."---------------------------------------------------------")
    self:newline()
end

function list_meta:pan_right()
    self.posX = self.posX - o.pan_speed
    self:update()
end

 function list_meta:pan_left()
    self.posX = self.posX + o.pan_speed
    if self.posX > 15 then
        self.posX = 15
        return
    end
    self:update()
end

function list_meta:page_left(match_search)
    self:close()
    local index = self.id
    index = (index == 1 and 4 or index - 1)
    local new_page = PAGES[ PAGE_IDS[index] ]
    list_meta.current_page = new_page
    if match_search then new_page:run_search(self.keyword, self.flags) end
    new_page:open()
end

function list_meta:page_right(match_search)
    self:close()
    local index = self.id
    index = (index == 4 and 1 or index + 1)
    local new_page = PAGES[ PAGE_IDS[index] ]
    list_meta.current_page = new_page
    if match_search then new_page:run_search(self.keyword, self.flags) end
    new_page:open()
end

--closes all pages that are open
local function close_all()
    for _,page in pairs(PAGES) do
        if not page.hidden then page:close() end
    end
end

--handles the search queries
local function compare(str, keyword, flags)
    if not flags then
        return str:lower():find(keyword:lower())
    end

    --custom handling for flags
    if flags.wrap then
        if flags.exact then
            return str:find("%f[%w_]" .. keyword .. "%f[^%w_]")
        elseif flags.pattern then
            return str:find("%f[%w_]" .. keyword .. "%f[^%w_]") or str:lower():find("%f[%w_]" .. keyword .. "%f[^%w_]")
        else
            return str:lower():find("%f[%w_]" .. keyword:lower() .. "%f[^%w_]")
        end
    end

    --searches for a pattern, but also searches the pattern
    --if exact is flagged and got a hit then there is no need to run this
    if flags.pattern and not flags.exact then
        return str:find(keyword) or str:lower():find(keyword)
    end

    --only searches the exact string/pattern
    if flags.exact then
        return str:find(keyword)
    end
end

local function return_spaces(string_len, width)
    local num_spaces = width - string_len
    if num_spaces < 2 then num_spaces = 2 end
    return string.rep(" ", num_spaces)
end

local function create_set(t)
    if not t then return nil end
    local flags = {}
    for flag in t:gmatch("[^%+]+") do
        flags[flag] = true
    end
    return flags
end

--search keybinds
function KEYBINDS:search(keyword, flags)
    local keys = mp.get_property_native('input-bindings')
    local keybound = {}

    for _,keybind in ipairs(keys) do
        --saves the cmd for that key so we can grey out the overwritten keys
        --console keybinds are ignored because it is automatically closed after
        --sending the command and would otherwise always override many basic keybinds
        if keybind.priority >= 0 and keybind.section ~= "input_forced_console" then
            if keybound[keybind.key] == nil then
                keybound[keybind.key] = {
                    priority = -1
                }
            end
            if keybind.priority >= keybound[keybind.key].priority then
                keybound[keybind.key].cmd = keybind.cmd
                keybound[keybind.key].priority = keybind.priority
            end
        end
        if
        compare(keybind.key, keyword, flags)
        or compare(keybind.cmd, keyword, flags)
        or (keybind.comment ~= nil and compare(keybind.comment, keyword, flags))
        or compare(keybind.section, keyword, flags)
        or (keybind.owner ~= nil and compare(keybind.owner, keyword, flags))
        then
            local key = keybind.key
            local section = ""
            local cmd = ""
            local comment = ""

            --add section string to entry
            if keybind.section ~= nil and keybind.section ~= "default" then
                section = "  (" .. keybind.section .. ")"
            end

            --add command to entry
            cmd = return_spaces(key:len() + section:len(), 20) .. keybind.cmd

            --add comments to entry
            if keybind.comment ~= nil then
                comment = return_spaces(key:len()+section:len()+cmd:len(),60) .. "#" .. keybind.comment
            end

            key = self.ass_escape(key)
            section = self.ass_escape(section)
            cmd = self.ass_escape(cmd)
            comment = self.ass_escape(comment)

            --appends the result to the list
            self:insert({
                type = "key",
                ass = o.ass_allkeybindresults .. o.ass_key .. key .. o.ass_section .. section .. o.ass_cmdkey .. cmd .. o.ass_comment .. comment,
                key = keybind.key,
                cmd = keybind.cmd,
                keybind = keybind
            })
        end
    end

    --does a second pass of the results and greys out any overwritten keys
    for _,v in self:ipairs() do
        if keybound[v.key] and keybound[v.key].cmd ~= v.cmd then
            v.ass = "{\\alpha&H80&}"..v.ass.."{\\alpha&H00&}"
            v.overwritten = true
        end
        v.key = nil
        v.cmd = nil
    end
end

--search commands
function COMMANDS:search(keyword, flags)
    local commands = mp.get_property_native('command-list')

    for _,command in ipairs(commands) do
        if
        compare(command.name, keyword, flags)
        then
            local cmd = command.name

            local arg_string = ""

            for _,arg in ipairs(command.args) do
                if arg.optional then arg_string = arg_string .. o.ass_optargs
                else arg_string = arg_string .. o.ass_args end
                arg_string = arg_string .. " " .. arg.name .. o.ass_argtype.." ("..arg.type..") "
            end

            self:insert({
                type = "command",
                ass = o.ass_cmd..self.ass_escape(cmd)..return_spaces(cmd:len(), 20)..arg_string,
                command = command
            })
        end
    end
end

function OPTIONS:search(keyword, flags)
    local options = mp.get_property_native('options')

    for _,option in ipairs(options) do
        local option_info = mp.get_property_native("option-info/"..option) or {name = option}
        local choices = mp.get_property_osd("option-info/"..option..'/choices', ""):gsub(",", " , ")
        option_info.choices_str = choices

        if
            compare(option, keyword, flags)
            or compare(choices, keyword, flags)
        then
            local type = option_info.type or ""

            --we're saving the string lengths as an incrementing variable so that
            --ass modifiers don't bloat the string. This is for calculating spaces
            local length_no_ass = type:len() + option:len()
            local first_space = return_spaces(length_no_ass, 40)

            local val = mp.get_property_osd('options/'..option, "")
            local opt_value = "= "..val
            length_no_ass = length_no_ass + first_space:len() + opt_value:len()
            local second_space = return_spaces(length_no_ass, 60)

            local default = mp.get_property_osd('option-info/'..option..'/default-value', "")
            option_info.default_str = default
            length_no_ass = length_no_ass + default:len() + second_space:len()
            local third_space = return_spaces(length_no_ass, 70)

            local options_spec = ""

            if type == "Choice" then
                options_spec = "    [ " .. choices .. ' ]'
            elseif type == "Integer"
            or type == "ByteSize"
            or type == "Float"
            or type == "Aspect"
            or type == "Double" then
                options_spec = "    [ "..(option_info.min or "").."  -  "..(option_info.max or "").." ]"
            end

            local result = o.ass_options..self.ass_escape(option).."  "..o.ass_optionstype..type..first_space..o.ass_optvalue..self.ass_escape(opt_value)
            result = result..second_space..o.ass_optionsdefault..self.ass_escape(default)..third_space..o.ass_optionsspec..self.ass_escape(options_spec)
            self:insert({
                type = "option",
                ass = result,
                option = option_info,
                val = val
            })
        end
    end
end

function PROPERTIES:search(keyword, flags)
    local properties = mp.get_property_native('property-list', {})

    for _,property in ipairs(properties) do
        if compare(property, keyword, flags) then
            local val = mp.get_property(property, "")
            self:insert({
                type = "property",
                ass = o.ass_properties..self.ass_escape(property)..return_spaces(property:len(), 40)..o.ass_propertycurrent..self.ass_escape(val),
                name = property,
                val = val
            })
        end
    end
end

--prepares the page for a search
function list_meta:run_search(keyword, flags)
    self.latest_search.keyword = keyword
    self.latest_search.flags = flags
    self:clear()
    self.keyword = keyword
    self.flags = flags

    self:search( keyword, create_set(flags) )
    self:update()
end

--recieves the input messages
mp.register_script_message('search_page/input', function(type, keyword, flags)
    local list = type and PAGES[type] or list_meta.current_page

    if keyword == nil then
        if list then
            mp.command("script-binding console/_console_1")
            -- remove_bindings()
            list:open()
        end
        return
    end

    if not list then
        msg.error("invalid search type - must be one of:")
        msg.error("'key$', 'cmd$', 'opt$', or 'prop$'")
        return
    end

    close_all()
    list_meta.current_page = list
    list:run_search(keyword, flags)

    mp.command("script-binding console/_console_1")
    list.selected = 1
    list:open()
end)


mp.add_key_binding('f12','search-keybinds', function()
    mp.commandv('script-message-to', 'console', 'type', 'script-message search_page/input key$ ')
end)

mp.add_key_binding("Ctrl+f12",'search-commands', function()
    mp.commandv('script-message-to', 'console', 'type', 'script-message search_page/input cmd$ ')
end)

mp.add_key_binding("Shift+f12", "search-properties", function()
    mp.commandv('script-message-to', 'console', 'type', 'script-message search_page/input prop$ ')
end)

mp.add_key_binding("Alt+f12", "search-options", function()
    mp.commandv('script-message-to', 'console', 'type', 'script-message search_page/input opt$ ')
end)

--substitutes string codes for keybind info
function KEYBINDS:format_command(str, current)
    return str:gsub("%%.", {
        ["%%"] = "%",
        ["%k"] = current.keybind.key,
        ["%K"] = string.format("%q", current.keybind.key or ""),
        ["%c"] = current.keybind.cmd,
        ["%C"] = string.format("%q", current.keybind.cmd or ""),
        ["%s"] = current.keybind.section,
        ["%S"] = string.format("%q", current.keybind.section or ""),
        ["%p"] = current.keybind.priority,
        ["%P"] = string.format("%q", current.keybind.priority or ""),
        ["%h"] = current.keybind.comment,
        ["%H"] = string.format("%q", current.keybind.comment or "")
    })
end

--ensures the keybind passes the filter
function KEYBINDS:pass_filter(keybind)
    return self[self.selected].overwritten and keybind.filter == "disabled" or keybind.filter == "enabled"
end

--formats the argument string for commands
function COMMANDS:format_args(args, separator)
    if not args or #args < 1 then return "" end
    local output = (args[1].optional and "" or "!")..args[1].name.." ("..args[1].type..")"

    for i = 2, #args do
        output = output..separator..(args[i].optional and "" or "!")..args[i].name.." ("..args[i].type..")"
    end
    return output
end

--substitutes string codes for command info
function COMMANDS:format_command(str, current, bind)
    return str:gsub("%%.", {
        ["%%"] = "%",
        ["%n"] = current.command.name,
        ["%N"] = string.format("%q", current.command.name),
        ["%a"] = self:format_args(current.command.args, bind.separator or " "),
        ["%A"] = string.format("%q", self:format_args(current.command.args, bind.separator or " "))
    })
end

--formats the option choices as defined by user options
function OPTIONS:format_choices(choices, separator, format)
    if not choices or #choices < 1 then return "" end
    local output = format and string.format("%q", choices[1]) or choices[1]
    for i = 2, #choices do
        output = output..separator..(format and string.format("%q", choices[i]) or choices[i])
    end
    return output
end

--substitutes string codes for option info
function OPTIONS:format_command(str, current, bind)
    return str:gsub("%%.", {
        ["%%"] = "%",
        ["%n"] = current.option.name,
        ["%N"] = string.format("%q", current.option.name),
        ["%v"] = current.val or "",
        ["%V"] = string.format("%q", current.val or ""),
        ["%c"] = self:format_choices(current.option.choices, bind.separator or ",", bind.format_choices),
        ["%C"] = string.format("%q", self:format_choices(current.option.choices, bind.separator or ",", bind.format_choices)),
        ["%d"] = current.option.default_str,
        ["%D"] = string.format("%q", current.option.default_str),
        ["%u"] = current.option.max or "",
        ["%U"] = string.format("%q", current.option.max or ""),
        ["%l"] = current.option.min or "",
        ["%L"] = string.format("%q", current.option.min or "")
    })
end

--checks if the current option passes the filter
function OPTIONS:pass_filter(keybind)
    return self[self.selected].option.type == keybind.filter
end

--substitutes string codes for property info
function PROPERTIES:format_command(str, current)
    return str:gsub("%%.", {
        ["%%"] = "%",
        ["%n"] = current.name,
        ["%N"] = string.format("%q", current.name),
        ["%v"] = current.val,
        ["%V"] = string.format("%q", current.val)
    })
end

--formats the command strings for each comand
function list_meta:format_command_table(t, keybind)
    local current = self.list[self.selected]
    local copy = {}
    for i = 1, #t do copy[i] = self:format_command(t[i], current, keybind) end
    return copy
end

--a timer to re-enable the page if temporarily hidden by a keybind
local hide_timer = mp.add_timeout(osd_display, function() list_meta.current_page:update() end)
hide_timer:kill()

--runs one of the custom commands
local function custom_command(t, page, keybind)
    if type(t[1]) == "table" then
        for i = 1, #t do
            custom_command(t[i], page, keybind)
        end
    else
        if keybind.filter and not page:pass_filter(keybind) then return end
        local custom_cmd = page:format_command_table(t, keybind)
        msg.debug("running command: " .. utils.to_string(custom_cmd))

        if keybind.close_page then page:close()
        elseif keybind.hide_page then
            page.ass:remove()
            hide_timer:kill()
            hide_timer:resume()
        end

        --if the code is given we use the mp.command API call
        if custom_cmd[1] == "!c" then mp.command(custom_cmd[2])
        else mp.command_native(custom_cmd) end
    end
end

--loading the custom keybinds
if o.custom_keybinds then
    local path = mp.command_native({"expand-path", "~~/script-opts"}).."/search-page-keybinds.json"
    local custom_keybinds = assert(io.open( path ))
    if custom_keybinds then
        local json = custom_keybinds:read("*a")
        custom_keybinds:close()

        json = utils.parse_json(json)
        if not json then error("invalid json syntax for "..path) end
        custom_keybinds = json

        for key, page in pairs(PAGES) do
            for i,keybind in ipairs(custom_keybinds[key]) do
                table.insert(page.keybinds, {keybind.key, "custom"..tostring(i), function() custom_command(keybind.command, page, keybind) end, {} })
            end
        end
    end
end
