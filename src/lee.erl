-module(lee).

%% API exports
-export([ namespace/2
        , base_model/0
        , base_metamodel/0
        , metametamodel/0
        , validate_term/3
        , get/3
        , validate/2
        , validate_value/4
        , from_string/3
        ]).

-export_type([ node_id/0
             , key/0
             , metatype/0
             , type/0
             , moc/0
             , model/0
             , model_fragment/0
             , properties/0
             , data/0
             ]).

-include("lee_internal.hrl").

%%====================================================================
%% Types
%%====================================================================

-type data() :: {data, _, _}.

-type model_fragment() :: #{node_id() => moc() | model_fragment()}.

-type model() :: #model{}.

-type validate_result() :: ok | {error, term()}.

-type metatype() :: atom().

-type node_id() :: term().

-type key() :: [node_id()].

-type properties() :: #{atom() => term()}.

-type type() :: #type{} | atom() | {var, term()}.

%% Managed object class
-type moc() :: {[metatype()], properties(), model_fragment()}
             | {[metatype()], properties()} %% Shortcut for child-free MOs
             .

%%====================================================================
%% Macros
%%====================================================================

-define(typedef(Name, Arity, Validate, Rest),
        {Name, Arity} => {[type]
                         , #{ validate => fun lee_types:Validate/3
                            , typename => ??Name
                            } Rest
                         , #{}
                         }).

