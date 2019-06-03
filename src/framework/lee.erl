-module(lee).

%% API exports
-export([ namespace/2
        , base_metamodel/0
        , metametamodel/0
        , get/3
        , list/3
        , validate/2
        , validate/3
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

-type metatype() :: atom().

-type node_id() :: atom() %% Should not begin with `$', these are reserved
                 | tuple()
                 | integer()
                 .

-type model_key() :: [ node_id() | ?children ].

-type key() :: [ node_id() | ?lcl(term()) | ?children ].

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

%% @doc Put model to a namespace
%%
%% ```namespace([foo, bar], A)''' is equivalent to writing
%% ```#{foo => #{bar => A}}'''
-spec namespace(lee:key(), lee:module()) ->
                       lee:module().
namespace(Key, M) ->
    lists:foldl( fun(NodeId, Acc) ->
                         #{NodeId => Acc}
                 end
               , M
               , lists:reverse(Key)
               ).

%% @doc Model module containing basic configuration validation
%% metaclasses
-spec base_metamodel() -> lee:module().
base_metamodel() ->
    namespace([metatype]
             , #{ value =>
                      {[metatype],
                       #{ validate_node => fun validate_value/4
                        }}
                , map =>
                      {[metatype], #{}}
                , type =>
                      {[metatype] , #{}}
                , typedef =>
                      {[metatype] , #{}}
                }
             ).

%% @doc A model validating metamodels
-spec metametamodel() -> lee:module().
metametamodel() ->
    MetaModel = #{
                 },
    {ok, Result} = lee_model:merge([MetaModel]),
    Result.

%% @doc Get a value from the config:
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

%% List instances that can match the pattern
-spec list(model() | cooked_module(), data(), lee:key()) -> [lee:key()].
list(_Model, Data, Pattern) when ?is_storage(Data) ->
    %% TODO: Include default values in the list
    lee_storage:list(Pattern, Data);
list(Model, Data, Pattern) when is_list(Data) ->
    lists:usort(lists:foldl( fun(I, Acc) ->
                                     list(Model, I, Pattern) ++ Acc
                             end
                           , []
                           , Data)).

%% Validate all values against the model
-spec validate(lee:model(), data()) -> validate_result().
validate(Model, Data) ->
    validate(all, Model, Data).

%% Validate all instances of certain metatypes against the model
-spec validate([metatype()] | all, lee:model(), data()) -> validate_result().
validate(MetaTypes, Model, Data) ->
    ModelIdx0 = Model#model.meta_class_idx,
    ModelIdx = case MetaTypes of
                   all -> ModelIdx0;
                   L   -> maps:with(L, ModelIdx0)
               end,
    {Errors, Warnings} =
        maps:fold( fun(MetaType, Nodes, {Err0, Warn0}) ->
                           {Err1, Warn1} = validate_nodes(Model, Data, MetaType, Nodes),
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

-spec from_string(lee:model(), lee:model_key(), string()) ->
                         {ok, term()} | {error, string()}.
from_string(Model, Key, String) ->
    #mnode{metaparams = MP} = lee_model:get(Key, Model),
    Type = maps:get(type, MP),
    Default = fun(Str) ->
                      case typerefl:from_string(Type, Str) of
                          Ok = {ok, _} ->
                              Ok;
                          error ->
                              {error, "Unable to parse term"}
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
            %% from_string callback is defined:
            #{?m_valid(value, from_string) := Fun} ->
                {ok, [case Fun(I) of
                          {ok, T}          -> T;
                          Err = {error, _} -> throw(Err)
                      end || I <- Strings]};
            %% Fallback to typerefl:
            _ ->
                case typerefl:from_string(Type, Strings) of
                    {ok, L} ->
                        {ok, L};
                    error ->
                        Msg = lee_lib:format("Not an Erlang term: ~p", [Strings]),
                        throw({error, Msg})
                end
        end
    catch
        Err = {error, _} -> Err
    end.

%%====================================================================
%% Internal functions
%%====================================================================

%% Validate all nodes belonging to a metatype
-spec validate_nodes( lee:model()
                    , lee:data()
                    , atom() | integer() | tuple()
                    , ordsets:set(lee:model_key())
                    ) -> {[string()], [string()]}.
validate_nodes(Model, Data, MetaTypeId, Nodes) ->
    #model{metamodel = Meta} = Model,
    #mnode{metaparams = Attrs} = lee_model:get([metatype, MetaTypeId], Meta),
    ValidateFun = maps:get( validate_node
                          , Attrs
                          , fun(_, _, _, _) -> {[], []} end
                          ),
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
                   ) -> {[string()], [string()]}.
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
-spec validate_value( lee:model()
                    , lee:data()
                    , lee:key()
                    , #mnode{}
                    ) -> {[string()], [string()]}.
validate_value(Model, Data, Key, #mnode{metaparams = Attrs}) ->
    Type = maps:get(type, Attrs),
    Default = case Attrs of
                  #{default := Default0} ->
                      {ok, Default0};
                  _ ->
                      undefined
              end,
    case {lee_storage:get(Key, Data), Default} of
        {{ok, Term}, _} ->
            Result = case typerefl:typecheck(Type, Term) of
                         ok           -> {ok, []};
                         {error, Err} -> {error, [Err], []}
                     end,
            case lee_lib:inject_error_location(Key, Result) of
                {ok, Warn} ->
                    {[], Warn};
                {error, Err1, Warn} ->
                    {Err1, Warn}
            end;
        {undefined, {ok, _}} ->
            {[], []};
        {undefined, undefined} ->
            Err = lee_lib:format("~p: Mandatory value is missing in the config", [Key]),
            {[Err] , []}
    end.
