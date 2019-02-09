-module(lee_storage).

-include("lee_internal.hrl").

-export([ new/2
        , get/3
        , put/3
        , list/3
        ]).

-export_type([ storage/0
             ]).

-type storage() :: term().

-callback create(Options :: term()) ->
    storage().

-callback get(lee:model(), storage(), lee:key()) ->
    {ok, term()} | undefined.

-callback put(lee:model(), A, [{lee:key(), term()}]) -> A
    when A :: storage().

-callback list(lee:model(), storage(), lee:key()) ->
    [lee:key()].

-spec new(atom(), term()) -> lee:data().
new(Module, Options) ->
    #data{ backend = Module
         , data    = Module:create(Options)
         }.

-spec get(lee:model(), #data{}, lee:key()) ->
                 {ok, term()} | undefined.
get(Model, #data{backend = Backend, data = Data}, Key) ->
    Backend:get(Model, Data, Key).

-spec put(lee:model(), lee:data(), [{lee:key(), term()}]) ->
                 lee:data().
put(Model, #data{backend = Backend, data = Data}, Patch) ->
    #data{ backend = Backend
         , data = Backend:put(Model, Data, Patch)
         }.

%% List instances that can potentially match the pattern
-spec list(lee:model(), lee:data(), lee:key()) ->
                 [lee:key()].
list(Model, #data{backend = Module, data = Data}, Key) ->
    Module:list(Model, Data, Key).