-define(typedef(Name, Arity, Validate),
        ?typedef(Name, Arity, Validate, #{})).

-define(typedef(Name, Validate),
        ?typedef(Name, 0, Validate)).

-define(print(Fun), #{print => fun lee_types:Fun/2}).

%%====================================================================
%% API functions
%%====================================================================

%% @doc Put model fragment in a namespace
-spec namespace(lee:key(), lee:model_fragment()) ->
                       lee:model_fragment().
namespace(Key, M) ->
    lists:foldl( fun(NodeId, Acc) ->
                         #{NodeId => Acc}
                 end
               , M
               , lists:reverse(Key)
               ).

%% @doc Model fragment containing base types.
-spec base_model() -> lee:model_fragment().
base_model() ->
    namespace([lee, base_types]
             , #{ ?typedef(union,      2, validate_union,     ?print(print_union)     )
                , ?typedef(term,          validate_term                               )
                , ?typedef(integer,    0, validate_integer,   ?print(print_integer)   )
                , ?typedef(float,         validate_float                              )
                , ?typedef(atom,          validate_atom                               )
                , ?typedef(binary,        validate_binary                             )
                , ?typedef(tuple,         validate_any_tuple                          )
                , ?typedef(tuple,      1, validate_tuple,     ?print(print_tuple)     )
                , ?typedef(list,       1, validate_list,      ?print(print_list)      )
                , ?typedef(map,        2, validate_map                                )
                , ?typedef(exact_map,  1, validate_exact_map, ?print(print_exact_map) )
                }
             ).

%% @doc Model fragment containing basic configuration validation
%% metaclasses
-spec base_metamodel() -> lee:model_fragment().
base_metamodel() ->
    Model = namespace([metatype]
                     , #{ value =>
                              {[metatype]
                              , #{validate_mo => fun validate_value/4}
                              }
                        , map => {[metatype] , #{}}
                        , type => {[metatype] , #{}}
                        , typedef => {[metatype] , #{}}
                        }
                     ),
    {ok, Val} = lee_model:merge( Model
                               , base_model()
                               ),
    Val.

%% @doc A model validating metamodels
-spec metametamodel() -> lee:model_fragment().
metametamodel() ->
    MetaModel = #{
                 },
    {ok, Result} = lee_model:merge([MetaModel, base_model()]),
    Result.

-spec validate_term( lee:model_fragment()
                   , lee:type()
                   , term()
                   ) -> validate_result().
validate_term(_Model, Atom, Term) when is_atom(Atom) ->
    case Term of
        Atom ->
            ok;
        _ ->
            {error, format( "Expected ~p, got ~p"
                          , [Atom, Term]
                          )}
    end;
validate_term(Model, Type = #type{id = TypeName, parameters = Params}, Term) ->
    {Meta, Attr1, _} = lee_model:get(TypeName, Model),
    case {lists:member(type, Meta), lists:member(typedef, Meta)} of
        {true, false} ->
            #{validate := Fun} = Attr1,
            Fun(Model, Type, Term);
        {false, true} ->
            #{ type := Type1
             , type_variables := TypeVars
             } = Attr1,
            VarVals = maps:from_list(lists:zip(TypeVars, Params)),
            Type2 = subst_type_vars(Type1, VarVals),
            validate_term(Model, Type2, Term)
    end.

%% Get a `value' from the config:
-spec get(lee:model(), data(), lee:key()) ->
                 {ok, term()} | undefined.
get(Model, Data, Key) ->
    case lee_storage:get(Model, Data, Key) of
        {ok, Val} ->
            {ok, Val};
        undefined ->
            {MetaTypes, Attrs, _} = lee_model:get(Key, Model#model.model),
            case Attrs of
                #{default := Val} ->
                    {ok, Val};
                _ ->
                    undefined
            end
    end.

%% Validate the config against a model
-spec validate(lee:model(), data()) ->
                            {ok, Warnings :: [string()]}
                          | {error, Errors :: [string()], Warnings :: [string()]}
                          .
validate(Model, Config) ->
    ModelIdx = lee_model:mk_metatype_index(Model#model.model),
    {Errors, Warnings} =
        lists:foldl( fun({MT, MOCS}, {Errors0, Warnings0}) ->
                             {Errors1, Warnings1} = validate_mt_instances(Model, Config, MT, MOCS),
                             {Errors1 ++ Errors0, Warnings1 ++ Warnings0}
                     end
                   , {[], []}
                   , maps:to_list(ModelIdx)
                   ),
    case Errors of
        [] ->
            {ok, Warnings};
        _ ->
            {error, Errors, Warnings}
    end.

-spec from_string(lee:model_fragment(), lee:type(), string()) ->
                         {ok, term()} | {error, string()}.
from_string(Model, Type = #type{id = TId}, String) ->
    {_, Attrs, _} = lee_model:get(TId, Model),
    Fun = maps:get( read
                  , Attrs
                  , fun(_, _, S) -> lee_lib:parse_erl_term(S) end
                  ),
    Fun(Model, Type, String).

%%====================================================================
%% Internal functions
%%====================================================================

-spec validate_mt_instances( lee:model()
                           , lee:data()
                           , lee:key()
                           , map_sets:set(lee:key())
                           ) -> {ok, Warnings :: [string()]}
                              | {error, Errors :: [string()], Warnings :: [string()]}
                              .
validate_mt_instances(Model, Config, MetaTypeId, MOCS) ->
    #model{metamodel = Meta} = Model,
    {[metatype], Attrs, _} = lee_model:get([metatype, MetaTypeId], Meta),
    Validate = maps:get( validate_mo
                       , Attrs
                       , fun(_,_,_,_) -> {[], []} end
                       ),
    GlobalValidate = maps:get(meta_global_validate, Attrs, fixme),
    lists:foldl( fun(MOCId, {E0, W0}) ->
                         {E1, W1} = validate_moc_instances( Model
                                                          , Config
                                                          , Validate
                                                          , MOCId
                                                          ),
                         {E1 ++ E0, W1 ++ W0}
                 end
               , {[], []}
               , map_sets:to_list(MOCS)
               ).

-spec validate_moc_instances( lee:model()
                            , lee:data()
                            , fun()
                            , lee:key()
                            ) -> {[string()], [string()]}.
validate_moc_instances(Model = #model{model = MF}, Config, Validate, MOCId) ->
    MOC = lee_model:get(MOCId, MF),
    Validate(Model, Config, MOCId, MOC).

validate_value(Model, Data, MOCId, {_, Attrs, _}) ->
    Type = maps:get(type, Attrs),
    Mandatory = maps:get(mandatory, Attrs, false),
    Instances = case lee_model:optional_part(Model, MOCId) of
                    {[], MOCId} ->
                        [MOCId];
                    {Optional, Required} ->
                        [I ++ Required || I <- lee_storage:list(Model, Data, Optional)]
                end,
    lists:foldl( fun(Id, {Err0, Warn0}) ->
                         {Err1, Warn1} = validate_instance(Model, Data, Id, Mandatory, Type),
                         {Err1 ++ Err0, Warn1 ++ Warn0}
                 end
               , {[], []}
               , Instances
               ).

validate_instance(Model, Data, MOIid, Mandatory, Type) ->
    case {get(Model, Data, MOIid), Mandatory} of
        {{ok, Term}, _} ->
            case validate_term(Model#model.model, Type, Term) of
                ok ->
                    {[], []};
                {error, Err} ->
                    {[Err], []}
            end;
        {undefined, false} ->
            {[], []};
        {undefined, true} ->
            Err = format( "Mandatory value ~p is missing in the config"
                        , [MOIid]
                        ),
            {[Err] , []}
    end.

%% TODO get rid of duplicated functions and types
format(Fmt, Attrs) ->
    lists:flatten(io_lib:format(Fmt, Attrs)).

-spec subst_type_vars(lee:type(), map()) -> lee:type().
subst_type_vars(Atom, _) when is_atom(Atom) ->
    Atom;
subst_type_vars({var, Var}, VarVals) ->
    #{Var := Subst} = VarVals,
    Subst;
subst_type_vars(Type = #type{parameters = Params0}, VarVals) ->
    Params = [case I of
                  {var, Var} ->
                      #{Var := Subst} = VarVals,
                      Subst;
                  _ ->
                      subst_type_vars(I, VarVals)
              end || I <- Params0],
    Type#type{parameters = Params}.
