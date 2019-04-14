%% Simple config storage type that stores everything in a map
-module(lee_dirty_mnesia_storage).

-behavior(lee_storage).

-include("lee.hrl").

-export([ create/1
        , get/2
        , patch/3
        ]).

-export([from_table/1]).

%%====================================================================
%% API functions
%%====================================================================
from_table(TabName) ->
    lee_storage:wrap(?MODULE, TabName).

%%====================================================================
%% lee_storage callbacks
%%====================================================================

create(Options) ->
    error(unsupported).

get(Key, TabName) ->
    case mnesia:dirty_read(TabName, Key) of
        [{_, Key, Val}] ->
            {ok, Val};
        [] ->
            undefined
    end.

patch(TabName, Delete, Set) ->
    %% Dirty patches are not allowed.
    error(unsupported).
