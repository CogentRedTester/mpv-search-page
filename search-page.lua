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

    The keybind and command pages have a jumplist implementation, while on the search page you can press the number keys, 1-9,
    to select the entry at that location. On the keybinds page it runs the command without exitting the page,
    on the commands page it exits the page and loads the command up into console.lua.

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
    max_list = 28,

    --number of pixels to pan on each click
    --this refers to the horizontal panning
    pan_speed = 100,

    --all colour options
    ass_header = "{\\c&H00ccff>&\\fs40\\b500\\q2\\fnMonospace}",
    ass_underline = "{\\c&00ccff>&\\fs30\\b100\\q2}",
    ass_footer = "{\\c&00ccff>&\\b500\\fs20}",

    --colours for keybind page
    ass_allkeybindresults = "{\\fs20\\q2}",
    ass_key = "{\\c&Hffccff>&}",
    ass_section = "{\\c&H00cccc>&}",
    ass_cmdkey = "{\\c&Hffff00>&}",
    ass_comment = "{\\c&H33ff66>&}",

    --colours for commands page
    ass_cmd = "{\\c&Hffccff>\\fs20\\q2}",
    ass_args = "{\\fs20\\c&H33ff66>&}",
    ass_optargs = "{\\fs20\\c&Hffff00>&}",
    ass_argtype = "{\\c&H00cccc>&\\fs12}",

    --colours for property list
    ass_properties = "{\\c&Hffccff>\\fs20\\q2}",
    ass_propertycurrent = "{\\c&Hffff00>&}",

    --colours for options list
    ass_options = "{\\c&Hffccff>\\fs20\\q2}",
    ass_optvalue = "{\\fs20\\c&Hffff00>&}",
    ass_optionstype = "{\\c&H00cccc>&}{\\fs20}",
    ass_optionsdefault = "{\\c&H00cccc>&}",
    --list of choices for choice options, ranges for numeric options
    ass_optionsspec = "{\\c&H33ff66>&\\fs20}",
}

opt.read_options(o, "search_page")

local ov = mp.create_osd_overlay("ass-events")

--an array of objects for each entry
--each object contains:
--  line = the ass formatted string
--  type = the type of entry
--  funct = the function to run on keypress
local results = {}

local osd_display = mp.get_property_number('osd-duration')
ov.hidden = true
local search = {
    posX = 25,
    start = 1,
    keyword = "",
    flags = ""
}

dynamic_keybindings = {
    "search_page_key/down_page",
    "search_page_key/up_page",
    "search_page_key/close_overlay",
    "search_page_key/run_current",
    "search_page_key/pan_left",
    "search_page_key/pan_right"
}

local jumplist_keys = {
    "search_page_key/1",
    "search_page_key/2",
    "search_page_key/3",
    "search_page_key/4",
    "search_page_key/5",
    "search_page_key/6",
    "search_page_key/7",
    "search_page_key/8",
    "search_page_key/9"
}

--removes keybinds
function remove_bindings()
    for _,key in ipairs(jumplist_keys) do
        mp.remove_key_binding(key)
    end
    for _,key in ipairs(dynamic_keybindings) do
        mp.remove_key_binding(key)
    end
end

--closes the overlay and removes bindings
function close_overlay()
    ov.hidden = true
    ov:update()
    remove_bindings()
end

--loads the header for the search page
function load_header(keyword, name, flags)
    if name == nil then name = "" end
    ov.data = ov.data .. "\\N" .. o.ass_header .. "Search results for " .. name .. ' "' .. keyword .. '"'..flags.."\\N"..o.ass_underline.."---------------------------------------------------------"
end

