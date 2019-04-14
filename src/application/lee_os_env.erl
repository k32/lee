-module(lee_os_env).

-export([ metamodel/0
        , read/1
        , read_to/2
        ]).

-include("lee.hrl").

-define(environment_variable, environment_variable).
-define(os_env, os_env).

-spec metamodel() -> lee:module().
metamodel() ->
    #{ metatype => #{ ?environment_variable =>
                          {[metatype]
                          , #{}
                          }
                    }}.

-spec read(lee:model()) -> lee:patch().
read(Model) ->
    EnvVars = lee_model:get_metatype_index(?environment_variable, Model),
    lists:foldl( fun(Key, Acc) ->
                         read_val(Model, Key, Acc)
                 end
               , []
               , EnvVars).

-spec read_to(lee:model(), lee:data()) -> lee:data().
read_to(Model, Data) ->
    Patch = read(Model),
    lee_storage:patch(Data, Patch).

read_val(Model, Key, Acc) ->
    #mnode{metaparams = Attrs} = lee_model:get(Key, Model),
    EnvVar = maps:get(?os_env, Attrs),
    case os:getenv(EnvVar) of
        false ->
            Acc;
        Value ->
            [{set, Key, Value} | Acc]
    end.
