%% @doc Read configuration from OS environment variables.
%%
%% This module privides means of mapping OS environment variables to
%% Lee configuration values. Values of environment variables are
%% parsed according to the following rules: Lee values of type
%% `string()' are used verbatim. Values of type `atom()' are
%% transformed using `list_to_atom/1' function and the rest of types
%% are parsed as Erlang terms.
-module(lee_os_env).

-export([ metamodel/0
        , read/1
        , read_to/2
        , document_values/2
        , meta_validate/4
        ]).

-include_lib("lee/src/framework/lee_internal.hrl").

-define(metatype, os_env).

%% @doc Metamodel module containing metatypes for reading
%% configuration from `eterm' files
%%
%% It defines the following metatype:
%% == os_env ==
%%
%% === Metaparameters ===
%% <ul><li>`os_env' of type `string()':
%%     Environment variable mapping
%%     </li>
%% </ul>
%%
%% === Depends on ===
%% {@link lee:base_metamodel/0 . value}
%%
%% === Example ===
%% ```
%%  #{ home => {[value, os_env],
%%              #{ os_env => "HOME"
%%               , type   => string()
%%               }}
%%   , path => {[value, os_env],
%%              #{ os_env => "PATH"
%%               , type   => string()
%%               }}
%%   }'''
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

%% @private
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

%% @private
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

%% @private
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