--loads the results up onto the screen
--is run for every scroll operation as well
function load_results()
    local start = search.start
    local keyword = search.keyword
    local flags = search.flags

    ov.data = "{\\pos("..search.posX..",0)\\an7}"
    if not flags then
        flags = ""
    else
        flags = " ("..flags..")"
    end

    --if there are no results then a header will never be printed. We don't want that, so here we are
    if #results == 0 then
        ov.data = ov.data .. "\\N" .. o.ass_header .. "No results for '" .. keyword .. "'"..flags.."\\N"..o.ass_underline.."---------------------------------------------------------"
        return
    end

    if o.enable_jumplist then
        mp.remove_key_binding("search_page_key/run_current")
        mp.add_forced_key_binding("ENTER", "search_page_key/run_current", results[search.start].funct)
    end
    local header = results[start].type
    load_header(keyword, header, flags)

    --prints the number of results above
    if start > 1 then
        ov.data = ov.data .. '\\N'..o.ass_footer..(start-1).." results above"
    end

    local max = o.max_list
    --prints the results themselves
    local i = start
    while i < start+max  do
        local result = results[i]
        if result == nil then break end

        if result.type ~= header then
            load_header(keyword, result.type, flags)
            header = result.type
            max = max - 5
        end
        ov.data = ov.data .. '\\N' .. result.line
        i = i + 1
    end

    --prints the number of results left
    if #results >= i then
        ov.data = ov.data .. "\\N".. o.ass_footer.. #results - i + 1 .. " results remaining"
    end
end

--enables the overlay
--and sets keybinds
function open_overlay()
    ov.hidden = false
    ov:update()

    --assigns the keybinds

    --scroll down
    mp.add_forced_key_binding("DOWN", "search_page_key/down_page", function()
        search.start = search.start+1
        if search.start > #results then
            search.start = #results
            return
        end
        load_results()
        ov:update()
    end, {repeatable = true})

    --scroll up
    mp.add_forced_key_binding("UP", "search_page_key/up_page", function()
        search.start = search.start-1
        if search.start < 1 then
            search.start = 1
            return
        end
        load_results()
        ov:update()
    end, {repeatable = true})

    --pan right
    mp.add_forced_key_binding("RIGHT", "search_page_key/pan_right", function()
        search.posX = search.posX - o.pan_speed
        load_results()
        ov:update()
    end, {repeatable = true})

    --pan left
    mp.add_forced_key_binding("LEFT", "search_page_key/pan_left", function()
        search.posX = search.posX + o.pan_speed
        if search.posX > 25 then
            search.posX = 25
            return
        end
        load_results()
        ov:update()
    end, {repeatable = true})

    --close search page
    mp.add_forced_key_binding("ESC", "search_page_key/close_overlay", close_overlay)

    --sets the jumplist commands
    if not o.enable_jumplist then return end
    for i,result in ipairs(results) do
        if i < 10 and result.funct then
            mp.add_forced_key_binding(tostring(i), jumplist_keys[i], result.funct)
        end
    end
end

--replaces any characters that ass can't display normally
--currently this is just curly brackets
function fix_chars(str)
    str = tostring(str)
    str = str:gsub([[\]], [[\ ]])
    str = str:gsub('{', "\\{")
    str = str:gsub('}', "\\}")
    return str
end

--handles the search queries
function compare(str, keyword, flags)
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

function return_spaces(string_len, width)
    local num_spaces = width - string_len
    if num_spaces < 2 then num_spaces = 2 end
    return string.rep(" ", num_spaces)
end

--search keybinds
function search_keys(keyword, flags)
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

            key = fix_chars(key)
            section = fix_chars(section)
            cmd = fix_chars(cmd)
            comment = fix_chars(comment)

            --appends the result to the list
            table.insert(results, {
                type = "key",
                line = o.ass_allkeybindresults .. o.ass_key .. key .. o.ass_section .. section .. o.ass_cmdkey .. cmd .. o.ass_comment .. comment,
                key = keybind.key,
                cmd = keybind.cmd,
                funct = function()
                    ov.hidden = true
                    ov:update()
                    mp.command(keybind.cmd)

                    mp.add_timeout(osd_display/1000, function()
                        ov.hidden = false
                        ov:update()
                    end)
                end
            })
        end
    end

    --does a second pass of the results and greys out any overwritten keys
    for _,v in ipairs(results) do
        if keybound[v.key] and keybound[v.key].cmd ~= v.cmd then
            v.line = "{\\alpha&H80&}"..v.line.."{\\alpha&H00&}"
        end
        v.key = nil
        v.cmd = nil
    end
end

