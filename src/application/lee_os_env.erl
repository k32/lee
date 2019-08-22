-module(lee_os_env).

-export([ metamodel/0
        , read/1
        , read_to/2
        , document_values/2
        , meta_validate/4
        ]).

-include_lib("lee/src/framework/lee_internal.hrl").

-define(metatype, os_env).

-spec metamodel() -> lee:lee_module().
metamodel() ->
    #{ metatype =>
           #{ ?metatype =>
                  {[metatype, documented]
                  , #{ doc_chapter_title => "OS Environment Variables"
                     , doc_gen           => fun ?MODULE:document_values/2
                     , meta_validate     => fun ?MODULE:meta_validate/4
                     }
                  }
            }
     }.

-spec meta_validate(lee:model(), _, lee:key(), #mnode{}) ->
                            lee_lib:check_result().
meta_validate(_, _, Key, MNode) ->
    lee_lib:validate_meta_attr( os_env
                              , typerefl:printable_latin1_list()
                              , MNode
                              ).

%% @doc Make a patch from OS environment variables
%% @throws {error, string()}
-spec read(lee:model()) -> lee:patch().
read(Model) ->
    EnvVars = lee_model:get_metatype_index(?metatype, Model),
    lists:foldl( fun(Key, Acc) ->
                         read_val(Model, Key, Acc)
                 end
               , []
               , EnvVars).

%% @doc Make a patch from OS environment variables and apply it to
%% data
%% @throws {error, string()}
-spec read_to(lee:model(), lee_storage:data()) -> lee_storage:data().
read_to(Model, Data) ->
    Patch = read(Model),
    lee_storage:patch(Data, Patch).

read_val(Model, Key, Acc) ->
    #mnode{metaparams = Attrs} = lee_model:get(Key, Model),
    EnvVar = ?m_attr(?metatype, os_env, Attrs),
    case os:getenv(EnvVar) of
        false ->
            Acc;
        Value0 ->
            case lee:from_string(Model, Key, Value0) of
                {ok, Value} ->
                    [{set, Key, Value} | Acc];
                {error, _} = Error ->
                    throw(Error)
            end
    end.

-spec document_values(lee:model(), term()) -> lee_doc:doc().
document_values(Model, _Config) ->
    #model{meta_class_idx = Idx} = Model,
    Keys = maps:get(?metatype, Idx, []),
    Fun = fun(Key) ->
                  MNode = lee_model:get(Key, Model),
                  #mnode{metaparams = Attrs} = MNode,
                  EnvVar = ?m_attr(?metatype, os_env, Attrs),
                  lee_doc:refer_value(Key, ?metatype, EnvVar, MNode)
          end,
    Intro = "<para>The following OS environment variables are used to
             set configuration values. Values of type string() are
             taken from OS environment variables verbatim, other types
             are parsed as Erlang terms.</para>",
    lee_doc:docbook(Intro) ++ lists:map(Fun, Keys).
