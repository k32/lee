-module(lee).

%% API exports
-export([ namespace/2
        , base_metamodel/0
        , get/3
        , list/3
        , validate/2
        , validate/3
        , meta_validate/1
        , meta_validate/2
        , from_string/3
        , from_strings/3
        ]).

-export_type([ node_id/0
             , model_key/0
             , key/0
             , metatype/0
             , type/0
             , mnode/0
             , model/0
             , lee_module/0
             , cooked_module/0
             , properties/0
             , data/0
             , patch/0
             ]).

-include("lee_internal.hrl").

%%====================================================================
%% Types
%%====================================================================

-type data() :: lee_storage:data() | [lee_storage:data()].

-type patch() :: lee_storage:patch(term()).

-type namespace() :: #{node_id() => mnode() | namespace()}.

-type lee_module() :: namespace().

-type cooked_module() :: lee_storage:data(#mnode{}).

-type model() :: #model{}.

-type validate_result() :: {ok, Warnings :: [string()]}
                         | {error, Errors :: [term()], Warnings :: [term()]}.

-type validate_callback() :: fun((model(), data(), key(), #mnode{}) ->
                                        validate_result()).

-type validation_type() :: validate_node | meta_validate.

-type metatype() :: atom().

-type node_id() :: atom() %% Should not begin with `$', these are reserved
                 | tuple()
                 | integer()
                 .

-type model_key() :: [ node_id() | tuple() ].

-type key() :: [ node_id() | tuple() ].

-type properties() :: #{atom() => term()}.

-type type() :: #type{} | atom() | {var, term()}.

%% Model node
-type mnode() :: {[metatype()], properties(), lee_module()}
               | {[metatype()], properties()} %% Shortcut for child-free MOs
               .

%%====================================================================
%% Macros
%%====================================================================

%%====================================================================
%% API functions
%%====================================================================

%% @doc Put model to a namespace.
%%
%% `namespace([foo, bar], A)' is equivalent to `#{foo => #{bar => A}}'
-spec namespace(lee:key(), lee:module()) ->
                       lee:module().
namespace(Key, M) ->
    lists:foldl( fun(NodeId, Acc) ->
                         #{NodeId => Acc}
                 end
               , M
               , lists:reverse(Key)
               ).

%% @doc Model module containing basic metatypes:
%%
%% == value ==
%%
%% `value' is a leaf node, i.e. a concrete value.
%%
%% === Metaparameters ===
%% <ul><li>`type' of type `typerefl:type()':
%%     Type of the value
%%     </li>
%%     <li>`default' (optional):
%%     Default value, if present</li>
%%     <li>`oneliner' of type `string()' (optional, but highly desired):
%%     One-sentence doc string</li>
%%     <li>`doc' of type `string()' (optional, but highly desired):
%%     Long description using <a href="https://docbook.org/">DocBook</a>
%%     markup</li>
%% </ul>
%%
%% == map ==
%% `map' denotes a container node that groups multiple values together.
%%
%% <b>Metaparameters</b>:
%% <ul><li>`key_elements' of type `[lee:key()]':
%%     List of child element keys that identify the map. Optional,
%%     defaults to `[]'
%%     </li>
%% </ul>
%%
-spec base_metamodel() -> lee:module().
base_metamodel() ->
    namespace([metatype]
             , #{ value =>
                      {[metatype, documented],
                       #{ validate_node     => fun validate_value/4
                        , meta_validate     => fun meta_validate_value/4
                        , doc_chapter_title => "Values"
                        , doc_gen           => fun lee_doc:document_values/2
                        }}
                , map =>
                      {[metatype],
                       #{ meta_validate     => fun meta_validate_map/4
                        }}
                , doc_root =>
                      {[metatype],
                       #{ meta_validate     => fun lee_doc:validate_doc_root/4
                        }}
                , undocumented =>
                      {[metatype],
                       #{
                        }}
                }
             ).

%% @doc Get a value from the config
%%
%% The return value is guaranteed safe, as long as `Data' has been
%% validated against the `Model', and `Key' is a valid `Model' key
-spec get(lee:model() | lee:cooked_module(), data(), lee:key()) -> term().
get(Model, Data, Key) when ?is_storage(Data) ->
    case lee_storage:get(Key, Data) of
        {ok, Val} ->
            Val;
        _ ->
            MKey = lee_model:get_model_key(Key),
            #mnode{metaparams = Attrs} = lee_model:get(MKey, Model),
            case Attrs of
                #{default := Val} ->
                    Val;
                #{default_ref := RefKey} ->
                    get(Model, Data, RefKey);
                _ ->
                    %% Data shouldn't have passed validation without
                    %% the default, so just crash here
                    error({missing_data, Key})
            end
    end;
get(Model, [Data], Key) ->
    get(Model, Data, Key);
get(Model, [Data|Rest], Key) ->
    case lee_storage:get(Key, Data) of
        {ok, Val} ->
            Val;
        undefined ->
            get(Model, Rest, Key)
    end.

%% @doc List objects in `Data' that can match `Key'
%%
%% `?children' nodes in the key will be replaced with actual child
%% keys, e.g. ```list(Model, Data, [foo, ?children])''' will return
%% ```[[foo, {1}], [foo, {2}]]''' when map `[foo]' contains
%% two children with keys `1' and `2'.
-spec list(model() | cooked_module(), data(), lee:key()) -> [lee:key()].
list(_Model, Data, Key) when ?is_storage(Data) ->
    %% TODO: Include default values in the list
    lee_storage:list(Key, Data);
list(Model, Data, Pattern) when is_list(Data) ->
    lists:usort(lists:foldl( fun(I, Acc) ->
                                     list(Model, I, Pattern) ++ Acc
                             end
                           , []
                           , Data)).

%% @equiv validate(all, Model, Data)
-spec validate(lee:model(), data()) -> validate_result().
validate(Model, Data) ->
    validate(all, Model, Data).

%% @doc Validate `Data' against `Model'. `MetaTypes' is a list of
%% metatypes that should be validated, or atom `all'
-spec validate([metatype()] | all, lee:model(), data()) -> validate_result().
validate(MetaTypes, Model, Data) ->
    validate(validate_node, MetaTypes, Model, Data).

%% @equiv meta_validate(all, Model)
-spec meta_validate(lee:model()) -> validate_result().
meta_validate(Model) ->
    meta_validate(all, Model).

%% @doc Validate model itself against its metamodel. Useful for
%% spotting bugs in the model definition
-spec meta_validate([metatype()] | all, lee:model()) -> validate_result().
meta_validate(MetaTypes, Model) ->
    Data = lee_storage:new(lee_map_storage), %% Mostly to make dialyzer happy
    validate(meta_validate, MetaTypes, Model, Data).

-spec from_string(lee:model(), lee:model_key(), string()) ->
                         {ok, term()} | {error, string()}.
from_string(Model, Key, String) ->
    #mnode{metaparams = MP} = lee_model:get(Key, Model),
    Type = maps:get(type, MP),
    Default = fun(Str) ->
                      case typerefl:from_string(Type, Str) of
                          Ok = {ok, _} ->
                              Ok;
                          {error, Err} ->
                              {error, Err}
                      end
              end,
    Fun = maps:get(from_string, MP, Default),
    Fun(String).

%% @doc Temporary function, don't use it.
-spec from_strings(lee:model(), lee:model_key(), [string()]) ->
                          {ok, [term()]} | {error, string()}.
from_strings(Model, Key, Strings) ->
    #mnode{metaparams = MP} = lee_model:get(Key, Model),
    Type = ?m_attr(value, type, MP),
    try
        case MP of
            #{?m_valid(value, from_string) := Fun} ->
                %% Custom from_string callback is defined:
                {ok, [case Fun(I) of
                          {ok, T}          -> T;
                          Err = {error, _} -> throw(Err)
                      end || I <- Strings]};
            _ ->
                %% Fallback to typerefl:
                {ok, typerefl:from_string_(Type, Strings)}
        end
    catch
        Err = {error, _} -> Err
    end.

%%====================================================================
%% Internal functions
%%====================================================================

%% Validate all instances of certain metatypes against the model
-spec validate(validation_type(), [metatype()] | all, lee:model(), data()) ->
                      validate_result().
validate(ValidationType, MetaTypes, Model, Data) ->
    ModelIdx0 = Model#model.meta_class_idx,
    ModelIdx = case MetaTypes of
                   all -> ModelIdx0;
                   L   -> maps:with(L, ModelIdx0)
               end,
    {Errors, Warnings} =
        maps:fold( fun(MetaType, Nodes, {Err0, Warn0}) ->
                           {Err1, Warn1} = validate_nodes( ValidationType
                                                         , Model
                                                         , Data
                                                         , MetaType
                                                         , Nodes
                                                         ),
                           {Err1 ++ Err0, Warn1 ++ Warn0}
                   end
                 , {[], []}
                 , ModelIdx
                 ),
    case Errors of
        [] ->
            {ok, Warnings};
        _ ->
            {error, Errors, Warnings}
    end.

%% Validate all nodes belonging to a metatype
-spec validate_nodes( validation_type()
                    , lee:model()
                    , lee:data()
                    , atom() | integer() | tuple()
                    , ordsets:set(lee:model_key())
                    ) -> lee_lib:check_result().
validate_nodes(ValidationType, Model, Data, MetaTypeId, Nodes) ->
    #model{metamodel = Meta} = Model,
    #mnode{metaparams = Attrs} = lee_model:get([metatype, MetaTypeId], Meta),
    Default = fun(_, _, _, _) -> {[], []} end,
    ValidateFun = ?m_attr(metatype, ValidationType, Attrs, Default),
    ordsets:fold( fun(NodeId, {E0, W0}) ->
                          {E1, W1} = validate_node(Model, Data, NodeId, ValidateFun),
                          {E1 ++ E0, W1 ++ W0}
                  end
                , {[], []}
                , Nodes
                ).

-spec validate_node( lee:model()
                   , lee:data()
                   , lee:key()
                   , validate_callback()
                   ) -> lee_lib:check_result().
validate_node(Model, Data, NodeId, ValidateFun) ->
    MNode = lee_model:get(NodeId, Model),
    Instances = case lee_model:split_key(NodeId) of
                    {[], _} ->
                        [NodeId];
                    {Base, Required} ->
                        [I ++ Required || I <- lee_storage:list(Base, Data)]
                end,
    lists:foldl( fun(Id, {Err0, Warn0}) ->
                         {Err1, Warn1} = ValidateFun(Model, Data, Id, MNode),
                         {Err1 ++ Err0, Warn1 ++ Warn0}
                 end
               , {[], []}
               , Instances
               ).

%% Validate nodes of `value' metatype
-spec validate_value(lee:model(), lee:data(), lee:key(), #mnode{}) ->
                            lee_lib:check_result().
validate_value(Model, Data, Key, #mnode{metaparams = Attrs}) ->
    Type = ?m_attr(value, type, Attrs),
    HasDefault = case Attrs of
                     #{default     := _} -> true;
                     #{default_ref := _} -> true;
                     _                   -> false
                 end,
    case lee_storage:get(Key, Data) of
        {ok, Term} ->
            Result = case typerefl:typecheck(Type, Term) of
                         ok           -> {[], []};
                         {error, Err} -> {[Err], []}
                     end,
            lee_lib:inject_error_location(Key, Result);
        undefined when HasDefault ->
            {[], []};
        undefined ->
            Err = lee_lib:format("~p: Mandatory value is missing in the config", [Key]),
            {[Err] , []}
    end.

-spec meta_validate_value(lee:model(), _, lee:key(), #mnode{}) ->
                            lee_lib:check_result().
meta_validate_value(Model, _, Key, #mnode{metaparams = Attrs}) ->
    Results = lee_lib:compose_checks([ lee_doc:check_docstrings(Attrs)
                                     , check_type_and_default(Model, Attrs)
                                     ]),
    lee_lib:inject_error_location(Key, Results).


-spec meta_validate_map(lee:model(), _, lee:key(), #mnode{}) ->
                            lee_lib:check_result().
meta_validate_map(#model{model = Model}, _, Key, #mnode{metaparams = Params}) ->
    ValidateKey =
        fun(ChildKey) ->
                case lee_storage:get(Key ++ [?children|ChildKey], Model) of
                    undefined ->
                        Error = lee_lib:format( "~p: ~p is not a valid child key", [Key, ChildKey]),
                        {true, Error};
                    {ok, _} ->
                        false
                end
        end,
    { case Params of
          #{key_elements := KeyElems} when is_list(KeyElems) ->
              lists:filtermap(ValidateKey, KeyElems);
          #{key_elements := _}  ->
              [lee_lib:format("~p: `key_elements' should be a list of valid child keys", [Key])];
          _ ->
              []
      end
    , []
    }.

check_type_and_default(Model, Attrs) ->
    case Attrs of
        #{type := Type, default := Default} ->
            case typerefl:typecheck(Type, Default) of
                ok ->
                    {[], []};
                {error, Err} ->
                    Str = lee_lib:format("Mistyped default value: ~s", [Err]),
                    {[Str], []}
            end;
        #{type := Type, default_ref := DefaultRef} ->
            try lee_model:get(DefaultRef, Model) of
                #mnode{metatypes = MTs, metaparams = RefAttrs} ->
                    case lists:member(value, MTs) of
                        true ->
                            case RefAttrs of
                                #{type := Type} -> %% TODO: Better type comparison?
                                    {[], []};
                                _ ->
                                    {["Type of the `default_ref' is different"], []}
                            end;
                        false ->
                            {"Invalid `default_ref' metatype", []}
                    end
            catch
                _:_ -> {["Invalid `default_ref' reference key"], []}
            end;
        #{type := _Type} ->
            %% TODO: typerefl:is_type?
            {[], []};
        _ ->
            {["Missing `type' metaparameter"], []}
    end.
