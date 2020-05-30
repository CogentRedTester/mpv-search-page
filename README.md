# mpv-search-page

This script allows you to search for keybinds, properties, options and commands and have matching entries display on the OSD.
The search is case insensitive by default, and the script sends the filter directly to a lua string match function, so you can use patterns to get more complex filtering. For options and limitations see the Queries and Flags sections.

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

These queries can be combined, i.e. `key$cmd$` to search multiple categories at once. Queries can have spaces in them, but if so they must be enclosed in brackets.

Sending a query message without any arguments (or with only the type argument) will reopen the last search page.

## Lua Patterns

This script sends queries directly into the Lua string find function, with the only modification being that the query is converted into lowercase. The find function supports something called [patterns](http://lua-users.org/wiki/PatternsTutorial) to identify any matching substrings. In order to facilitate this there are a number of symbols, such as `? % . ^ [ ]`, which are reserved for pattern creation. If you try to search with any of these symbols you may get some unexpected results; however, you can escape these characters using a `%` sign. If you wish to use patterns to run extremely precise searches, then you may want to look at the flags section for how to make the queries more pattern friendly.

## Flags

By default the script will convert both the search query, and all the strings it scans into lower case for a wider range of results. It returns any result that contains the full query somewhere in its values. Flags can be used to modify this behaviour. Flags are strings you can add after query, currently there are 3:

        wrap        search for a whole word only (may not work with some symbols)
        pattern     don't convert the query to lowercase, required for some Lua patterns
        exact       don't convert anything into lowercase

These flags can be combined, so for example a query `t wrap` would normally result in both lower and upper case t matches, however, `t wrap+exact` will return only lowercase t. The pattern flag is only useful when doing some funky pattern stuff, for example:
`f%A wrap+pattern` will return all complete words containing f followed by a non-letter. Often `exact` will work just fine for this,
but in this example we might still want to find upper-case keys, like function keys, so using just `pattern` can be more useful.

These flags may be subject to change


## Options

Search page will read several options from script-opts when the player is lanched, the current options, and their defaults are:

    enable_jumplist = yes   #this disables the jumplist keybinds
    max_list = 30           #this defines how many search results to show

In addition there are a sizeable number of options to customise the ass tags that the page uses. This theoretically allows you to customise the page in almost any way you like. There are far too many to show here, the full list is near the top of the script.

## Future Plans

Some ideas for future functionality:

*   Add jumplists for properties and options
*   Add multiple commands for each item using Ctrl,Alt, etc
*   Implement scrolling
*   Implement a cursor to select items for commands (same as jumplist)
*   Search multiple queries at once (may already be possible with lua patterns)