--search commands
function search_commands(keyword, flags)
    commands = mp.get_property_native('command-list')

    for _,command in ipairs(commands) do
        if
        compare(command.name, keyword, flags)
        then
            local cmd = fix_chars(command.name)
            local result_no_ass = cmd

            --add set number of spaces
            local result = o.ass_cmd .. cmd .. return_spaces(cmd:len(), 20)

            for _,arg in ipairs(command.args) do
                if arg.optional then
                    result = result .. o.ass_optargs
                else
                    result_no_ass = result_no_ass .. " !"
                    result = result .. o.ass_args
                end
                result_no_ass = result_no_ass .. arg.name .. "("..arg.type..") "
                result = result .. " " .. arg.name .. o.ass_argtype.." ("..arg.type..") "
            end

            table.insert(results, {
                type = "command",
                line = result,
                funct = function()
                    mp.commandv('script-message-to', 'console', 'type', command.name .. " ")
                    close_overlay()
                    msg.info("")
                    msg.info(result_no_ass)
                end
            })
        end
    end
end

function search_options(keyword, flags)
    local options = mp.get_property_native('options')

    for _,option in ipairs(options) do
        local choices = mp.get_property_osd("option-info/"..option..'/choices', ""):gsub(",", " , ")

        if
        compare(option, keyword, flags)
        or compare(choices, keyword, flags)
        then
            local type = mp.get_property_osd('option-info/'..option..'/type', '')
            local opt_value = fix_chars(mp.get_property_osd('options/'..option, ""))

            local result = o.ass_options..fix_chars(option).."  "..o.ass_optionstype..type..return_spaces(option:len()+type:len()+2, 35)
            local result = result..o.ass_optvalue.."= "..opt_value

            -- local whitespace = 60 - (option:len() + option_type:len() + opt_value:len())
            -- if whitespace < 4 then whitespace = 4 end
            -- whitespace = string.rep(" ", whitespace)
            local default =fix_chars(mp.get_property_osd('option-info/'..option..'/default-value', ""))
            local result = result..return_spaces(result:len(), 115)..o.ass_optionsdefault..default

            local options_spec = ""

            if type == "Choice" then
                options_spec = fix_chars("    [ " .. choices .. ' ]')
            elseif type == "Integer"
            or type == "ByteSize"
            or type == "Float"
            or type == "Aspect"
            or type == "Double" then
                options_spec = fix_chars("    [ "..mp.get_property_number('option-info/'..option..'/min', "").."  -  ".. mp.get_property_number("option-info/"..option..'/max', "").." ]")
            end

            table.insert(results, {
                type = "option",
                line = result.. return_spaces(result:len(), 140) .. o.ass_optionsspec..options_spec})
        end
    end
end

function search_property(keyword, flags)
    local properties = mp.get_property_native('property-list', {})

    for _,property in ipairs(properties) do
        if compare(property, keyword, flags) then
            table.insert(results, {
                type = "property",
                line = o.ass_properties .. property .. return_spaces(property:len(), 35) .. o.ass_propertycurrent .. fix_chars(mp.get_property(property, ""))})
        end
    end
end

--recieves the input messages
mp.register_script_message('search_page/input', function(type, keyword, flags)
    if keyword == nil then
        if ov.data ~= "" then
            mp.command("script-binding console/_console_1")
            remove_bindings()
            open_overlay()
        end
        return
    end

    local flagsstr = flags
    if flagsstr then
        flags = {}
        for flag in flagsstr:gmatch("[^%+]+") do
            flags[flag] = true
        end
    end

    results = {}
    if type:find("key%$") or type == "all$" then
        search_keys(keyword, flags)
    end
    if type:find("cmd%$") or type == "all$" then
        search_commands(keyword, flags)
    end
    if type:find("prop%$") or type == "all$" then
        search_property(keyword, flags)
    end
    if type:find("opt%$") or type == "all$" then
        search_options(keyword, flags)
    end

    mp.command("script-binding console/_console_1")
    remove_bindings()
    search.keyword = keyword
    search.flags = flagsstr
    search.start = 1
    load_results()
    open_overlay()
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

mp.add_key_binding("Alt+Shift+Ctrl+f12", "search-all", function ()
    mp.commandv('script-message-to', 'console', 'type', 'script-message search_page/input all$ ')
end)
