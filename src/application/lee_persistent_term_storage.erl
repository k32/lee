-module(lee_persistent_term_storage).

-behavior(lee_storage).

-include("lee.hrl").

-export([ create/1
        , get/2
        , patch/3
        ]).

-export_type([storage/0]).

-type storage_key() :: atom().

-opaque storage() :: atom().

%% @private
-spec create(storage_key()) -> storage().
create(StorageKey) ->
    StorageKey.

%% @private
get(Key, StorageKey) ->
    persistent_term:get({StorageKey, Key}, undefined).

%% @private
patch(StorageKey, Delete, Set) ->
    [persistent_term:erase({StorageKey, Key}) || Key <- Delete],
    [persistent_term:put({StorageKey, Key}, {ok, Value}) || {Key, Value} <- Set],
    StorageKey.
