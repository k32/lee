%% Simple config storage type that stores everything in a map
-module(lee_mnesia_storage).

-behavior(lee_storage).

-include("lee.hrl").

-export([ create/1
        , get/2
        , patch/3
        ]).

-export([ patch/2
        , ensure_table/2
        ]).

%%====================================================================
%% API functions
%%====================================================================

ensure_table(TabName, TabOpts0) ->
    TabOpts = [{attributes, [key, val]} | TabOpts0],
    case mnesia:create_table(TabName, TabOpts) of
        {atomic, ok} ->
            {atomic, Ret} = mnesia:transaction(
                              fun() ->
                                      lee_storage:new( lee_mnesia_storage
                                                     , #{table_name => TabName}
                                                     )
                              end),
            Ret;
        {aborted, {already_exists, _}} ->
            lee_storage:wrap(?MODULE, TabName)
    end.

%% @doc Apply a patch in transaction
patch(Data, Patch) ->
    {atomic, ok} = mnesia:transaction(
                     fun() ->
                             lee_storage:patch(Data, Patch),
                             ok
                     end),
    ok.

%%====================================================================
%% lee_storage callbacks
%%====================================================================

%% Note: it does not actually create table!
create(Options) ->
    TabName = maps:get(table_name, Options, lee_mnesia_storage),
    Keys = mnesia:all_keys(TabName),
    [mnesia:delete({TabName, K}) || K <- Keys],
    TabName.

get(Key, TabName) ->
    case mnesia:read(TabName, Key) of
        [{_, Key, Val}] ->
            {ok, Val};
        [] ->
            undefined
    end.

patch(TabName, Delete, Set) ->
    [mnesia:delete({TabName, K}) || K <- Delete],
    [mnesia:write({TabName, K, V}) || {K, V} <- Set],
    TabName.
