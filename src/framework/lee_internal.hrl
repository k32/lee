-ifndef(LEE_INTERRNAL_HRL).
-define(LEE_INTERNAL_HRL, 1).

-include("lee.hrl").

-record(model,
        { metamodel        :: lee:cooked_module()
        , model            :: lee:cooked_module()
        , meta_class_idx   :: #{lee:metatype() => [lee:key()]}
        }).

-record(data,
        { %% Callback module implementing lee_storage behavior:
          backend          :: atom()
          %% Data itself:
        , data             :: term()
        }).

-endif.
