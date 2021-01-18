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

local o = {
    --enables the 1-9 jumplist for the search pages
    enable_jumplist = true,

    --there seems to be a significant performance hit from having lots of text off the screen
    max_list = 22,

    --number of pixels to pan on each click
    --this refers to the horizontal panning
    pan_speed = 100,

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

local osd_display = mp.get_property_number('osd-duration')

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
        {"ENTER", "run_current", function() if temp[temp.selected] then temp[temp.selected].funct() end end, {}},
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
                funct = function()
                    self:close()
                    mp.command(keybind.cmd)

                    mp.add_timeout(osd_display/1000, function()
                        self:open()
                    end)
                end
            })
        end
    end

    --does a second pass of the results and greys out any overwritten keys
    for _,v in self:ipairs() do
        if keybound[v.key] and keybound[v.key].cmd ~= v.cmd then
            v.ass = "{\\alpha&H80&}"..v.ass.."{\\alpha&H00&}"
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
            local result_no_ass = cmd

            local arg_string = ""

            for _,arg in ipairs(command.args) do
                if arg.optional then
                    arg_string = arg_string .. o.ass_optargs
                    result_no_ass = result_no_ass .. " "
                else
                    result_no_ass = result_no_ass .. " !"
                    arg_string = arg_string .. o.ass_args
                end
                result_no_ass = result_no_ass .. arg.name .. "("..arg.type..") "
                arg_string = arg_string .. " " .. arg.name .. o.ass_argtype.." ("..arg.type..") "
            end

            self:insert({
                type = "command",
                ass = o.ass_cmd..self.ass_escape(cmd)..return_spaces(cmd:len(), 20)..arg_string,
                funct = function()
                    mp.commandv('script-message-to', 'console', 'type', command.name .. " ")
                    self:close()
                    msg.info("")
                    msg.info(result_no_ass)
                end
            })
        end
    end
end

function OPTIONS:search(keyword, flags)
    local options = mp.get_property_native('options')

    for _,option in ipairs(options) do
        local choices = mp.get_property_osd("option-info/"..option..'/choices', ""):gsub(",", " , ")

        if
        compare(option, keyword, flags)
        or compare(choices, keyword, flags)
        then
            local type = mp.get_property_osd('option-info/'..option..'/type', '')

            --we're saving the string lengths as an incrementing variable so that
            --ass modifiers don't bloat the string. This is for calculating spaces
            local length_no_ass = type:len() + option:len()
            local first_space = return_spaces(length_no_ass, 40)

            local opt_value = "= "..mp.get_property_osd('options/'..option, "")
            length_no_ass = length_no_ass + first_space:len() + opt_value:len()
            local second_space = return_spaces(length_no_ass, 60)

            local default =mp.get_property_osd('option-info/'..option..'/default-value', "")
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
                options_spec = "    [ "..mp.get_property_number('option-info/'..option..'/min', "").."  -  ".. mp.get_property_number("option-info/"..option..'/max', "").." ]"
            end

            local result = o.ass_options..self.ass_escape(option).."  "..o.ass_optionstype..type..first_space..o.ass_optvalue..self.ass_escape(opt_value)
            result = result..second_space..o.ass_optionsdefault..self.ass_escape(default)..third_space..o.ass_optionsspec..self.ass_escape(options_spec)
            self:insert({
                type = "option",
                ass = result,
                funct = function()
                    mp.commandv('script-message-to', 'console', 'type', 'set '.. option .. " ")
                    self:close()
                end
            })
        end
    end
end

function PROPERTIES:search(keyword, flags)
    local properties = mp.get_property_native('property-list', {})

    for _,property in ipairs(properties) do
        if compare(property, keyword, flags) then
            self:insert({
                type = "property",
                ass = o.ass_properties..self.ass_escape(property)..return_spaces(property:len(), 40)..o.ass_propertycurrent..self.ass_escape(mp.get_property(property, "")),
                funct = function()
                    mp.commandv('script-message-to', 'console', 'type', 'print-text ${'.. property .. "} ")
                    self:close()
                end
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
