# mpv-search-page

This script allows you to search for keybinds, properties, options and commands and have matching entries display on the OSD.
The search is case insensitive, and the script sends the filter directly to a lua string match function, so you can use patterns to get more complex filtering. However, there are some limitations, in order to have 

## Pages

The keybind page searches and displays the key, command, section, and any comments.

The command page searches just the command name, but also shows information about arguments.

The properties page will search just the property name, but will also show contents of the property

The options page will search the name and option choices, it shows default values, choices, and ranges

The search page will remain open until told to close. This key is esc.

## Jumplist

The keybind and command pages have a jumplist implementation, while on the search page you can press the number keys, 1-9,
to select the entry at that location. On the keybinds page it runs the command without exitting the page,
on the commands page it exits the page and loads the command up into console.lua.


## Keybinds

The default commands are:

    f12 script-binding search-keybinds
    Ctrl+f12 script-binding search-commands
    Shift+f12 script-binding search-properties
    Alt+f12 script-binding search-options
    Ctrl+Shift+Alt script-binding search-all


## Queries

Once the command is sent the console will open with a pre-entered search command, simply add a query string as the first argument.
Using the above keybinds will pre-enter the raw query command into the console, but you can modify it to search multiple criteria at once.

The raw command is:

    script-message search_page/input [query types] [query string] {flags}

The valid query types are as follows:

    key$    searches keybindings
    cmd$    searches command
    prop$   searches properties
    opt$    searches options
    all$    searches all

These queries can be combined, i.e. `key$cmd$` to search multiple categories at once

Sending a query message without any arguments (or with only the type argument) will reopen the last search.

## Flags

Flags are strings you can add to the end to customise the query, currently there are 3:

        wrap        search for a whole word only
        pattern     don't convert the query to lowercase (the default) required for some Lua patterns
        exact       don't convert the search results into lowercase, might solve some incorrect pattern returns

These flags can be combined, so for example a query `t wrap` would normally result in both lower and upper case t binds, however, `t wrap+exact` will return only lowercase t, and `T wrap+exact+pattern` will return only uppercase T

These flags may be subject to change


## Future Plans

Some ideas for future functionality:

*   Add jumplists for properties and options
*   Add multiple commands for each item using Ctrl,Alt, etc
*   Implement scrolling
*   Implement a cursor to select items for commands (same as jumplist)
*   Search multiple queries at once (may already be possible with lua patterns)

