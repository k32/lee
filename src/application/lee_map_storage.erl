%% @doc Simple config storage type that stores everything in a map
-module(lee_map_storage).

-behavior(lee_storage).

-include("lee.hrl").

-export([ create/1
        , get/2
        , patch/3
        ]).

%% @private
create(_) ->
    #{}.

%% @private
get(Key, Map) ->
    case Map of
        #{Key := Val} ->
            {ok, Val};
        #{} ->
            undefined
    end.

%% @private
patch(Data0, Delete, Set) ->
    Data1 = maps:without(Delete, Data0),
    maps:merge(Data1, maps:from_list(Set)).
